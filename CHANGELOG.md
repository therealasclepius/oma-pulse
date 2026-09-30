# Changelog

## 0.7.1

- Fixed Todoist helpers waiting for input EOF, which could leave syncing stuck and task checkboxes disabled.
- Read each JSON-line request immediately and bound helper execution to 90 seconds, with a retryable timeout message.
- Added a regression check that holds stdin open and verifies the request still completes.

## 0.7.0

- Added a Connections screen with persistent task, mail and calendar choices.
- Added beta Gmail and Outlook inbox adapters with user-owned OAuth setup, plus TLS IMAP with app-password setup.
- Added beta direct Google Calendar support, including calendar timezone, recurring and multi-day events.
- Preserved HEY, Todoist and OmaCal integrations; local tasks also work with assistant commands.
- Added full weekday names to calendar headings.
- Added connection setup documentation and updated the public website with supported choices and setup requirements.
- New adapters have automated protocol/UI coverage; live provider verification requires configured accounts.

## 0.6.0

- Renamed Oma Owl to **Oma Pulse**, with new branding, a pulse icon and an `omapulse` launcher.
- Retained old commands, plugin identity and data paths for a seamless upgrade.
- Added a fifth website preview card for HEY email: sample messages, open, mark read and Undo.
- Updated public URLs and added a redirect from the old website.
- Added Kosta Hantzis’s social links to a shared footer on every page, including the branded 404 page.

## 0.5.0

First public Omarchy release.

- Native bar plugin, compact workspace, full-screen workspace and command bar.
- Local tasks, daily notes, focus sessions, stopwatch and activity insights.
- Optional Todoist, OmaCal, HEY, Codex and Voxtype connections.
- Full task titles, direct Todoist task links, and event links to the full calendar.
- User-local installer, application launcher, Git-managed updates and backup-preserving prototype migration.
- Safe first-run workspace creation and remembered task-source selection.
- Responsive landing page with an interactive, account-free sample workspace.

## Earlier versions

Versions 0.1–0.4 were local prototypes, not public releases.
