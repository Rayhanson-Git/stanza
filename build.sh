#!/bin/bash
# Builds build/Stanza.app and runs its self-check.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Stanza.app

# Sparkle (the updater) is fetched once, pinned by version and checksum, into Vendor/ (not committed).
SPARKLE_VERSION=2.10.1
SPARKLE_SHA256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
SPARKLE_DIR="Vendor/Sparkle-$SPARKLE_VERSION"
if [ ! -d "$SPARKLE_DIR/Sparkle.framework" ]; then
    echo "Fetching Sparkle $SPARKLE_VERSION"
    mkdir -p Vendor
    archive="Vendor/Sparkle-$SPARKLE_VERSION.tar.xz"
    curl -fsSL -o "$archive" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
    echo "$SPARKLE_SHA256  $archive" | shasum -a 256 -c - >/dev/null || { echo "Sparkle download failed its checksum"; rm -f "$archive"; exit 1; }
    staging="$SPARKLE_DIR.partial"
    rm -rf "$staging" && mkdir -p "$staging"
    tar -xJf "$archive" -C "$staging"
    rm -rf "$SPARKLE_DIR" && mv "$staging" "$SPARKLE_DIR"
    rm -f "$archive"
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macosx15.0 Sources/*.swift -o "$APP/Contents/MacOS/Stanza" \
    -F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks
cp Info.plist "$APP/Contents/Info.plist"
# The app icon and the menu-bar mark (made by design/logo/quatrain_variations.swift --icon).
cp Resources/Stanza.icns Resources/StanzaMenuBar.png Resources/StanzaMenuBar@2x.png "$APP/Contents/Resources/"
# Sparkle keeps its own signature; ditto keeps the framework's symlinks intact.
rm -rf "$APP/Contents/Frameworks" && mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# Releases are signed with the maintainer's "Stanza Release Signing" certificate, so the app keeps one identity and
# macOS remembers its Spotify and Music permission across updates. Without that certificate it is signed ad hoc.
SIGNING_IDENTITY="Stanza Release Signing"
identities=$(security find-identity -p codesigning 2>/dev/null || true)
if [[ "$identities" == *"\"$SIGNING_IDENTITY\""* ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/Stanza" --self-check
echo "Built $APP"
