# Spec: Human-in-the-Loop Confirmation Flow

**Slug:** hitl-confirmation-flow
**Date:** 2026-03-25
**Status:** Draft

---

## Summary

State-changing bot operations (book, delete, delete all, play, register) execute immediately after parsing user input, with no chance to catch misinterpreted parameters. This spec introduces a confirmation step: after parsing, the bot sends a summary with ✅ Confirm / ❌ Cancel inline keyboard buttons. The operation executes only after the user taps Confirm.

---

## Research Findings: Telegram Inline Keyboards in n8n

**Does n8n support inline keyboards? Yes, natively.**

The `n8n-nodes-base.telegram` node (typeVersion 1.2) exposes a `replyMarkup` parameter with an `"inlineKeyboard"` option. Each button has:
- `text` — label shown to user
- `additionalFields.callback_data` — string (1–64 bytes) sent back on press

**Does the Telegram Trigger support `callback_query`? Yes.**

`n8n-nodes-base.telegramTrigger` lists `callback_query` as an explicit "Trigger On" event option.

**Dynamic keyboards limitation:** The native Telegram node only supports static (hard-coded) button counts. For dynamically computed buttons, use an HTTP Request node calling `api.telegram.org/bot<TOKEN>/sendMessage` directly with a `reply_markup` JSON body.

**For this HITL feature, only static 2-button keyboards (Confirm / Cancel) are needed — the native n8n Telegram node is sufficient.**

**Answering the callback (mandatory):** After a `callback_query` event, Telegram shows a loading spinner on the button until `answerCallbackQuery` is called. The Telegram node supports this via `resource: "callback"`, `operation: "answerQuery"`.

---

## Architecture Overview

```
User sends /book (or NLP equivalent)
        │
        ▼
Sub-workflow parses parameters
        │
        ▼
Check confirmed flag
   NOT confirmed ──────────────────────────────────────────────────────────┐
        │                                                                    │
        ▼                                                                    │
Store pending action in pending_confirmations (PG)                          │
        │                                                                    │
        ▼                                                                    │
Send confirmation message with [✅ Confirm] [❌ Cancel] inline keyboard      │
        │                                                                    │
        ▼                                                                    │
EXIT sub-workflow (no execution yet)                                         │
                                                                             │
[User taps ✅ Confirm or ❌ Cancel]                                          │
        │                                                                    │
        ▼                                                                    │
NEW: Confirmation Handler Workflow (telegramTrigger → callback_query)        │
        │                                                                    │
        ├──parse confirmation_id from callback_data                          │
        ├──lookup pending_confirmations in PG                                │
        ├──answer callback query (remove spinner)                            │
        ├──delete pending record from PG                                     │
        │                                                                    │
   confirmed? ─YES──▶ Call original sub-workflow with confirmed=true  ◀─────┘
        │                     │
       NO                     ▼
        │              Execute actual operation (MCP, DB writes, etc.)
        ▼              Send success message
   Send "Cancelled" message
```

---

## Node Pipeline: Confirmation Handler Workflow (new)

| # | Node Name | Type | Purpose | Key Parameters |
|---|-----------|------|---------|----------------|
| 1 | Telegram Callback Trigger | `telegramTrigger` | Entry point for button presses | triggerOn: `callback_query` |
| 2 | Extract Callback Data | `set` | Parse action and confirmation_id | See expressions below |
| 3 | Get Pending Confirmation | `postgres` | Load pending action from DB | SELECT by confirmation_id |
| 4 | Check Found & Valid | `if` | Expired or not found? | `found === true && not expired` |
| 5 | Answer Callback Query | `telegram` | Remove loading spinner | resource: callback, operation: answerQuery |
| 6 | Delete Pending Record | `postgres` | Clean up pending_confirmations | DELETE WHERE confirmation_id = $1 |
| 7 | Route by Action | `switch` | Confirm vs Cancel | value: `$json.action` |
| 8 | Call Book Command | `executeWorkflow` | Execute confirmed book | workflowId: p5NpS5X1VLPdY3mX |
| 9 | Call Delete Command | `executeWorkflow` | Execute confirmed delete | workflowId: wYEfXMLutTlrEgBq |
| 10 | Call Delete All Command | `executeWorkflow` | Execute confirmed deleteall | workflowId: b7xXjE899CcIb9eo |
| 11 | Call Play Command | `executeWorkflow` | Execute confirmed play | workflowId: CRCVg9hV0gdk0WNb |
| 12 | Call Register Command | `executeWorkflow` | Execute confirmed register | workflowId: w8lC6D3QXh47u6w1 |
| 13 | Send Cancelled Message | `telegram` | Inform user of cancellation | chatId from pending payload |
| 14 | Answer Expired Callback | `telegram` | Handle stale button press | answerQuery with "Expired" text |

