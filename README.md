# M(a)C Dungeons II

**English** · [한국어](README.ko.md)

An unofficial launcher that runs **Minecraft Dungeons II** (Minecraft Launcher / Microsoft Store edition) on macOS.
Sign in with your Microsoft account and it downloads the game under your own license and runs it in Wine. No VM, no streaming from a Windows PC. Just one app.

> [!CAUTION]
> This is an unofficial project. Use it at your own risk. It is not affiliated with, endorsed by, or sponsored by Mojang, Microsoft or Xbox. Minecraft, Minecraft Dungeons and all other trademarks, product names, and company names or logos mentioned here are the property of their respective owners.

> [!IMPORTANT]
> **You need an account that owns the game.** The license check is not bypassed. The game checks your account's Microsoft-signed license as usual and won't run on an account that doesn't own it.

The Steam edition got a Linux/Steam Deck update; the Launcher edition didn't. I made this to play my Launcher copy on a Mac.

## What works

Checked on an M4 MacBook (macOS 27).

- Online play, including the heroes you already had on Windows
- Settings and saves
- Intro and in-game videos
- Bluetooth Xbox controllers
- Quitting from the game menu (the launcher shuts Wine down and closes too)

Tested on one machine only. A game update may break things.

## Requirements

- Apple Silicon Mac with Rosetta 2
- macOS 14 or later
- A Microsoft account that owns Minecraft Dungeons II
- About 25 GB free for the first install (about 10 GB download)

## Install

1. Get `MaC-Dungeons-II.dmg` from [Releases](../../releases), open it, and drag the app to Applications.
2. Open the app. It isn't notarized, so macOS blocks it the first time. Go to **System Settings → Privacy & Security** and click **Open Anyway**.
3. Sign in and wait. The first run downloads the game. After that it only checks for updates.

What the app does:

1. Microsoft sign-in (refresh token stored in the keychain as "M(a)C Dungeons II")
2. Microsoft GDK runtime license consent → downloaded from nuget.org, SHA-256 checked
3. Game version check → if needed, download from Microsoft's CDN and extract (parallel, resumable, shows speed and time left)
4. Launch the game

All data lives in `~/Library/Application Support/M(a)C Dungeons II`. To remove everything, delete the app, that folder, and the keychain item.

## How it works

The game expects the Xbox GDK runtime. On a Mac, a few layers on top of Wine fill that in.

```
Dungeons-WinGDK-Shipping.exe
 └─ xgameruntime.dll            mcd2-crossover adapter — Xbox session, curl wrapper
     └─ xgameruntime-native.dll Flightdeck proxy — Store, saves, websockets
         └─ xgameruntime_original.dll  Microsoft's genuine GDK runtime (downloaded on first run)
macd2-broker   answers Store license queries from your Microsoft-signed license (xodus)
macd2          sign-in, session refresh, download/extract, launch (xodus)
```

- Wine — built from CodeWeavers' CrossOver 26.3 sources
- DXMT — Direct3D 11 → Metal
- GStreamer — game videos (H.264)
- SDL — controller input

Details per layer: [docs/architecture.md](docs/architecture.md).

Notes:

- The game's executables stay encrypted on disk. At launch they're decrypted into a RAM disk only.
- Saves stay in a local store inside the Wine prefix. Heroes live on the game's servers, so they load the same as on Windows.
- This repo and the release contain no Microsoft or Mojang files. The game, the GDK runtime and curl are downloaded on first run.

## Building

> [!IMPORTANT]
> Built on a single M4 Mac. `mac/build-runtime.sh` is a copy of the steps actually run; it hasn't been re-run from scratch on a clean machine.

Inputs are listed at the top of `mac/build-runtime.sh`. Put them all under `.work/` in the repo (git-ignored).

- CrossOver sources with `mac/patches/` applied
- llvm-mingw
- FFmpeg 7.1.1
- GStreamer 1.28.7
- SDL 2.32.10
- DXMT 68af85e
- GDK-Proton 11-7 builtins

Order:

1. `mac/build-store-bridge.sh` — WineGDK pieces and the Flightdeck proxy
2. `mac/build-runtime.sh` — Wine runtime
3. Build the [mcd2-crossover fork](https://github.com/MaC-Dungeons-II/mcd2-crossover) with llvm-mingw → `xgameruntime.dll`, `XCurl.dll`
4. `cargo build --release` in the [xodus fork](https://github.com/MaC-Dungeons-II/xodus)
5. `app/build.sh` → app in `app/dist/`
6. `app/dmg/make_dmg.sh` → `app/dist/MaC-Dungeons-II.dmg`

To regenerate the app icon (Icon Composer format, Liquid Glass), run:

```bash
uv run --no-project --with pillow python app/icon/make_icon.py
```

## Not done yet

- Saves aren't uploaded to the Xbox cloud. They stay on the Mac.
- Updates download the full package again, not a delta.
- Not notarized.

## Components

| Component | Repository | License |
|---|---|---|
| Launcher app, build scripts, Wine patches | this repo | MIT (Wine patches LGPL-2.1+) |
| xodus (`macd2`, `macd2-broker`) | [MaC-Dungeons-II/xodus](https://github.com/MaC-Dungeons-II/xodus) | GPL-3.0 |
| Runtime proxy | [MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox](https://github.com/MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox) | LGPL-2.1+ |
| Runtime adapter, XCurl wrapper | [MaC-Dungeons-II/mcd2-crossover](https://github.com/MaC-Dungeons-II/mcd2-crossover) | MIT |
| Wine | CodeWeavers crossover-sources 26.3 | LGPL-2.1+ |
| DXMT, GDK-Proton, WineGDK, GStreamer, FFmpeg, SDL | see [app/NOTICE.md](app/NOTICE.md) | per project |

Changes in the forks are on their `macos` branches.

## Credits

- [xodus](https://github.com/xodus-gaming/xodus) — Microsoft sign-in, licenses, package downloads
- [Flightdeck](https://github.com/marselnenaj/flightdeck-msfs-2024-linux-xbox) — GDK runtime proxy, Store broker
- [mcd2-crossover](https://github.com/Wanzho/mcd2-crossover) — the adapter that made the genuine runtime usable
- [WineGDK](https://github.com/Sightem/WineGDK), [GDK-Proton](https://github.com/LukasPAH/GDK-Proton-Custom) — GDK builtins
- [DXMT](https://github.com/3Shain/dxmt) — Direct3D 11 → Metal
- CodeWeavers, the Wine project
