#!/usr/bin/env bash
# YABus macOS DMG builder
# Usage: create_dmg.sh <app_path> <version> <output_dir>
# Uses sindresorhus/create-dmg for a polished DMG with
# auto-positioned app icon + Applications shortcut.

set -euo pipefail

APP_PATH="${1:?Usage: create_dmg.sh <app_path> <version> <output_dir>}"
VERSION="${2:?Version required}"
OUTPUT_DIR="${3:?Output directory required}"

mkdir -p "${OUTPUT_DIR}"

# Install create-dmg via npm if not present
if ! command -v create-dmg &>/dev/null; then
  echo "Installing create-dmg…"
  npm install --global create-dmg
fi

# create-dmg generates the DMG filename automatically from the app name,
# then we rename it to our preferred naming scheme.
create-dmg \
  --overwrite \
  --dmg-title="YABus" \
  "${APP_PATH}" \
  "${OUTPUT_DIR}"

# create-dmg outputs "YABus {version}.dmg" — rename to our format
GENERATED_DMG="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "YABus *.dmg" -type f | head -1)"
if [ -n "${GENERATED_DMG}" ]; then
  mv "${GENERATED_DMG}" "${OUTPUT_DIR}/YABus-${VERSION}-macos.dmg"
fi

echo "DMG created: ${OUTPUT_DIR}/YABus-${VERSION}-macos.dmg"
