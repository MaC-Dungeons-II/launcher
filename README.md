# M(a)C Dungeons II

**English** · [한국어](README.ko.md)

An unofficial macOS launcher for **Minecraft Dungeons II** (the Minecraft Launcher /
Microsoft Store edition). You sign in with your Microsoft account and the app
downloads the game from Microsoft under your own license. It then runs the game
through Wine with a small compatibility layer. No virtual machine is needed.

> [!CAUTION]
> This is an unofficial project. Use it at your own risk. It is not affiliated
> with, endorsed by, or sponsored by Mojang, Microsoft or Xbox. Minecraft,
> Minecraft Dungeons and all other trademarks, product names, and company names
> or logos mentioned here are the property of their respective owners.

> [!IMPORTANT]
> You need your own copy of the game. Nothing here bypasses the license check:
> ownership is confirmed with the Microsoft-signed license token for your account.

## What it does

Opening `M(a)C Dungeons II.app` runs these steps:

1. **Sign in** with your Microsoft account in a web view. The refresh token is
   kept in your login keychain under the item "M(a)C Dungeons II".
2. **License consent** for the Microsoft GDK runtime. The runtime is downloaded
   from nuget.org and checked against a pinned SHA-256.
3. **Download or update** the game. The app checks the current package version.
   If needed, it downloads the full package from Microsoft's CDN over parallel,
   resumable connections, then extracts it with your license. Progress shows
   speed and time left.
4. **Launch.** The game runs on Wine (CrossOver 26.3 sources) with DXMT
   (Direct3D 11 on Metal).

What works:
- Online play and your existing heroes
- Settings and saves (kept in a local GameSave store)
- Intro and UI videos (H.264 via GStreamer)
- Xbox controllers (SDL)
- A rounded Dock icon for the game

When you quit the game, the app cleans up Wine and exits.

Everything the app stores lives in `~/Library/Application Support/M(a)C Dungeons II`:
- `game/`
- `prefix/`
- `deps/`
- `session/`
- `logs/`

## Requirements

- A Mac with Apple silicon and Rosetta 2. Tested only on an M4 Mac with macOS 27.
- macOS 14 or later.
- A Microsoft account that owns Minecraft Dungeons II.
- About 25 GB of free disk space during the first install.

## Install

1. Download `M(a)C-Dungeons-II.zip` from [Releases](../../releases) and move the app to `/Applications`.
2. The app is ad-hoc signed, not notarized. The first time you open it, macOS
   blocks it. To allow it, open **System Settings → Privacy & Security** and
   click **Open Anyway**.

### Uninstall

Delete the app, the `~/Library/Application Support/M(a)C Dungeons II` folder,
and the "M(a)C Dungeons II" item in Keychain Access.

## How it works

```
Dungeons-WinGDK-Shipping.exe
 └─ xgameruntime.dll            mcd2-crossover adapter (session, XCurl wrapper)
     └─ xgameruntime-native.dll Flightdeck runtime proxy (Store, GameSave, networking)
         └─ xgameruntime_original.dll  Microsoft GDK runtime (downloaded at first run)
macd2-broker   xodus service: XStore answers from Microsoft-signed license tokens
macd2          xodus CLI: sign-in, session refresh, package download/extract, run
```

- **Encrypted executables.** The game's executables stay encrypted on disk.
  At launch they are decrypted only into a RAM disk.
- **Saves.** Game saves use a local GameSave store inside the Wine prefix.
  Heroes are stored server-side by the game, so they load as on Windows.

## Components

| Component | Repository | License |
|---|---|---|
| Launcher app, build scripts, Wine patches | this repository | MIT |
| xodus (`macd2`, `macd2-broker`) | [MaC-Dungeons-II/xodus](https://github.com/MaC-Dungeons-II/xodus) (`macos` branch, fork of xodus-gaming/xodus) | GPL-3.0 |
| Runtime proxy | [MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox](https://github.com/MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox) (`macos` branch) | LGPL-2.1+ |
| Runtime adapter, XCurl wrapper | [MaC-Dungeons-II/mcd2-crossover](https://github.com/MaC-Dungeons-II/mcd2-crossover) (`macos` branch) | MIT |
| Wine | CodeWeavers crossover-sources 26.3 + `mac/patches` | LGPL-2.1+ |
| DXMT, GDK-Proton builtins, WineGDK, GStreamer, FFmpeg, SDL | upstream, see [app/NOTICE.md](app/NOTICE.md) | see notice |

The app does not include any Microsoft or Mojang files. The game, the GDK
runtime and curl are downloaded on first run.

## Building

The build steps were run on an M4 Mac with macOS 27. `mac/build-runtime.sh`
records the exact steps used, but it has not been re-run from scratch on a
clean machine.

1. **Wine runtime.** Run `mac/build-runtime.sh`. The header of the script
   lists the inputs to prepare under `~/Games/dungeons2-mac`:
   - CrossOver sources with the patches in `mac/patches/` applied
   - llvm-mingw
   - FFmpeg 7.1.1
   - GStreamer 1.28.7
   - SDL 2.32.10
   - DXMT 68af85e
   - GDK-Proton 11-7 builtins

   `mac/build-store-bridge.sh` builds the WineGDK pieces and the runtime proxy.
2. **Adapter.** Build `xgameruntime.dll` and `XCurl.dll` from the
   mcd2-crossover fork with llvm-mingw.
3. **xodus.** Build the xodus fork with `cargo build --release`.
4. **App.** Run `app/build.sh`. The app is written to `app/dist/`.
5. **Icon (optional).** To regenerate the app icon (Liquid Glass, Icon Composer
   format), run:

   ```bash
   uv run --no-project --with pillow python app/icon/make_icon.py
   ```

## Known limitations

- Unofficial and lightly tested. Game updates can break it.
- Cloud saves are not uploaded back to Xbox. Saves stay in the local store.
- Each game update is downloaded as the full package (about 10 GB). Delta
  updates are not used.

## Credits

Built on the work of:
- [xodus](https://github.com/xodus-gaming/xodus)
- [Flightdeck](https://github.com/marselnenaj/flightdeck-msfs-2024-linux-xbox)
- [mcd2-crossover](https://github.com/Wanzho/mcd2-crossover)
- [WineGDK](https://github.com/Sightem/WineGDK)
- [GDK-Proton](https://github.com/LukasPAH/GDK-Proton-Custom)
- [DXMT](https://github.com/3Shain/dxmt)
- CodeWeavers' CrossOver sources and the Wine project
