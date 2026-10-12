#!/bin/bash
# Add a minimal GStreamer (x86_64) to the Wine runtime so winegstreamer can
# decode the game's H.264/AAC videos through Media Foundation.
#
# Input: the official GStreamer macOS packages (gstreamer.freedesktop.org,
# gstreamer-1.0-<v>-universal.pkg + -devel-), expanded (not installed) into
# $GST (default .work/src-gst/root). Wine must already be
# configured with GSTREAMER_CFLAGS/LIBS pointing there (mac/build-runtime.sh)
# and winegstreamer built in $BUILD.
#
# Layout written into $RT (runtime-cx), matching the rpaths of the official
# binaries: lib/*.dylib, lib/gstreamer-1.0/*.dylib, libexec/gstreamer-1.0/.
set -euo pipefail

D2=${D2:-$(cd "$(dirname "$0")/.." && pwd)/.work}
GST=${GST:-$D2/src-gst/root}
BUILD=${BUILD:-$D2/build-cx/wine}
RT=${RT:-$D2/runtime-cx}

# Elements winegstreamer builds its pipelines from: decodebin + mp4 demux,
# libav decoders, parsers, and the convert/resample elements.
PLUGINS="coreelements playback typefindfunctions isomp4 libav audioparsers
videoparsersbad videoconvertscale audioconvert audioresample app autodetect
videorate volume deinterlace videofilter"

thin() {  # copy a Mach-O as an x86_64-only file
    local src=$1 dst=$2
    if lipo -archs "$src" 2>/dev/null | grep -q arm64; then
        lipo "$src" -thin x86_64 -output "$dst"
    else
        cp "$src" "$dst"
    fi
    chmod u+w "$dst"
}

# @rpath dependencies of a file, resolved against $GST/lib
deps() {
    local self
    self=$(otool -D "$1" | awk 'NR==2 {print $1}')
    otool -L "$1" | awk -v self="$self" 'NR>1 && $1 ~ /^@rpath\// && $1 != self {sub("@rpath/","",$1); print $1}'
}

mkdir -p "$RT/lib/gstreamer-1.0" "$RT/libexec/gstreamer-1.0"

queue=("$BUILD/dlls/winegstreamer/winegstreamer.so")
for p in $PLUGINS; do
    src="$GST/lib/gstreamer-1.0/libgst$p.dylib"
    [ -f "$src" ] || { echo "missing plugin $p" >&2; exit 1; }
    thin "$src" "$RT/lib/gstreamer-1.0/libgst$p.dylib"
    queue+=("$src")
done
thin "$GST/libexec/gstreamer-1.0/gst-plugin-scanner" "$RT/libexec/gstreamer-1.0/gst-plugin-scanner"
queue+=("$GST/libexec/gstreamer-1.0/gst-plugin-scanner")

seen=" "
while [ ${#queue[@]} -gt 0 ]; do
    f=${queue[0]}; queue=("${queue[@]:1}")
    for d in $(deps "$f"); do
        case $d in winegstreamer.so|ntdll.so) continue;; esac
        case $seen in *" $d "*) continue;; esac
        seen="$seen$d "
        src="$GST/lib/$d"
        [ -f "$src" ] || { echo "missing dependency $d" >&2; exit 1; }
        thin "$src" "$RT/lib/$d"
        queue+=("$src")
    done
done

# winegstreamer itself; resolve GStreamer from lib/ like winedmo does
cp "$BUILD/dlls/winegstreamer/winegstreamer.so" "$RT/lib/wine/x86_64-unix/winegstreamer.so"
cp "$BUILD/dlls/winegstreamer/x86_64-windows/winegstreamer.dll" "$RT/lib/wine/x86_64-windows/winegstreamer.dll"
so="$RT/lib/wine/x86_64-unix/winegstreamer.so"
install_name_tool -delete_rpath @loader_path/../../gstreamer "$so" 2>/dev/null || true
otool -l "$so" | grep -q '@loader_path/../..' || install_name_tool -add_rpath @loader_path/../.. "$so"

codesign --force --sign - "$so" "$RT/libexec/gstreamer-1.0/gst-plugin-scanner" "$RT"/lib/gstreamer-1.0/*.dylib
for d in $seen; do codesign --force --sign - "$RT/lib/$d"; done

mkdir -p "$RT/share/licenses"
rm -rf "$RT/share/licenses/gstreamer"
cp -R "$GST/share/licenses" "$RT/share/licenses/gstreamer"

echo "plugins: $(ls "$RT/lib/gstreamer-1.0" | wc -l | tr -d ' '), libraries: $(echo $seen | wc -w | tr -d ' ')"
du -sh "$RT/lib/gstreamer-1.0"
