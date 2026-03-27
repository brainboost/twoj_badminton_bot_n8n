# n8n Rules & Notes

## PostgreSQL executeQuery Parameters

> ⚠️ RECURRING MISTAKE: This rule is violated often when building new workflows. Every time you add a Postgres `executeQuery` node, verify: is `queryReplacement` inside `options`?

The correct field name for parameterized query values in the PostgreSQL node's `executeQuery` operation is `queryReplacement`, placed inside `options`.

**Correct format (single param):**
```json
{
  "operation": "executeQuery",
  "query": "SELECT * FROM table WHERE id = $1",
  "options": {
    "queryReplacement": "={{ $json.myValue }}"
  }
}
```

**Correct format (multiple params — comma-separated expressions):**
```json
{
  "operation": "executeQuery",
  "query": "INSERT INTO table (a, b, c) VALUES ($1, $2, $3)",
  "options": {
    "queryReplacement": "={{ $json.a }},{{ $json.b }},{{ $json.c }}"
  }
}
```

**IMPORTANT**: For multiple params, use comma-separated `{{ }}` expressions — the FIRST has `=`, the rest do NOT:
`={{ val1 }},{{ val2 }},{{ val3 }}`

The array format `={{ [val1, val2, val3] }}` does NOT work reliably — do NOT use it.

**For JSONB columns**: pass `{{ $json }}` (the whole item object) — n8n/pg driver handles serialization automatically:
```
"queryReplacement": "={{ $json.id }},{{ $json.name }},{{ $json }}"
                                                         ^^^^^^^^ becomes JSONB
```

Wrong field names that silently fail: `queryParams`, `parameters`, `values`.
Wrong location (silently ignored): top-level `parameters.queryReplacement` — must be inside `options`.

## Telegram Node — sendMessage with Inline Keyboard

**`chatId`**: use plain string expression, NOT `__rl` resource locator format:
```json
"chatId": "={{ $json.chat_id }}"
```
The `__rl` object format causes "chat not found" errors even with a valid chat_id.

> ⚠️ RECURRING MISTAKE: This rule applies to **ALL** Telegram node operations, not just `sendMessage` — including `answerQuery`, `editMessageText`, and any node inside callback handler workflows. Specs and templates are often drafted with `__rl` format — always override to plain string when implementing.

**`replyMarkup` and `inlineKeyboard`**: must be TOP-LEVEL parameters, NOT inside `additionalFields`. n8n silently overrides them to `"none"` if placed inside `additionalFields`:
```json
{
  "chatId": "={{ $json.chat_id }}",
  "text": "={{ $json.text }}",
  "replyMarkup": "inlineKeyboard",
  "inlineKeyboard": {
    "rows": [
      {
        "row": {
          "buttons": [
            { "text": "✅ Confirm", "additionalFields": { "callbackData": "={{ 'confirm:' + $json.id }}" } },
            { "text": "❌ Cancel",  "additionalFields": { "callbackData": "={{ 'cancel:'  + $json.id }}" } }
          ]
        }
      }
    ]
  },
  "additionalFields": { "parse_mode": "HTML" }
}
```

Button callback field is **`callback_data`** (snake_case) — NOT `callbackData` (camelCase). It stays inside the button's own `additionalFields`:
```
inlineKeyboard.rows[].row.buttons[].additionalFields.callback_data
```

---

## Telegram Callback Query Handler Patterns

For workflows triggered by `callback_query` (button presses), the `telegramTrigger` delivers a nested structure. Access fields like this:

```javascript
$json.callback_query.data                    // "confirm:a1b2c3d4" — the button's callback_data string
$json.callback_query.id                      // query ID — needed for answerQuery (removing spinner)
$json.callback_query.from.id                 // Telegram user ID who pressed the button
$json.callback_query.message.chat.id         // chat to reply to (convert to string with String())
$json.callback_query.message.message_id      // original message ID (for editMessageText)
```

**answerQuery node** — removes the loading spinner from the button. Must be called immediately after receiving the callback, before any routing logic:
```json
{
  "resource": "callback",
  "operation": "answerQuery",
  "queryId": "={{ $('Extract Callback Data').first().json.callback_query_id }}"
}
```
- Resource is `"callback"` (NOT `"message"`)
- `chatId` is NOT needed on this node
- If not called, Telegram shows a loading spinner on the button indefinitely

**editMessageText node** — replaces confirmation message text and removes the inline keyboard:
```json
{
  "resource": "message",
  "operation": "editMessageText",
  "chatId": "={{ $json.chat_id }}",
  "messageId": "={{ $json.message_id }}",
  "text": "✅ Confirmed — executing..."
}
```
- `chatId` must be plain string (not `__rl`) — same rule as sendMessage
- Replacing the text automatically removes the inline keyboard buttons
