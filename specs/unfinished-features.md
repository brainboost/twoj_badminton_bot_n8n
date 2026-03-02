# Spec: Unfinished Features - twoj_badminton_bot

**Slug:** unfinished-features
**Date:** 2026-02-19
**Last Updated:** 2026-02-19 (after second workflow download audit)
**Status:** Draft

## Summary

Analysis of refreshed workflow JSON files (re-downloaded 2026-02-19) audited against the previous spec version. **3 features were resolved** since the last review. **2 original features remain open**. **2 new issues were identified** in the refreshed files.

Current outstanding items: **4 features/bugs**.

---

## Findings Overview

| # | Feature | Status | Priority |
|---|---------|--------|----------|
| 1 | List Bookings — player count per reservation | Not implemented | Medium |
| 2 | Delete Command — registered-players warning | Not implemented | Medium |
| 3 | Noshow Command — missing translation keys | Partial (hardcoded EN fallback) | Medium |
| 4 | Delete Command — `Format API Error Message` references wrong node | Bug | Low |

---

## Recently Resolved (no longer actionable)

| Feature | Resolution |
|---------|-----------|
| Play Command (credential, activation, multi-session UX) | Fully rearchitected. `active: true`, credential `3SDluWLUa1vIU50a`, clean Switch-based flow. Multi-session responds with "please be more specific" message. |
| `reservation_id` storage from bulk booking | `Build Insert Query` now extracts `inserted[i].booking_id` from MCP response and stores it in the INSERT query. |
| Reservation Status Update — date range | `Generate Date Range` now iterates `i = 1..7` (7 days, starting tomorrow). Note: today is excluded — possibly intentional (past slots). |

---

## Feature 1: List Bookings Command — Player Count per Reservation

### Current State

The `List Bookings Command` (`51Y9SIV139LvX5jl`) fetches reservations from the TwojTenis MCP (`get_reservations`) and formats them in the `Format Reservations` Code node. The format code displays: date, time, club number/name, booking ID.

```javascript
// Current format (Format Reservations code node)
return `${i + 1}. <b>${date}</b> ${time}\n  Club: ${club_no} - ${club}\n  ID: <code>${bookingId}</code>`;
```

**Player count is absent.** Zero matches of `player_count` confirmed in `List Bookings Command.json`.

The implementation plan (`.claude/player_registration_implementation_plan.md`, Task 4.1) specifies adding player count to the list output. The `match_registrations` table is in place.

### Proposed Fix

**Option A — Add a local DB query after receiving MCP reservations:**

