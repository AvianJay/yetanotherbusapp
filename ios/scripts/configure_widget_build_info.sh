#!/bin/sh

set -e

generated_xcconfig="${SRCROOT}/Flutter/Generated.xcconfig"
info_plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

read_generated_setting() {
  key="$1"
  if [ ! -f "$generated_xcconfig" ]; then
    return 1
  fi

  awk -F= -v lookup="$key" '$1 == lookup { print substr($0, index($0, "=") + 1); exit }' "$generated_xcconfig"
}

sanitize_value() {
  value="$(printf "%s" "${1:-}" | tr -d '\r')"
  value="$(printf "%s" "$value" | sed 's/[[:space:]]\+/_/g')"
  if [ -z "$value" ]; then
    printf "%s" "$2"
    return
  fi
  printf "%s" "$value"
}

set_plist_value() {
  key="$1"
  value="$2"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$info_plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$info_plist"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$info_plist"
  fi
}

version="$(read_generated_setting FLUTTER_BUILD_NAME || true)"
build_number="$(read_generated_setting FLUTTER_BUILD_NUMBER || true)"
git_sha="$(printf "%s" "${APP_GIT_SHA:-unknown}" | tr '[:upper:]' '[:lower:]')"

version="$(sanitize_value "$version" "unknown")"
build_number="$(sanitize_value "$build_number" "1")"
git_sha="$(sanitize_value "$git_sha" "unknown")"

set_plist_value "CFBundleShortVersionString" "$version"
set_plist_value "CFBundleVersion" "$build_number"
set_plist_value "YABusGitSha" "$git_sha"