#!/bin/bash
# Package app/dist/M(a)C Dungeons II.app as a drag-to-install DMG:
# app + Applications link on a background with an arrow, app icon as the
# volume icon. The Finder layout is set with AppleScript on a writable image,
# then the image is converted to a compressed read-only one (ULFO, lzfse).
#
# Usage: app/dmg/make_dmg.sh [output.dmg]   (default app/dist/MaC-Dungeons-II.dmg)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
APP=${APP:-"$HERE/../dist/M(a)C Dungeons II.app"}
OUT=${1:-$HERE/../dist/MaC-Dungeons-II.dmg}
VOL="M(a)C Dungeons II"
NAME=$(basename "$APP")
[ -d "$APP" ] || { echo "build the app first (app/build.sh)" >&2; exit 1; }

WORK=$(mktemp -d)
MNT=
trap 'hdiutil detach -quiet "$MNT" 2>/dev/null || true; rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$NAME"
ln -s /Applications "$STAGE/Applications"
cp "$HERE/background.tiff" "$STAGE/.background/background.tiff"
cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

SIZE=$(( $(du -sm "$STAGE" | cut -f1) + 64 ))
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -size ${SIZE}m "$WORK/rw.dmg"
MNT=$(hdiutil attach -readwrite -noverify -noautoopen "$WORK/rw.dmg" | awk -F'\t' '/\/Volumes\//{print $NF}')
SetFile -a C "$MNT"

osascript <<EOF
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {200, 120, 840, 548}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "$NAME" of container window to {160, 190}
        set position of item "Applications" of container window to {480, 190}
        set extension hidden of item "$NAME" to true
        update without registering applications
        delay 1
        close
        open
        set bounds of container window to {200, 120, 840, 548}
        delay 1
        close
    end tell
end tell
EOF

chflags hidden "$MNT/.background" "$MNT/.VolumeIcon.icns" 2>/dev/null || true
sync
hdiutil detach -quiet "$MNT"
rm -f "$OUT"
hdiutil convert -quiet "$WORK/rw.dmg" -format ULFO -o "$OUT"
echo "DMG $OUT ($(du -h "$OUT" | cut -f1))"