Add a Postgres query node after `Format Reservations` (or replace the MCP data with local DB data for the organizer's own reservations):

```sql
SELECT
    r.id,
    r.reservation_id,
    r.date,
    r.time_start,
    r.time_end,
    r.court,
    (SELECT COUNT(*) FROM match_registrations mr
     WHERE mr.reservation_id = r.id AND mr.status = 'confirmed') AS player_count
FROM reservations r
WHERE r.user_id = '{{ $json.user_id }}'
  AND r.date >= CURRENT_DATE
ORDER BY r.date, r.time_start;
```

Then update the `Format Reservations` code:

```javascript
// After - add player count
return `${i + 1}. <b>${date}</b> ${time}\n  🏸 ${club_no}\n  👥 ${player_count} players\n  ID: <code>${bookingId}</code>`;
```

**Option B (simpler) — Add a scalar subquery to the existing format code:**

After the MCP call returns, fetch a batch player_count from DB by `reservation_id` values, merge into the MCP results before formatting.

### Database Integration

- **Tables:** `reservations` (read), `match_registrations` (subquery COUNT)
- **Operations:** SELECT with scalar subquery for player count

---

## Feature 2: Delete Command — Registered-Players Warning

### Current State

The `Delete command` (`wYEfXMLutTlrEgBq`) cancels a TwojTenis reservation via MCP and deletes it from the local `reservations` table. It does **not** check whether other users have registered via `/play` before proceeding.

From the implementation plan (Task 4.2): a warning should be shown listing registered players before the deletion proceeds.

### Gap

When a reservation is deleted, its `match_registrations` rows are cascade-deleted (FK with `ON DELETE CASCADE`), but the registered players receive no notification and the organizer sees no warning about who will be affected.

### Proposed Fix

Add new nodes between `Check Input Valid` (true branch) and `Get User Credentials`:

#### New Node: Get Registration Count
```sql
SELECT
    COUNT(*) AS registered_count,
    STRING_AGG(u.full_name, ', ') AS player_names
FROM match_registrations mr
JOIN users u ON mr.player_id = u.id
WHERE mr.reservation_id = (
    SELECT id FROM reservations
    WHERE reservation_id = '{{ $json.reservation_id }}'
    AND user_id = '{{ $json.user_id }}'
)
AND mr.status = 'confirmed';
```

#### New Node: Has Registered Players? (IF)
- `$json.registered_count > 0` → TRUE → warn path
- FALSE → proceed to `Get User Credentials` as before

#### Warning path
- Get translation `delete_has_players_warning`
- Replace `{count}` and `{player_names}` placeholders
- Send warning to Telegram and terminate (user re-sends `/delete ID` to confirm, or add inline keyboard)

### Missing Translation Keys

These keys are referenced in the implementation plan but **are not present** in the `translations` table:

```sql
INSERT INTO translations (key, lang, text) VALUES
('delete_has_players_warning', 'en', '⚠️ Warning: {count} players are registered for this session:
{player_names}

They will not be notified automatically. Proceed with deletion by sending /delete {id} again.'),
('delete_has_players_warning', 'pl', '⚠️ Uwaga: {count} graczy jest zarejestrowanych na tę sesję:
{player_names}

Nie zostaną automatycznie powiadomieni. Kontynuuj usuwanie wysyłając /delete {id} ponownie.'),
('delete_has_players_warning', 'ru', '⚠️ Внимание: {count} игроков зарегистрировано на эту сессию:
{player_names}

Они не будут уведомлены автоматически. Продолжите удаление, отправив /delete {id} снова.');
```

### Node Pipeline Additions

| # | Node Name | Type | Purpose |
|---|-----------|------|---------|
| A | Get Registration Count | `postgres` v2.6 | Count + names of registered players |
| B | Has Registered Players? | `if` v2.3 | Branch on `registered_count > 0` |
| C | Get Warning Translation | `postgres` v2.6 | Fetch `delete_has_players_warning` |
| D | Format Warning Message | `set` v3.4 | Replace `{count}`, `{player_names}` |
| E | (Merge into) Send a text message | existing Telegram node | Send and end |

---

## Feature 3: Noshow Command — Missing Translation Keys

### Current State

A new workflow `Noshow Command` (`RURORDihq0oJJTKJ`, active: true, created 2026-01-14) was added. It allows users to unregister from a `/play` session by setting `match_registrations.status = 'cancelled'`.

The Command Parser (`QbD3Epml4ANF9vr0`) **already routes** `/noshow` to this workflow (confirmed — `noshow` output key present in Switch node at lines 664/676 and 2336/2348 of `Command Parser.json`).

The workflow's `Get Translations` node queries three keys:
- `noshow_no_registrations`
- `noshow_multiple`
- `noshow_success`

### Gap

**None of these keys exist in the `translations` table** (verified via SQL query — zero rows returned for `key LIKE 'noshow%'`).

When translations are missing, the workflow falls back to hardcoded English strings in the `Merge Translations` Code node:
- `noshow_no_registrations` → `'No active registrations found.'`
- `noshow_multiple` → `'Multiple registrations found. Please specify date/time.'`
- `noshow_success` → `'Successfully unregistered.'`

This means the `/noshow` command **works in English only** regardless of the user's language setting. PL and RU users will receive English responses.

### Proposed Fix

Insert the missing translation keys for all three languages. Suggested text (should be reviewed for tone consistency with other messages):

```sql
INSERT INTO translations (key, lang, text) VALUES
-- noshow_no_registrations
('noshow_no_registrations', 'en', '❌ You have no active registrations to cancel.
Use /play to register for a session first.'),
('noshow_no_registrations', 'pl', '❌ Nie masz aktywnych rejestracji do anulowania.
Użyj /play, aby najpierw zarejestrować się na sesję.'),
('noshow_no_registrations', 'ru', '❌ У вас нет активных регистраций для отмены.
Используйте /play для регистрации на сессию.'),
-- noshow_multiple
('noshow_multiple', 'en', '📋 Multiple registrations found. Please specify the date and time:
/noshow YYYY-MM-DD HH:MM'),
('noshow_multiple', 'pl', '📋 Znaleziono kilka rejestracji. Podaj datę i czas:
/noshow RRRR-MM-DD GG:MM'),
('noshow_multiple', 'ru', '📋 Найдено несколько регистраций. Укажите дату и время:
/noshow ГГГГ-ММ-ДД ЧЧ:ММ'),
-- noshow_success
('noshow_success', 'en', '✅ You have been unregistered from:
📅 {date} ⏰ {time_start}-{time_end} 🏸 Court {court}'),
('noshow_success', 'pl', '✅ Zostałeś wyrejestrowany z:
📅 {date} ⏰ {time_start}-{time_end} 🏸 Kort {court}'),
('noshow_success', 'ru', '✅ Вы отменили регистрацию:
📅 {date} ⏰ {time_start}-{time_end} 🏸 Корт {court}');
```

Note: The `noshow_success` template uses `{date}`, `{time_start}`, `{time_end}`, `{court}` placeholders, which matches the `Format Success` Set node substitution logic:
```javascript
$json.success_message
  .replace('{date}', $json.registration.date)
  .replace('{time_start}', $json.registration.time_start)
  .replace('{time_end}', $json.registration.time_end)
  .replace('{court}', $json.registration.court)
```

### Database Integration

- **Tables affected:** `translations` (INSERT 9 rows)
- No workflow changes needed — the workflow structure is correct

---

## Feature 4: Delete Command — Bug in `Format API Error Message` Node

### Current State

The `Delete command` (`wYEfXMLutTlrEgBq`) has a node named `Format API Error Message` that is reached when the MCP `delete_reservation` call returns `success: false` (via `Check Delete Result` → FALSE branch → `Get API Error Translation` → `Format API Error Message`).

### Bug

The `Format API Error Message` node references a node named `"Set Reservation Data"` that **does not exist** in this workflow:

```json
{
  "name": "chat_id",
  "value": "={{ $('Set Reservation Data').first().json.chat_id }}"
}
```

The context-setting node in this workflow is actually named **`"Set Delete Context"`**, not `"Set Reservation Data"`. This reference error will cause an n8n expression error at runtime when the delete API call fails.

### Proposed Fix

Update the `chat_id` expression in `Format API Error Message` from:
```
={{ $('Set Reservation Data').first().json.chat_id }}
```
to:
```
={{ $('Set Delete Context').first().json.chat_id }}
```

This is a 1-line expression fix in a single node.

### Impact

Low severity — only triggers when the TwojTenis `delete_reservation` API call returns a non-success response. On the happy path (deletion succeeds), this node is never reached. But when deletion fails, the user receives no message at all (the workflow errors silently).

---

## Trigger / Entry Points Summary

| Feature | Trigger Type | Workflow ID |
|---------|-------------|-------------|
| List player count | Modified Code node + new Postgres query | `51Y9SIV139LvX5jl` |
| Delete player warning | New nodes in Delete | `wYEfXMLutTlrEgBq` |
| Noshow translation keys | DB INSERT only (no workflow change) | `RURORDihq0oJJTKJ` |
| Delete API error chat_id fix | 1-expression fix in Format API Error Message | `wYEfXMLutTlrEgBq` |

---

## Implementation Order (Recommended)

### Quick wins (low risk, high value)
1. **Feature 4** — Fix 1-expression bug in `Format API Error Message` (Delete Command)
2. **Feature 3** — Insert 9 translation rows for Noshow Command (DB only, no workflow change)

### Medium complexity
3. **Feature 1** — Add player count SQL + format update in List Bookings
4. **Feature 2** — Add player warning nodes to Delete Command + insert missing `delete_has_players_warning` translations (3 rows)

---

## Database Changes Required

| Change | Type | SQL |
|--------|------|-----|
| Insert `noshow_no_registrations` translations (3 langs) | INSERT | See Feature 3 section |
| Insert `noshow_multiple` translations (3 langs) | INSERT | See Feature 3 section |
| Insert `noshow_success` translations (3 langs) | INSERT | See Feature 3 section |
| Insert `delete_has_players_warning` translations (3 langs) | INSERT | See Feature 2 section |

All other required tables already exist. No new tables needed.

---

## Credentials Reference

| Credential | ID | Used in |
|------------|----|---------|
| Telegram API | `pHQDqhsnrwimdaY2` | All Telegram nodes |
| PostgreSQL | `3SDluWLUa1vIU50a` | All DB nodes |
| TwojTenis MCP | `G9CyzT9PT67tg4V7` | Book, List, Delete, DeleteAll |
| Ollama | `OwoNqqKy33Tzlan7` | LLM nodes |
| QDrant | `R97Yi6THM8qVyAcv` | Vector store |

---

## Notes

- The `play_list_header`, `play_list_empty`, `play_session_full`, `play_unregister_success`, `play_not_registered`, `play_select_session`, `play_organizer_list` translation keys exist in DB but the corresponding workflow flows are **not implemented**. These represent further optional enhancements (e.g., organizer dashboard, session-full warning with confirmation, player list view). Out of scope for current pass.
- The `Reservation Status Update` generates days `i=1..7` (tomorrow through day+7). Today's slots are not synced. This may be intentional (past time slots cannot be booked), but it means a user who asks `/show today` will see potentially stale data from the last sync cycle.
- The OpenAI Whisper dependency for voice transcription is a known issue (CLAUDE.md). Out of scope for this spec.
