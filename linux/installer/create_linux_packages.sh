#!/usr/bin/env bash
# YABus Linux packaging: .deb and AppImage
# Usage: create_linux_packages.sh <bundle_dir> <version> <output_dir>

set -euo pipefail

BUNDLE_DIR="${1:?Usage: create_linux_packages.sh <bundle_dir> <version> <output_dir>}"
VERSION="${2:?Version required}"
OUTPUT_DIR="${3:?Output directory required}"
ARCH="amd64"

APP_NAME="yabus"
APP_DISPLAY_NAME="YABus"
APP_ID="tw.avianjay.taiwanbus.flutter"
MAINTAINER="AvianJay"
DESCRIPTION="台灣公車即時動態查詢"
DEPS="libgtk-3-0, libglib2.0-0, libpango-1.0-0, libharfbuzz0b, libc6, libstdc++6"

SANITIZED_DEB_VERSION="$(printf '%s' "${VERSION}" | sed 's/[^A-Za-z0-9.+:~_-]/./g')"
NORMALIZED_DEB_VERSION="$(printf '%s' "${SANITIZED_DEB_VERSION}" | tr '-' '.')"
if [[ "${NORMALIZED_DEB_VERSION}" =~ ^[0-9] ]]; then
  DEB_VERSION="${NORMALIZED_DEB_VERSION}"
else
  DEB_VERSION="0~${NORMALIZED_DEB_VERSION}"
fi

mkdir -p "${OUTPUT_DIR}"

# ── .deb package ────────────────────────────────────────────
DEB_STAGING="$(mktemp -d)"
trap "rm -rf ${DEB_STAGING}" EXIT

INSTALL_DIR="/opt/${APP_NAME}"
mkdir -p "${DEB_STAGING}${INSTALL_DIR}"
mkdir -p "${DEB_STAGING}/usr/bin"
mkdir -p "${DEB_STAGING}/usr/share/applications"
mkdir -p "${DEB_STAGING}/usr/share/icons/hicolor/256x256/apps"
mkdir -p "${DEB_STAGING}/DEBIAN"

# Copy app bundle
cp -R "${BUNDLE_DIR}/." "${DEB_STAGING}${INSTALL_DIR}/"

# Wrapper script
cat > "${DEB_STAGING}/usr/bin/${APP_NAME}" <<SCRIPT
#!/bin/sh
exec ${INSTALL_DIR}/${APP_NAME} "\$@"
SCRIPT
chmod +x "${DEB_STAGING}/usr/bin/${APP_NAME}"

# .desktop entry
cat > "${DEB_STAGING}/usr/share/applications/${APP_ID}.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=${APP_DISPLAY_NAME}
Comment=${DESCRIPTION}
Exec=${APP_NAME}
Icon=${APP_NAME}
Categories=Utility;Maps;
Terminal=false
DESKTOP

# Copy icon if available (placeholder otherwise)
if [ -f "${BUNDLE_DIR}/data/flutter_assets/assets/branding/icon_transparent.png" ]; then
  cp "${BUNDLE_DIR}/data/flutter_assets/assets/branding/icon_transparent.png" \
     "${DEB_STAGING}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
fi

# Control file
INSTALLED_SIZE=$(du -sk "${DEB_STAGING}" | cut -f1)
cat > "${DEB_STAGING}/DEBIAN/control" <<CONTROL
Package: ${APP_NAME}
Version: ${DEB_VERSION}
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Description: ${DESCRIPTION}
Depends: ${DEPS}
Installed-Size: ${INSTALLED_SIZE}
Section: utils
Priority: optional
Homepage: https://github.com/AvianJay/yetanotherbusapp
CONTROL

# Post-install: update desktop database
cat > "${DEB_STAGING}/DEBIAN/postinst" <<POSTINST
#!/bin/sh
update-desktop-database /usr/share/applications 2>/dev/null || true
POSTINST
chmod 755 "${DEB_STAGING}/DEBIAN/postinst"

# Build .deb
DEB_FILE="${OUTPUT_DIR}/YABus-${VERSION}-linux-${ARCH}.deb"
dpkg-deb --build "${DEB_STAGING}" "${DEB_FILE}"
echo "DEB created: ${DEB_FILE}"

rm -rf "${DEB_STAGING}"

# ── AppImage ────────────────────────────────────────────────
# Download appimagetool if not present
APPIMAGETOOL="$(command -v appimagetool 2>/dev/null || echo '')"
if [ -z "${APPIMAGETOOL}" ]; then
  APPIMAGETOOL="/tmp/appimagetool"
  if [ ! -x "${APPIMAGETOOL}" ]; then
    echo "Downloading appimagetool..."
    curl -fsSL "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" \
      -o "${APPIMAGETOOL}"
    chmod +x "${APPIMAGETOOL}"
  fi
fi

APPDIR="$(mktemp -d)"
trap "rm -rf ${APPDIR}" EXIT

mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/icons/hicolor/256x256/apps"
mkdir -p "${APPDIR}/usr/lib"

# Copy app bundle
cp -R "${BUNDLE_DIR}/." "${APPDIR}/usr/lib/${APP_NAME}/"

# AppRun
cat > "${APPDIR}/AppRun" <<APPRUN
#!/bin/sh
SELF=\$(readlink -f "\$0")
HERE=\$(dirname "\$SELF")
exec "\$HERE/usr/lib/${APP_NAME}/${APP_NAME}" "\$@"
APPRUN
chmod +x "${APPDIR}/AppRun"

# .desktop entry (AppDir root)
cat > "${APPDIR}/${APP_ID}.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=${APP_DISPLAY_NAME}
Comment=${DESCRIPTION}
Exec=${APP_NAME}
Icon=${APP_NAME}
Categories=Utility;Maps;
Terminal=false
DESKTOP

# Icon
if [ -f "${BUNDLE_DIR}/data/flutter_assets/assets/branding/icon_transparent.png" ]; then
  cp "${BUNDLE_DIR}/data/flutter_assets/assets/branding/icon_transparent.png" \
     "${APPDIR}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
  ln -sf "usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png" "${APPDIR}/${APP_NAME}.png"
fi

# Build AppImage
APPIMAGE_FILE="${OUTPUT_DIR}/YABus-${VERSION}-linux-x86_64.AppImage"
APPIMAGE_EXTRACT_AND_RUN=1 "${APPIMAGETOOL}" "${APPDIR}" "${APPIMAGE_FILE}"
echo "AppImage created: ${APPIMAGE_FILE}"

rm -rf "${APPDIR}"

echo "All Linux packages created successfully."
