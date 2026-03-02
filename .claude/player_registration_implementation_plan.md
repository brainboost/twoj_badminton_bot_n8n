# Player Registration Feature - Implementation Plan

## 📋 Feature Overview

**Feature Name**: Player Registration for Reserved Courts  
**Command**: `/play` (or natural language: "I want to play", "зарегистрируюсь на игру", "zapisz mnie")  
**Purpose**: Allow players to register for badminton sessions on courts reserved by other users

### Use Case Example
> A user reserved two courts for two hours to play with colleagues, but wasn't sure how many people could arrive. They ask players to register themselves using `/play` command. As a result, multiple players register, and the organizer can add more courts or cancel excessive bookings before play day.

---

## 🗄️ Database Schema Changes

### New Table: `match_registrations`

```sql
CREATE TABLE match_registrations (
    id SERIAL PRIMARY KEY,
    
    -- Link to reservation (matches reservations.id)
    reservation_id INTEGER NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
    
    -- Player who registered (matches users.id)
    player_id VARCHAR(50) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Registration status
    status VARCHAR(20) NOT NULL DEFAULT 'confirmed' 
        CHECK (status IN ('confirmed', 'cancelled', 'waitlist')),
    
    -- Optional notes from player
    notes TEXT,
    
    -- Timestamps
    registered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Prevent duplicate registrations
    CONSTRAINT uq_reservation_player UNIQUE (reservation_id, player_id)
);

-- Performance indexes
CREATE INDEX idx_match_reg_reservation ON match_registrations(reservation_id);
CREATE INDEX idx_match_reg_player ON match_registrations(player_id);
CREATE INDEX idx_match_reg_status ON match_registrations(status) WHERE status = 'confirmed';

-- Comment for documentation
COMMENT ON TABLE match_registrations IS 'Player registrations for badminton matches on reserved courts';
COMMENT ON COLUMN match_registrations.reservation_id IS 'FK to reservations.id - the court booking';
COMMENT ON COLUMN match_registrations.player_id IS 'FK to users.id - the registered player';
COMMENT ON COLUMN match_registrations.status IS 'confirmed=playing, cancelled=withdrawn, waitlist=backup';
```

### Design Rationale

1. **Simple Junction Table**: Links `reservations` → `users` with status tracking
2. **CASCADE DELETE**: When reservation is cancelled, all registrations auto-delete
3. **Unique Constraint**: Prevents double-registration via `(reservation_id, player_id)`
4. **Status Field**: Supports future waitlist functionality
5. **No `updated_at`**: Following project convention - not needed unless explicitly required

---

## 🌍 Translation Keys

Add to `translations` table (remember: use actual line breaks, not `\n`):

