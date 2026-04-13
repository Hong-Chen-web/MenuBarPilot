#!/bin/bash
# Build and package MenuBarPilot as a macOS .app bundle

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/debug"
APP_BUNDLE="$PROJECT_DIR/build/MenuBarPilot.app"

echo "Building MenuBarPilot..."
cd "$PROJECT_DIR"
swift build -c debug

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/MenuBarPilot" "$APP_BUNDLE/Contents/MacOS/MenuBarPilot"

# Copy Info.plist
cp "$PROJECT_DIR/MenuBarPilot/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy Assets
cp -R "$PROJECT_DIR/MenuBarPilot/Assets.xcassets" "$APP_BUNDLE/Contents/Resources/Assets.xcassets"

echo "App bundle created at: $APP_BUNDLE"
echo "To run: open \"$APP_BUNDLE\""
