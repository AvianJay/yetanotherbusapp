#!/usr/bin/env bash
# YABus macOS DMG builder
# Usage: create_dmg.sh <app_path> <version> <output_dir>
# Uses sindresorhus/create-dmg for a polished DMG with
# auto-positioned app icon + Applications shortcut.

set -euo pipefail

APP_PATH="${1:?Usage: create_dmg.sh <app_path> <version> <output_dir>}"
VERSION="${2:?Version required}"
OUTPUT_DIR="${3:?Output directory required}"
FINAL_DMG_PATH="${OUTPUT_DIR}/YABus-${VERSION}-macos.dmg"

mkdir -p "${OUTPUT_DIR}"

if ! command -v codesign &>/dev/null; then
  echo "codesign is required to package the macOS DMG."
  exit 1
fi

# Install create-dmg via npm if not present
if ! command -v create-dmg &>/dev/null; then
  echo "Installing create-dmg…"
  npm install --global create-dmg
fi

# create-dmg expects a signed app bundle. Use ad-hoc signing in CI when
# no Developer ID certificate is configured.
echo "Ad-hoc signing app bundle…"
codesign --force --deep --sign - "${APP_PATH}"
codesign --verify --deep --strict "${APP_PATH}"

# create-dmg generates the DMG filename automatically from the app name,
# then we rename it to our preferred naming scheme.
create-dmg \
  --overwrite \
  --dmg-title="YABus" \
  "${APP_PATH}" \
  "${OUTPUT_DIR}"

# create-dmg outputs "YABus {version}.dmg" — rename to our format
GENERATED_DMG="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "YABus *.dmg" -type f | head -1)"
if [ -z "${GENERATED_DMG}" ]; then
  echo "create-dmg did not produce a DMG file."
  exit 1
fi

mv "${GENERATED_DMG}" "${FINAL_DMG_PATH}"

echo "Ad-hoc signing DMG…"
codesign --force --sign - "${FINAL_DMG_PATH}"
codesign --verify --strict "${FINAL_DMG_PATH}"

echo "DMG created: ${FINAL_DMG_PATH}"