```sql
-- English translations
INSERT INTO translations (key, lang, text) VALUES
('play_registered', 'en', '✅ You are registered!
📅 Date: {date}
⏰ Time: {time_start} - {time_end}
🏸 Court: {court}
👥 Players registered: {player_count}'),

('play_already_registered', 'en', 'ℹ️ You are already registered for this session.'),

('play_no_reservations', 'en', '📭 No upcoming reservations available for registration.
Ask the organizer to share a reservation link or check /list for your own bookings.'),

('play_select_session', 'en', '🏸 Available sessions to join:
{sessions_list}

Reply with the session number to register.'),

('play_unregister_success', 'en', '✅ Successfully unregistered from:
📅 {date} ⏰ {time_start}-{time_end} 🏸 Court {court}'),

('play_not_registered', 'en', 'ℹ️ You are not registered for this session.'),

('play_list_header', 'en', '📋 Your registered sessions:'),

('play_list_empty', 'en', '📭 You have no active registrations.
Use /play to register for available sessions.'),

('play_organizer_list', 'en', '👥 Players registered for your session:
📅 {date} ⏰ {time_start}-{time_end} 🏸 Court {court}

{player_list}
Total: {count} players'),

('play_session_full', 'en', '⚠️ This session already has {count} registered players.
Maximum recommended: 4 players per court.
Register anyway? Reply "yes" to confirm.');

-- Polish translations
INSERT INTO translations (key, lang, text) VALUES
('play_registered', 'pl', '✅ Jesteś zarejestrowany!
📅 Data: {date}
⏰ Czas: {time_start} - {time_end}
🏸 Kort: {court}
👥 Zarejestrowanych graczy: {player_count}'),

('play_already_registered', 'pl', 'ℹ️ Już jesteś zarejestrowany na tę sesję.'),

('play_no_reservations', 'pl', '📭 Brak dostępnych rezerwacji do rejestracji.
Poproś organizatora o link do rezerwacji lub sprawdź /list dla swoich własnych rezerwacji.'),

('play_select_session', 'pl', '🏸 Dostępne sesje do dołączenia:
{sessions_list}

Odpowiedz numerem sesji, aby się zarejestrować.'),

('play_unregister_success', 'pl', '✅ Wyrejestrowano z:
📅 {date} ⏰ {time_start}-{time_end} 🏸 Kort {court}'),

('play_not_registered', 'pl', 'ℹ️ Nie jesteś zarejestrowany na tę sesję.'),

('play_list_header', 'pl', '📋 Twoje zarejestrowane sesje:'),

('play_list_empty', 'pl', '📭 Nie masz aktywnych rejestracji.
Użyj /play, aby zarejestrować się na dostępne sesje.'),

('play_organizer_list', 'pl', '👥 Gracze zarejestrowani na Twoją sesję:
📅 {date} ⏰ {time_start}-{time_end} 🏸 Kort {court}

{player_list}
Łącznie: {count} graczy'),

('play_session_full', 'pl', '⚠️ Ta sesja ma już {count} zarejestrowanych graczy.
Zalecane maksimum: 4 graczy na kort.
Zarejestrować mimo to? Odpowiedz "tak" aby potwierdzić.');

-- Russian translations
INSERT INTO translations (key, lang, text) VALUES
('play_registered', 'ru', '✅ Вы зарегистрированы!
📅 Дата: {date}
⏰ Время: {time_start} - {time_end}
🏸 Корт: {court}
👥 Зарегистрировано игроков: {player_count}'),

('play_already_registered', 'ru', 'ℹ️ Вы уже зарегистрированы на эту сессию.'),

('play_no_reservations', 'ru', '📭 Нет доступных бронирований для регистрации.
Попросите организатора поделиться ссылкой или проверьте /list для своих бронирований.'),

('play_select_session', 'ru', '🏸 Доступные сессии для присоединения:
{sessions_list}

Ответьте номером сессии для регистрации.'),

('play_unregister_success', 'ru', '✅ Регистрация отменена:
📅 {date} ⏰ {time_start}-{time_end} 🏸 Корт {court}'),

('play_not_registered', 'ru', 'ℹ️ Вы не зарегистрированы на эту сессию.'),

('play_list_header', 'ru', '📋 Ваши зарегистрированные сессии:'),

('play_list_empty', 'ru', '📭 У вас нет активных регистраций.
Используйте /play для регистрации на доступные сессии.'),

('play_organizer_list', 'ru', '👥 Игроки, зарегистрированные на вашу сессию:
📅 {date} ⏰ {time_start}-{time_end} 🏸 Корт {court}

{player_list}
Всего: {count} игроков'),

('play_session_full', 'ru', '⚠️ На эту сессию уже зарегистрировано {count} игроков.
Рекомендуемый максимум: 4 игрока на корт.
Всё равно зарегистрироваться? Ответьте "да" для подтверждения.');
```

---

## 🔄 n8n Workflow Architecture

### Overview: New and Modified Workflows

```
┌─────────────────────────────────────────────────────────────────────┐
│                        WORKFLOW CHANGES                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  MODIFY: Command Parser (QbD3Epml4ANF9vr0)                          │
│  ├── Add "play" command to JSON schema                               │
│  ├── Add "play" to NLP Command Switch                                │
│  └── Add Execute Play connection                                     │
│                                                                      │
│  NEW: Play Command (sub-workflow)                                    │
│  ├── Trigger: executeWorkflowTrigger                                 │
│  ├── List available reservations (future dates)                      │
│  ├── Show selection menu OR auto-register                            │
│  ├── Insert into match_registrations                                 │
│  └── Send confirmation via Telegram                                  │
│                                                                      │
│  MODIFY: List Bookings Command (51Y9SIV139LvX5jl)                   │
│  └── Show player registration count for each reservation             │
│                                                                      │
│  MODIFY: Delete Command (wYEfXMLutTlrEgBq)                          │
│  └── Show warning if players are registered                          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 📝 Implementation Tasks

### Phase 1: Database Setup

#### Task 1.1: Create `match_registrations` Table
```sql
-- Execute via postgres MCP or direct connection
CREATE TABLE match_registrations (
    id SERIAL PRIMARY KEY,
    reservation_id INTEGER NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
    player_id VARCHAR(50) NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'confirmed' 
        CHECK (status IN ('confirmed', 'cancelled', 'waitlist')),
    notes TEXT,
    registered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_reservation_player UNIQUE (reservation_id, player_id)
);

