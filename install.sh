#!/usr/bin/env bash
# User-local installation. Review before running. Never requests sudo.
set -euo pipefail
repo='https://github.com/therealasclepius/oma-pulse.git'
plugin_id='kosta.omaowl'
local_source=false
adopt=false
enable=true
for arg in "$@"; do
  case "$arg" in
    --local) local_source=true ;;
    --adopt) adopt=true ;;
    --no-enable) enable=false ;;
    -h|--help) echo 'Usage: install.sh [--local] [--adopt] [--no-enable]'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
for cmd in git jq python3 omarchy omarchy-shell; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd. Install on an Omarchy desktop with the plugin-capable shell." >&2; exit 1; }
done
target="$HOME/.config/omarchy/plugins/$plugin_id"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
if $local_source; then
  source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  git clone --quiet --no-hardlinks -- "$source_dir" "$stage/plugin"
  git -C "$stage/plugin" remote set-url origin "$repo"
else
  git clone --quiet -- "$repo" "$stage/plugin"
fi
omarchy plugin validate "$stage/plugin"
if [[ -e "$target" || -L "$target" ]]; then
  if ! $adopt; then
    echo "Oma Pulse is already installed at $target." >&2
    echo "Update with: omarchy plugin update $plugin_id" >&2
    echo 'To replace a local prototype and keep a backup, rerun with --adopt.' >&2
    exit 1
  fi
  backup="${XDG_DATA_HOME:-$HOME/.local/share}/omaowl-backups/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$backup"
  mv -- "$target" "$backup/$plugin_id"
  echo "Previous plugin backed up to $backup/$plugin_id"
fi
mkdir -p "$(dirname -- "$target")"
mv -- "$stage/plugin" "$target"
python3 "$target/initialize.py"
bash "$target/scripts/install-desktop.sh"
if $enable; then
  if ! omarchy-shell shell rescanPlugins >/dev/null; then
    echo "Reloading the shell to finish registering Oma Pulse…"
    omarchy restart shell
  fi
  for ((attempt = 0; attempt < 40; attempt++)); do
    if omarchy plugin list --json | jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' >/dev/null; then break; fi
    sleep 0.05
  done
  omarchy plugin enable "$plugin_id"
fi
printf '\nOma Pulse is installed. Run: omapulse\nUpdates: omarchy plugin update %s\n' "$plugin_id"
