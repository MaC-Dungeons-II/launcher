#!/bin/bash
# Build the Wine runtime that M(a)C Dungeons II.app ships (app/build.sh copies
# $RT into the bundle). Apple silicon host; Wine is x86_64 and runs under
# Rosetta.
#
# Wine for macOS is cross-built in two passes, because on macOS 27 the Command
# Line Tools' xcrun has no x86_64 slice:
#   1. tools/  Wine's build tools (widl, winebuild, ...) as native arm64
#   2. wine/   Wine itself for x86_64-apple-darwin, using those tools
#
# Inputs under $D2 (default ~/Games/dungeons2-mac):
#   src-cx/wine         CodeWeavers crossover-sources 26.3.0, wine/ directory
#                       (https://media.codeweavers.com/pub/crossover/source/)
#                       with mac/patches/wine-*.patch and winemac-*.patch applied
#   toolchain/llvm-mingw-*/bin   PE cross compiler (mstorsjo/llvm-mingw)
#   toolchain/hostlibs/x86_64    x86_64 gnutls/freetype dylibs and their deps
#   /opt/local                   MacPorts bison 3.x, gnutls/freetype headers
#   ffmpeg-x64          FFmpeg 7.1.1 LGPL build (build_ffmpeg below)
#   src-gst/root        official GStreamer macOS packages, expanded
#                       (gstreamer-1.0[-devel]-1.28.7-universal.pkg)
#   sdl-x64             SDL 2.32.10 x86_64 build (build_sdl below)
#   dxmt/<rev>          3Shain/dxmt CI artifact 68af85e (D3D11 on Metal)
#   gdk-wgdk            PE builtins from GDK-Proton 11-7 (LukasPAH/GDK-Proton-Custom):
#                       xgameruntime, wintypes, twinapi.appcore, windows.web,
#                       windows.devices.enumeration, windows.ui.core.textinput,
#                       Microsoft.WindowsAppRuntime.Bootstrap
#   build-fd            mac/build-store-bridge.sh output (Sightem/WineGDK with
#                       Flightdeck's runtime patch): gameinput, xodus_store_test
#
# Usage: mac/build-runtime.sh [ffmpeg|sdl|wine|assemble|all]   (default: all)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
D2=${D2:-$HOME/Games/dungeons2-mac}
SRC=${SRC:-$D2/src-cx/wine}
OUT=${OUT:-$D2/build-cx}
RT=${RT:-$D2/runtime-cx}
HOSTLIBS=$D2/toolchain/hostlibs/x86_64
MINGW=$(echo "$D2"/toolchain/llvm-mingw-*/bin)
FFMPEG=$D2/ffmpeg-x64
GST=$D2/src-gst/root
SDL=$D2/sdl-x64
DXMT=$D2/dxmt/68af85e96196e1cf9f50de9fe24c70f03a1db4a7
JOBS=$(sysctl -n hw.ncpu)
export PATH="/opt/local/bin:$MINGW:/usr/bin:/bin:/usr/sbin:/sbin"

# FFmpeg 7.1.1 (ffmpeg.org), decoders/demuxers for the game's mp4 videos only.
# LGPL: no --enable-gpl / --enable-nonfree.
build_ffmpeg() {
    local src=$D2/src-ffmpeg/ffmpeg-7.1.1
    mkdir -p "$D2/src-ffmpeg/build" && cd "$D2/src-ffmpeg/build"
    "$src/configure" --prefix="$FFMPEG" --enable-cross-compile --arch=x86_64 --target-os=darwin \
        --cc="/usr/bin/clang -arch x86_64" --enable-shared --disable-static \
        --disable-programs --disable-doc --disable-network --disable-autodetect --disable-x86asm \
        --disable-everything \
        --enable-demuxer=mov,mp3,aac,matroska,wav,ogg \
        --enable-decoder=h264,hevc,aac,mp3,mp3float,vp9,opus,vorbis,pcm_s16le,pcm_f32le \
        --enable-parser=h264,hevc,aac,mpegaudio,vp9,opus,vorbis \
        --enable-protocol=file --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb \
        --install-name-dir='@rpath'
    make -j"$JOBS" && make install
}

# SDL 2.32.10 (libsdl-org/SDL release, signature checked): winebus uses it
# for game controllers, which maps Xbox Bluetooth pads correctly on macOS.
build_sdl() {
    mkdir -p "$D2/src-sdl/build" && cd "$D2/src-sdl/build"
    cmake ../SDL2-2.32.10 -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$SDL" -DCMAKE_INSTALL_NAME_DIR=@rpath \
        -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF
    make -j"$JOBS" && make install
}

