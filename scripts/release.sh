#!/bin/bash
# Builds Stanza, packs it into a disk image, signs that for the updater and writes the update feed.
#   scripts/release.sh             make build/release/Stanza-<version>.dmg and appcast.xml
#   scripts/release.sh --publish   then publish both as GitHub release v<version>
# The version comes from Info.plist (raise CFBundleShortVersionString and CFBundleVersion first) and the
# notes from that version's section in CHANGELOG.md. Signing uses the private key that
# `Vendor/Sparkle-*/bin/generate_keys --account tech.rayhanson.stanza` keeps in the login Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=Rayhanson-Git/stanza
KEY_ACCOUNT=tech.rayhanson.stanza
VOLUME=Stanza
# The install window: its size and the two icon spots match design/dmg/dmg_background.swift.
WINDOW_WIDTH=640 WINDOW_HEIGHT=400 ICON_Y=186 APP_X=170 APPLICATIONS_X=470 ICON_SIZE=112

publish=false
[ "${1:-}" = "--publish" ] && publish=true

./build.sh
plist() { /usr/libexec/PlistBuddy -c "Print :$1" build/Stanza.app/Contents/Info.plist; }
VERSION=$(plist CFBundleShortVersionString)
BUILD=$(plist CFBundleVersion)
MIN_SYSTEM=$(plist LSMinimumSystemVersion)
# The Sparkle tools of the version build.sh pins.
SPARKLE_BIN="Vendor/Sparkle-$(sed -n 's/^SPARKLE_VERSION=//p' build.sh)/bin"

OUT=build/release
DMG="$OUT/Stanza-$VERSION.dmg"
rm -rf "$OUT" && mkdir -p "$OUT"

# The release notes: this version's bullets from CHANGELOG.md.
NOTES=$(awk -v v="## $VERSION" '$0 == v {on = 1; next} /^## / {on = 0} on' CHANGELOG.md | sed '/^$/d')
[ -n "$NOTES" ] || { echo "CHANGELOG.md has no section for $VERSION"; exit 1; }

if [ -e "/Volumes/$VOLUME" ]; then echo "/Volumes/$VOLUME is already mounted; eject it first"; exit 1; fi

# 1. A writable image holding the app, a link to Applications and the background.
# Everything temporary is cleaned up however the script ends: the key copy, the staging folder and a mounted image.
stage=$(mktemp -d) keydir="" mounted=false
detach() {
    for _ in 1 2 3 4 5; do hdiutil detach -quiet "/Volumes/$VOLUME" 2>/dev/null && return 0; sleep 2; done
    hdiutil detach -quiet -force "/Volumes/$VOLUME"
}
cleanup() {
    if [ -n "$keydir" ]; then rm -P "$keydir/key" 2>/dev/null || true; rm -rf "$keydir"; fi
    if $mounted; then detach || true; fi
    rm -rf "$stage"
}
trap cleanup EXIT
ditto build/Stanza.app "$stage/Stanza.app"
ln -s /Applications "$stage/Applications"
mkdir "$stage/.background"
cp Resources/DMGBackground.tiff "$stage/.background/background.tiff"
cp Resources/Stanza.icns "$stage/.VolumeIcon.icns"
hdiutil create -quiet -srcfolder "$stage" -volname "$VOLUME" -fs HFS+ -format UDRW -ov "$OUT/rw.dmg"

# 2. Lay out the window in Finder. A failure here only costs the layout, never the release.
hdiutil attach -quiet -readwrite -noverify -noautoopen -mountpoint "/Volumes/$VOLUME" "$OUT/rw.dmg"
mounted=true
# The disk's own icon. The app itself gets no Finder flags: they would fail macOS's strict signature check.
if command -v SetFile >/dev/null; then
    SetFile -a C "/Volumes/$VOLUME" || echo "could not set the disk icon"
else
    echo "SetFile missing: the disk keeps the plain icon"
fi
perl -e 'alarm 60; exec @ARGV' osascript <<EOF || echo "Finder layout skipped: the window opens with Finder's own arrangement"
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, $((200 + WINDOW_WIDTH)), $((120 + WINDOW_HEIGHT + 28))}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to $ICON_SIZE
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Stanza.app" of container window to {$APP_X, $ICON_Y}
        set position of item "Applications" of container window to {$APPLICATIONS_X, $ICON_Y}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
sync
detach
mounted=false

# 3. Compress, then sign the exact bytes people will download.
hdiutil convert -quiet "$OUT/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$OUT/rw.dmg"
# generate_keys made the Keychain item, so it reads it without a prompt; sign_update would ask on screen.
# The key passes through a private temporary file that is overwritten and removed straight after.
keydir=$(mktemp -d) && chmod 700 "$keydir"
"$SPARKLE_BIN/generate_keys" --account "$KEY_ACCOUNT" -x "$keydir/key" >/dev/null
SIGNATURE=$("$SPARKLE_BIN/sign_update" --ed-key-file "$keydir/key" "$DMG")
rm -P "$keydir/key"
[[ "$SIGNATURE" == sparkle:edSignature=* ]] || { echo "signing failed"; exit 1; }

# 4. The update feed Sparkle reads (SUFeedURL points at the latest release's copy of this file).
python3 -I - "$OUT/appcast.xml" "$VERSION" "$BUILD" "$MIN_SYSTEM" "$REPO" "$SIGNATURE" "$NOTES" <<'EOF'
import sys
from email.utils import formatdate
from html import escape
path, version, build, min_system, repo, signature, notes = sys.argv[1:]
items = "".join(f"<li>{escape(line[2:].strip())}</li>" for line in notes.splitlines() if line.startswith(("- ", "* ")))
url = f"https://github.com/{repo}/releases/download/v{version}/Stanza-{version}.dmg"
feed = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Stanza</title>
    <item>
      <title>Stanza {escape(version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(min_system)}</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>{items}</ul>]]></description>
      <enclosure url="{url}" {signature} type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""
open(path, "w", encoding="utf-8").write(feed)
EOF
echo "Made $DMG and $OUT/appcast.xml"

$publish || exit 0

# 5. Publish. The commit being released must already be on GitHub.
# The image was built from the working tree, so it must match the pushed commit exactly, new files included.
[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first"; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "Push main to GitHub first"; exit 1; }
cat > "$OUT/notes.md" <<EOF
$NOTES

### Install

1. Download **Stanza-$VERSION.dmg** below and open it.
2. Drag **Stanza** into **Applications**, then open it from there.
3. The first time, macOS says it cannot check Stanza for malicious software, because Stanza is not notarised by Apple. Click **Done**, then open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Stanza.

From then on Stanza updates itself. Needs a Mac with Apple silicon and macOS 15 or later.
EOF
gh release create "v$VERSION" "$DMG" "$OUT/appcast.xml" --repo "$REPO" --target main \
    --title "Stanza $VERSION" --notes-file "$OUT/notes.md"
echo "Published https://github.com/$REPO/releases/tag/v$VERSION"
