#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/debug"
APP_BUNDLE="$PROJECT_DIR/build/MenuBarPilot.app"
RESOURCE_BUNDLE="$BUILD_DIR/MenuBarPilot_MenuBarPilot.bundle"

echo "Building MenuBarPilot..."
cd "$PROJECT_DIR"
swift build -c debug

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/MenuBarPilot" "$APP_BUNDLE/Contents/MacOS/MenuBarPilot"
cp "$PROJECT_DIR/MenuBarPilot/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

echo "App bundle created at: $APP_BUNDLE"
echo "To run: open \"$APP_BUNDLE\""
