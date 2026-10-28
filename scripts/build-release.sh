#!/bin/bash
# Builds dist/reaper-web-faders-<version>-macos.zip and -windows.zip
set -e
cd "$(dirname "$0")/.."
V="${1:?usage: scripts/build-release.sh <version>}"
rm -rf dist && mkdir -p dist/stage
for os in macos windows; do
  d="dist/stage/reaper-web-faders-$V-$os"
  mkdir -p "$d"
  cp faders.html reaper-scripts/web_fx_bridge.lua README.md "$d/"
  cp installer/$os/* "$d/"
  (cd dist/stage && zip -qrX "../reaper-web-faders-$V-$os.zip" "reaper-web-faders-$V-$os")
done
rm -rf dist/stage
ls -l dist