CREATE INDEX idx_match_reg_reservation ON match_registrations(reservation_id);
CREATE INDEX idx_match_reg_player ON match_registrations(player_id);
CREATE INDEX idx_match_reg_status ON match_registrations(status) WHERE status = 'confirmed';
```

#### Task 1.2: Insert Translation Keys
Execute the translation INSERT statements from above.

---

### Phase 2: Play Command Workflow (NEW)

#### Workflow: "Play Command"
**ID**: To be assigned  
**Tag**: `bot_command`

#### Node Structure:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          PLAY COMMAND WORKFLOW                            │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  [Trigger] ──► [Get Future Reservations] ──► [Has Reservations?]         │
│                                                    │                      │
│                             ┌──────────────────────┴──────────────┐       │
│                             ▼                                     ▼       │
│                    [Single or Multiple?]              [No Reservations]   │
│                             │                                │            │
│            ┌────────────────┴────────────────┐               ▼            │
│            ▼                                 ▼        [Get Translation]   │
│    [Auto-Register]              [Format Selection Menu]      │            │
│            │                                 │               ▼            │
│            ▼                                 ▼        [Send Empty Msg]    │
│    [Check Already Registered?]        [Send Menu]                         │
│            │                                 │                            │
│    ┌───────┴───────┐                        ...                           │
│    ▼               ▼                                                      │
│  [Yes]          [No]                                                      │
│    │               │                                                      │
│    ▼               ▼                                                      │
│ [Already Msg]  [Insert Registration]                                      │
│                    │                                                      │
│                    ▼                                                      │
│            [Get Player Count]                                             │
│                    │                                                      │
│                    ▼                                                      │
│            [Format Success Msg]                                           │
│                    │                                                      │
│                    ▼                                                      │
│            [Send Telegram]                                                │
│                                                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

#### Key Nodes Configuration:

**1. Trigger Node**
```json
{
  "name": "When Executed by Another Workflow",
  "type": "n8n-nodes-base.executeWorkflowTrigger",
  "parameters": {
    "workflowInputs": {
      "values": [
        {"name": "chat_id", "type": "any"},
        {"name": "user_id", "type": "any"},
        {"name": "username", "type": "any"},
        {"name": "fullname", "type": "any"},
        {"name": "lang", "type": "any"},
        {"name": "arg1", "type": "any"},
        {"name": "arg2", "type": "any"}
      ]
    }
  }
}
```

**2. Get Future Reservations (Postgres)**
```sql
-- Base query with optional date and time filtering
SELECT 
    r.id,
    r.date,
    r.time_start,
    r.time_end,
    r.court,
    r.user_id as organizer_id,
    u.full_name as organizer_name,
    u.user_name as organizer_username,
    (SELECT COUNT(*) FROM match_registrations mr 
     WHERE mr.reservation_id = r.id AND mr.status = 'confirmed') as player_count
FROM reservations r
JOIN users u ON r.user_id = u.id
WHERE r.date >= CURRENT_DATE
  -- Optional date filter (arg1)
  AND (CAST('{{ $json.arg1 }}' AS TEXT) = '' OR r.date = CAST('{{ $json.arg1 }}' AS DATE))
  -- Optional time filter (arg2)
  AND (CAST('{{ $json.arg2 }}' AS TEXT) = '' OR r.time_start = '{{ $json.arg2 }}')
