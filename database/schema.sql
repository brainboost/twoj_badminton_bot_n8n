-- Twój Badminton Bot Database Schema
-- PostgreSQL 16+

-- Users table: Stores Telegram users and their TwojTenis credentials
CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(50) PRIMARY KEY,           -- Telegram user ID
    chat_id VARCHAR(50) NOT NULL UNIQUE,  -- Telegram chat ID
    user_name VARCHAR(100) NOT NULL,      -- Telegram username
    full_name VARCHAR(200),               -- Full name
    email VARCHAR(255),                   -- TwojTenis email
    hash VARCHAR(255),                    -- TwojTenis password (encrypted/hashed)
    session VARCHAR(500),                 -- TwojTenis session token
    phone VARCHAR(50),                    -- Optional phone number
    lang VARCHAR(10) DEFAULT 'en',        -- Preferred language (en, pl, ru)
    created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for quick lookups by chat_id
CREATE INDEX IF NOT EXISTS idx_users_chat_id ON users(chat_id);

-- Translations table: Multilingual message templates
CREATE TABLE IF NOT EXISTS translations (
    id SERIAL PRIMARY KEY,
    key VARCHAR(100) NOT NULL,            -- Translation key (e.g., 'help_message')
    lang VARCHAR(10) NOT NULL,            -- Language code (en, pl, ru)
    text TEXT NOT NULL,                   -- Translated text (supports HTML)
    created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(key, lang)
);

-- Index for quick translation lookups
CREATE INDEX IF NOT EXISTS idx_translations_key_lang ON translations(key, lang);

-- Club schedules table: Court availability data
CREATE TABLE IF NOT EXISTS club_schedules (
    id SERIAL PRIMARY KEY,
    club_id VARCHAR(100) NOT NULL,        -- Club identifier (e.g., 'blonia_sport')
    sport_id INTEGER NOT NULL,            -- Sport ID (84 = badminton, 70 = tennis)
    date DATE NOT NULL,                   -- Schedule date
    court_number VARCHAR(50) NOT NULL,    -- Court identifier (e.g., 'Badminton 1')
    time_slot TIME NOT NULL,              -- Time slot start
    is_available BOOLEAN DEFAULT TRUE,    -- Availability status
    updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(club_id, sport_id, date, court_number, time_slot)
);

-- Index for schedule queries
CREATE INDEX IF NOT EXISTS idx_club_schedules_date ON club_schedules(date);
CREATE INDEX IF NOT EXISTS idx_club_schedules_lookup ON club_schedules(club_id, sport_id, date);

