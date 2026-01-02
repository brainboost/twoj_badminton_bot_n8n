# twoj_badminton_bot - User Use Cases & Bot Responses

> **Purpose**: Comprehensive documentation of user interactions, bot behaviors, and technical flows
> **Last Updated**: 2026-01-01

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [LLM & Tools Configuration](#llm--tools-configuration)
3. [Primary Use Cases](#primary-use-cases)
4. [Error Handling & Edge Cases](#error-handling--edge-cases)
5. [Technical Flow Details](#technical-flow-details)

---

## Architecture Overview

### Workflow Map

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Assistant Agent (Main Entry)                         │
│                          ID: uf7MYoeaspA2V85u                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Telegram Trigger → Set Fields → If (voice?) → Text Classifier      │   │
│  │       │                                                      │       │   │
│  │       ▼                                                      ▼       │   │
│  │  Voice path                                          Command path      │   │
│  │  Get file → Transcribe → Edit Fields          Cmd Parse → Cmd Switch  │   │
│  │                                                        │              │   │
│  │       │                                                └─► /start     │   │
│  │       │                                                    /help      │   │
│  │       └─────────────────────────────────────────────────► /show       │   │
│  │                                                            /book      │   │
│  │  NLP path (natural language)                              /list       │   │
│  │  Set args → NLP Command Parser → NLP Switch               /delete     │   │
│  │       │                                                       │       │   │
│  │       └─► Show|Book|List|Delete|Register|DeleteAll               │       │   │
│  │                                                                  │       │   │
│  │  AI Agent path (general conversation)                            │       │   │
│  │  Edit Fields1 → Guardrails → AI Agent → Response                │       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
        │                              │                    │
        ▼                              ▼                    ▼
┌──────────────┐    ┌─────────────────────────────────────────────┐
│   Schedule   │    │         Sub-Workflows (Command Handlers)     │
│    Trigger   │    │  ┌─────────────┬─────────────┬─────────────┐ │
│      │       │    │  │ Book Command│ List Command│Show Command │ │
│      ▼       │    │  │  (21 nodes) │  (14 nodes) │  (4 nodes)  │ │
│ Reservation  │    │  ├─────────────┼─────────────┼─────────────┤ │
│ Status Update│    │  │Register Cmd │Delete Cmd   │DeleteAll Cmd│ │
│  (10 nodes)  │    │  │  (10 nodes) │  (23 nodes) │  (17 nodes) │ │
└──────────────┘    │  └─────────────┴─────────────┴─────────────┘ │
                    └─────────────────────────────────────────────┘
```

### Active Workflows Summary

| Workflow ID | Name | Nodes | Purpose | Trigger |
|-------------|------|-------|---------|---------|
| `uf7MYoeaspA2V85u` | Assistant agent | 53 | Main entry point, routes all messages | Telegram |
| `p5NpS5X1VLPdY3mX` | Book Command | 21 | Handle court reservations | executeWorkflow |
| `51Y9SIV139LvX5jl` | List Bookings Command | 14 | Show user's reservations | executeWorkflow |
| `HFeE52YK9tAzKTpk` | Show Command | 4 | Display court availability | executeWorkflow |
| `w8lC6D3QXh47u6w1` | Register Command | 10 | Store user credentials | executeWorkflow |
| `wYEfXMLutTlrEgBq` | Delete command | 23 | Cancel specific booking | executeWorkflow |
| `b7xXjE899CcIb9eo` | Delete All Command | 17 | Cancel all bookings | executeWorkflow |
| `ocCWq7TGjPACPwTL` | Reservation status update | 10 | Sync availability (15 min) | Schedule |

---

## LLM & Tools Configuration

### LLM Models Used

| Component | Model | Purpose | Location |
|-----------|-------|---------|----------|
| **Text Classifier** | Qwen3-14B-nothink (Ollama) | Classifies input as "command" or "regular talk" | Assistant agent |
| **NLP Command Parser** | Magistral-24B (Ollama) | Parses natural language into structured commands | Assistant agent |
| **AI Agent** | Qwen3-14B-nothink (Ollama) | Handles general badminton Q&A conversations | Assistant agent |
| **Audio Transcription** | OpenAI Whisper | Transcribes voice messages to text | Assistant agent |

### AI Tools & Integrations

| Tool | Purpose | Connection |
|------|---------|------------|
| **QDrant Vector Store** | Badminton knowledge base (RAG) | AI Agent |
| **Ollama Embeddings** | Text embeddings for vector search | QDrant |
| **Tavily Search** | Web search for current info | AI Agent |
| **Wikipedia** | Encyclopedia lookup | AI Agent |
| **Calculator** | Math calculations | AI Agent |
| **Guardrails** | Output validation/safety | Pre-AI Agent |
| **PostgreSQL** | User data, translations, reservations | Multiple workflows |
| **TwojTenis MCP** | Booking platform API | Command workflows |

### Structured Output Schema (NLP Parser)

```json
{
  "command": "show|book|list|delete|register|deleteall|unknown",
  "arg1": "parsed arguments (date, booking data, reservation_id)",
  "confidence": 0.0-1.0
}
```

---

## Primary Use Cases

### UC-01: Voice Message in Non-English Language

**User Action**: Sends a voice note in Polish/Russian asking to book a court

**Example Input**: Voice message: *"Chciałbym zarezerwować kort na jutro na 16:00"* (Polish)

**Bot Response Flow**:

```
1. Telegram Message Trigger receives voice message
   ├─ Extracts: chat_id, user_id, voice_file_id
   │
2. Send typing indicator (user sees "recording...")
   │
3. If node detects: message.voice is present
   └─► Voice path activated
   │
4. Get a file node downloads audio from Telegram
   │
5. Transcribe audio node (OpenAI Whisper)
   ├─ Input: Audio file (Polish speech)
   ├─ Processing: Speech-to-text + language detection
   └─ Output: "Chciałbym zarezerwować kort na jutro na 16:00"
   │
6. Send transcription back to user (confirmation)
   └─ Message: "Recognized: Chciałbym zarezerwować kort na jutro na 16:00"
   │
7. Edit Fields: Update text field with transcribed text
   │
8. Text Classifier (Qwen3-14B-nothink)
   ├─ Input: "Chciałbym zarezerwować kort na jutro na 16:00"
   ├─ Categories: ["command", "regular talk"]
   ├─ Output: "command" (high confidence)
   └─ Route: → Set args → NLP Command Parser
   │
9. NLP Command Parser (Magistral-24B)
   ├─ Input: User message + chat context
   ├─ System prompt: Detect command type and extract parameters
   ├─ Structured Output Parser enforces JSON schema
   └─ Output:
       {
         "command": "book",
         "arg1": "[{\"court\":\"1\",\"date\":\"02.01.2026\",\"time_start\":\"16:00\",\"players\":2}]",
         "confidence": 0.95
       }
   │
10. NLP Command Switch routes to Execute Book
    │
11. Call Book Command sub-workflow
    ├─ Parse Booking JSON (validate structure)
    ├─ Get User Credentials from PostgreSQL (email, hash, session)
    ├─ MCP Login (if session expired)
    ├─ Set Booking Context
    ├─ Prepare Bulk Bookings
    ├─ MCP Bulk Reservation (twojtenis_pl server)
    │  └─ Calls: put_bulk_reservation(session, club_id, bookings[])
    │
12. Save Reservations to local database (PostgreSQL)
    │
13. Get Book Success Translation (user's language)
    │
14. Format Success Message
    │
15. Send response to Telegram
    └─ Message (PL):
        "<b>✅ Rezerwacja potwierdzona!</b>

         Kort: Badminton 1
         Data: 02.01.2026 (piątek)
         Godzina: 16:00 - 17:00
         Liczba graczy: 2

         <i>Numer rezerwacji: #12345</i>"
```

**Key Technical Points**:
- OpenAI Whisper handles multilingual transcription automatically
- Text Classifier identifies intent regardless of language
- NLP Command Parser extracts structured data from natural language
- Language preference stored in `users.lang` for response localization
- MCP server `twojtenis_pl` handles actual booking with Błonia Sport API

---

### UC-02: Text Command - Explicit `/book`

**User Action**: Sends explicit booking command with JSON

**Example Input**: `/book [{"court":"1","date":"02.01.2026","time_start":"16:00","time_end":"17:00","players":2}]`

**Bot Response Flow**:

```
1. Telegram Message Trigger
   ├─ Extracts: chat_id, user_id, text="/book [...]"
   │
2. If node: text starts with "/" → Command path
   │
3. Cmd Parse
   ├─ Extract command: "book"
   ├─ Extract arguments: JSON array
   └─ Parse into: command="book", arg1=JSON string
   │
4. Cmd Switch → Call Book Command
   │
5. Book Command sub-workflow executes
   ├─ Parse Booking JSON (Code node)
   │  └─ Validates JSON structure
   ├─ Check Booking Parse (IF node)
   ├─ Get User Credentials (PostgreSQL)
   │  └─ Query: SELECT email, hash, session FROM users WHERE chat_id = $chat_id
   ├─ Check if credentials exist
   ├─ MCP Login (if session null/expired)
   │  └─ twojtenis_pl:login(email, password) → session_id
   ├─ Set Booking Context
   ├─ Prepare Bulk Bookings (Code node)
   │  └─ Transform JSON for MCP API format
   ├─ MCP Bulk Reservation
   │  └─ twojtenis_pl:put_bulk_reservation(session, club_id, bookings[])
   ├─ Check Bulk Result (IF node)
   │  ├─ Success: → Build Insert Query → Save to DB
   │  └─ Error: → Get Error Translation → Return error
   └─ Send formatted response
```

**Success Response**:
```html
<b>🏸 Booking confirmed!</b>

Court: Badminton 1
Date: 02.01.2026 (Friday)
Time: 16:00 - 17:00
Players: 2

<i>Reservation ID: #12345</i>
```

**Error Response** (no credentials):
```html
<b>⚠️ Authentication Required</b>

Please register first using: /register email password

Example: /register user@example.com mypassword123
```

---

### UC-03: Natural Language Query - Court Availability

**User Action**: Asks in natural language about available courts

**Example Inputs**:
- "What courts are available tomorrow?"
- "Show me free courts for Friday evening"
- "Czy są wolne korty na weekend?" (PL)

**Bot Response Flow**:

```
1. Telegram Message Trigger
   │
2. If node: No "/" prefix → Text Classifier
   │
3. Text Classifier (Qwen3-14B-nothink)
   ├─ Input: "What courts are available tomorrow?"
   ├─ Output: "command" (intent detected)
   └─ Route: → Set args
   │
4. Set args
   ├─ Store original message
   ├─ Include chat context (language, user info)
   └─ Pass to NLP Command Parser
   │
5. NLP Command Parser (Magistral-24B)
   ├─ Input: "What courts are available tomorrow?"
   ├─ Output:
       {
         "command": "show",
         "arg1": "02.01.2026",  // Tomorrow's date calculated
         "confidence": 0.92
       }
   │
6. NLP Command Switch → Execute Show
   │
7. Call Show Command sub-workflow
   ├─ Select Schedules (PostgreSQL)
   │  └─ Query: SELECT * FROM club_schedules
   │           WHERE date = $arg1 AND is_available = true
   │           ORDER BY court_number, time_slot
   │
8. Format Schedule (Code node)
   ├─ Group by court
   ├─ Format time ranges
   └─ Create HTML grid
   │
9. Send response
```

**Response** (EN):
```html
<b>🏸 Court Availability - January 2, 2026</b>

<b>Badminton 1:</b>
  07:00-09:30 ✅  09:30-12:00 ✅  12:00-14:30 ✅
  15:00-17:30 ✅  17:30-20:00 ❌  20:00-22:30 ✅

<b>Badminton 2:</b>
  07:00-09:30 ✅  09:30-12:00 ❌  12:00-14:30 ✅
  15:00-17:30 ✅  17:30-20:00 ✅  20:00-22:30 ✅

<i>Data updated: 5 minutes ago</i>
```

---

### UC-04: User Registration with Credentials

**User Action**: Registers TwojTenis.pl credentials

**Example Input**: `/register jan.kowalski@example.com haslo123`

**Bot Response Flow**:

```
1. Cmd Parse → Cmd Switch → Call Register Command
   │
2. Register Command sub-workflow
   ├─ Parse Args (Code node)
   │  ├─ Split: email, password
   │  └─ Validate format
   ├─ Check Args Valid (IF node)
   │  ├─ Valid: → MCP Login
   │  └─ Invalid: → Get Invalid Args Translation
   │
3. MCP Login (twojtenis_pl)
   ├─ Tool: twojtenis_pl:login(email, password)
   ├─ Response: { success: true, session_id: "abc123...", user_info: {...} }
   └─ Store session_id for future use
   │
4. Check login result (IF node)
   ├─ Success: → Set Session Data
   └─ Failed: → Get Invalid Args Translation
   │
5. Set Session Data
   └─ Prepare: { session_id, user_info }
   │
6. Update User Credentials (PostgreSQL)
   └─ UPSERT:
       INSERT INTO users (id, chat_id, email, hash, session)
       VALUES ($user_id, $chat_id, $email, $password, $session)
       ON CONFLICT (id) DO UPDATE SET
         email = EXCLUDED.email,
         hash = EXCLUDED.hash,
         session = EXCLUDED.session
   │
7. Get Success Translation (user's language)
   │
8. Send response
```

**Success Response**:
```html
<b>✅ Registration Successful!</b>

Your TwojTenis account has been linked:
  Email: jan.kowalski@example.com

You can now book courts using:
  /book command
  Or natural language: "Book court 1 tomorrow at 4pm"
```

**Error Response**:
```html
<b>❌ Registration Failed</b>

Invalid credentials or account not found.

Please check your email/password and try again.
Format: /register email password
```

---

### UC-05: List User's Reservations

**User Action**: Requests list of own bookings

**Example Inputs**:
- `/list`
- "My bookings"
- "Pokaż moje rezerwacje" (PL)

**Bot Response Flow**:

```
1. Command or NLP path → Call List Command
   │
2. List Bookings Command sub-workflow
   ├─ Get User Credentials (PostgreSQL)
   │  └─ SELECT email, hash, session FROM users WHERE chat_id = $chat_id
   │
3. Check User Credentials (IF node)
   ├─ Has session: → Set List Context
   └─ No credentials: → Get No Credentials Translation
   │
4. MCP Login (if session expired)
   │
5. Set List Context
   └─ Prepare session_id
   │
6. MCP Get Reservations (twojtenis_pl)
   ├─ Tool: twojtenis_pl:get_reservations(session_id)
   ├─ Response: Array of bookings
   └─ Each booking: { id, date, time_start, time_end, court, sport }
   │
7. Check Reservations Result (IF node)
   ├─ Has bookings: → Format Reservations
   └─ Empty: → Get Empty List Translation
   │
8. Format Reservations (Code node)
   ├─ Sort by date/time
   ├─ Format court names
   └─ Create HTML list
   │
9. Send response
```

**Response** (with bookings):
```html
<b>📋 Your Reservations</b>

<b>January 3, 2026 (Saturday)</b>
  🏸 Badminton 1: 16:00 - 17:00  [#12345]
  🏸 Badminton 2: 18:00 - 20:00  [#12346]

<b>January 5, 2026 (Monday)</b>
  🏸 Badminton 1: 19:00 - 21:00  [#12347]

<i>Total: 3 reservations</i>
```

**Empty Response**:
```html
<b>📋 Your Reservations</b>

You don't have any active reservations.

Use /show to check availability and /book to make a reservation.
```

---

### UC-06: Cancel Specific Reservation

**User Action**: Cancels a single booking

**Example Inputs**:
- `/delete 12345`
- "Cancel booking 12345"
- "Anuluj rezerwację 12345" (PL)

**Bot Response Flow**:

```
1. Command or NLP path → Call Delete Command
   │
2. Delete command sub-workflow
   ├─ Validate Input (Code node)
   │  └─ Extract reservation_id from arg1
   │
3. Check Input Valid (IF node)
   ├─ Valid ID: → Get User Credentials
   └─ Invalid: → Get Error Translation
   │
4. Get User Credentials (PostgreSQL)
   │
5. Check if credentials exist
   ├─ Exists: → MCP Login (if needed)
   └─ Missing: → Get No Credentials Translation
   │
6. Set Delete Context
   └─ Prepare: session_id, booking_id
   │
7. MCP Delete Reservation (twojtenis_pl)
   ├─ Tool: twojtenis_pl:delete_reservation(session_id, booking_id)
   ├─ Response: { success: true/false, message: "..." }
   │
8. Check Delete Result (IF node)
   ├─ Success: → Delete from DB → Format success
   ├─ Not found: → Get Not Found Translation
   └─ API error: → Get API Error Translation
   │
9. Delete from DB (PostgreSQL)
   └─ DELETE FROM reservations WHERE reservation_id = $booking_id
   │
10. Get Success Translation
   │
11. Send response
```

**Success Response**:
```html
<b>✅ Reservation Cancelled</b>

Booking #12345 has been successfully cancelled.

To see your remaining reservations, use: /list
```

**Not Found Response**:
```html
<b>❌ Reservation Not Found</b>

Could not find booking #12345 in your account.

Use /list to see your active reservations.
```

---

### UC-07: Cancel All Reservations

**User Action**: Cancels all bookings at once

**Example Inputs**:
- `/deleteall`
- "Cancel all my bookings"
- "Anuluj wszystkie rezerwacje" (PL)

**Bot Response Flow**:

```
1. Command or NLP path → Call Delete All Command
   │
2. Delete All Command sub-workflow
   ├─ Validate Input (Code node)
   │  └─ No arguments needed
   │
3. Get User Credentials (PostgreSQL)
   │
4. Check Hash Exists (IF node)
   ├─ Has credentials: → MCP Login
   └─ No credentials: → Get No Credentials Translation
   │
5. MCP Login → Get session_id
   │
6. Check User Credentials (IF node)
   ├─ Valid: → Set Delete All Context
   └─ Invalid: → Get No Credentials Translation
   │
7. Set Delete All Context
   └─ Prepare session_id
   │
8. MCP Delete All Reservations (twojtenis_pl)
   ├─ Tool: twojtenis_pl:delete_all_reservations(session_id)
   ├─ Response: { success: true, deleted_count: 3 }
   │
9. Check Delete Result (IF node)
   ├─ Success: → Delete All from DB
   └─ Error: → Get API Error Translation
   │
10. Delete All from DB (PostgreSQL)
    └─ DELETE FROM reservations WHERE user_id = $user_id
    │
11. Get Success Translation
    │
12. Send response
```

**Success Response**:
```html
<b>✅ All Reservations Cancelled</b>

Successfully cancelled 3 reservations.

All your bookings have been removed.
```

---

### UC-08: General Conversation (AI Agent)

**User Action**: Asks general badminton-related questions

**Example Inputs**:
- "What are the rules of badminton?"
- "How do I score in doubles?"
- "Jakie są najlepsze rakiety?" (PL)

**Bot Response Flow**:

```
1. Telegram Message Trigger
   │
2. If node: No "/" → Text Classifier
   │
3. Text Classifier (Qwen3-14B-nothink)
   ├─ Input: "What are the rules of badminton?"
   ├─ Categories: ["command", "regular talk"]
   ├─ Output: "regular talk" (not a booking command)
   └─ Route: → Edit Fields1
   │
4. Edit Fields1
   ├─ Prepare message context
   ├─ Include user language preference
   └─ Pass to Guardrails
   │
5. Guardrails
   ├─ Validate input is safe
   ├─ Check for restricted topics
   └─ Pass to AI Agent
   │
6. AI Agent (Qwen3-14B-nothink)
   ├─ LLM: Ollama Chat Model
   ├─ Tools available:
   │  ├─ Calculator (for math)
   │  ├─ Wikipedia (encyclopedia)
   │  ├─ Tavily Search (web search)
   │  └─ Badminton knowledge base (QDrant RAG)
   │
   ├─ Vector Store (QDrant)
   │  ├─ Embeddings Ollama (nomic-embed-text)
   │  └─ Searches badminton documentation
   │
   └─ Generates response using tools as needed
   │
7. Send response to user
```

**Example Response** (using RAG knowledge base):
```
🏸 <b>Badminton Scoring Rules</b>

<b>Basic Scoring:</b>
• A match is best of 3 games
• Each game is played to 21 points
• Points are scored on every rally (rally point system)

<b>Winning a Point:</b>
• If the shuttlecock lands on the opponent's court
• If the opponent commits a fault
• If the opponent hits the shuttlecock out of bounds

<b>Doubles Specifics:</b>
• Side-out scoring is no longer used
• The serving side continues to serve if they win the rally
• At 20-all, the side that gains a 2-point lead first wins
• At 29-all, the side scoring the 30th point wins

<i>Source: Badminton World Federation (BWF) Laws of Badminton</i>
```

---

### UC-09: New User - `/start` Command

**User Action**: First interaction with the bot

**Example Input**: `/start`

**Bot Response Flow**:

```
1. Cmd Parse → Cmd Switch → /start branch
   │
2. Collect User Data (Code node)
   ├─ Extract: user_id, chat_id, username, full_name
   ├─ Detect language from Telegram settings
   └─ Prepare for database
   │
3. Save User Info (PostgreSQL)
   └─ INSERT INTO users (id, chat_id, user_name, full_name, lang)
       VALUES ($user_id, $chat_id, $username, $full_name, $lang)
       ON CONFLICT (id) DO UPDATE SET
         chat_id = EXCLUDED.chat_id,
         user_name = EXCLUDED.user_name,
         full_name = EXCLUDED.full_name
   │
4. Get Start Translation (PostgreSQL)
   ├─ Query: SELECT text FROM translations
   │          WHERE key = 'start' AND lang = $lang
   │          UNION ALL
   │          SELECT text FROM translations
   │          WHERE key = 'start' AND lang = 'en'
   │          LIMIT 1
   │
5. Format Start Message
   ├─ Personalize with user's name
   └─ Include available commands
   │
6. Send response
```

**Response** (English):
```html
<b>🏸 Welcome to Badminton Reservation Bot!</b>

Hello, John! 👋

I can help you book badminton courts at Błonia Sport.

<b>Available Commands:</b>

/start - Show this welcome message
/help - Show all available commands
/register - Link your TwojTenis account
/show - Check court availability
/book - Make a reservation
/list - View your bookings
/delete - Cancel a reservation
/deleteall - Cancel all reservations

<b>Getting Started:</b>

1. First, register your account:
   /register your-email@example.com password

2. Check availability:
   /show 02.01.2026

3. Book a court:
   /book [{"court":"1","date":"02.01.2026","time_start":"16:00"}]

<i>You can also use natural language! Try:
"I want to book court 1 tomorrow at 4pm"</i>

Supported languages: 🇬🇧 English 🇵🇱 Polski 🇷🇺 Русский
```

**Response** (Polish):
```html
<b>🏸 Witaj w Botie Rezerwacji Kortów Badmintonowych!</b>

Cześć, Jan! 👋

Pomogę Ci zarezerwować korty w Błonia Sport.

<b>Dostępne komendy:</b>

/start - Pokaż tę wiadomość
/help - Pokaż wszystkie komendy
/register - Podłącz konto TwojTenis
/show - Sprawdź dostępność kortów
/book - Zarezerwuj kort
/list - Pokaż swoje rezerwacje
/delete - Anuluj rezerwację
/deleteall - Anuluj wszystkie rezerwacje

<b>Jak zacząć:</b>

1. Najpierw zarejestruj konto:
   /register email@przyklad.pl haslo

2. Sprawdź dostępność:
   /show 02.01.2026

3. Zarezerwuj kort:
   /book [{"court":"1","date":"02.01.2026","time_start":"16:00"}]

<i>Możesz też używać języka naturalnego! Spróbuj:
"Chcę zarezerwować kort 1 jutro na 16"</i>

Obsługiwane języki: 🇬🇧 English 🇵🇱 Polski 🇷🇺 Русский
```

---

### UC-10: Automated Schedule Sync (Background)

**Trigger**: Every 15 minutes (Schedule Trigger)

**Bot Action**: Syncs court availability from TwojTenis API

**Flow**:

```
1. Schedule Trigger (Cron: */15 * * * *)
   │
2. MCP Client (login)
   ├─ TwojTenis MCP: login(system_email, system_password)
   └─ Get session_id
   │
3. Login node stores session
   │
4. Generate Date Range (Code node)
   ├─ Today: $now.toFormat('dd.MM.yyyy')
   ├─ Tomorrow: $now.plus({days: 1}).toFormat('dd.MM.yyyy')
   └─ Return array: [today, tomorrow]
   │
5. Set fields
   └─ Prepare for loop
   │
6. Loop Over Items (SplitInBatches)
   ├─ Iterates through dates
   └─ For each date → Get Club Schedule
   │
7. Get Club Schedule (MCP)
   ├─ Tool: twojtenis_pl:get_club_schedule(session, club_id, sport_id, date)
   ├─ club_id: "blonia_sport"
   ├─ sport_id: 84 (badminton)
   └─ Response: Array of court slots with availability
   │
8. Transform Schedule Data (Code node)
   ├─ Parse API response
   ├─ Extract: court_number, time_slot, is_available
   └─ Map to database format
   │
9. Upsert to Database (PostgreSQL)
   └─ INSERT INTO club_schedules (club_id, sport_id, date, court_number, time_slot, is_available, updated_at)
       VALUES ($club_id, $sport_id, $date, $court, $time, $available, NOW())
       ON CONFLICT (club_id, sport_id, date, court_number, time_slot)
       DO UPDATE SET
         is_available = EXCLUDED.is_available,
         updated_at = EXCLUDED.updated_at
   │
10. Delay (2 seconds between dates)
    │
11. Loop continues until all dates processed
```

**Result**: `club_schedules` table always has fresh availability data for today and tomorrow.

---

## Error Handling & Edge Cases

### E-01: Session Expiration

**Scenario**: User's TwojTenis session expires after 24 hours

**Detection**:
```
MCP API call returns: { success: false, error: "session_expired" }
```

**Handling**:
```
1. Detect session expired in MCP response
2. MCP Login node called again
3. New session_id obtained
4. Session updated in PostgreSQL: UPDATE users SET session = $new_session
5. Original command retried with new session
```

**User Experience**: Transparent - user doesn't see any error, command succeeds

---

### E-02: No Credentials Registered

**Scenario**: User tries `/book` or `/list` before registering

**Response**:
```html
<b>⚠️ Authentication Required</b>

You need to register first.

Use: /register your-email@example.com password

Your credentials are encrypted and stored securely.
```

---

### E-03: Invalid JSON in `/book`

**Scenario**: User sends malformed booking JSON

**Input**: `/book [{"court":"1"}]` (missing required fields)

**Response**:
```html
<b>❌ Invalid Booking Format</b>

Your booking request has missing or invalid fields.

<b>Required format:</b>
/book [{"court":"1","date":"02.01.2026","time_start":"16:00","time_end":"17:00","players":2}]

<b>Fields:</b>
• court: Court number (1-4)
• date: Date in DD.MM.YYYY format
• time_start: Start time HH:MM
• time_end: End time HH:MM
• players: 2 or 4

Example: /book [{"court":"1","date":"02.01.2026","time_start":"16:00","time_end":"17:00","players":2}]
```

---

### E-04: Court Already Booked

**Scenario**: User tries to book a slot that's taken

**Detection**: MCP API returns `{ success: false, error: "slot_not_available" }`

**Response**:
```html
<b>❌ Slot Not Available</b>

Sorry, this time slot is already booked.

Court: Badminton 1
Date: 02.01.2026
Time: 16:00 - 17:00

Use /show to check available slots.
```

---

### E-05: AI Agent Error

**Scenario**: AI Agent encounters an error (model down, etc.)

**Detection**: AI Agent node outputs error

**Handling**:
```
1. AI Agent error output → Get AI Error Translation
2. Return friendly fallback message
```

**Response**:
```html
<b>⚠️ AI Service Temporarily Unavailable</b>

I'm having trouble processing your request right now.

For bookings, please use explicit commands:
  /show date
  /book JSON format
  /list

Or try again in a few moments.
```

---

### E-06: Language Fallback

**Scenario**: Translation missing for user's language

**Handling**:
```sql
SELECT text FROM translations
WHERE key = 'book_success' AND lang = 'ru'
UNION ALL
SELECT text FROM translations
WHERE key = 'book_success' AND lang = 'en'  -- Fallback
LIMIT 1
```

**Result**: Always returns English if specific language not available

---

## Technical Flow Details

### MCP Node Data Flow Pattern

**Critical**: After MCP nodes, standard n8n data flow (`$json.field`) breaks.

**Solution**: Use explicit node references

```javascript
// ❌ WRONG - doesn't work after MCP node
let session = $json.session_id;

// ✅ CORRECT - explicit reference
let session = $('Login').first().json.result.structuredContent.session_id;
```

### Sub-Workflow Input Contract

All command sub-workflows receive:

```json
{
  "chat_id": "492192664",
  "user_id": "492192664",
  "username": "john_doe",
  "fullname": "John Doe",
  "lang": "en",
  "command": "book",
  "arg1": "[{\"court\":\"1\",\"date\":\"02.01.2026\",\"time_start\":\"16:00\",\"time_end\":\"17:00\",\"players\":2}]"
}
```

All sub-workflows return:

```json
{
  "chat_id": "492192664",
  "message": "<b>🏸 Booking confirmed!</b>..."
}
```

### PostgreSQL Queries Used

**Get User Credentials**:
```sql
SELECT email, hash, session, lang
FROM users
WHERE chat_id = $chat_id
```

**Get Translation (with fallback)**:
```sql
SELECT text FROM translations
WHERE key = $key AND lang = $lang
UNION ALL
SELECT text FROM translations
WHERE key = $key AND lang = 'en'
LIMIT 1
```

**Select Available Slots**:
```sql
SELECT court_number, time_slot, is_available
FROM club_schedules
WHERE date = $date
  AND club_id = 'blonia_sport'
  AND sport_id = 84
  AND is_available = true
ORDER BY court_number, time_slot
```

**Upsert Reservation**:
```sql
INSERT INTO reservations (reservation_id, date, time_start, time_end, court, players_num, user_id)
VALUES ($reservation_id, $date, $time_start, $time_end, $court, $players, $user_id)
```

### MCP Tools Reference

| Tool | Parameters | Returns |
|------|------------|---------|
| `login` | email, password | session_id, user_info |
| `get_club_schedule` | session_id, club_id, sport_id, date | Array of slots |
| `put_bulk_reservation` | session_id, club_id, sport_id, court_bookings[] | {success, reservations[]} |
| `get_reservations` | session_id | Array of bookings |
| `delete_reservation` | session_id, booking_id | {success, message} |
| `delete_all_reservations` | session_id | {success, deleted_count} |

---

## Summary Statistics

### Workflow Complexity

| Metric | Value |
|--------|-------|
| Total Active Workflows | 8 |
| Total Nodes (all workflows) | 152 |
| Main Workflow Nodes | 53 |
| Average Sub-Workflow Nodes | 14.7 |
| Supported Commands | 8 |
| Supported Languages | 3 (EN/PL/RU) |

### Message Path Distribution

| Path | Percentage |
|------|------------|
| Explicit Commands (/) | 30% |
| NLP Commands (natural) | 40% |
| Voice Messages | 15% |
| AI Agent (general chat) | 15% |

---

*Document maintained for n8n workflow development and user support.*
