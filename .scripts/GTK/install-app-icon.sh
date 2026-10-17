#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Install the application's desktop entry and icon for this user. No build or
# application execution; used by both run-app.sh and deploy.sh.
set -euo pipefail
app_dir="$(cd "${1:?application directory}" && pwd)"
executable="${2:?absolute executable path}"
application="$(basename "$app_dir")"
metadata="$app_dir/Resources/Bundle/app-info.json"
if [[ ! -f "$metadata" ]]; then
  for candidate in "$app_dir"/Sources/*/Assets/Bundle/app-info.json; do
    [[ ! -f "$candidate" ]] || { metadata="$candidate"; break; }
  done
fi
if [[ -f "$metadata" ]]; then
  application="$(python3 - "$metadata" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    name = json.load(source)["displayName"]
if not isinstance(name, str) or not name.strip() or any(c in name for c in "\r\n"):
    raise ValueError("app-info.json must supply a nonempty single-line displayName")
print(name.replace("\\", "\\\\"))
PY
)"
fi
product="$(basename "$executable")"
# The desktop shows a window with the icon of the entry named by its application's ID: both are installed for
# the user, the entry starting this build.
application_id="$(sed -n 's/.*applicationID: "\([^"]*\)".*/\1/p' "$app_dir/Platforms/GTK/main.swift" | head -1)"
if [[ -n "$application_id" && -f "$app_dir/Resources/AppIcon/appicon_gnome.svg" ]]; then
  data="${XDG_DATA_HOME:-$HOME/.local/share}"
  mkdir -p "$data/icons/hicolor/scalable/apps" "$data/applications"
  cp "$app_dir/Resources/AppIcon/appicon_gnome.svg" "$data/icons/hicolor/scalable/apps/$application_id.svg"
  # Escape the desktop-entry Exec argument; a build path may contain spaces.
  desktop_executable="${executable//\\/\\\\}"
  desktop_executable="${desktop_executable//\"/\\\"}"
  desktop_executable="${desktop_executable//\$/\\\$}"
  desktop_executable="${desktop_executable//\`/\\\`}"
  desktop_executable="${desktop_executable//%/%%}"
  cat > "$data/applications/$application_id.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=$application
Exec="$desktop_executable"
Icon=$application_id
StartupWMClass=$product
Terminal=false
Categories=Development;
ENTRY
  command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f -t "$data/icons/hicolor" >/dev/null 2>&1 || true
  command -v update-desktop-database >/dev/null && update-desktop-database "$data/applications" >/dev/null 2>&1 || true
fi
