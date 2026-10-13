#!/bin/bash
# Assemble "M(a)C Dungeons II.app" from the locally built components.
# The app ships only the compatibility layer: no game files, no Microsoft GDK
# runtime and no curl (the launcher fetches those on first run, hash-checked).
#
# Inputs (D2, default .work/ in this repo):
#   runtime-cx/                     Wine (CrossOver sources, mac/build-runtime.sh) + DXMT + WineGDK builtins
#   build-fd/runtime/xgameruntime.dll   Flightdeck proxy (mac chain patches)
#   src-mcd2/build/{xgameruntime,XCurl}.dll  mcd2-crossover adapter + curl wrapper (patched)
#   src-xodus/xodus/target/release/{xodus-cli,xodus-service}  xodus (mac-fetch, mac-session)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
D2=${D2:-$(cd "$HERE/.." && pwd)/.work}
OUT=${OUT:-$HERE/dist}
APP="$OUT/M(a)C Dungeons II.app"
C="$APP/Contents"
R="$C/Resources"

echo "== launcher binary"
mkdir -p "$HERE/build"
swiftc -O -parse-as-library -target arm64-apple-macos14 "$HERE"/Sources/*.swift -o "$HERE/build/MaCDungeons"

echo "== bundle layout"
rm -rf "$APP"
mkdir -p "$C/MacOS" "$R/bin" "$R/layer" "$R/licenses"
cp "$HERE/build/MaCDungeons" "$C/MacOS/MaCDungeons"
cp "$HERE/Info.plist" "$C/Info.plist"
cp "$HERE/icon/compiled/AppIcon.icns" "$HERE/icon/compiled/Assets.car" "$HERE/icon/dock-mask.png" "$R/"   # from icon/make_icon.py (Icon Composer document)

echo "== wine runtime"
rsync -a --exclude include --exclude '*.a' --exclude 'share/man' "$D2/runtime-cx/" "$R/wine/"

echo "== compatibility layer"
cp "$D2/build-fd/runtime/xgameruntime.dll" "$R/layer/xgameruntime-native.dll"
cp "$D2/src-mcd2/build/xgameruntime.dll" "$R/layer/xgameruntime.dll"
cp "$D2/src-mcd2/build/XCurl.dll" "$R/layer/XCurl.dll"

echo "== helpers"
cp "$D2/src-xodus/xodus/target/release/xodus-cli" "$R/bin/macd2"
cp "$D2/src-xodus/xodus/target/release/xodus-service" "$R/bin/macd2-broker"

echo "== licenses"
cp "$D2/src-xodus/xodus/LICENSE" "$R/licenses/xodus-GPL-3.0.txt"
cp "$D2/src-mcd2/LICENSE" "$R/licenses/mcd2-crossover-MIT.txt"
cp "$D2/src-cx/wine/COPYING.LIB" "$R/licenses/wine-LGPL-2.1.txt" 2>/dev/null || true
cp "$D2/src-cx/wine/LICENSE" "$R/licenses/wine-LICENSE.txt" 2>/dev/null || true
cp "$D2/src-ffmpeg/ffmpeg-7.1.1/COPYING.LGPLv2.1" "$R/licenses/ffmpeg-LGPL-2.1.txt"
cp "$HERE/NOTICE.md" "$R/licenses/NOTICE.md"

echo "== ad-hoc signature"
codesign --force --deep --sign - "$APP" >/dev/null || { echo "error: codesign failed" >&2; exit 1; }
du -sh "$APP"
echo "BUILT $APP"
