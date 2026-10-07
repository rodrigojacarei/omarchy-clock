# Omarchy Clock 📅

A feature-rich, modern Clock, Month Calendar, Agenda, and Google Calendar Two-Way Cloud Sync plugin for **[Omarchy Linux](https://omarchy.org/)**.

> **Note**: This plugin is **derived from and built upon Omarchy's official built-in clock plugin (`omarchy.clock`)**, heavily enhanced with Google Calendar OAuth 2.0 two-way cloud synchronization, Google Meet 1-click video call integration, recurrence engine, and persistent desktop notifications.

<div align="center">
  <img src="preview.png?v=3" alt="Omarchy Clock & Calendar" width="700" />
</div>

<p align="center">
  <em>Live top-bar upcoming event countdown, interactive month calendar, Google Calendar 2-Way Sync, Google Meet 1-click Join, and persistent desktop notifications.</em>
</p>

---

## ✨ Features

### 🕒 Status Bar Clock & Upcoming Event Countdown
- **Live Clock Display**: Configurable 12h/24h formats, date displays, and vertical bar layout support.
- **Next Event Preview**: Displays your upcoming event title and time countdown directly beside the clock on the top status bar.
- **Meeting Indicator**: Shows a video camera icon (`📹`) when the upcoming event has a Google Meet or conference link.

<div align="center">
  <img src="assets/preview_bar.png?v=3" alt="Top Bar Countdown" width="600" />
  <p><em>Top status bar displaying live date/time alongside the upcoming event countdown</em></p>
</div>

---

### 🗓️ Full Month Calendar & Agenda
- **Interactive Calendar Grid**: Clean monthly layout with ISO week numbers and color-coded event indicator dots.
- **Keyboard Navigation**: Fast navigation via hotkeys (`[` / `]` for months, `{` / `}` for years, `T` for today, `W` to toggle week start between Monday and Sunday).
- **Today & Tomorrow's Agenda**: Clean event cards showing start/end times, calendar badges, locations, and descriptions.
- **1-Click Google Meet Join**: Events with meeting links feature a green **`Join`** button to open the call directly in your browser.

<div align="center">
  <img src="assets/preview_panel.png?v=3" alt="Calendar and Agenda View" width="560" />
</div>

---

### 📝 Event Creation & Smart Recurrence Rules
- **Local & Google Cloud Event Creation**: Add events locally or sync them directly to your Google Calendar account.
- **Advanced Recurrence Engine**: Set events to repeat **Daily**, **Weekly** on specific days (e.g. Mon, Wed, Fri), **Monthly** (by day of month or nth weekday), or **Yearly**, with optional end dates (`UNTIL`) or count limits.
- **Generate Meeting Link**: Toggle to automatically provision a Google Meet video conference link for the new event.

<div align="center">
  <img src="assets/preview_addevent.png?v=3" alt="Add Event Drawer" width="560" />
  <p><em>Add event drawer with custom recurrence rules and Google Meet generation</em></p>
</div>

---

### 🗑️ Smart Recurring Event Deletion
When deleting a repeating event, an interactive dialog prompts you to choose the exact deletion scope:
- **This event only**: Cancels and removes only the selected occurrence on that date.
- **This and all following events**: Truncates the recurrence rule so future occurrences stop.
- **All events in the series**: Permanently deletes every occurrence in the repeating series.

---

### 🔔 Persistent Desktop Notifications & Reminders
- **Background Reminder Engine**: Monitors upcoming meetings without requiring the panel to stay open.
- **1-Click Action**: Notifications include a **`Join Meeting`** action that opens video calls directly in your browser.
- **Advance Reminder Options**: Choose when to be alerted: **5 min**, **10 min** *(default)*, **15 min**, or **30 min** before events.
- **Stay on Screen Until Clicked (Persistent Mode)**: Keeps reminders visible on your screen until clicked or dismissed so you never miss a meeting.

---

### 🔄 Google Cloud Two-Way Sync (OAuth 2.0)
- **Real-Time 2-Way Sync**: Changes made in Omarchy update immediately on Google Calendar servers and your mobile devices.
- **Multi-Calendar Filtering**: Toggle visibility and custom colors for individual Google Calendars and iCal feeds.
- **Configurable Auto-Sync Cadence**: Choose background auto-sync frequency (**1 min**, **2 min** *(default)*, **5 min**, or **15 min**).

<div align="center">
  <img src="assets/preview_settings.png?v=3" alt="Settings & Google Cloud Sync" width="560" />
  <p><em>Settings view with Google Cloud OAuth 2.0 status, sync frequency, and notification preferences</em></p>
</div>

---

## ⚡ Google Calendar Setup Guide

### Option A: Fast Setup via Google Cloud CLI (`gcloud`)

```bash
# 1. Create a project and set as active
gcloud projects create omarchy-calendar-sync --name="Omarchy Calendar"
gcloud config set project omarchy-calendar-sync

# 2. Enable Google Calendar API
gcloud services enable calendar-json.googleapis.com

# 3. Create desktop OAuth client
gcloud iam oauth-client-ids create omarchy-clock \
  --project=omarchy-calendar-sync \
  --client-type=desktop-app \
  --description="Omarchy Clock Desktop Client"
```

After setup, copy your **Client ID** and **Client Secret** into the Clock panel settings (**Settings ⚙️** → **Configure Client ID & Secret**), or place `client_secret.json` in `~/.config/omarchy-clock/client_secret.json`.

---

### Option B: Manual Google Cloud Console Setup (Web GUI)

1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Create a new project (e.g. `Omarchy Calendar`).
3. Under **APIs & Services** → **Library**, search for **Google Calendar API** and click **Enable**.
4. Under **APIs & Services** → **OAuth consent screen**:
   - Select **External** (or Internal for Google Workspace).
   - Enter an App name (e.g. `Omarchy Clock`) and your email address.
   - Under **Scopes**, add `https://www.googleapis.com/auth/calendar`.
   - Under **Test users**, add your Google email address.
5. Under **APIs & Services** → **Credentials**:
   - Click **Create Credentials** → **OAuth client ID**.
   - Select **Application type**: `Desktop app`.
   - Click **Create**.
6. Open your Clock panel in Omarchy, click **Settings (⚙️)** → **Configure Client ID & Secret**, and paste your credentials.
7. Click **`Connect with Google`** to sign in through your browser.

---

### Option D: Instant Read-Only Sync (Secret iCal URL)

If you only need to view events without creating/editing:
1. Open [Google Calendar](https://calendar.google.com/) in your browser.
2. Go to **Settings** → click your calendar under *Settings for my calendars*.
3. Scroll to **Integrate calendar** and copy the **Secret address in iCal format** (`https://calendar.google.com/calendar/ical/.../basic.ics`).
4. Open the Clock panel, click **Settings (⚙️)** → **Add iCal Subscription URL**, and paste the URL.

---

## 📦 Installation

### Option 1: Using Omarchy CLI (Recommended)

```bash
omarchy plugin add https://github.com/rodrigojacarei/omarchy-clock.git --enable
```

### Option 2: Manual Installation / Local Development

Copy or link the plugin directory into your Omarchy plugins folder:

```bash
# 1. Copy or link plugin into Omarchy plugins directory
mkdir -p ~/.config/omarchy/plugins
cp -r /path/to/omarchy-clock ~/.config/omarchy/plugins/omarchy-clock

# 2. Symlink CLI helper and desktop application launcher
mkdir -p ~/.local/bin ~/.local/share/applications
ln -sf ~/.config/omarchy/plugins/omarchy-clock/bin/omarchy-clock ~/.local/bin/omarchy-clock
cp ~/.config/omarchy/plugins/omarchy-clock/omarchy-clock.desktop ~/.local/share/applications/

# 3. Reload Omarchy shell
omarchy-restart-shell
omarchy plugin enable omarchy-clock --section center
```

---

## 🗑️ Removal / Uninstallation

### Option 1: Using Omarchy CLI (Recommended)

To remove the plugin using the Omarchy CLI:

```bash
omarchy plugin remove omarchy-clock
```

To remove non-interactively without confirmation prompts:

```bash
omarchy plugin remove omarchy-clock --yes
```

### Option 2: Manual Removal

To manually uninstall and remove all local plugin files and configuration:

```bash
# 1. Disable the plugin in Omarchy shell
omarchy plugin disable omarchy-clock

# 2. Remove CLI helper and desktop application launcher
rm -f ~/.local/bin/omarchy-clock
rm -f ~/.local/share/applications/omarchy-clock.desktop

# 3. Remove the plugin directory
rm -rf ~/.config/omarchy/plugins/omarchy-clock

# 4. (Optional) Remove plugin configuration and cached calendar data
rm -rf ~/.config/omarchy-clock
rm -rf ~/.cache/omarchy/clock

# 5. Reload Omarchy shell
omarchy-restart-shell
```

---

## 📋 Dependencies

- **Omarchy Shell** / **Quickshell** (Built into Omarchy Linux)
- **Python 3** (Standard library only — zero pip dependencies required)
- **xdg-open** (Included in desktop environments, used to open Google Meet video calls and browser authorization)

---

## ⌨️ Keyboard Shortcuts & Hyprland Keybindings

### In-Panel Keyboard Shortcuts
| Key | Action |
| :--- | :--- |
| `[` / `]` | Previous / Next Month |
| `{` / `}` | Previous / Next Year |
| `T` | Jump to Today |
| `W` | Toggle Week Start (Monday / Sunday) |
| `N` / `+` | Open Add Event Drawer |
| `S` | Open Settings & Calendars View |
| `Esc` | Close Drawer / Dismiss Popup |

### Hyprland Keybinding (Optional)
Add to `~/.config/hypr/bindings.conf`:

```ini
# Toggle Clock & Calendar popup
bind = SUPER, C, exec, omarchy-clock toggle
```

---

## 🛠️ CLI Commands

```bash
omarchy-clock toggle         # Open or close the Calendar panel
omarchy-clock open           # Open the panel
omarchy-clock close          # Close the panel
omarchy-clock sync           # Trigger immediate background sync
omarchy-clock status         # Check Google Cloud OAuth status
omarchy-clock auth           # Run Google Cloud authentication flow
omarchy-clock logout         # Disconnect Google Cloud account
```

---

## 📄 License & Credits

MIT License. See [LICENSE](LICENSE) for details.

- **Author**: [rodrigojacarei](https://github.com/rodrigojacarei)
- **Base Widget**: Derived from and built upon Omarchy's official built-in clock plugin (`omarchy.clock`).
