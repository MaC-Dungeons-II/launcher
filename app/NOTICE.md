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
| Flightdeck runtime proxy (marselnenaj/flightdeck-msfs-2024-linux-xbox) | LGPL-2.1-or-later | modified for this launcher |
| mcd2-crossover adapter and curl wrapper (Wanzho/mcd2-crossover) | MIT | modified for this launcher |
| wasdmod 1.5.1 xinput1_4.dll, layouts, Korean texts (Wanzho/mcd2-wasd da3c591) | MIT | unmodified, Nexus flavor (no update check), built by mac/build-wasdmod.sh; the key layout editor is ported to Swift (app/Sources/KeyEditor.swift, WasdModel.swift) |
| xodus (xodus-gaming/xodus), shipped as `macd2` / `macd2-broker` | GPL-3.0 | modified: mac-fetch, mac-session, keychain/socket names |

## Downloaded on first run (not bundled)

| Component | Source | Verification |
|---|---|---|
| Microsoft GDK runtime 2604.4.7897 (xgameruntime) | nuget.org, Microsoft.GDK.Windows | SHA-256 pinned; you accept Microsoft's license in the launcher |
| curl 8.22.0 for Windows | curl.se | SHA-256 pinned |
| The game | Microsoft, with your account's license | package identity checked by xodus |
