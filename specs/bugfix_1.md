# Plan: Fix Reservation DB Tracking + 3-State Show Command

## Context

When a bot user books a court, the booking is sent to TwojTenis via MCP, but the local
`reservations` table is not reliably populated due to a date format bug in the Book Command.
Additionally, the `/show` command has no awareness of the `reservations` table — all booked
slots look identical (`❌`) regardless of whether a bot user or an external user made the booking.

**Goal:**
1. Fix Book Command so reservations are properly saved to the `reservations` SQL table
2. Update `/show` to visually distinguish bot-user bookings from external ones

---

## Root Causes

### Bug 1: Date format mismatch in Book Command
**File:** `workflows/Book Command.json` → node `build-insert-query`

The input `b.date` arrives as `DD.MM.YYYY` (e.g. `"01.03.2026"`). PostgreSQL's `DATE` column
rejects this format, causing the INSERT to silently fail. `notes` also uses `.replace()` without
a global regex, only fixing the first apostrophe.

### Bug 2: Sync delay leaves booked slots appearing green
The `Reservation status update` workflow runs every **20 minutes** (`*/20 7-21 * * *`). After a
booking is made via MCP, `club_schedules` is NOT immediately updated — the `is_available` column
stays `true` until the next sync cycle. Combined with Bug 1 (empty `reservations` table),
the Show Command has no immediate record of the booking and keeps displaying `✅`.

Even after the sync corrects `is_available = false`, the Show Command treats ALL unavailable
slots identically — no way to distinguish bot bookings from external ones.

### Bug 3: Show Command doesn't read `reservations` table
**File:** `workflows/Show Command.json` → node `Select Schedules` + `Format Schedule`

The SQL only queries `club_schedules` with a boolean `is_available`. No JOIN with `reservations`.
The `club_schedules.user_id` column is always NULL (never written by the sync workflow).

**The JOIN approach in Fix 2/3 below acts as an "immediate cache"** — bot-booked slots are
visible as `🏸` from the `reservations` table as soon as they're saved, even before the
next 20-minute sync updates `club_schedules.is_available`.

---

## Fix 1: Book Command — "Build Insert Query" Node

**Workflow:** `p5NpS5X1VLPdY3mX` | **Node name:** `Build Insert Query` | **ID:** `build-insert-query`

Replace `jsCode` with:

```javascript
const original_args = $('When Executed by Another Workflow').first().json.arg1;
const bookings = JSON.parse(original_args);
const user_id = $('When Executed by Another Workflow').first().json.user_id;
let queries = [];
const inserted = $input.first().json.result.structuredContent.reservation.bookings;

for (let i = 0; i < inserted.length; i++) {
  const b = bookings[i];
  const reservation_id = inserted[i].booking_id;

  // Convert date from DD.MM.YYYY to YYYY-MM-DD for PostgreSQL DATE column
  let dbDate = b.date;
  const dateMatch = b.date.match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/);
  if (dateMatch) {
    const day = dateMatch[1].padStart(2, '0');
    const month = dateMatch[2].padStart(2, '0');
    const year = dateMatch[3];
    dbDate = `${year}-${month}-${day}`;
  }

  // Safe notes: handle null/undefined and escape ALL apostrophes
  const safeNotes = (b.notes || '').replace(/'/g, "''");

  const query = "INSERT INTO reservations " +
    "(date, time_start, time_end, court, players_num, user_id, notes, reservation_id) " +
    "VALUES(" +
    "'" + dbDate + "'," +
    "'" + b.time_start + "'," +
    "'" + b.time_end + "'," +
    "'" + b.court + "'," +
    b.players_num + "," +
    "'" + user_id + "'," +
    "'" + safeNotes + "'," +
    "'" + reservation_id + "'" +
    ");";
  queries.push(query);
}

return [{ json: { queries: queries } }];
```

**Key changes:**
- `dbDate`: extracts D/M/Y from `DD.MM.YYYY` → stores as `YYYY-MM-DD`
- `safeNotes`: null-coalesces with `||''` and uses `/'/g` regex for all apostrophes

**n8n-MCP operation:** `n8n_update_partial_workflow` with `updateNode` on `Build Insert Query`

---

## Fix 2: Show Command — "Select Schedules" Node (SQL → JOIN query)

**Workflow:** `HFeE52YK9tAzKTpk` | **Node name:** `Select Schedules`
**Node ID:** `5d9763e6-3b39-402e-b0c2-165225b1371d`

Switch `operation` from `select` to `executeQuery` with this SQL:

```sql
SELECT
  cs.club_id,
  cs.sport_id,
  cs.date,
  cs.court_number,
  cs.time_slot,
  cs.is_available,
  cs.updated_at,
  r.user_id   AS bot_user_id,
  u.full_name AS bot_user_name,
  u.user_name AS bot_username
FROM club_schedules cs
LEFT JOIN reservations r
  ON  cs.date = r.date
  AND cs.time_slot::time = r.time_start::time
  AND cs.court_number = 'Badminton ' || r.court
LEFT JOIN users u
  ON r.user_id = u.id
WHERE cs.date = $1
  AND cs.sport_id = 84
ORDER BY cs.time_slot, cs.court_number
```

