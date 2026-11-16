#!/bin/bash
# Builds build/Stanza.app and runs its self-check.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Stanza.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macosx15.0 Sources/*.swift -o "$APP/Contents/MacOS/Stanza"
cp Info.plist "$APP/Contents/Info.plist"
# The app icon and the menu-bar mark (made by design/logo/quatrain_variations.swift --icon).
cp Resources/Stanza.icns Resources/StanzaMenuBar.png Resources/StanzaMenuBar@2x.png "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/Stanza" --self-check
echo "Built $APP"