---

## Database: New Table `pending_confirmations`

```sql
CREATE TABLE pending_confirmations (
    id               SERIAL PRIMARY KEY,
    confirmation_id  VARCHAR(20) NOT NULL UNIQUE,   -- 16-char hex token
    chat_id          VARCHAR(50) NOT NULL,
    user_id          VARCHAR(50) NOT NULL,
    lang             VARCHAR(10) DEFAULT 'en',
    command          VARCHAR(50) NOT NULL,           -- 'book','delete','deleteall','play','register'
    payload          JSONB NOT NULL,                 -- Full original sub-workflow input
    message_id       INTEGER,                        -- Telegram message_id of confirmation msg
    created_at       TIMESTAMP DEFAULT NOW(),
    expires_at       TIMESTAMP DEFAULT (NOW() + INTERVAL '15 minutes')
);

-- Index for fast lookup by token
CREATE INDEX idx_pending_conf_id ON pending_confirmations(confirmation_id);

-- Index for cleanup of expired records
CREATE INDEX idx_pending_conf_expires ON pending_confirmations(expires_at);
```

**Design notes:**
- `payload` stores the complete sub-workflow input JSON (chat_id, user_id, lang, command, arg1). On confirm, this is passed directly to the sub-workflow with `confirmed: true` added.
- `expires_at` is 15 minutes from creation. Stale confirmations are ignored by the handler and cleaned up periodically.
- `message_id` allows editing the original message (e.g., replacing buttons with "Confirmed!" text) via `editMessageText`.

---

## Sub-Workflow Interface Changes

Each affected sub-workflow receives one new input field:

```json
{
  "chat_id": "...",
  "user_id": "...",
  "lang": "en",
  "command": "book",
  "arg1": "...",
  "confirmed": false    // ← NEW: boolean, default false
}
```

### Modified Flow in Each Sub-Workflow

At the very beginning (after the existing parameter-parse step), insert:

```
Parse Parameters
      │
      ▼
Check "confirmed" flag (IF node)
  confirmed === true ──────▶ [existing execution logic — unchanged]
      │
  confirmed !== true (default)
      │
      ▼
Generate confirmation_id (Code node)
      │
      ▼
Build confirmation message (Code node)
      │
      ▼
Store Pending Confirmation (PG node)
      │
      ▼
Send Confirmation Keyboard (Telegram node)
      │
      ▼
EXIT (no-op return)
```

### Code: Generate Confirmation ID

In a Code node named `Generate Confirmation ID`:

```javascript
const crypto = require('crypto');
const confirmation_id = crypto.randomBytes(8).toString('hex'); // 16 hex chars
return [{ json: { ...$input.first().json, confirmation_id } }];
```

### Telegram Node: Send Confirmation Keyboard

Node type: `n8n-nodes-base.telegram`
Operation: `sendMessage`

```json
{
  "resource": "message",
  "operation": "sendMessage",
  "chatId": {
    "__rl": true,
    "mode": "expression",
    "value": "={{ $json.chat_id }}"
  },
  "text": "={{ $json.confirmation_message }}",
  "additionalFields": {
    "parse_mode": "HTML",
    "reply_markup": "inlineKeyboard"
  },
  "inlineKeyboard": {
    "rows": [
      {
        "row": {
          "buttons": [
            {
              "text": "✅ Confirm",
              "additionalFields": {
                "callback_data": "={{ 'confirm:' + $json.confirmation_id }}"
              }
            },
            {
              "text": "❌ Cancel",
              "additionalFields": {
                "callback_data": "={{ 'cancel:' + $json.confirmation_id }}"
              }
            }
          ]
        }
      }
    ]
  }
}
```

### Store Pending Confirmation (PG node)

```sql
INSERT INTO pending_confirmations
  (confirmation_id, chat_id, user_id, lang, command, payload)
VALUES ($1, $2, $3, $4, $5, $6::jsonb)
```

Parameters (in order):
1. `={{ $json.confirmation_id }}`
2. `={{ $json.chat_id }}`
3. `={{ $json.user_id }}`
4. `={{ $json.lang }}`
5. `={{ $json.command }}`
6. `={{ JSON.stringify($json.original_input) }}` — original workflow input

---

## Confirmation Handler Workflow: Key Nodes

### Node 2: Extract Callback Data (Set node)

