#!/usr/bin/env bash
#
# build-app.sh — build GitKeys in release mode and assemble dist/GitKeys.app
#
# Usage: scripts/build-app.sh   (from anywhere; the script cd's to the repo root)
#
set -euo pipefail

# Resolve the repo root from this script's location, regardless of cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

APP_NAME="GitKeys"
BUNDLE_ID="com.matej.gitkeys"
VERSION="${VERSION:-0.2.0}"
DIST_DIR="${REPO_ROOT}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
ICNS_SRC="${REPO_ROOT}/Assets/AppIcon.icns"

# Build a universal (arm64 + x86_64) binary so the released app runs on
# Intel Macs too — CI builds on Apple Silicon runners, and an arm64-only
# Mach-O cannot launch on x86_64 at all (Rosetta does not apply).
echo "==> Building ${APP_NAME} (release, universal)"
swift build -c release --arch arm64 --arch x86_64

BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
    echo "error: release binary not found at ${BIN_PATH}" >&2
    exit 1
fi

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

if [[ -f "${ICNS_SRC}" ]]; then
    cp "${ICNS_SRC}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
else
    echo "warning: ${ICNS_SRC} not found; run 'swift scripts/generate_icon.swift' first. Continuing without an icon." >&2
fi

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

echo "==> Code signing (ad-hoc)"
if codesign --force -s - "${APP_DIR}"; then
    echo "==> Signed ${APP_NAME}.app with ad-hoc identity"
else
    echo "warning: ad-hoc codesign failed; the app is unsigned but may still run locally." >&2
fi

echo "==> Done: ${APP_DIR}"
