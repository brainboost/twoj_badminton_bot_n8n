# CLAUDE.md - twoj_badminton_bot Development Guide

> **Purpose**: Technical reference for Claude AI assistants working on this n8n-based Telegram bot project.
> **Last Updated**: 2026-01-01

---
# Your Role

You are the expert n8n Workflow automation developer using the n8n-mcp tools. Use SKILLS available to build and maintain n8n workflows within the project boundaries.

### Files to read first
 - `n8n-rules.md` - additional rules and notes regarding n8n workflows, updateable. Use it to save quick tips and hints or important notes for future tasks  

## Project Overview

**twoj_badminton_bot** is a multilingual (EN/PL/RU) Telegram bot for badminton court reservations at Błonia Sport club in Kraków, Poland. It integrates with TwojTenis.pl booking platform via MCP (Model Context Protocol) server.

### Architecture

```
┌─────────────────┐     ┌──────────────────────────┐     ┌─────────────────┐
│  Telegram Bot   │────▶│  n8n Workflows (8 total) │────▶│   PostgreSQL    │
│  @twoj_badminton│     │  - Assistant Agent       │     │   (club_schedules)│
│       _bot      │     │  - Command Sub-workflows │     └─────────────────┘
└─────────────────┘     └──────────────────────────┘
                               │
                               ▼
                        ┌──────────────────┐
                        │  TwojTenis MCP   │  ← Python MCP server
                        │  Server (STDIO)  │     twojtenis_mcp
                        └──────────────────┘
```

### Tech Stack
- **n8n**: Workflow automation (self-hosted via Portainer)
- **PostgreSQL 16**: Data storage (Docker container `club-schedules-db`)
- **TwojTenis MCP Server**: Python-based MCP for booking API
- **LLMs**: Qwen3-14B-nothink (via Ollama) for NLP command parsing and chat, Magistral-24B for NLP Command Parser
- **Vector DB**: QDrant vector store for badminton knowledge base (RAG)

---

## Workflow Architecture

### Active Workflows (n8n Instance)

| ID | Name | Purpose | Trigger |
|----|------|---------|---------|
| `uf7MYoeaspA2V85u` | **Assistant agent** | Main entry point, routes messages | Telegram Message Trigger |
| `p5NpS5X1VLPdY3mX` | Book Command | `/book` - court reservations | executeWorkflowTrigger |
| `51Y9SIV139LvX5jl` | List Bookings Command | `/list` - show user reservations | executeWorkflowTrigger |
| `HFeE52YK9tAzKTpk` | Show Command | `/show` - court availability | executeWorkflowTrigger |
| `w8lC6D3QXh47u6w1` | Register Command | `/register` - save credentials | executeWorkflowTrigger |
| `wYEfXMLutTlrEgBq` | Delete Command | `/delete` - cancel reservation | executeWorkflowTrigger |
| `b7xXjE899CcIb9eo` | Delete All Command | `/deleteall` - cancel all | executeWorkflowTrigger |
| `ocCWq7TGjPACPwTL` | Reservation status update | Scheduled availability sync | Schedule Trigger (15 min) |

### Message Flow (Assistant Agent)

```
Telegram Message
    │
    ▼
Set fields (extract chat_id, text, user_id)
    │
    ▼
If (voice message?) ──Yes──▶ Get file → Transcribe → Edit Fields
    │                                        │
    No                                       │
    │                                        │
    ▼                                        ▼
If command (starts with /) ◄────────────────┘
    │
    ├─Yes─▶ Cmd Parse → Cmd Switch ──▶ [/start, /help, /show, /book, /list, /delete, /register, /deleteall]
    │                                         │
    No                                        ▼
    │                              Call <Command> sub-workflow
    ▼
Text Classifier (Qwen3)
    │
    ├─"command"─▶ Set args → NLP Command Parser → NLP Command Switch → Execute <command>
    │
    └─"regular talk"─▶ Edit Fields1 → Guardrails → AI Agent → Telegram
```

### Two Input Paths for Commands

1. **Explicit Commands**: `/show 15.01.2025` → Cmd Parse → Cmd Switch → Call Show Command
2. **NLP Commands**: "What's available tomorrow?" → Text Classifier → NLP Command Parser → Execute Show

---

## Database Schema

### Tables

