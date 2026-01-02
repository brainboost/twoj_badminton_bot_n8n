# Twój Badminton Bot 🏸

A multilingual Telegram bot for badminton court reservations, built with n8n workflow automation and integrated with the TwojTenis.pl booking platform.

## Features

- **Multilingual Support**: English, Polish, and Russian interfaces
- **Natural Language Commands**: Book courts using simple Telegram commands
- **Real-time Availability**: Automated court schedule monitoring
- **Session Management**: Secure credential storage with session-based authentication
- **Bulk Booking**: Reserve multiple time slots in a single request

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Telegram Bot   │────▶│  n8n Workflows   │────▶│   PostgreSQL    │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌──────────────────┐
                        │  TwojTenis MCP   │
                        │     Server       │
                        └──────────────────┘
```

## Workflows

| Workflow | Description |
|----------|-------------|
| `assistant_agent.json` | Main bot workflow with AI agent for natural language processing |
| `book_command.json` | Handles `/book` command for court reservations |
| `list_bookings_command.json` | Handles `/list` command to show user's reservations |
| `show_command.json` | Handles `/show` command for court availability display |
| `register_command.json` | Handles `/register` command for user authentication |
| `delete_command.json` | Handles `/delete` command to cancel reservations |
| `reservation_status_update.json` | Scheduled workflow for availability monitoring |

## Bot Commands

| Command | Description | Example |
|---------|-------------|---------|
| `/start` | Initialize bot and set language | `/start` |
| `/help` | Show available commands | `/help` |
| `/register <email> <password>` | Register TwojTenis credentials | `/register user@email.com mypassword` |
| `/book <date> <time> [court]` | Book a court | `/book 15.01.2025 18:00` |
| `/list` | Show your reservations | `/list` |
| `/show [date]` | Show court availability | `/show 15.01.2025` |
| `/delete <reservation_id>` | Cancel a reservation | `/delete abc123` |

## Setup

### Prerequisites

- n8n instance (self-hosted or cloud)
- PostgreSQL database
- Telegram Bot Token (from [@BotFather](https://t.me/botfather))
- TwojTenis.pl account credentials
- TwojTenis MCP Server

### 1. Database Setup

Create the required database schema using the provided `schema.sql` file or set up tables manually.

### 2. Configure Credentials in n8n

Create the following credentials in your n8n instance:

1. **Telegram API** (`twoj_badminton_bot`)
   - Bot Token from BotFather

2. **PostgreSQL** (`Postgres account`)
   - Host, Port, Database, User, Password

3. **MCP Client** (`Twojtenis MCP Client (STDIO)`)
   - Configure for your TwojTenis MCP server

### 3. Import Workflows

1. Import each JSON file from the `workflows/` directory
2. Update credential references to match your configured credentials
3. Activate the workflows

### 4. Update Sensitive Values

Search for and replace these placeholder values:

- `CREDENTIAL_ID` - Replace with actual n8n credential IDs
- `YOUR_EMAIL_HERE` - TwojTenis login email (in reservation_status_update.json)
- `YOUR_PASSWORD_HERE` - TwojTenis login password (in reservation_status_update.json)

## Database Schema

Key tables:

- `users` - Telegram users and their TwojTenis credentials
- `translations` - Multilingual message templates
- `club_schedules` - Court availability data
- `reservations` - User booking records

See `database/schema.sql` for full schema definition.

## Configuration

### Environment Variables

For Docker deployment, configure in `docker-compose.yml`:

```yaml
environment:
  POSTGRES_DB: club_schedules
  POSTGRES_USER: n8n_user
  POSTGRES_PASSWORD: your_secure_password
```

### Workflow Settings

All workflows use:
- Execution order: v1
- Timezone: Europe/Warsaw
- Caller policy: workflowsFromSameOwner

## Development

### Project Structure

```
twoj_badminton_bot/
├── workflows/
│   ├── assistant_agent.json
│   ├── book_command.json
│   ├── delete_command.json
│   ├── list_bookings_command.json
│   ├── register_command.json
│   ├── reservation_status_update.json
│   └── show_command.json
├── database/
│   └── schema.sql
├── docker-compose.yml
├── README.md
└── .gitignore
```

### Key Design Decisions

1. **Session-based Authentication**: Eliminates redundant MCP login calls by storing session tokens in PostgreSQL
2. **Bulk Operations**: Uses bulk reservation API instead of individual calls for better performance
3. **Sub-workflow Architecture**: Each command is a separate workflow for maintainability
4. **Translation System**: Key-language table structure enables seamless i18n

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test workflows in n8n
5. Submit a pull request

## License

MIT License - See LICENSE file for details.

## Acknowledgments

- [n8n](https://n8n.io/) - Workflow automation platform
- [TwojTenis.pl](https://twojtenis.pl/) - Court booking platform
- Claude AI - Development assistance

---

**Note**: This bot is not affiliated with TwojTenis.pl. Use responsibly and in accordance with their terms of service.
