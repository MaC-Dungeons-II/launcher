#!/bin/bash
# Build Flightdeck's Store/User bridge (marselnenaj/flightdeck-msfs-2024-linux-xbox)
# for the Mac runtime. XStore license queries go to the local xodus broker,
# which answers only from Microsoft-signed license tokens.
#
# Outputs in $OUT/artifacts:
#   xgameruntime.dll          proxy the game loads (wraps xgameruntime_original.dll)
#   xodus_store_test.dll      Wine builtin User/Store module (PE)
#   xodus_store_test.so       Unix socket transport to xodus-service (x86_64)
#
# Inputs:
#   $FD    Flightdeck checkout (compat/runtime, compat/patches)
#   $SRC   Sightem/WineGDK b5d23b0 with compat/patches/winegdk-runtime.patch applied
set -euo pipefail

D2=${D2:-$(cd "$(dirname "$0")/.." && pwd)/.work}
FD=${FD:?Flightdeck checkout}
SRC=${SRC:-$D2/src-fd/wine}
OUT=${OUT:-$D2/build-fd}
MINGW=$(echo "$D2"/toolchain/llvm-mingw-*/bin)
JOBS=$(sysctl -n hw.ncpu)
export PATH="/opt/local/bin:$MINGW:/usr/bin:/bin:/usr/sbin:/sbin"

common=(--disable-tests --without-x --without-ffmpeg --without-gnutls --without-freetype --without-vulkan)

echo "== tools (arm64)"
mkdir -p "$OUT/tools" && cd "$OUT/tools"
[ -f Makefile ] || "$SRC/configure" --enable-archs=x86_64 "${common[@]}" \
  CC=/usr/bin/clang CXX=/usr/bin/clang++ >configure.log 2>&1
make -j"$JOBS" __tooldeps__ >make.log 2>&1

echo "== xodus_store_test.dll (PE)"
mkdir -p "$OUT/wine" && cd "$OUT/wine"
[ -f Makefile ] || "$SRC/configure" --host=x86_64-apple-darwin --enable-archs=x86_64 "${common[@]}" \
  --with-wine-tools="$OUT/tools" \
  CC="/usr/bin/clang -arch x86_64" CXX="/usr/bin/clang++ -arch x86_64" \
  x86_64_CC=x86_64-w64-mingw32-clang x86_64_CXX=x86_64-w64-mingw32-clang++ >configure.log 2>&1
make -j"$JOBS" dlls/xgameruntime/x86_64-windows/xodus_store_test.dll >make.log 2>&1

A="$OUT/artifacts"; mkdir -p "$A"
cp dlls/xgameruntime/x86_64-windows/xodus_store_test.dll "$A/"

echo "== xodus_store_test.so (x86_64 macOS)"
/usr/bin/clang -arch x86_64 -shared -fPIC -O2 -D__WINESRC__ -DWINE_NO_TRACE_MSGS -DWINE_NO_DEBUG_MSGS \
  -fshort-wchar -pthread -undefined dynamic_lookup -I"$SRC/include" -I"$OUT/wine/include" \
  "$SRC/dlls/xgameruntime/GDKComponent/Xodus/Unix/socket.c" -o "$A/xodus_store_test.so"

echo "== proxy xgameruntime.dll"
R="$OUT/runtime"; rm -rf "$R"; cp -R "$FD/compat/runtime" "$R"
for h in xasync xgameerr xgameruntimetypes xtaskqueue; do cp "$SRC/include/$h.h" "$R/include/"; done
for h in xasyncprovider xgameruntimefeature xnetworking xsystem xuser; do
  "$OUT/tools/tools/widl/widl" --win64 -D__WINESRC__ -h -I "$SRC/include" -o "$R/include/$h.h" "$SRC/include/$h.idl"
done
"$OUT/tools/tools/widl/widl" --win64 -D__WINESRC__ -h -I "$SRC/include" -o "$R/include/xstore.h" "$R/idl/xstore.idl"
(cd "$R" && sed -e 's/x86_64-w64-mingw32-g++ -std=c++17 /x86_64-w64-mingw32-clang++ -std=c++17 -include type_traits /' build.sh > build-mac.sh && bash build-mac.sh >build.log 2>&1)
cp "$R/xgameruntime.dll" "$A/"
ls -la "$A"
