# M(a)C Dungeons II — third-party notice

Unofficial macOS launcher. Not affiliated with, endorsed by, or sponsored by
Mojang, Microsoft or Xbox. Minecraft and Minecraft Dungeons are trademarks of
Microsoft. You need your own copy of the game; it is downloaded from Microsoft
with your account's license.

## Bundled (source available, modified where noted)

| Component | License | Notes |
|---|---|---|
| Wine (CodeWeavers crossover-sources 26.3) | LGPL-2.1-or-later | built for Apple silicon via Rosetta; small build patch |
| DXMT (3Shain/dxmt) | see upstream | Direct3D 11 to Metal |
| GStreamer 1.28.7 (core, base, good, bad, libav plugins; GLib) from the official macOS packages, x86_64 subset | LGPL-2.1-or-later (see licenses/gstreamer) | decodes in-game H.264/AAC videos for Media Foundation (winegstreamer) |
| FFmpeg (libavcodec, libavformat, libavutil, libswresample, libswscale; from the GStreamer build) | LGPL-2.1-or-later | used by gst-libav and winedmo |
| SDL 2.32.10 (libsdl-org/SDL) | zlib | game controller input (winebus SDL backend) |
| GDK builtins from GDK-Proton 11-7 (LukasPAH/GDK-Proton-Custom, WineGDK-based): xgameruntime, wintypes, twinapi.appcore, windows.* | LGPL-2.1-or-later | PE builtins, unmodified |
| WineGDK (Sightem/WineGDK b5d23b0) + Flightdeck runtime patch: gameinput, xodus_store_test | LGPL-2.1-or-later | built by mac/build-store-bridge.sh |
| Flightdeck runtime (marselnenaj/flightdeck-msfs-2024-linux-xbox), shipped as `xgameruntime.dll` | LGPL-2.1-or-later | modified for this launcher (MaC-Dungeons-II fork, `macos` branch); its title-config default follows mcd2-crossover (MIT, see below) |
| XCurl wrapper (`XCurl.dll`, `compat/xcurl` in the same fork) | MIT | behaviour follows the XCurl wrapper and Wine wait-queue fix of mcd2-crossover (Wanzho/mcd2-crossover), MIT, Copyright (c) 2026 Wanzho |
| xodus (xodus-gaming/xodus), shipped as `macd2` / `macd2-broker` | GPL-3.0 | modified: mac-fetch, mac-session (`--check`), keychain/socket names |

## Downloaded on first run (not bundled)

| Component | Source | Verification |
|---|---|---|
| Microsoft GDK runtime 2604.4.7897 (xgameruntime) | nuget.org, Microsoft.GDK.Windows | SHA-256 pinned; you accept Microsoft's license in the launcher |
| curl 8.22.0 for Windows | curl.se | SHA-256 pinned |
| The game | Microsoft, with your account's license | package identity checked by xodus |

## License texts in the app

`Contents/Resources/licenses/` holds this notice and the license files that
`app/build.sh` copies: xodus (GPL-3.0), Wine (LGPL-2.1 and its LICENSE) and
FFmpeg (LGPL-2.1). GStreamer's license files are in
`Contents/Resources/wine/share/licenses/gstreamer`. curl's license is saved next
to curl when the app downloads it.

mcd2-crossover's MIT license, which applies to the XCurl wrapper and the
title-config default above:

    Copyright (c) 2026 Wanzho

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
