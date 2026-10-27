# M(a)C Dungeons II

**English** · [한국어](README.ko.md)

An unofficial launcher that runs **Minecraft Dungeons II** (Minecraft Launcher / Microsoft Store edition) on a Mac.

> [!CAUTION]
> This is an unofficial project. Use it at your own risk. It is not affiliated with, endorsed by, or sponsored by Mojang, Microsoft or Xbox. Minecraft, Minecraft Dungeons and all other trademarks, product names, and company names or logos mentioned here are the property of their respective owners.

> [!IMPORTANT]
> **You need an account that owns the game.** The license check is not bypassed; the game won't run on an account that doesn't own it.

## What works

Checked on an M4 MacBook (macOS 27): online play with the heroes you already have, settings and saves, game videos, Bluetooth Xbox controllers. A game update may break things.

Not yet: saves stay on the Mac (no Xbox cloud sync), and every game update downloads the full package again.

## Requirements

- Apple Silicon Mac with Rosetta 2, macOS 14 or later
- A Microsoft account that owns Minecraft Dungeons II
- About 25 GB free for the first install

## Install

1. Get `MaC-Dungeons-II.dmg` from [Releases](../../releases), open it, and drag the app to Applications.
2. Open the app. It isn't notarized, so macOS blocks it the first time: go to **System Settings → Privacy & Security** and click **Open Anyway**.

## Play

1. Sign in with your Microsoft account. This is separate from the Minecraft Launcher's sign-in.
2. Accept the Microsoft GDK license (once).
3. Click **설치** (Install), or **플레이** (Play) once the game is installed.

## Play from the Minecraft Launcher (optional)

If the Mac Minecraft Launcher is installed, you can start Dungeons II from there too. Turn on **Minecraft Launcher에서도 플레이** ("Also play from the Minecraft Launcher") on the app's ready-to-play screen, or from **File → Minecraft Launcher 연결…**.

The Dungeons II page in the Minecraft Launcher then has an Install/Play button and shows the download there. This app runs hidden and only shows its window when you need to do something, like signing in.

To do this the app modifies the Minecraft Launcher, so macOS asks you to allow it under **App Management**. Turning the switch off puts the Minecraft Launcher back the way it was.

## Uninstall

1. If you turned on the Minecraft Launcher link, turn it off in the app first.
2. Delete the app.
3. Delete `~/Library/Application Support/M(a)C Dungeons II` (the game and your saves).
4. In Keychain Access, delete the items named "M(a)C Dungeons II".

Already deleted the app with the link on? See [Removing the Minecraft Launcher link by hand](docs/architecture.md#removing-the-link-by-hand).

## For developers

- How it works: [docs/architecture.md](docs/architecture.md)
- Building: [docs/building.md](docs/building.md)

| Component | Repository | License |
|---|---|---|
| Launcher app, build scripts, Wine patches | this repo | MIT (Wine patches LGPL-2.1+) |
| xodus (`macd2`, `macd2-broker`) | [MaC-Dungeons-II/xodus](https://github.com/MaC-Dungeons-II/xodus) | GPL-3.0 |
| Runtime (`xgameruntime.dll`), XCurl wrapper | [MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox](https://github.com/MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox) | LGPL-2.1+ (XCurl wrapper MIT) |
| Wine | CodeWeavers crossover-sources 26.3 | LGPL-2.1+ |
| DXMT, GDK-Proton, WineGDK, GStreamer, FFmpeg, SDL | see [app/NOTICE.md](app/NOTICE.md) | per project |

This repo and the release contain no Microsoft or Mojang files; the app downloads the game and the GDK runtime itself.

## Credits

- [xodus](https://github.com/xodus-gaming/xodus) — Microsoft sign-in, licenses, package downloads
- [Flightdeck](https://github.com/marselnenaj/flightdeck-msfs-2024-linux-xbox) — GDK runtime proxy, Store broker
- [mcd2-crossover](https://github.com/Wanzho/mcd2-crossover) by Wanzho — the early adapter that first made the genuine runtime usable; our XCurl fixes, the Wine wait-queue fix, the title-config default and the XUser interface layout follow its work
- [WineGDK](https://github.com/Sightem/WineGDK), [GDK-Proton](https://github.com/LukasPAH/GDK-Proton-Custom) — GDK builtins
- [DXMT](https://github.com/3Shain/dxmt) — Direct3D 11 → Metal
- CodeWeavers, the Wine project