ORDER BY r.date, r.time_start;
```

**Note**: When both `arg1` (date) and `arg2` (time) are provided, the query filters to exact match. This allows:
- `/play` → all future reservations
- `/play 2026-01-17` → all reservations on that date  
- `/play 2026-01-17 19:00` → exact reservation at that date/time

**3. Check Already Registered (Postgres)**
```sql
SELECT id FROM match_registrations 
WHERE reservation_id = {{ $json.reservation_id }}
AND player_id = '{{ $json.user_id }}'
AND status = 'confirmed';
```

**4. Insert Registration (Postgres)**
```sql
INSERT INTO match_registrations (reservation_id, player_id, status)
VALUES ({{ $json.reservation_id }}, '{{ $json.user_id }}', 'confirmed')
ON CONFLICT (reservation_id, player_id) 
DO UPDATE SET status = 'confirmed', registered_at = CURRENT_TIMESTAMP
RETURNING id;
```

**5. Get Updated Player Count (Postgres)**
```sql
SELECT COUNT(*) as player_count 
FROM match_registrations 
WHERE reservation_id = {{ $json.reservation_id }}
AND status = 'confirmed';
```

---

### Phase 3: Command Parser Modifications

#### Task 3.1: Update Structured Output Parser Schema

Add `"play"` to the command enum:
```json
{
  "command": {
    "enum": ["show", "list", "delete", "deleteall", "book", "register", "play"]
  }
}
```

Add conditional rule for `play` command:
```json
{
  "comment": "Case: 'play' optionally takes date and/or time",
  "if": {
    "properties": {
      "command": {"const": "play"}
    }
  },
  "then": {
    "properties": {
      "arg1": {
        "type": "string",
        "description": "Optional: date in YYYY-MM-DD format"
      },
      "arg2": {
        "type": "string",
        "description": "Optional: start time in HH:MM format"
      }
    }
  }
}
```

#### Task 3.2: Update LLM System Prompt

Add to the COMMANDS REFERENCE section:
```
## 7. play
Purpose: Register to play on a reserved court
Trigger words: play, join, register for game, записаться на игру, dołącz do gry, хочу играть, zagraj
arg1: Optional - date (YYYY-MM-DD)
arg2: Optional - start time (HH:MM)

Examples:
- "I want to play" → {"command": "play"}
- "join tomorrow's game" → {"command": "play", "arg1": "{{ $now.plus({days: 1}).format('yyyy-MM-dd') }}"}
- "/play 2026-01-17 19:00" → {"command": "play", "arg1": "2026-01-17", "arg2": "19:00"}
- "хочу играть в субботу в 16:00" → {"command": "play", "arg1": "2026-01-18", "arg2": "16:00"}
- "zapisz mnie na jutro na 18" → {"command": "play", "arg1": "{{ $now.plus({days: 1}).format('yyyy-MM-dd') }}", "arg2": "18:00"}
- "join the 7pm game on Friday" → {"command": "play", "arg1": "2026-01-17", "arg2": "19:00"}
```

#### Task 3.3: Add Play to NLP Command Switch

Add new case to the Switch node:
```json
{
  "conditions": {
    "options": {"version": 2, "caseSensitive": true, "typeValidation": "strict"},
    "combinator": "and",
    "conditions": [{
      "id": "play-cond",
      "leftValue": "={{ $json.command }}",
      "rightValue": "play",
      "operator": {"type": "string", "operation": "equals"}
    }]
  },
  "renameOutput": true,
  "outputKey": "play"
}
```

#### Task 3.3b: Update Cmd Parse Node for arg2 Extraction

The existing `Cmd Parse` node handles `/command arg1` format. For `/play date time`, we need to extract both arguments:

```javascript
// In Cmd Parse node, add arg2 extraction
// arg1 = first argument (date)
// arg2 = second argument (time) - NEW

