#!/bin/bash
# Build wasdmod's xinput1_4.dll (keyboard and mouse as an Xbox controller,
# https://github.com/Wanzho/mcd2-wasd, MIT) from source, the Nexus flavor
# (no update check: the DLL links only kernel32, user32 and gdi32).
#
# Inputs under $D2 (default .work/ in this repo):
#   src-wasd            git clone of Wanzho/mcd2-wasd at $WASD_COMMIT
#   toolchain/llvm-mingw-*/bin/lld-link
# Output: $D2/wasdmod/{xinput1_4.dll,default.txt,author.txt,ko.json,LICENSE}
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
D2=${D2:-$(cd "$HERE/.." && pwd)/.work}
WASD_COMMIT=da3c5918b11de1119c88febcf73834029190ca30   # wasdmod 1.5.1
VERSION=1.5.1
SRC="$D2/src-wasd"
OUT="$D2/wasdmod"

[ -d "$SRC/.git" ] || { echo "clone https://github.com/Wanzho/mcd2-wasd into $SRC first" >&2; exit 1; }
[ "$(git -C "$SRC" rev-parse HEAD)" = "$WASD_COMMIT" ] || { echo "$SRC is not at $WASD_COMMIT" >&2; exit 1; }
LLD=$(ls "$D2"/toolchain/llvm-mingw-*/bin/lld-link 2>/dev/null | head -1)
[ -x "$LLD" ] || { echo "lld-link not found under $D2/toolchain/llvm-mingw-*/bin" >&2; exit 1; }

cd "$SRC"
mkdir -p build
# Import libraries for the DLL's imports, from upstream build.sh's export lists
# (pinned commit; the lines are plain printf).
grep -E "^printf 'LIBRARY (KERNEL32|USER32|GDI32)\.dll" build.sh | sh
for l in kernel32 user32 gdi32; do "$LLD" /lib /machine:x64 /def:build/$l.def /out:build/$l.lib >/dev/null; done

# Translation tables (build/lang_game.h)
WASDMOD_FLAVOR=nexus WASDMOD_VERSION=$VERSION uv run --no-project python lang.py

CFLAGS="-DVERSION=\"$VERSION\" -DNEXUS --target=x86_64-pc-windows-msvc -O2 -fno-stack-protector -fno-builtin -Wall -Wno-incompatible-pointer-types -Wno-int-conversion"
/usr/bin/clang $CFLAGS -Ibuild -c xinput_wasd.c -o build/xinput_wasd.obj
"$LLD" /dll /brepro /nodefaultlib /entry:DllMain /machine:x64 /def:xinput1_4.def /out:build/xinput1_4.dll \
    build/xinput_wasd.obj build/kernel32.lib build/user32.lib build/gdi32.lib
rm -f build/*.obj build/*.exp build/xinput1_4.lib

mkdir -p "$OUT"
cp build/xinput1_4.dll default.txt author.txt LICENSE "$OUT/"
cp lang/ko.json "$OUT/ko.json"   # the key layout editor's Korean (KeyEditor.swift)
echo "BUILT $OUT ($(shasum -a 256 "$OUT/xinput1_4.dll" | cut -c1-16)…)"