**JOIN logic:**
- `cs.court_number = 'Badminton ' || r.court` bridges naming difference (`'Badminton 1'` vs `'1'`)
- `cs.time_slot::time = r.time_start::time` compares `TIME` vs `VARCHAR(5)` (PostgreSQL auto-casts)
- `sport_id = 84` filters badminton only

**Parameter binding:** `options.queryParams` = `={{ $json.arg1 || $today }}`

**Fallback** if `queryParams` syntax is problematic: embed expression directly in SQL:
```sql
WHERE cs.date = '{{ $json.arg1 || $today }}'::date
```

**n8n-MCP operation:** `n8n_update_partial_workflow` with `updateNode` on `Select Schedules`

---

## Fix 3: Show Command — "Format Schedule" Node (3-state display)

**Workflow:** `HFeE52YK9tAzKTpk` | **Node name:** `Format Schedule`
**Node ID:** `23333bcf-24de-43e8-8c16-0ac274362f52`

Update the 3-state grid logic and legend in `jsCode`:

```javascript
// ---- Within the timeslots.forEach / courts.forEach loop ----
// IMPORTANT: Check bot_user_id FIRST — a slot may still have is_available=true
// in club_schedules if the 20-min sync hasn't run since the booking was made.
// The reservations JOIN acts as an immediate override.
if (!slot) {
  message += '⬜ ';
} else if (slot.bot_user_id) {
  message += '🏸 ';  // booked by a bot user (takes priority — handles pre-sync window)
} else if (slot.is_available) {
  message += '✅ ';
} else {
  message += '❌ ';  // booked externally
}

// ---- Updated legend ----
message += '\n✅ Available  🏸 Bot booking  ❌ External';

// ---- Bot Reservations section (append after legend) ----
const botSlots = items.filter(item => item.bot_user_id);
if (botSlots.length > 0) {
  message += '\n\n<b>📋 Bot Reservations:</b>';
  const byUser = {};
  botSlots.forEach(slot => {
    const key = slot.bot_user_id;
    if (!byUser[key]) {
      byUser[key] = {
        name: slot.bot_user_name || slot.bot_username || `user ${slot.bot_user_id}`,
        username: slot.bot_username ? `@${slot.bot_username}` : '',
        slots: []
      };
    }
    const timeDisplay = (slot.time_slot || '').substring(0, 5);
    const courtNum = slot.court_number.replace('Badminton ', '#');
    byUser[key].slots.push(`${courtNum} ${timeDisplay}`);
  });
  Object.values(byUser).forEach(u => {
    const displayName = u.username ? `${u.name} (${u.username})` : u.name;
    message += `\n• <b>${displayName}</b>: ${u.slots.join(', ')}`;
  });
}
```

**n8n-MCP operation:** `n8n_update_partial_workflow` with `updateNode` on `Format Schedule`

---

## Execution Order

1. `n8n_update_partial_workflow` → Fix Book Command `Build Insert Query` jsCode
2. `n8n_validate_workflow` → validate `p5NpS5X1VLPdY3mX`
3. `n8n_update_partial_workflow` → Fix Show Command `Select Schedules` (SQL + operation mode)
4. `n8n_update_partial_workflow` → Fix Show Command `Format Schedule` (jsCode)
5. `n8n_validate_workflow` → validate `HFeE52YK9tAzKTpk`

---

## Verification

1. Make a test booking (date in the future)
2. Query `SELECT * FROM reservations ORDER BY created_at DESC LIMIT 5` — confirm row with `date = 'YYYY-MM-DD'` appears
3. **Immediately** (before the 20-minute sync runs) send `/show <date>` for the booked date — confirm:
   - Booked slot shows `🏸` even though `club_schedules.is_available` may still be `true`
   - Legend shows all 3 states: `✅ Available  🏸 Bot booking  ❌ External`
   - "Bot Reservations" section lists the booker by name
4. Send `/show` for a date with no bot bookings — confirm external bookings show `❌`
5. After the next scheduled sync (wait ≤20 min), send `/show` again — confirm `🏸` still shows (not reverted to `✅`)

---

## Files Modified

| File | Nodes Changed |
|------|--------------|
| `workflows/Book Command.json` (live: `p5NpS5X1VLPdY3mX`) | `Build Insert Query` |
| `workflows/Show Command.json` (live: `HFeE52YK9tAzKTpk`) | `Select Schedules`, `Format Schedule` |

## Log
C:\Users\Codete\.claude\projects\D--Projects-n8n-twoj-badminton-bot\17be6689-3f80-4ce3-a715-b3cd7e8463b7.jsonl