```sql
-- users: Telegram users + TwojTenis credentials
users (
    id VARCHAR(50) PK,        -- Telegram user ID
    chat_id VARCHAR(50),      -- Telegram chat ID
    user_name VARCHAR(100),   -- @username
    full_name VARCHAR(200),   -- Display name
    email VARCHAR(255),       -- TwojTenis email
    hash VARCHAR(255),        -- TwojTenis password (plain text - consider encrypting)
    session VARCHAR(500),     -- TwojTenis session token (stored after login)
    created TIMESTAMP
)

-- translations: i18n messages (key-lang-text pattern)
translations (
    id SERIAL PK,
    key VARCHAR(100),         -- e.g., 'help', 'book_success', 'delete_confirm'
    lang VARCHAR(10),         -- 'en', 'pl', 'ru'
    text TEXT,                -- Message template (supports HTML)
    UNIQUE(key, lang)
)

-- reservations: User bookings (local mirror)
reservations (
    id SERIAL PK,
    reservation_id VARCHAR(100),  -- TwojTenis booking ID (from MCP response)
    date DATE,
    time_start VARCHAR(5),        -- 'HH:MM'
    time_end VARCHAR(5),
    court VARCHAR(50),
    players_num INTEGER,          -- 2 or 4
    user_id VARCHAR(50) FK,
    notes TEXT,
    created_at TIMESTAMP
)

-- club_schedules: Court availability cache
club_schedules (
    id SERIAL PK,
    club_id VARCHAR(100),         -- 'blonia_sport'
    sport_id INTEGER,             -- 84 = badminton, 70 = tennis
    date DATE,
    court_number VARCHAR(50),     -- 'Badminton 1', 'Badminton 2', etc.
    time_slot TIME,               -- 30-min slots: '07:00', '07:30', ...
    is_available BOOLEAN,
    user_id INTEGER,              -- Reserved by (TwojTenis user ID)
    updated_at TIMESTAMP,
    UNIQUE(club_id, sport_id, date, court_number, time_slot)
)
```

---

## MCP Server Integration

### TwojTenis MCP Tools

Available tools via `twojtenis_pl:*` MCP server:

| Tool | Purpose | Key Parameters |
|------|---------|----------------|
| `login` | Authenticate user | email, password → session_id |
| `get_club_schedule` | Fetch availability | session_id, club_id, sport_id, date (DD.MM.YYYY) |
| `put_reservation` | Book single slot | session_id, club_id, court_number, date, start_time, end_time, sport_id |
| `put_bulk_reservation` | Book multiple slots | session_id, club_id, sport_id, court_bookings[] |
| `get_reservations` | List user bookings | session_id |
| `delete_reservation` | Cancel booking | session_id, booking_id |
| `delete_all_reservations` | Cancel all bookings | session_id |

### MCP Node Data Flow Issue (CRITICAL)

**Problem**: MCP nodes break standard n8n data flow. After an MCP node, `$json.field` returns undefined.

**Solution**: Use explicit node references:
```javascript
// ❌ WRONG - doesn't work after MCP node
$json.session_id

// ✅ CORRECT - explicit reference
$('Set Context').first().json.session_id
$('MCP Login').first().json.result.structuredContent.session_id
```

### Session-Based Authentication

Sessions are stored in `users.session` column after `/register` command:
1. User sends `/register email password`
2. Register Command calls MCP `login` → gets `session_id`
3. Session stored in DB: `UPDATE users SET session = $session_id WHERE chat_id = $chat_id`
4. Subsequent commands (book/list/delete) retrieve session from DB instead of re-logging

---

## Sub-Workflow Interface Contract

All command sub-workflows receive standardized input via `executeWorkflowTrigger`:

```json
{
  "chat_id": "492192664",
  "user_id": "492192664",
  "username": "username",
  "fullname": "Name Surname",
  "lang": "en",
  "command": "book",
  "arg1": "[{\"court\":\"1\", \"date\":\"27.12.2025\", \"time_start\":\"16:00\", ...}]"
}
```

All sub-workflows MUST return:

```json
{
  "chat_id": "492192664",
  "message": "<b>🏸 Booking confirmed!</b>\n..."
}
```

The main workflow sends `message` to Telegram using `chat_id`.

---

## LLM Configuration

### Text Classifier (Intent Detection)
- **Model**: Qwen3-14B or Gemma3 (via Ollama)
- **Categories**: `command`, `regular talk`
- **Purpose**: Route natural language requests vs. general conversation

### NLP Command Parser
- **Model**: Qwen3-14B (via Ollama)
- **Output Format**: Structured JSON via `outputParserStructured`
- **Schema**:
```json
{
  "command": "show|book|list|delete|register|deleteall|unknown",
  "arg1": "parsed date/booking data/reservation_id",
  "confidence": 0.0-1.0
}
```

### AI Agent (General Conversation)
- **Model**: Qwen3-14B (via Ollama)
- **Tools**: Calculator, Wikipedia, Tavily Search, Badminton Knowledge Base (QDrant)
- **System Prompt**: Multilingual badminton assistant with tool usage guidelines

---

## Key Technical Learnings

### 1. Translations Table: Use Actual Line Breaks
```sql
-- ❌ WRONG - shows literal "\n"
INSERT INTO translations (key, lang, text) VALUES ('help', 'en', 'Line 1\nLine 2');

-- ✅ CORRECT - use actual newlines
INSERT INTO translations (key, lang, text) VALUES ('help', 'en', 'Line 1
Line 2');
```

### 2. MCP Node References (Critical)
After MCP nodes, data flow breaks. Always use explicit node references:
```javascript
$('NodeName').first().json.field
```

### 3. Telegram Node Format
Use resource locator format for `chatId`:
```json
{
  "chatId": {
    "__rl": true,
    "mode": "expression",
    "value": "={{ $json.chat_id }}"
  },
  "operation": "sendMessage"
}
```

