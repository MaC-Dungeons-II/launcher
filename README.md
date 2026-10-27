<div align="center">

<img src="app/icon/AppIcon-preview.png" width="128" alt="">

# M(a)C Dungeons II

**English** · [한국어](README.ko.md)

</div>

M(a)C Dungeons II runs **Minecraft Dungeons II** (Minecraft Launcher / Microsoft Store edition) on Apple Silicon Macs. Sign in with the Microsoft account that owns the game, and the app downloads and runs it. It is built on Wine (CrossOver 26.3), [DXMT](https://github.com/3Shain/dxmt), a [Flightdeck](https://github.com/marselnenaj/flightdeck-msfs-2024-linux-xbox)-based GDK runtime and [xodus](https://github.com/xodus-gaming/xodus).

Unofficial, and not affiliated with or endorsed by Mojang, Microsoft or Xbox.

## Features

- Online play with your existing heroes
- Settings and saves (kept on the Mac)
- Game videos and Bluetooth Xbox controllers
- Download with pause and resume
- Optional: start the game from the Mac Minecraft Launcher

## System Requirements

- Apple Silicon Mac with Rosetta 2
- macOS 14 or later
- About 25 GB of free space

## Installation

Download `MaC-Dungeons-II.dmg` from [Releases](../../releases/latest) and drag the app to Applications.

## Problems

Tested on an M4 MacBook (macOS 27). A game update may break things. Please [open an issue](../../issues) with the logs from `~/Library/Application Support/M(a)C Dungeons II/logs`.

## Development

- [How it works](docs/architecture.md)
- [Building](docs/building.md)

## Credits

- [xodus](https://github.com/xodus-gaming/xodus) — Microsoft sign-in, licenses, package downloads
- [Flightdeck](https://github.com/marselnenaj/flightdeck-msfs-2024-linux-xbox) — GDK runtime
- [mcd2-crossover](https://github.com/Wanzho/mcd2-crossover) by Wanzho — XCurl and Wine fixes, XUser layout
- [WineGDK](https://github.com/Sightem/WineGDK), [GDK-Proton](https://github.com/LukasPAH/GDK-Proton-Custom) — GDK builtins
- [DXMT](https://github.com/3Shain/dxmt) — Direct3D 11 on Metal
- CodeWeavers and the Wine project

## License

MIT. Bundled components keep their own licenses; see [app/NOTICE.md](app/NOTICE.md). Our changes to xodus and Flightdeck are in the [MaC-Dungeons-II](https://github.com/MaC-Dungeons-II) forks.

Minecraft and Minecraft Dungeons are trademarks of their respective owners.
