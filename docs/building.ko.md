# 빌드

[English](building.md) · **한국어**

> [!IMPORTANT]
> M4 Mac 한 대에서 빌드했습니다. `mac/build-runtime.sh`는 실제로 실행한 단계를 그대로 옮긴 것이고, 깨끗한 환경에서 처음부터 다시 돌려 보지는 않았습니다.

준비물은 `mac/build-runtime.sh` 머리말에 있습니다. 모두 저장소 안의 `.work/`에 둡니다(git에서 제외됨).

- `mac/patches/`를 적용한 CrossOver 소스
- llvm-mingw
- FFmpeg 7.1.1
- GStreamer 1.28.7
- SDL 2.32.10
- DXMT 68af85e
- GDK-Proton 11-7 빌트인
- `.work/src-flightdeck`에 [Flightdeck 포크](https://github.com/MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox) (`macos` 브랜치), 포크의 런타임 패치를 적용한 WineGDK b5d23b0 (`mac/build-store-bridge.sh` 머리말 참고)

순서:

1. `FD=.work/src-flightdeck mac/build-store-bridge.sh` — WineGDK 부분, Flightdeck 포크의 런타임(`xgameruntime.dll`)과 `XCurl.dll`
2. `mac/build-runtime.sh` — Wine 런타임
3. [xodus 포크](https://github.com/MaC-Dungeons-II/xodus)에서 `cargo build --release` (Rust 1.98 이상)
4. `app/build.sh` → `app/dist/`에 앱 생성
5. `app/dmg/make_dmg.sh` → `app/dist/MaC-Dungeons-II.dmg` 생성

앱 아이콘(Icon Composer 형식, Liquid Glass)을 다시 만들려면 다음을 실행합니다.

```bash
uv run --no-project --with pillow python app/icon/make_icon.py
```

