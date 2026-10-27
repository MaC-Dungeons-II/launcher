# M(a)C Dungeons II

[English](README.md) · **한국어**

Minecraft Launcher(Microsoft Store)판 **Minecraft Dungeons II**를 macOS에서 실행하는 비공식 런처입니다.
Microsoft 계정으로 로그인하면 본인 라이선스로 게임을 내려받아 Wine에서 실행합니다. 가상 머신이나 Windows PC 스트리밍 없이 앱 하나로 동작합니다.

> [!CAUTION]
> 비공식 프로젝트입니다. 사용에 따른 책임은 사용자에게 있습니다. Mojang, Microsoft, Xbox와 관련이 없으며 이들의 승인이나 후원을 받지 않았습니다. Minecraft, Minecraft Dungeons를 비롯해 여기 나오는 상표, 제품명, 회사명, 로고는 각 소유자의 것입니다.

> [!IMPORTANT]
> **게임을 구매한 계정이 있어야 합니다.** 라이선스 확인을 우회하지 않습니다. 게임은 계정의 Microsoft 서명 라이선스를 그대로 확인하고, 소유하지 않은 계정으로는 실행되지 않습니다.

Steam판은 Linux/Steam Deck 대응 업데이트를 받았지만 Launcher판은 받지 못했습니다. 그래서 Launcher판을 Mac에서 돌리려고 만들었습니다.

## 되는 것

M4 MacBook(macOS 27)에서 확인했습니다.

- 온라인 플레이, Windows에서 쓰던 기존 영웅
- 설정·저장
- 인트로와 게임 안 영상
- 블루투스 Xbox 컨트롤러
- 게임 메뉴에서 종료 (런처가 Wine까지 정리하고 같이 닫힘)

기기 한 대에서만 시험했습니다. 게임 업데이트로 동작이 깨질 수 있습니다.

## 요구 사항

- Apple Silicon Mac, Rosetta 2
- macOS 14 이상
- Minecraft Dungeons II를 소유한 Microsoft 계정
- 첫 설치 시 여유 공간 약 25GB (다운로드 약 10GB)

## 설치

1. [Releases](../../releases)에서 `MaC-Dungeons-II.dmg`를 받아 열고, 앱을 Applications로 끌어다 놓습니다.
2. 앱을 엽니다. 공증(notarization)을 받지 않은 앱이라 처음에는 macOS가 막습니다. **시스템 설정 → 개인정보 보호 및 보안**에서 **그래도 열기**를 누릅니다.
3. 로그인하고 기다립니다. 첫 실행 때 게임을 받고, 그다음부터는 업데이트만 확인합니다.

앱이 하는 일:

1. Microsoft 로그인 (리프레시 토큰은 키체인 "M(a)C Dungeons II" 항목에 저장)
2. Microsoft GDK 런타임 라이선스 동의 → nuget.org에서 받고 SHA-256 확인
3. 게임 버전 확인 → 필요하면 Microsoft CDN에서 받아서 풀기 (병렬 다운로드, 이어받기, 속도·남은 시간 표시)
4. 게임 실행

데이터는 전부 `~/Library/Application Support/M(a)C Dungeons II`에 있습니다. 지우려면 앱, 이 폴더, 키체인 항목을 삭제하면 됩니다.

## WASD 조작 (선택)