```javascript
// In a Code node or Set node with expressions:
const data = $json.callback_query.data;            // "confirm:a1b2c3d4"
const [action, confirmation_id] = data.split(':');

return [{
  json: {
    action,                                          // "confirm" or "cancel"
    confirmation_id,                                 // "a1b2c3d4e5f6g7h8"
    callback_query_id: $json.callback_query.id,
    chat_id: String($json.callback_query.message.chat.id),
    user_id: String($json.callback_query.from.id),
    message_id: $json.callback_query.message.message_id
  }
}];
```

### Node 3: Get Pending Confirmation (PG)

```sql
SELECT * FROM pending_confirmations
WHERE confirmation_id = $1
  AND expires_at > NOW()
```

Parameter: `={{ $json.confirmation_id }}`

Set `continueOnFail: true` and connect to the "Check Found" IF node.

### Node 4: Check Found & Valid (IF node)

Condition: `{{ $items().length > 0 }}` (true branch = found and valid)

### Node 5: Answer Callback Query (Telegram node)

```json
{
  "resource": "callback",
  "operation": "answerQuery",
  "queryId": "={{ $('Extract Callback Data').first().json.callback_query_id }}"
}
```

Run this BEFORE routing to Confirm/Cancel to remove the spinner immediately.

### Node 6: Delete Pending Record (PG)

```sql
DELETE FROM pending_confirmations WHERE confirmation_id = $1
```

Parameter: `={{ $('Extract Callback Data').first().json.confirmation_id }}`

### Node 7: Route by Action (Switch node)

```
Value: ={{ $('Extract Callback Data').first().json.action }}
Rules:
  "confirm"  → [Confirm branch]
  "cancel"   → [Cancel branch]
```

### Confirm Branch: Call Sub-Workflow (executeWorkflow node)

The pending `payload` column contains the original sub-workflow input. Add `confirmed: true`:

```javascript
// Code node: Build Confirmed Input
const pending = $('Get Pending Confirmation').first().json;
const payload = pending.payload;  // parsed JSONB
return [{
  json: {
    ...payload,
    confirmed: true
  }
}];
```

Then call the appropriate sub-workflow using a Switch on `pending.command`:

| command value | Workflow ID |
|---|---|
| `book` | `p5NpS5X1VLPdY3mX` |
| `delete` | `wYEfXMLutTlrEgBq` |
| `deleteall` | `b7xXjE899CcIb9eo` |
| `play` | `CRCVg9hV0gdk0WNb` |
| `register` | `w8lC6D3QXh47u6w1` |

### Optional: Edit Confirmation Message After Action

After success/cancel, edit the original Telegram message to remove the keyboard and show status:

Telegram node → `editMessageText`:
```json
{
  "resource": "message",
  "operation": "editMessageText",
  "messageId": "={{ $('Extract Callback Data').first().json.message_id }}",
  "chatId": { "__rl": true, "mode": "expression", "value": "={{ $('Extract Callback Data').first().json.chat_id }}" },
  "text": "✅ Confirmed — executing..."
}
```

---

## Confirmation Messages Per Command

### Book Command

```
📋 <b>Confirm Booking</b>

🏸 <b>Court:</b> {{ court }}
📅 <b>Date:</b> {{ date }}
⏰ <b>Time:</b> {{ time_start }} – {{ time_end }}
👥 <b>Players:</b> {{ players_num }}

Tap ✅ to book or ❌ to cancel.
```

For multiple slots:
```
📋 <b>Confirm Booking ({{ count }} slots)</b>

{{ slot 1 summary }}
{{ slot 2 summary }}
...
```

### Delete Command

```
🗑 <b>Confirm Cancellation</b>

📅 <b>Date:</b> {{ date }}
⏰ <b>Time:</b> {{ time_start }}
🏸 <b>Court:</b> {{ court }}

This action cannot be undone.
Tap ✅ to cancel or ❌ to keep it.
```

### Delete All Command

```
⚠️ <b>Confirm Cancel ALL Reservations</b>

This will cancel ALL your upcoming reservations.
This action cannot be undone.

Tap ✅ to cancel all or ❌ to keep them.
```

### Register Command

```
🔐 <b>Confirm Registration</b>

📧 <b>Email:</b> {{ email }}

Your credentials will be saved for automatic login.
Tap ✅ to confirm or ❌ to cancel.
```

_(Do NOT echo password in confirmation message.)_

### Play Command

```
🏸 <b>Confirm Play Session</b>

📅 <b>Date:</b> {{ date }}
⏰ <b>Time:</b> {{ time }}
👥 <b>Players needed:</b> {{ players_needed }}

Tap ✅ to register or ❌ to cancel.
```

---

## Translation Keys to Add

