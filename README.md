# Reminder

**Remind Me** is a small native macOS app for writing down anything you don't want to forget. It sends a notification when the time comes.

## Features

- **Quick capture:** type a reminder and press Return.
- **Times in plain English:** type "call mom tomorrow at 6pm", "pay bill on friday" or "buy milk in 20 minutes". The time is set for you and the phrase is removed from the text.
- **Quick times:** in 1 hour, this evening, tomorrow morning, this weekend, next Monday. There's also a picker for any day and exact time.
- **Snooze or reschedule** any reminder from the hover menu, the right-click menu, or by clicking its time.
- **Color-coded list:** overdue (red), today (orange), later (blue), no date (purple) and done (green).
- **Notifications even when the app is closed:** macOS delivers them itself.
- Light and dark mode.

## Build and install

Requires macOS 14 or later and Xcode (or the Xcode Command Line Tools).

```sh
./build.sh
```

This compiles the app, draws its icon, and installs it to `/Applications/Remind Me.app`. Open it from Spotlight or Launchpad, and allow notifications when asked.

Run `./build.sh` again after changing the code. Your reminders are kept.

## Files

| File | What it is |
|---|---|
| `RemindMe.swift` | The whole app (SwiftUI) |
| `build.sh` | Builds the `.app` bundle and installs it |
| `Info.plist` | App name, identifier and version |
| `make_icon.swift` | Draws the app icon |

Reminders are stored in `~/Library/Application Support/Remind Me/reminders.json`.

## Disclaimer

This is a personal hobby project, provided **as is** without any warranty. Use it at your own risk.

- Notifications depend on macOS and your notification settings, so they can be delayed or missed. Don't rely on this app for anything critical, such as medication, legal deadlines or safety-related tasks.
- Reminders are stored only on your Mac and are not backed up or synced. The author is not responsible for lost data or missed reminders.
- This project is not affiliated with, endorsed by or connected to Apple Inc. "macOS" and "Reminders" are trademarks of Apple Inc.
