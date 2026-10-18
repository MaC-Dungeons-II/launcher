# Moving off Rosetta

**English** · [한국어](arm64-migration.ko.md)

## Why

The Wine runtime in the app is x86_64 and runs under Rosetta 2. Apple's plan:

- macOS 27 is the last release with full Rosetta.
- From macOS 28 (expected fall 2027) only "a subset of Rosetta functionality aimed at supporting older unmaintained gaming titles" stays. Nothing says a Wine-based app counts.
- Assume the current runtime stops working on macOS 28.

## What needs Rosetta today

| Part | Architecture | After the move |
|---|---|---|
| Launcher (`MaCDungeons`), `macd2`, `macd2-broker` | arm64 | unchanged |
| Wine Unix side, DXMT `winemetal.so`, GStreamer, FFmpeg, SDL, gnutls, freetype | x86_64 | rebuild for arm64 |
| Wine PE DLLs, DXMT PE DLLs | x86_64 (Windows) | ARM64EC/ARM64X builds |
| The game, the GDK runtime, mcd2 adapter, Flightdeck proxy | x86_64 (Windows) | unchanged; emulated by FEX inside the ARM64 Wine process |

## Target

ARM64 Wine on macOS, with **FEX** emulating x86_64 code through ARM64EC. This is what CodeWeavers ships in CrossOver Preview (July 2026). It needs macOS 26.5 or later (x18 ABI, 4K-page spawn, per-thread TSO).

A side benefit, measured 2026-10-18: the game's anti-tamper code deliberately executes invalid opcodes (AAM, AAD, `push es`, `pusha` in 64-bit mode) and decodes them in its own exception handler, about **10,000 times per second during play**, plus several hundred direct `syscall` instructions per second. Under Rosetta every one of these goes through Rosetta's exception server, a signal and Wine's handler, which keeps a full core busy. With FEX the emulator raises the Windows exception itself, so most of that round trip goes away.

## Status of the pieces (2026-10)

- **ARM64 Wine for macOS:** CodeWeavers says the Wine side (LGPL) will be published with the CrossOver 27 sources in early 2027. Upstream Wine has only preparatory changes merged.
- **FEX on macOS:** not upstream. A community port (`dbc-hbin/FEX-darwin`) exists, but it is unreviewed.
- **DXMT:** ARM64EC support is merged (PR #202, #209), and the bundled build (50102f9) includes it. CI does not package an arm64 Unix side yet, so `winemetal.so` has to be built from source.
- **Prebuilt community runtimes** (Hadron, neutron): **not used**. We don't run binaries whose sources and build we can't verify.

## Already prepared in this repo

- The launcher reads the runtime's architecture from the bundle (`lib/wine/aarch64-unix` vs `x86_64-unix`). It checks for Rosetta only when the runtime is x86_64, and explains how to install it if it's missing.
- The build scripts derive every architecture-specific name from `HOST_ARCH` (default `x86_64`). Other values stop with a pointer here until an arm64 runtime can be built.

## Work when the sources are out

1. Build ARM64 Wine from the CrossOver 27 sources (`HOST_ARCH=arm64`, `aarch64-unix`/`aarch64-windows`) and FEX for macOS from reviewed sources.
2. Port our Wine patches:
   - `wine-dll-file-map.patch` (loader): needed for the encrypted executables.
   - `winemac-icon-mask.patch`: Dock icon.
   - `wine-vulkan-soname-fallback.patch`: may no longer be needed.
3. Rebuild the Unix-side dependencies for arm64: GStreamer (the official package is universal, so `bundle-gstreamer.sh` only needs `HOST_ARCH`), FFmpeg, SDL, gnutls, freetype, and DXMT's `winemetal.so` from source.
4. Check the `MACD2_VIEW` RAM-disk path under ARM64 Wine. The game's anti-tamper re-reads its executable, and behavior under FEX is unknown.
5. Check the exit watchdog thresholds. They were measured on x86_64 Wine (about 100–130 threads while playing, 8 after exit); FEX may add threads.
6. Compare against the x86_64 runtime with the same settings (60 fps pacing, same resolution): CPU, GPU, frame time, load time.

## Decision points

- **When CrossOver 27 sources are published:** start steps 1–6 on a branch.
- **Before macOS 28 betas (around June 2027):** if the arm64 runtime isn't ready, tell users to stay on macOS 27.
- **Never:** hard-code a "game owns license" answer or skip the license check to work around emulation problems.

## Sources

- [Apple Developer Forums: Rosetta 2 in 2027/macOS 28](https://developer.apple.com/forums/thread/787530)
- [CodeWeavers: CrossOver Preview, ARM64 on Mac (2026-07-31)](https://www.codeweavers.com/blog/mjohnson/2026/7/31/crossover-preview-the-right-to-bear-arm64-on-mac)
- [Tracking issue with a status summary (cities-skylines-2-macos #16)](https://github.com/macgameport/cities-skylines-2-macos/issues/16)
