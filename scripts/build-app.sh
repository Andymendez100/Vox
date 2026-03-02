#!/bin/bash
set -euo pipefail

# Build SttTool as a proper macOS .app bundle
# Usage: ./scripts/build-app.sh [--release]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="SttTool"
BUNDLE_NAME="${APP_NAME}.app"
BUILD_DIR="${PROJECT_DIR}/build"

# Parse args
BUILD_CONFIG="debug"
if [[ "${1:-}" == "--release" ]]; then
    BUILD_CONFIG="release"
fi

echo "==> Building ${APP_NAME} (${BUILD_CONFIG})..."
cd "$PROJECT_DIR"
swift build -c "$BUILD_CONFIG"

# Locate the built executable
if [[ "$BUILD_CONFIG" == "release" ]]; then
    EXECUTABLE="${PROJECT_DIR}/.build/release/${APP_NAME}"
else
    EXECUTABLE="${PROJECT_DIR}/.build/debug/${APP_NAME}"
fi

if [[ ! -f "$EXECUTABLE" ]]; then
    echo "ERROR: Executable not found at ${EXECUTABLE}"
    exit 1
fi

echo "==> Creating app bundle..."
rm -rf "${BUILD_DIR}/${BUNDLE_NAME}"
mkdir -p "${BUILD_DIR}/${BUNDLE_NAME}/Contents/MacOS"
mkdir -p "${BUILD_DIR}/${BUNDLE_NAME}/Contents/Resources"

# Copy executable
cp "$EXECUTABLE" "${BUILD_DIR}/${BUNDLE_NAME}/Contents/MacOS/${APP_NAME}"

# Copy Info.plist
cp "${PROJECT_DIR}/SttTool/Info.plist" "${BUILD_DIR}/${BUNDLE_NAME}/Contents/"

# Copy icon if it exists and is not empty
ICON_FILE="${PROJECT_DIR}/SttTool/Resources/AppIcon.icns"
if [[ -f "$ICON_FILE" && -s "$ICON_FILE" ]]; then
    cp "$ICON_FILE" "${BUILD_DIR}/${BUNDLE_NAME}/Contents/Resources/"
fi

# Copy entitlements (used during signing)
ENTITLEMENTS="${PROJECT_DIR}/SttTool/SttTool.entitlements"

# Ad-hoc code sign
echo "==> Code signing (ad-hoc)..."
codesign --force --deep --sign - \
    --entitlements "$ENTITLEMENTS" \
    "${BUILD_DIR}/${BUNDLE_NAME}"

echo "==> Verifying signature..."
codesign --verify --deep --strict "${BUILD_DIR}/${BUNDLE_NAME}" && echo "    Signature OK" || echo "    WARNING: Signature verification failed"

echo ""
echo "==> Done! App bundle created at:"
echo "    ${BUILD_DIR}/${BUNDLE_NAME}"
echo ""
echo "To install, copy to /Applications:"
echo "    cp -r ${BUILD_DIR}/${BUNDLE_NAME} /Applications/"
echo ""
echo "To run directly:"
echo "    open ${BUILD_DIR}/${BUNDLE_NAME}"
echo ""
echo "NOTE: On first launch, you may need to right-click > Open to bypass Gatekeeper."
echo "      Then grant Microphone, Accessibility, and Input Monitoring permissions in"
echo "      System Settings > Privacy & Security."
