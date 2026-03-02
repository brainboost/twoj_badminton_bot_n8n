Put here your raw and immature ideas to grind, refine and make specs for implementation. **Claude** - look at ideas listed, fill them with details, correct them if wrong or insecure ideas proposed.
---

- Add posting the Poll on schedule - admin only feature to publish the multi-options poll for counting players and planning court reservations.

- Add notification functionality - A user can ask the bot to notify him if court(s) will become available on particular date/time. The 'Reservation status update' job should check if the time slots are available after the refresh job finished, then trigger notification in Telegram. Optionally - reserve the slot(s). Remove expired notifications.

- Human-in-the-middle approve for booking and deletion. Bot should ask the user to hit the button to approve reservation or deletion with parameters, with the ability to cancel. 