New keys in `translations` table (EN/PL/RU):

| Key | Description |
|-----|-------------|
| `confirm_cancelled` | "Operation cancelled." |
| `confirm_expired` | "This confirmation has expired. Please send the command again." |
| `confirm_book` | Template for book confirmation (use `{court}`, `{date}`, `{time}` placeholders) |
| `confirm_delete` | Template for delete confirmation |
| `confirm_deleteall` | Template for delete-all confirmation |
| `confirm_register` | Template for register confirmation |
| `confirm_play` | Template for play confirmation |
| `confirm_yes` | "✅ Confirm" |
| `confirm_no` | "❌ Cancel" |

---

## Credentials Required

| Credential | Type | Used by |
|---|---|---|
| `twoj_badminton_bot` | Telegram API | Confirmation Handler Trigger + all Telegram nodes |
| `3SDluWLUa1vIU50a` | PostgreSQL | Store/retrieve/delete pending_confirmations |

---

## Error Handling

| Scenario | Handling |
|---|---|
| Callback arrives after 15-min expiry | `expires_at > NOW()` check fails → Answer callback with "Expired" text → send message to user |
| Stale callbacks from restarted bot | Same expiry check handles this |
| DB write fails (store pending) | `continueOnFail: true` → send "Something went wrong" message |
| Sub-workflow execution fails after confirm | Sub-workflow sends its own error message (existing behavior) |
| User clicks button twice | Second click: `confirmation_id` already deleted → treated as expired |

### Periodic Cleanup of Expired Records

Add to `Reservation status update` workflow (or a new scheduled workflow):

```sql
DELETE FROM pending_confirmations WHERE expires_at < NOW();
```

Run every 15 minutes alongside the existing availability sync.

---

## Implementation Order

### Phase 1: Database
1. Create `pending_confirmations` table (run SQL via `mcp__postgres__execute_sql`)
2. Add translations for new keys

### Phase 2: Sub-Workflow Modifications (one at a time)

For each affected command sub-workflow:

1. Add `confirmed` input parameter check (IF node at top)
2. Insert `Generate Confirmation ID` → `Build Confirmation Message` → `Store Pending` → `Send Keyboard` nodes on the "not confirmed" branch
3. Connect existing execution logic to the "confirmed=true" branch
4. Validate with `n8n_validate_workflow`

**Order:** Delete All first (highest risk) → Delete → Book → Register → Play

### Phase 3: Confirmation Handler Workflow (new)
1. Create new workflow via `n8n_create_workflow`
2. Add `telegramTrigger` on `callback_query`
3. Wire all nodes per pipeline above
4. Activate workflow

### Phase 4: Test

1. Send `/deleteall` → verify confirmation message with buttons appears
2. Tap Cancel → verify "Cancelled" message, no deletions
3. Tap Confirm → verify deletion executes, success message sent
4. Wait 6 minutes, tap stale button → verify "Expired" response
5. Repeat for `/book`, `/delete`, `/register`, `/play`

---

## Files to Modify

| Workflow | ID | Change |
|---|---|---|
| Book Command | `p5NpS5X1VLPdY3mX` | Add HITL branch at beginning |
| Delete Command | `wYEfXMLutTlrEgBq` | Add HITL branch at beginning |
| Delete All Command | `b7xXjE899CcIb9eo` | Add HITL branch at beginning |
| Play Command | `CRCVg9hV0gdk0WNb` | Add HITL branch at beginning |
| Register Command | `w8lC6D3QXh47u6w1` | Add HITL branch at beginning |
| Reservation status update | `ocCWq7TGjPACPwTL` | Add periodic cleanup query |
| _(new)_ Confirmation Handler | — | Create from scratch |

---

## Known Constraints

- Telegram `callback_data` is limited to **64 bytes**. The format `confirm:a1b2c3d4e5f6g7h8` is 26 bytes — safely within limit.
- Inline keyboards with **static 2 buttons** use the native n8n Telegram node. No HTTP Request workaround needed.
- The Confirmation Handler must be a **separate workflow** with its own `telegramTrigger` — it cannot share the main assistant agent's trigger (n8n triggers are 1-per-workflow).
- Both the main assistant agent trigger AND the new Confirmation Handler trigger are registered as Telegram webhooks. Telegram sends **all updates** to a single webhook URL per bot — n8n handles routing internally via separate trigger webhook paths. Each `telegramTrigger` node registers a distinct webhook path with Telegram's `setWebhook` using the `allowed_updates` filter. **Action required:** Verify after creating the Confirmation Handler workflow that both workflows receive their respective update types (message vs callback_query).
