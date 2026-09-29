# Oma Pulse

**Your day, within reach.** A native workspace for Omarchy: tasks, focus, daily notes, calendar, mail and a desktop assistant.

[Website & interactive preview](https://oma-pulse.vercel.app/) · [Releases](https://github.com/therealasclepius/oma-pulse/releases) · [Report an issue](https://github.com/therealasclepius/oma-pulse/issues)

Oma Pulse runs inside Omarchy's Quickshell desktop. Hover over its bar icon for a quick look, click to pin it, or right-click for the full workspace. It follows your current theme. An application-menu launcher opens the same native workspace. This is an Omarchy Linux plugin, not an Electron wrapper or a cross-platform standalone app.

## Installation

Requires **Omarchy with its plugin-capable Quickshell shell** (tested on Omarchy 4.0.4), Git, Python 3.11+, Qt Quick Controls and `notify-send`. Omarchy supplies the desktop dependencies. Local tasks, notes and focus need no account. Node.js is only used for website development.

```sh
curl -fsSL https://oma-pulse.vercel.app/install.sh | bash
```

[Inspect the installer](install.sh). It clones the public repository, validates the manifest, enables `kosta.omaowl`, and installs a user-local application launcher. It never uses sudo, changes keyboard shortcuts or includes account credentials.

Alternatively, use Omarchy's plugin manager:

```sh
omarchy plugin add https://github.com/therealasclepius/oma-pulse.git --enable
bash ~/.config/omarchy/plugins/kosta.omaowl/scripts/install-desktop.sh
```

The plugin also initializes its storage when installed directly through the plugin manager. Open **Oma Pulse** in the application menu, or run `omapulse`.

### Updating and removing

```sh
omarchy plugin update kosta.omaowl
```

If a QML dependency remains cached, run `omarchy restart shell` after updating. Your local tasks, notes, credentials and focus history are stored outside the plugin directory.

Disable with `omarchy plugin disable kosta.omaowl`; remove with `omarchy plugin remove kosta.omaowl`. To remove launcher files too, remove `~/.local/bin/omapulse`, the legacy `~/.local/bin/omaowl` alias, `$XDG_DATA_HOME/applications/omapulse.desktop` and `$XDG_DATA_HOME/icons/hicolor/scalable/apps/omapulse.svg` (data home defaults to `~/.local/share`). User data is deliberately retained.

Existing local prototype: download and inspect `install.sh`, then run `bash install.sh --adopt`. This moves the old plugin into `$XDG_DATA_HOME/omaowl-backups/` before replacement, preserving your existing plugin ID, bar placement, shortcuts, workspace and connection files. Ordinary installation refuses to overwrite an existing plugin.

### Keyboard shortcut

Bind `omapulse command` in your Hyprland bindings using a key you choose. Existing Super+N bindings from the local prototype continue to work; a fresh install does not claim that shortcut. `omapulse dashboard` opens full screen; Escape returns to the compact workspace.

## Renamed from Oma Owl

Oma Pulse is the new name from version 0.6.0. The original GitHub URL redirects to the new repository, and the old website redirects to the new site. The plugin identifier `kosta.omaowl` and `omaowl` data directories intentionally remain stable so updates preserve accounts, notes and bar placement. Existing `omaowl` commands and IPC shortcuts still work; new installations also provide `omapulse`. Run the desktop installer once after updating to refresh your app-menu name and icon.

## Connections

All integrations are optional and installed separately:

| Connection | Setup | Adds |
| --- | --- | --- |
| Todoist | Switch Local to Todoist, then Account → API key | Synced tasks, Quick Add and reminders |
| OmaCal | Install OmaCal and connect a calendar there | Read-only daily event feed and links to the full calendar |
| HEY | Install a compatible `hey` CLI and run `hey auth login` | New for You, mark read and Undo |
| Codex | Install Codex CLI and run `codex login` | Assistant answers and supported desktop actions |
| Voxtype | Install and configure Voxtype's daemon | Dictation into the command input |

The HEY adapter expects the CLI's `box view imbox --json`, `seen` / `unseen`, and `watch` commands. Codex uses `exec` with structured output and an existing login. These optional CLIs can change; check helper errors and your installed CLI version when troubleshooting. Third-party services may require accounts or paid plans. No service subscription is included.

## Todoist

New installations start with local tasks. A saved Todoist connection is recognized automatically unless you have chosen a different source. Your source choice is remembered. Use **Account** in the Tasks card to connect
or replace an API key. Use your own Todoist account; no credentials are bundled.

- **Today** shows overdue and today's tasks; **All** shows all active tasks.
- The add field supports Todoist Quick Add syntax: `Buy milk tomorrow #Shopping p1`.
- Tasks without a parsed due date default to **Today**. Explicit dates and recurrence are preserved.
- The circle completes a task in Todoist. Recurring tasks advance to their next occurrence.
- Click a task name to open that task in Todoist. Long names wrap in full.
- ▶ selects a task for the focus timer.
- 🔔 opens **Remind me**: 30 minutes, one hour, this evening at 6 PM, tomorrow at 9 AM, or a custom local date/time.
  Reminders are saved as absolute Todoist push reminders without changing the task’s due date. Existing
  reminders appear in the dialog. A failed request keeps the selected time and idempotency key for retry.
  Delivery uses Todoist’s notification settings and devices.
- ↻ refreshes; automatic refresh also runs every two minutes, and when reopening
  a workspace whose last refresh was over a minute ago.
- Creation and completion are confirmed by the API before the UI reports success.
  Failed creation preserves the draft. An idempotency key prevents duplicates
  when retrying the same task after an interrupted response.
- Click the **Todoist / Local** button to switch to the original local list.
  Existing local tasks are preserved and are never uploaded automatically.

The API key is stored separately from the workspace in
`${XDG_CONFIG_HOME:-~/.config}/omaowl/todoist.json`, mode 600, inside a private
directory. It never enters process arguments or shell.json. Network calls go
only to `https://api.todoist.com/api/v1/`. Requests follow the
[official Todoist API](https://developer.todoist.com/api/v1/).

Disconnect removes Oma Pulse's local credential; it does not delete Todoist data.
Completed Todoist tasks remain in Todoist history; this UI currently shows active
tasks only. Insights counts tasks completed through Oma Pulse, not all Todoist history.

## Calendar

Use ‹ / › in the Events card to switch days, and **Back to today** to reset.
The date and full day's events change together. Arrows stop at the limits of
OmaCal's feed, currently today plus seven days. Event times use OmaCal's published
clock labels where available. Calendar access is read only; synchronization is
managed by OmaCal. No extra calendar account connection is needed. Clicking an event opens the full OmaCal app on that day and closes Oma Pulse.

## Focus and notes

25/50-minute presets, custom minutes, stopwatch, pause/resume and +5 minutes.
A small, square timer notch appears below the top bar while running and the workspace is closed.
Click its time/title to return to the workspace, or pause directly from the notch. It disappears
when paused or finished. Completion sends a desktop notification.
Sessions pause after sleep or a clock gap longer than three seconds. Restarts
restore sessions paused, so unattended time is not counted as active work.

Daily notes autosave. ‹ / › browse older days; Today resets the date.
Ctrl+Enter adds the current line to the selected task source and preserves the note.
Workspace and full-screen views share the same live data.

## Assistant and voice

The command bar and **Assistant** tab share a session-only conversation. Codex uses the existing
ChatGPT CLI login; it receives the request plus the displayed tasks, calendar, note, and optional
mail previews. Turn off **Include mail previews** in the Assistant tab to omit mail.

Installed-app matches and common explicit commands (focus, volume, add task, file search, and calendar day) run locally without an AI request. Try `start 25 minutes of focus`, `volume 40%`, or `add task Buy milk tomorrow`. Codex returns a structured plan;
direct requests run automatically, including “make a timer for 10min”. Ask for a preview to get action cards with **Run** buttons. Multi-step actions run in order and stop if an action fails. Supported actions are focus control, Todoist tasks
and reminders, app/web/document opening, common-folder file search, volume, calendar navigation,
and appending notes. Results are shown after execution. It can answer questions and draft text,
but this version does not send mail, modify arbitrary system settings, or execute generated shell code.

**Voice** uses the existing Voxtype daemon. Click again to stop; the transcript fills the input
for review before submission. No wake-word listener or spoken replies are enabled. Closing the
window cancels an active Oma Pulse recording. Codex can use live web search for weather, news, and current facts. Answers include source links. Desktop tool access stays disabled, with an isolated
working directory; it only proposes actions, which the app validates and runs for direct requests.

## HEY mail

The HEY card shows **New for You** from the recent Imbox, preserving HEY’s order. It uses stored
HEY CLI authentication and a websocket watch for live changes, plus refresh on reopening when
stale. Clicking a message opens it in the HEY web app. Listing mail never marks it seen.
Up to 50 recent Imbox entries are loaded; full mail remains available through **Open HEY**.

## Theme

All surfaces, text, accent colors, borders, and fonts bind to Omarchy’s live theme. Cards
use subtle theme tints, and the workspace, command bar, and focus notch have square corners.

## Storage

`${XDG_DATA_HOME:-~/.local/share}/omaowl/workspace.json` contains local tasks,
notes, timer state, and activity. Copy it to back up or export. Writes are atomic;
notes save after 300 ms and active timers checkpoint about every five seconds.
Closing the workspace also saves. Invalid saved workspace data is preserved
instead of silently overwritten. Todoist active tasks are fetched from the server.

## Commands

```sh
omarchy-shell omapulse toggle
omarchy-shell omapulse command
omarchy-shell omapulse assistant
omarchy-shell omapulse open
omarchy-shell omapulse dashboard
omarchy-shell omapulse close
omarchy-shell omapulse status
omarchy plugin disable kosta.omaowl
omarchy plugin enable kosta.omaowl
```

`open` pins the workspace; `toggle` toggles the command bar. `dashboard` opens full screen on the first
display; the workspace's Full screen button uses its own display.

Requires Omarchy's Quickshell shell, Qt Quick Controls, Python 3, and notify-send.
OmaCal, Todoist, HEY CLI, Codex, and Voxtype provide their respective optional integrations.

### HEY quick actions

Swipe an email left or click its ✓ button to mark it read in HEY. The widget confirms the remote status, then removes it from New for You. **Undo** marks the last email unread again; repeated Undo walks back the last 20 reads in this session. Failed updates show an error and leave the email available. Actions use the email’s own linked account.


## Build and verify

```sh
npm run check
npm test
npm run build:site
omarchy plugin validate .
```

`site/` is a responsive landing page with a limited interactive sample, not a browser port of the plugin. Website builds copy only that directory and the public installer. All visuals use sample data. GitHub Actions checks the source and creates a checksum-bearing source archive for version tags; Vercel hosts the static site.

## License and credits

Publicly viewable source; no open-source license is granted at this time (`UNLICENSED`), following Oma Beats' distribution model. Barlow is used under the included SIL Open Font License. The original workspace concept was inspired by NotchOwl; Oma Pulse is an independent project, not affiliated with Omarchy or its connected services.