-- Reservations table: User booking records
CREATE TABLE IF NOT EXISTS reservations (
    id SERIAL PRIMARY KEY,
    reservation_id VARCHAR(100) NOT NULL UNIQUE,  -- TwojTenis booking ID
    user_id VARCHAR(50) NOT NULL REFERENCES users(id),
    club_id VARCHAR(100) NOT NULL,
    sport_id INTEGER NOT NULL,
    date DATE NOT NULL,
    time_start TIME NOT NULL,
    time_end TIME NOT NULL,
    court_number VARCHAR(50) NOT NULL,
    status VARCHAR(20) DEFAULT 'active',  -- active, cancelled, completed
    created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for user reservation lookups
CREATE INDEX IF NOT EXISTS idx_reservations_user ON reservations(user_id);
CREATE INDEX IF NOT EXISTS idx_reservations_date ON reservations(date);

-- Sample translations (English)
INSERT INTO translations (key, lang, text) VALUES
('welcome', 'en', '👋 Welcome to Badminton Court Bot!

Use /register to connect your TwojTenis account.
Use /help to see available commands.'),
('help_message', 'en', '🏸 <b>Badminton Court Bot</b>

<b>Available Commands:</b>

/register &lt;email&gt; &lt;password&gt;
Register your TwojTenis credentials

/book &lt;date&gt; &lt;time&gt; [court]
Book a court (date: DD.MM.YYYY, time: HH:MM)

/list
Show your reservations

/show [date]
Show court availability

/delete &lt;id&gt;
Cancel a reservation

/help
Show this help message'),
('register_success', 'en', '✅ Registration successful! Your credentials have been saved.'),
('register_invalid_args', 'en', '❌ Invalid format. Usage: /register email@example.com password'),
('book_success', 'en', '✅ Booking confirmed!
📅 Date: {date}
⏰ Time: {time_start} - {time_end}
🏸 Court: {court}'),
('delete_success', 'en', '✅ Reservation cancelled successfully.'),
('delete_not_found', 'en', '❌ Reservation not found.'),
('delete_no_credentials', 'en', '❌ Please register first using /register')
ON CONFLICT (key, lang) DO NOTHING;

-- Sample translations (Polish)
INSERT INTO translations (key, lang, text) VALUES
('welcome', 'pl', '👋 Witaj w Bocie Rezerwacji Kortów do Badmintona!

Użyj /register aby połączyć konto TwojTenis.
Użyj /help aby zobaczyć dostępne komendy.'),
('help_message', 'pl', '🏸 <b>Bot Rezerwacji Kortów</b>

<b>Dostępne Komendy:</b>

/register &lt;email&gt; &lt;hasło&gt;
Zarejestruj dane TwojTenis

/book &lt;data&gt; &lt;godzina&gt; [kort]
Zarezerwuj kort (data: DD.MM.YYYY, godzina: HH:MM)

/list
Pokaż twoje rezerwacje

/show [data]
Pokaż dostępność kortów

/delete &lt;id&gt;
Anuluj rezerwację

/help
Pokaż tę pomoc'),
('register_success', 'pl', '✅ Rejestracja pomyślna! Twoje dane zostały zapisane.'),
('register_invalid_args', 'pl', '❌ Nieprawidłowy format. Użycie: /register email@example.com hasło'),
('book_success', 'pl', '✅ Rezerwacja potwierdzona!
📅 Data: {date}
⏰ Godzina: {time_start} - {time_end}
🏸 Kort: {court}'),
('delete_success', 'pl', '✅ Rezerwacja anulowana pomyślnie.'),
('delete_not_found', 'pl', '❌ Rezerwacja nie znaleziona.'),
('delete_no_credentials', 'pl', '❌ Najpierw zarejestruj się używając /register')
ON CONFLICT (key, lang) DO NOTHING;

-- Sample translations (Russian)
INSERT INTO translations (key, lang, text) VALUES
('welcome', 'ru', '👋 Добро пожаловать в Бот Бронирования Кортов!

Используйте /register для подключения аккаунта TwojTenis.
Используйте /help для просмотра доступных команд.'),
('help_message', 'ru', '🏸 <b>Бот Бронирования Кортов</b>

<b>Доступные Команды:</b>

/register &lt;email&gt; &lt;пароль&gt;
Зарегистрировать данные TwojTenis

/book &lt;дата&gt; &lt;время&gt; [корт]
Забронировать корт (дата: DD.MM.YYYY, время: HH:MM)

/list
Показать ваши бронирования

/show [дата]
Показать доступность кортов

/delete &lt;id&gt;
Отменить бронирование

/help
Показать эту справку'),
('register_success', 'ru', '✅ Регистрация успешна! Ваши данные сохранены.'),
('register_invalid_args', 'ru', '❌ Неверный формат. Использование: /register email@example.com пароль'),
('book_success', 'ru', '✅ Бронирование подтверждено!
📅 Дата: {date}
⏰ Время: {time_start} - {time_end}
🏸 Корт: {court}'),
('delete_success', 'ru', '✅ Бронирование успешно отменено.'),
('delete_not_found', 'ru', '❌ Бронирование не найдено.'),
('delete_no_credentials', 'ru', '❌ Сначала зарегистрируйтесь используя /register')
ON CONFLICT (key, lang) DO NOTHING;

-- Function to update timestamp on record change
CREATE OR REPLACE FUNCTION update_updated_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for auto-updating timestamps
DROP TRIGGER IF EXISTS update_users_updated ON users;
CREATE TRIGGER update_users_updated BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_column();

DROP TRIGGER IF EXISTS update_translations_updated ON translations;
CREATE TRIGGER update_translations_updated BEFORE UPDATE ON translations
    FOR EACH ROW EXECUTE FUNCTION update_updated_column();

DROP TRIGGER IF EXISTS update_club_schedules_updated ON club_schedules;
CREATE TRIGGER update_club_schedules_updated BEFORE UPDATE ON club_schedules
    FOR EACH ROW EXECUTE FUNCTION update_updated_column();

DROP TRIGGER IF EXISTS update_reservations_updated ON reservations;
CREATE TRIGGER update_reservations_updated BEFORE UPDATE ON reservations
    FOR EACH ROW EXECUTE FUNCTION update_updated_column();
