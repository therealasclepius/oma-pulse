#!/usr/bin/env bash
set -euo pipefail
plugin_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$HOME/.local/bin" "$data_dir/applications" "$data_dir/icons/hicolor/scalable/apps"
# Both commands follow plugin updates; the old name keeps shortcuts working.
for name in omapulse omaowl; do
  if [[ -e "$HOME/.local/bin/$name" && ! -L "$HOME/.local/bin/$name" ]]; then
    cp -p "$HOME/.local/bin/$name" "$HOME/.local/bin/$name.before-omapulse-$(date +%s)"
  fi
  ln -sfn "$plugin_dir/bin/omapulse" "$HOME/.local/bin/$name"
done
cp "$plugin_dir/assets/omapulse.svg" "$data_dir/icons/hicolor/scalable/apps/omapulse.svg"
# Retire only the old launcher created by this plugin, keeping a backup.
legacy="$data_dir/applications/omaowl.desktop"
if [[ -f "$legacy" ]] && grep -Eq '^Name=Oma (Owl|Pulse)$' "$legacy"; then
  backup="$data_dir/omaowl-backups/launcher-$(date +%s)-$$"
  mkdir -p "$backup"
  mv -- "$legacy" "$backup/omaowl.desktop"
fi
# Desktop entries quote paths differently from shell commands.
python3 - "$plugin_dir/bin/omapulse" "$data_dir/applications/omapulse.desktop" <<'PY'
from pathlib import Path
import sys
exe = sys.argv[1].replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
Path(sys.argv[2]).write_text(f'''[Desktop Entry]
Type=Application
Name=Oma Pulse
Comment=Tasks, focus, notes, calendar and mail, within reach
Exec="{exe}" open
Icon=omapulse
Terminal=false
Categories=Office;
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
printf 'App launcher installed. Open Oma Pulse from your application menu.\n'
