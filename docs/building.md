# Building

**English** · [한국어](building.ko.md)

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

