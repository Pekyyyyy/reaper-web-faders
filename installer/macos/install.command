#!/bin/bash
# reaper-web-faders installer for macOS.
# Installs into the REAPER resource folder (no admin rights needed, survives REAPER updates):
#   reaper_www_root/faders.html, Scripts/WebRemote/web_fx_bridge.lua, and a line in Scripts/__startup.lua
# Usage: double-click, or: ./install.command [REAPER resource path]
set -e
cd "$(dirname "$0")"

RES="${1:-$HOME/Library/Application Support/REAPER}"
echo "reaper-web-faders installer"
echo
if [ ! -d "$RES" ]; then
  echo "REAPER resource folder not found: $RES"
  echo "Start REAPER once, or pass the folder (REAPER: Options > Show REAPER resource path) as an argument."
  read -r -p "Press Return to close." _
  exit 1
fi

mkdir -p "$RES/reaper_www_root" "$RES/Scripts/WebRemote"
cp faders.html "$RES/reaper_www_root/faders.html"
cp web_fx_bridge.lua "$RES/Scripts/WebRemote/web_fx_bridge.lua"
echo "Installed page:    $RES/reaper_www_root/faders.html"
echo "Installed bridge:  $RES/Scripts/WebRemote/web_fx_bridge.lua"

STARTUP="$RES/Scripts/__startup.lua"
if grep -qF "web_fx_bridge.lua" "$STARTUP" 2>/dev/null; then
  echo "Auto-start:        already in $STARTUP"
else
  printf '\n-- Web remote FX bridge (reaper-web-faders)\ndofile(reaper.GetResourcePath() .. "/Scripts/WebRemote/web_fx_bridge.lua")\n' >> "$STARTUP"
  echo "Auto-start:        added to $STARTUP"
fi

# If REAPER is running, start the new bridge now (it replaces any older running copy).
# A uniquely named launcher avoids REAPER's "script already running" prompt.
REAPER_BIN="$(pgrep -fl 'REAPER.app/Contents/MacOS/REAPER' | awk 'NR==1{ $1=""; sub(/^ /,""); print }')"
if [ -n "$REAPER_BIN" ] && [ -x "$REAPER_BIN" ]; then
  L="${TMPDIR:-/tmp}/rwf_launch_$$.lua"
  echo 'dofile(reaper.GetResourcePath() .. "/Scripts/WebRemote/web_fx_bridge.lua")' > "$L"
  "$REAPER_BIN" -nonewinst "$L" >/dev/null 2>&1 &
  echo "Bridge:            started in the running REAPER"
else
  echo "Bridge:            will start next time REAPER launches"
fi

if ! grep -q "^csurf_[0-9]*=HTTP" "$RES/reaper.ini" 2>/dev/null; then
  echo
  echo "No web interface is set up in REAPER yet:"
  echo "  Preferences > Control/OSC/Web > Add > Web browser interface,"
  echo "  pick a port (e.g. 8889) and choose 'faders.html' as the default interface."
fi
echo
IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
echo "Then open http://${IP:-<this-mac-ip>}:<port>/faders.html on your phone or tablet."
echo
read -r -p "Done. Press Return to close." _