build_wine() {
    local common=(--disable-tests --without-x --disable-wineopenxr --disable-amd_ags_x64)

    echo "== tools (arm64)"
    mkdir -p "$OUT/tools" && cd "$OUT/tools"
    [ -f Makefile ] || "$SRC/configure" --enable-archs=x86_64 "${common[@]}" \
        --without-gnutls --without-vulkan --without-ffmpeg --without-gstreamer --without-sdl \
        CC=/usr/bin/clang CXX=/usr/bin/clang++ \
        FREETYPE_CFLAGS="-I/opt/local/include/freetype2" FREETYPE_LIBS="-L/opt/local/lib -lfreetype" \
        >configure.log 2>&1
    make -j"$JOBS" __tooldeps__ >make.log 2>&1

    echo "== wine (x86_64)"
    mkdir -p "$OUT/wine" && cd "$OUT/wine"
    "$SRC/configure" --prefix="$RT" --host=x86_64-apple-darwin --enable-archs=x86_64 "${common[@]}" \
        --with-wine-tools="$OUT/tools" \
        CC="/usr/bin/clang -arch x86_64" CXX="/usr/bin/clang++ -arch x86_64" \
        x86_64_CC=x86_64-w64-mingw32-clang x86_64_CXX=x86_64-w64-mingw32-clang++ \
        GNUTLS_CFLAGS="-I/opt/local/include" GNUTLS_LIBS="-L$HOSTLIBS -lgnutls" \
        FREETYPE_CFLAGS="-I/opt/local/include/freetype2" FREETYPE_LIBS="-L$HOSTLIBS -lfreetype" \
        FFMPEG_CFLAGS="-I$FFMPEG/include" FFMPEG_LIBS="-L$FFMPEG/lib -lavformat -lavcodec -lavutil" \
        GSTREAMER_CFLAGS="-I$GST/include/gstreamer-1.0 -I$GST/include/glib-2.0 -I$GST/lib/glib-2.0/include -I$GST/include" \
        GSTREAMER_LIBS="-L$GST/lib -lgstreamer-1.0 -lgstvideo-1.0 -lgstaudio-1.0 -lgsttag-1.0 -lgstbase-1.0 -lgobject-2.0 -lglib-2.0" \
        SDL2_CFLAGS="-I$SDL/include/SDL2" SDL2_LIBS="-L$SDL/lib -lSDL2" \
        CFLAGS="-O2" LDFLAGS="-L$HOSTLIBS" \
        >configure.log 2>&1
    grep -E "SONAME_LIB(GNUTLS|FREETYPE|SDL2)" include/config.h
    make -j"$JOBS" >make.log 2>&1
    make install >install.log 2>&1
}

assemble() {
    local unix=$RT/lib/wine/x86_64-unix pe=$RT/lib/wine/x86_64-windows
    echo "== host libraries"
    cp -n "$HOSTLIBS"/*.dylib "$RT/lib/" 2>/dev/null || true
    cp "$FFMPEG"/lib/lib{avformat.61,avcodec.61,avutil.59,swresample.5}.dylib "$RT/lib/"
    cp "$SDL/lib/libSDL2-2.0.0.dylib" "$RT/lib/"
    # bundle-gstreamer.sh later replaces these with the GStreamer build of
    # FFmpeg (same major versions); winedmo resolves FFmpeg from lib/
    otool -l "$unix/winedmo.so" | grep -q '@loader_path/../..' || install_name_tool -add_rpath @loader_path/../.. "$unix/winedmo.so"

    echo "== DXMT (d3d11/dxgi on Metal)"
    cp "$DXMT"/x86_64-windows/{d3d11,dxgi,d3d10core,winemetal}.dll "$pe/"
    cp "$DXMT/x86_64-unix/winemetal.so" "$unix/"

    echo "== GDK builtins"
    cp "$D2"/gdk-wgdk/*.dll "$pe/"
    cp "$D2/build-fd/wine/dlls/gameinput/x86_64-windows/gameinput.dll" "$pe/"
    cp "$D2/build-fd/artifacts/xodus_store_test.dll" "$pe/"
    cp "$D2/build-fd/artifacts/xodus_store_test.so" "$unix/"

    echo "== GStreamer (in-game videos)"
    GST="$GST" BUILD="$OUT/wine" RT="$RT" "$HERE/bundle-gstreamer.sh"

    mkdir -p "$RT/share/licenses/sdl2"
    cp "$D2/src-sdl/SDL2-2.32.10/LICENSE.txt" "$RT/share/licenses/sdl2/"
    find "$RT/lib" -maxdepth 1 -name '*.dylib' -exec codesign --force --sign - {} \;
    codesign --force --sign - "$unix"/*.so
}

case ${1:-all} in
    ffmpeg) build_ffmpeg ;;
    sdl) build_sdl ;;
    wine) build_wine ;;
    assemble) assemble ;;
    all) build_ffmpeg; build_sdl; build_wine; assemble ;;
    *) echo "usage: $0 [ffmpeg|sdl|wine|assemble|all]" >&2; exit 2 ;;
esac
echo "RUNTIME_OK $RT"