### 4. Bulk Operations vs. Loops
Prefer `put_bulk_reservation` over loops with `put_reservation`:
- **Before**: N API calls + N×2s delays
- **After**: 1 API call, no delays

### 5. addConnection Syntax for n8n-MCP
```json
{
  "type": "addConnection",
  "source": "node-name",
  "target": "target-node-name",
  "sourcePort": "main",
  "targetPort": "main",
  "branch": "true"  // For IF nodes: "true" or "false"
}
```

---

## Development Workflow

### Making Changes
1. **Backup first**: Save/publish workflow in n8n before changes
2. **Use n8n-MCP tools**: `n8n_get_workflow`, `n8n_update_partial_workflow`
3. **Validate**: `n8n_validate_workflow` after changes
4. **Test**: Use pinned data in workflows for reproducible tests

### Credential IDs (Production)
| Name | ID |
|------|----|
| Telegram API | `twoj_badminton_bot` |
| PostgreSQL | `3SDluWLUa1vIU50a` |
| TwojTenis MCP | `G9CyzT9PT67tg4V7` |
| Ollama | `ollama_credentials` |
| QDrant | `qdrant_credentials` |

### Common n8n-MCP Operations

```javascript
// Get workflow structure
n8n_get_workflow({ id: "uf7MYoeaspA2V85u", mode: "structure" })

// Update node
n8n_update_partial_workflow({
  id: "workflow-id",
  operations: [{
    type: "updateNode",
    nodeId: "node-id",
    updates: { parameters: {...} }
  }]
})

// Add connection (IF node TRUE branch)
n8n_update_partial_workflow({
  id: "workflow-id",
  operations: [{
    type: "addConnection",
    source: "If Node",
    target: "Handler",
    sourcePort: "main",
    targetPort: "main",
    branch: "true"
  }]
})
```

---

## Completed Tasks Summary

### Phase 1: Core Bot Setup
- [x] Database schema (users, translations, club_schedules)
- [x] Telegram bot integration with n8n
- [x] `/start` command with user registration
- [x] `/help` command with multilingual support
- [x] Translations table with EN/PL/RU messages

### Phase 2: Availability System
- [x] Reservation status update workflow (15-min schedule)
- [x] MCP integration for `get_club_schedule`
- [x] `club_schedules` table with upsert pattern
- [x] `/show` command with HTML-formatted availability grid

### Phase 3: Booking System
- [x] `/book` command with JSON array input
- [x] Bulk reservation via `put_bulk_reservation` (optimized from loop)
- [x] `reservations` table for local booking records
- [x] `/list` command to show user reservations
- [x] `/delete` command with confirmation
- [x] `/deleteall` command for batch cancellation

### Phase 4: Authentication Refactor
- [x] Session-based auth (store session in `users.session`)
- [x] Eliminated redundant MCP login calls per operation
- [x] `/register` now stores session after successful login

### Phase 5: NLP Integration
- [x] Text Classifier for command vs. regular talk
- [x] NLP Command Parser with Qwen3-14B
- [x] Natural language command routing
- [x] AI Agent for general badminton Q&A

### Phase 6: Code Quality
- [x] Sub-workflow architecture for maintainability
- [x] Standardized input/output contracts
- [x] Version control setup (Git repository)

---

## Known Issues & TODOs

### Current Issues
- [ ] Session expiration handling (session may expire, need refresh logic)
- [ ] `reservation_id` from bulk booking not properly stored
- [ ] Voice transcription uses OpenAI (consider local Whisper)

### Future Enhancements
- [ ] Automated session refresh on expiry
- [ ] Booking reminders via scheduled workflow
- [ ] Partner matching feature
- [ ] Court preference learning

---

## Quick Reference

### Expression Cheat Sheet
```javascript
// Current item
$json.field

// Specific node (use after MCP nodes!)
$('NodeName').first().json.field

// Previous node in chain
$input.first().json.field

// Date formatting (Warsaw timezone)
$now.setZone('Europe/Warsaw').toFormat('dd.MM.yyyy')
$now.plus({ days: 1 }).toFormat('dd.MM.yyyy')  // Tomorrow
```

### SQL Patterns
```sql
-- Get translation by key+lang with English fallback
SELECT text FROM translations 
WHERE key = 'help' AND lang = $lang
UNION ALL
SELECT text FROM translations 
WHERE key = 'help' AND lang = 'en'
LIMIT 1;

-- Upsert schedule slot
INSERT INTO club_schedules (club_id, sport_id, date, court_number, time_slot, is_available)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (club_id, sport_id, date, court_number, time_slot)
DO UPDATE SET is_available = EXCLUDED.is_available, updated_at = NOW();
```

---

## Contact & Resources

- **n8n Instance**: Self-hosted via Portainer
- **Database**: `club-schedules-db` PostgreSQL container
- **Project Owner**: @brainb00st
- **Claude Project**: "N8N Workflows" in claude.ai

---

*This document is maintained for Claude AI assistants. Update when making significant architectural changes.*
