#!/usr/bin/env bash
set -euo pipefail
plugin_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$HOME/.local/bin" "$data_dir/applications" "$data_dir/icons/hicolor/scalable/apps"
# The symlink follows plugin updates without copying stale launcher code.
if [[ -e "$HOME/.local/bin/omaowl" && ! -L "$HOME/.local/bin/omaowl" ]]; then
  cp -p "$HOME/.local/bin/omaowl" "$HOME/.local/bin/omaowl.before-omaowl-$(date +%s)"
fi
ln -sfn "$plugin_dir/bin/omaowl" "$HOME/.local/bin/omaowl"
cp "$plugin_dir/assets/omaowl.svg" "$data_dir/icons/hicolor/scalable/apps/omaowl.svg"
# Desktop entries quote paths differently from shell commands.
python3 - "$plugin_dir/bin/omaowl" "$data_dir/applications/omaowl.desktop" <<'PY'
from pathlib import Path
import sys
exe = sys.argv[1].replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
Path(sys.argv[2]).write_text(f'''[Desktop Entry]
Type=Application
Name=Oma Owl
Comment=Tasks, focus, notes, calendar and mail, within reach
Exec="{exe}" open
Icon=omaowl
Terminal=false
Categories=Office;Utility;
Keywords=productivity;todoist;focus;notes;calendar;assistant;
Actions=Dashboard;Command;Assistant;

[Desktop Action Dashboard]
Name=Full workspace
Exec="{exe}" dashboard

[Desktop Action Command]
Name=Command bar
Exec="{exe}" command

[Desktop Action Assistant]
Name=Assistant
Exec="{exe}" assistant
''')
PY
if command -v update-desktop-database >/dev/null; then update-desktop-database "$data_dir/applications"; fi
printf 'App launcher installed. Open Oma Owl from your application menu.\n'