// Updated arg2 expression:
={{
(() => {
  const parts = $json.text
    .toLowerCase()
    .replace(/^\//, '')
    .split(/\s+/);
  
  // parts[0] = command, parts[1] = arg1 (date), parts[2] = arg2 (time)
  return parts[2] || '';
})()
}}
```

**Alternative**: Keep Cmd Parse simple and handle complex parsing in the LLM for NLP input, while slash commands use regex splitting.

#### Task 3.4: Add Execute Play Node

```json
{
  "name": "Execute Play",
  "type": "n8n-nodes-base.executeWorkflow",
  "parameters": {
    "workflowId": {"__rl": true, "mode": "id", "value": "<PLAY_WORKFLOW_ID>"},
    "workflowInputs": {
      "mappingMode": "defineBelow",
      "value": {
        "arg1": "={{ $json.arg1 }}",
        "arg2": "={{ $json.arg2 }}",
        "chat_id": "={{ $json.chat_id }}",
        "user_id": "={{ $json.user_id }}",
        "username": "={{ $json.username }}",
        "fullname": "={{ $json.fullname }}",
        "lang": "={{ $json.lang }}"
      }
    },
    "options": {"waitForSubWorkflow": true}
  }
}
```

#### Task 3.5: Update Merge Context Node

Add `arg2` to the assignments in Merge Context node:
```json
{
  "assignments": [
    {"id": "cmd", "name": "command", "type": "string", "value": "={{ $json.command }}"},
    {"id": "arg", "name": "arg1", "type": "string", "value": "={{ $json.arg1 }}"},
    {"id": "arg2", "name": "arg2", "type": "string", "value": "={{ $json.arg2 || '' }}"},
    {"id": "cid", "name": "chat_id", "type": "string", "value": "={{ $json.chat_id }}"},
    {"id": "uid", "name": "user_id", "type": "string", "value": "={{ $json.user_id }}"},
    {"id": "uname", "name": "username", "type": "string", "value": "={{ $json.username }}"},
    {"id": "fname", "name": "fullname", "type": "string", "value": "={{ $json.fullname }}"},
    {"id": "lng", "name": "lang", "type": "string", "value": "={{ $json.lang }}"}
  ]
}
```

---

### Phase 4: Modify Existing Workflows

#### Task 4.1: Update List Bookings Command

Modify the "Format Reservations" code node to include player count:

```javascript
// In Format Reservations node
const reservations = $input.all();
const lines = reservations.map((r, i) => {
  const json = r.json;
  const playerCount = json.player_count || 0;
  return `${i+1}. 📅 ${json.date} ⏰ ${json.time_start}-${json.time_end} 🏸 Court ${json.court} 👥 ${playerCount} players`;
});
return [{json: {formatted: lines.join('\n')}}];
```

Update the SQL query to include player count:
```sql
SELECT 
    r.*,
    (SELECT COUNT(*) FROM match_registrations mr 
     WHERE mr.reservation_id = r.id AND mr.status = 'confirmed') as player_count
FROM reservations r
WHERE r.user_id = '{{ $json.user_id }}'
AND r.date >= CURRENT_DATE
ORDER BY r.date, r.time_start;
```

#### Task 4.2: Update Delete Command

Add check for registered players before deletion:

```sql
-- New node: Get Registration Count
SELECT 
    COUNT(*) as registered_count,
    STRING_AGG(u.full_name, ', ') as player_names
FROM match_registrations mr
JOIN users u ON mr.player_id = u.id
WHERE mr.reservation_id = (
    SELECT id FROM reservations 
    WHERE reservation_id = '{{ $json.arg1 }}'
)
AND mr.status = 'confirmed';
```

Add warning message translation:
```sql
INSERT INTO translations (key, lang, text) VALUES
('delete_has_players_warning', 'en', '⚠️ Warning: {count} players are registered for this session:
{player_names}

They will be notified if you proceed. Continue with deletion?'),
('delete_has_players_warning', 'pl', '⚠️ Uwaga: {count} graczy jest zarejestrowanych na tę sesję:
{player_names}

Zostaną powiadomieni jeśli kontynuujesz. Kontynuować usuwanie?'),
('delete_has_players_warning', 'ru', '⚠️ Внимание: {count} игроков зарегистрировано на эту сессию:
{player_names}

Они будут уведомлены если продолжите. Продолжить удаление?');
```

---

## 🔗 Workflow Connections Summary

### Command Parser Switch Output Mapping

| Output Index | Command | Target Workflow |
|-------------|---------|-----------------|
| 0 | show | Execute Show |
| 1 | book | Execute Book |
| 2 | list | Execute List |
| 3 | delete | Execute Delete |
| 4 | register | NLP Execute Register |
| 5 | deleteall | Execute Delete All |
| 6 | help | Call Help Command |
| 7 | start | Call Start Command |
| **8** | **play** | **Execute Play** (NEW) |

---

## 📊 SQL Helper Queries

### Get All Players for a Reservation
```sql
SELECT 
    u.full_name,
    u.user_name,
    mr.registered_at,
    mr.status
FROM match_registrations mr
JOIN users u ON mr.player_id = u.id
WHERE mr.reservation_id = ?
ORDER BY mr.registered_at;
```

### Get Player's Registrations
```sql
SELECT 
    r.date,
    r.time_start,
    r.time_end,
    r.court,
    org.full_name as organizer,
    mr.registered_at
FROM match_registrations mr
JOIN reservations r ON mr.reservation_id = r.id
JOIN users org ON r.user_id = org.id
WHERE mr.player_id = ?
AND mr.status = 'confirmed'
AND r.date >= CURRENT_DATE
ORDER BY r.date, r.time_start;
```

### Count by Reservation (for organizer dashboard)
```sql
SELECT 
    r.id,
    r.date,
    r.time_start,
    r.time_end,
    r.court,
    COUNT(mr.id) as player_count
FROM reservations r
LEFT JOIN match_registrations mr ON r.id = mr.reservation_id AND mr.status = 'confirmed'
WHERE r.user_id = ?
AND r.date >= CURRENT_DATE
GROUP BY r.id
ORDER BY r.date, r.time_start;
```

---

## ⚡ Implementation Order for n8n-workflow-expert

### Step 1: Database (Execute SQL)
1. Create `match_registrations` table
2. Insert all translation keys

### Step 2: Create Play Command Workflow
1. Create new workflow named "Play Command"
2. Add tag `bot_command`
3. Build node structure as specified
4. Test with pinned data

### Step 3: Modify Command Parser
1. Update Structured Output Parser schema (add "play")
2. Update LLM system prompt (add play command reference)
3. Add new case to NLP Command Switch
4. Add Execute Play node and connection

### Step 4: Modify List Bookings Command
1. Update SQL to include player count
2. Update format node to show player count

### Step 5: Modify Delete Command (Optional - Phase 2)
1. Add player registration check
2. Add warning message flow
3. Add notification logic

---

## 🧪 Test Cases

### Test 1: Basic Registration
```
Input: /play
Expected: Shows list of available reservations, user selects one, registration confirmed
```

### Test 2: Already Registered
```
Input: /play (when already registered for all sessions)
Expected: "You are already registered for this session"
```

### Test 3: No Reservations
```
Input: /play (when no future reservations exist)
Expected: "No upcoming reservations available for registration"
```

### Test 4: NLP Registration with Date
```
Input: "хочу поиграть завтра"
Expected: Parses to {command: "play", arg1: "2026-01-15"}, shows matching sessions for that date
```

### Test 5: Exact Date + Time Match
```
Input: /play 2026-01-17 19:00
Expected: Parses to {command: "play", arg1: "2026-01-17", arg2: "19:00"}
         If single match found → auto-register
         If no match → "No session at 19:00 on 2026-01-17"
```

### Test 6: NLP with Time
```
Input: "zapisz mnie na sobotę na 16:00"
Expected: Parses to {command: "play", arg1: "2026-01-18", arg2: "16:00"}
```

### Test 7: List Shows Players
```
Input: /list (as organizer with registered players)
Expected: Each reservation shows "👥 3 players" count
```

### Test 8: Multiple Sessions Same Day
```
Input: /play 2026-01-17 (when 3 reservations exist on that day)
Expected: Shows only the 3 sessions on 2026-01-17 for selection
```

---

## 📁 Files to Create/Modify

| File/Resource | Action | Description |
|--------------|--------|-------------|
| `match_registrations` table | CREATE | New database table |
| `translations` table | INSERT | 30 new translation keys (10 keys × 3 languages) |
| Play Command workflow | CREATE | New sub-workflow |
| Command Parser workflow | MODIFY | Add play command routing |
| List Bookings workflow | MODIFY | Show player count |
| Delete Command workflow | MODIFY | Add player warning (Phase 2) |

---

## 🎯 Success Criteria

1. ✅ Users can register for any future reservation via `/play`
2. ✅ System prevents duplicate registrations
3. ✅ Organizers see player count in `/list` output
4. ✅ Registrations auto-delete when reservation is cancelled
5. ✅ Multilingual support (EN, PL, RU)
6. ✅ NLP correctly parses natural language play requests