키보드와 마우스를 Xbox 컨트롤러처럼 쓰게 해 주는 [wasdmod](https://github.com/Wanzho/mcd2-wasd)가 들어 있습니다. WASD로 움직이고 마우스로 조준합니다. 기본값은 꺼짐입니다.

- 메뉴 막대의 **조작 → WASD 조작 (wasdmod)** 에서 켭니다. 다음 게임 실행부터 적용됩니다.
- **키 배치** 에서 배치를 고릅니다. 게임 기본 키, 제작자 추천 배치, 직접 만든 배치가 있습니다.
- **키 배치 편집기 열기…** 로 편집기를 엽니다. wasdmod 편집기를 런처 안에 그대로 옮긴 것입니다. 공식·추천 배치를 고치면 새 배치로 저장됩니다.
- 편집기의 **대신 바꾸기** 는 게임 자체의 키보드 설정을 배치에 맞게 바꿉니다. 그러면 메뉴에서도 같은 키를 씁니다. 게임이 켜져 있으면 재시작할지 묻고, 게임이 꺼진 사이에 바꿉니다. 게임이 키 설정을 한 번은 저장한 상태여야 합니다(설정 › 조작 › 키보드에서 아무 키나 한 번 바꾸기). Launcher판은 키 설정을 로컬 세이브 저장소 안에 두기 때문에, 바꿀 때마다 그 저장소를 데이터 폴더의 `wasdmod/backups`에 먼저 복사해 둡니다.
- 왼쪽 Option 키를 누르고 있으면 마우스 커서가 나옵니다.

게임 파일이나 메모리는 건드리지 않고, 게임이 쓰는 `xinput1_4.dll`만 바꿔 끼웁니다. 소스에서 직접 빌드했습니다(1.5.1, 업데이트 확인 기능이 빠진 버전). 커뮤니티 모드라서 사용 책임은 본인에게 있습니다.

## 구조

게임은 Xbox GDK 런타임을 기대합니다. Mac에서는 Wine 위에 레이어를 몇 겹 얹어서 맞춥니다.

```
Dungeons-WinGDK-Shipping.exe
 └─ xgameruntime.dll            mcd2-crossover 어댑터 — Xbox 세션, curl 래퍼
     └─ xgameruntime-native.dll Flightdeck 프록시 — Store, 저장, 웹소켓
         └─ xgameruntime_original.dll  Microsoft 정품 GDK 런타임 (첫 실행 때 받음)
macd2-broker   Microsoft 서명 라이선스로 Store 라이선스 질의에 응답 (xodus)
macd2          로그인, 세션 갱신, 다운로드·풀기, 실행 (xodus)
```

- Wine — CodeWeavers CrossOver 26.3 소스로 직접 빌드
- DXMT — Direct3D 11 → Metal
- GStreamer — 게임 영상(H.264) 재생
- SDL — 컨트롤러 입력

계층별 자세한 설명은 [docs/architecture.ko.md](docs/architecture.ko.md)에 있습니다.

참고:

- 게임 실행 파일은 디스크에 암호화된 상태로 둡니다. 실행할 때 RAM 디스크에만 풀어서 씁니다.
- 저장은 Wine 프리픽스 안의 로컬 저장소에 남습니다. 영웅은 게임 서버에 있어서 Windows와 똑같이 불러옵니다.
- 이 저장소와 릴리스에는 Microsoft·Mojang 파일이 없습니다. 게임, GDK 런타임, curl은 첫 실행 때 내려받습니다.

## 빌드

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

순서:

1. `mac/build-store-bridge.sh` — WineGDK 부분과 Flightdeck 프록시
2. `mac/build-runtime.sh` — Wine 런타임
3. [mcd2-crossover 포크](https://github.com/MaC-Dungeons-II/mcd2-crossover)를 llvm-mingw로 빌드 → `xgameruntime.dll`, `XCurl.dll`
4. [xodus 포크](https://github.com/MaC-Dungeons-II/xodus)에서 `cargo build --release` (Rust 1.98 이상)
5. `mac/build-wasdmod.sh` — wasdmod `xinput1_4.dll` (먼저 [Wanzho/mcd2-wasd](https://github.com/Wanzho/mcd2-wasd)를 `.work/src-wasd`에 clone)
6. `app/build.sh` → `app/dist/`에 앱 생성
7. `app/dmg/make_dmg.sh` → `app/dist/MaC-Dungeons-II.dmg` 생성

앱 아이콘(Icon Composer 형식, Liquid Glass)을 다시 만들려면 다음을 실행합니다.

```bash
uv run --no-project --with pillow python app/icon/make_icon.py
```

## 아직 안 되는 것

- 저장을 Xbox 클라우드로 올리지 않습니다. Mac에만 남습니다.
- 업데이트를 받을 때 차분 패키지가 아니라 전체 패키지를 다시 받습니다.
- 공증을 받지 않았습니다.

## 구성 요소

| 구성 요소 | 저장소 | 라이선스 |
|---|---|---|
| 런처 앱, 빌드 스크립트, Wine 패치 | 이 저장소 | MIT (Wine 패치는 LGPL-2.1+) |
| xodus (`macd2`, `macd2-broker`) | [MaC-Dungeons-II/xodus](https://github.com/MaC-Dungeons-II/xodus) | GPL-3.0 |
| 런타임 프록시 | [MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox](https://github.com/MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox) | LGPL-2.1+ |
| 런타임 어댑터, XCurl 래퍼 | [MaC-Dungeons-II/mcd2-crossover](https://github.com/MaC-Dungeons-II/mcd2-crossover) | MIT |
| wasdmod (선택 기능, WASD 조작) | [Wanzho/mcd2-wasd](https://github.com/Wanzho/mcd2-wasd) 1.5.1, 수정 없음 | MIT |
| Wine | CodeWeavers crossover-sources 26.3 | LGPL-2.1+ |
| DXMT, GDK-Proton, WineGDK, GStreamer, FFmpeg, SDL | [app/NOTICE.md](app/NOTICE.md) 참고 | 각 프로젝트 |

포크는 모두 `macos` 브랜치에 변경 사항이 있습니다.

## 감사

- [xodus](https://github.com/xodus-gaming/xodus) — Microsoft 로그인, 라이선스, 패키지 다운로드
- [Flightdeck](https://github.com/marselnenaj/flightdeck-msfs-2024-linux-xbox) — GDK 런타임 프록시, Store 브로커
- [mcd2-crossover](https://github.com/Wanzho/mcd2-crossover) — 정품 런타임을 쓰게 해 준 어댑터
- [wasdmod](https://github.com/Wanzho/mcd2-wasd) — 키보드·마우스를 컨트롤러로
- [WineGDK](https://github.com/Sightem/WineGDK), [GDK-Proton](https://github.com/LukasPAH/GDK-Proton-Custom) — GDK 빌트인
- [DXMT](https://github.com/3Shain/dxmt) — Direct3D 11 → Metal
- CodeWeavers, Wine 프로젝트
