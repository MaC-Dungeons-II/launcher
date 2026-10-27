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
- Quitting from the game menu (the launcher shuts Wine down too)

Tested on one machine only. A game update may break things.

## Requirements

- Apple Silicon Mac with Rosetta 2
- macOS 14 or later
- A Microsoft account that owns Minecraft Dungeons II
- About 25 GB free for the first install (about 10 GB download)

## Install

1. Get `MaC-Dungeons-II.dmg` from [Releases](../../releases), open it, and drag the app to Applications.
2. Open the app. It isn't notarized, so macOS blocks it the first time. Go to **System Settings → Privacy & Security** and click **Open Anyway**.

## Use

The window is styled after the Minecraft Launcher. When you open the app it:

1. Checks your Microsoft account. The app has its own sign-in, separate from the Minecraft Launcher's. The refresh token is kept in the macOS keychain (service "M(a)C Dungeons II").
2. Asks you to accept the Microsoft GDK runtime license once. The runtime is then downloaded from nuget.org and its SHA-256 checked.
3. Shows **Install** if the game isn't installed yet, or **Play** if it is.

Install (and Play, when an update is out) downloads the game from Microsoft's CDN and extracts it. The download bar shows bytes, speed and time left, and can be paused and resumed. Downloads are parallel and resume where they stopped. Then the game starts.

## Play from the Minecraft Launcher (optional)

Off by default. Turn on the switch **Minecraft Launcher에서도 플레이** ("Also play from the Minecraft Launcher"). It is on the app's ready-to-play screen, or under **File → Minecraft Launcher 연결…** at any time (also before signing in). It appears only when the Mac Minecraft Launcher is installed. The app says what it changes and asks before doing anything.

When it's on:

- The Minecraft Launcher's Dungeons II page gets a Play button (or Install, if the game isn't installed yet), and its title is marked "(UNOFFICIAL MAC PORT)". Pressing it opens this app hidden; the launcher's own download bar shows our progress (with pause, resume and cancel). The app's window comes up only when you need to act (sign-in, the GDK license, an error).
- To do that, the app patches the Minecraft Launcher's UI file (`ui.zip`), Dungeons II page only. The original is kept as `~/Library/Application Support/minecraft/macd2-ui.zip.orig`.
- It installs a per-user LaunchAgent, `io.github.mac-dungeons-ii.link`. launchd listens on `127.0.0.1:47821` and answers only requests from the launcher's page.
- When the Minecraft Launcher updates, it puts its own `ui.zip` back. While the switch is on, the app re-applies the patch the next time it opens.
- macOS asks you to allow the app to modify other apps (**App Management**). Without that permission the patch can't be written.

Turn the switch off to undo it: the LaunchAgent is removed and the original `ui.zip` is restored.

This is an unofficial change to Mojang's launcher and not supported by Mojang or Microsoft. It doesn't change ownership: you still need an account that owns the game.

## How it works

The game expects the Xbox GDK runtime. On a Mac, one runtime DLL on top of Wine fills that in.

```
Dungeons-WinGDK-Shipping.exe
 ├─ xgameruntime.dll            Flightdeck-based runtime (our fork)
 │   └─ xgameruntime_original.dll  Microsoft's genuine GDK runtime (downloaded)
 └─ XCurl.dll                   curl wrapper over curl.se's libcurl (same fork)
xodus_store_test.dll ── /tmp/macd2.sock ── macd2-broker   Store licenses (xodus)
macd2          sign-in and session file, download/extract, launch (xodus)
```

- Sign-in happens on the Mac side: `macd2 mac-session` signs in and writes a session file with your Xbox Live tokens for the game's services, and the runtime hands that user to the game (XUser). No refresh credential goes into Wine. Store licenses come from your Microsoft-signed license through `macd2-broker`. Task queues stay with the genuine runtime.
- Wine — built from CodeWeavers' CrossOver 26.3 sources
- DXMT — Direct3D 11 → Metal
- GStreamer — game videos (H.264)
- SDL — controller input

Details per layer: [docs/architecture.md](docs/architecture.md).

Notes:

- The game's executables stay encrypted on disk. At launch they're decrypted into a RAM disk only.
- Saves stay in a local store inside the Wine prefix. Heroes live on the game's servers, so they load the same as on Windows.
- This repo and the release contain no Microsoft or Mojang files. The game, the GDK runtime and curl are downloaded by the app.

## Data and removal

Everything the app stores is in `~/Library/Application Support/M(a)C Dungeons II` (game, Wine prefix with your saves, logs).

To remove everything:

1. If the Minecraft Launcher link is on, turn it off first in the app. That restores the Minecraft Launcher and removes the LaunchAgent. Afterwards you can delete `~/Library/Application Support/minecraft/macd2-ui.zip.orig`.
2. Delete the app.
3. Delete the data folder above. Local saves are deleted with it.
4. In Keychain Access, delete the items with the name "M(a)C Dungeons II".

If you deleted the app while the link was on, remove `~/Library/LaunchAgents/io.github.mac-dungeons-ii.link.plist` (and log out or run `launchctl bootout gui/$(id -u)/io.github.mac-dungeons-ii.link`), then copy `macd2-ui.zip.orig` back over `~/Library/Application Support/minecraft/launcher/launcher.bundle/Contents/Resources/ui.zip`.

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
- The [Flightdeck fork](https://github.com/MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox) (`macos` branch) in `.work/src-flightdeck`, and WineGDK b5d23b0 with the fork's runtime patch (see the top of `mac/build-store-bridge.sh`)

Order:

1. `FD=.work/src-flightdeck mac/build-store-bridge.sh` — WineGDK pieces, the runtime (`xgameruntime.dll`) and `XCurl.dll` from the Flightdeck fork
2. `mac/build-runtime.sh` — Wine runtime
3. `cargo build --release` in the [xodus fork](https://github.com/MaC-Dungeons-II/xodus) (Rust 1.98 or later)
4. `app/build.sh` → app in `app/dist/`
5. `app/dmg/make_dmg.sh` → `app/dist/MaC-Dungeons-II.dmg`

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
| Runtime (`xgameruntime.dll`), XCurl wrapper | [MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox](https://github.com/MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox) | LGPL-2.1+ (XCurl wrapper MIT) |
| Wine | CodeWeavers crossover-sources 26.3 | LGPL-2.1+ |
| DXMT, GDK-Proton, WineGDK, GStreamer, FFmpeg, SDL | see [app/NOTICE.md](app/NOTICE.md) | per project |

Changes in the forks are on their `macos` branches.

## Credits

- [xodus](https://github.com/xodus-gaming/xodus) — Microsoft sign-in, licenses, package downloads
- [Flightdeck](https://github.com/marselnenaj/flightdeck-msfs-2024-linux-xbox) — GDK runtime proxy, Store broker
- [mcd2-crossover](https://github.com/Wanzho/mcd2-crossover) by Wanzho — the early adapter that first made the genuine runtime usable; our XCurl fixes, the Wine wait-queue fix, the title-config default and the XUser interface layout follow its work
- [WineGDK](https://github.com/Sightem/WineGDK), [GDK-Proton](https://github.com/LukasPAH/GDK-Proton-Custom) — GDK builtins
- [DXMT](https://github.com/3Shain/dxmt) — Direct3D 11 → Metal
- CodeWeavers, the Wine project
