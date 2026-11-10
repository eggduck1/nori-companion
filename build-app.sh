#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$APP_ROOT"

swift build --configuration release
BIN_PATH="$(swift build --show-bin-path --configuration release)"
APP_BUNDLE="$APP_ROOT/build/Nori.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH/NoriCompanion" "$APP_BUNDLE/Contents/MacOS/NoriCompanion"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
echo "Open it with: open \"$APP_BUNDLE\""
