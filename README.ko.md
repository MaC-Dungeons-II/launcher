# M(a)C Dungeons II

[English](README.md) · **한국어**

**Minecraft Dungeons II**(Minecraft Launcher / Microsoft Store판)를 macOS에서 실행하는 비공식 런처입니다. Microsoft 계정으로 로그인하면 본인 라이선스로 Microsoft에서 게임을 내려받고, 작은 호환 레이어를 얹은 Wine에서 실행합니다. 가상 머신은 필요 없습니다.

> [!CAUTION]
> 비공식 프로젝트입니다. 사용에 따른 책임은 사용자에게 있습니다. Mojang, Microsoft, Xbox와 관련이 없으며 이들의 승인이나 후원을 받지 않았습니다. Minecraft, Minecraft Dungeons를 비롯해 여기 나오는 상표, 제품명, 회사명, 로고는 각 소유자의 것입니다.

> [!IMPORTANT]
> 게임을 구매한 계정이 있어야 합니다. 라이선스 확인을 우회하지 않습니다. 소유권은 계정의 Microsoft 서명 라이선스 토큰으로 확인합니다.

## 하는 일

`M(a)C Dungeons II.app`을 열면 다음 순서로 진행됩니다.

1. **로그인:** 웹 화면에서 Microsoft 계정으로 로그인합니다. 리프레시 토큰은 로그인 키체인의 "M(a)C Dungeons II" 항목에 저장됩니다.
2. **라이선스 동의:** Microsoft GDK 런타임 라이선스에 동의합니다. 런타임은 nuget.org에서 받고 고정된 SHA-256으로 검증합니다.
3. **다운로드 또는 업데이트:** 게임 버전을 확인합니다. 받아야 하면 Microsoft CDN에서 전체 패키지를 여러 연결로 이어받기 가능하게 받고, 본인 라이선스로 풉니다. 속도와 남은 시간이 표시됩니다.
4. **실행:** Wine(CrossOver 26.3 소스)과 DXMT(Direct3D 11 → Metal)로 게임을 실행합니다.

**되는 것**
- 온라인 플레이와 기존 영웅
- 설정과 저장(로컬 GameSave 저장소)
- 인트로와 UI 영상(GStreamer로 H.264 재생)
- Xbox 컨트롤러(SDL)
- 둥근 Dock 아이콘

게임을 종료하면 런처가 Wine을 정리하고 같이 닫힙니다.

앱이 쓰는 데이터는 모두 `~/Library/Application Support/M(a)C Dungeons II`에 있습니다.
- `game/`
- `prefix/`
- `deps/`
- `session/`
- `logs/`

## 요구 사항

- Apple silicon Mac과 Rosetta 2. M4 Mac, macOS 27에서만 시험했습니다.
- macOS 14 이상
- Minecraft Dungeons II를 소유한 Microsoft 계정
- 첫 설치 중 여유 공간 약 25GB

## 설치

1. [Releases](../../releases)에서 `M(a)C-Dungeons-II.zip`을 받아 앱을 `/Applications`로 옮깁니다.
2. 이 앱은 ad-hoc 서명만 되어 있고 공증(notarization)은 받지 않았습니다. 그래서 처음 열면 macOS가 막습니다. **시스템 설정 → 개인정보 보호 및 보안**에서 **그래도 열기**를 눌러 주세요.

### 삭제

다음 세 가지를 지우면 됩니다.
- 앱
- `~/Library/Application Support/M(a)C Dungeons II` 폴더
- 키체인 접근의 "M(a)C Dungeons II" 항목

## 구조

```
Dungeons-WinGDK-Shipping.exe
 └─ xgameruntime.dll            mcd2-crossover 어댑터(세션, XCurl 래퍼)
     └─ xgameruntime-native.dll Flightdeck 런타임 프록시(Store, GameSave, 네트워크)
         └─ xgameruntime_original.dll  Microsoft GDK 런타임(첫 실행 때 받음)
macd2-broker   xodus 서비스: Microsoft 서명 라이선스 토큰으로 XStore 응답
macd2          xodus CLI: 로그인, 세션 갱신, 패키지 다운로드·풀기, 실행
```

- **실행 파일 암호화:** 게임 실행 파일은 디스크에서 암호화된 상태로 둡니다. 실행할 때 RAM 디스크에만 풀어서 씁니다.
- **저장:** 게임 저장은 Wine 프리픽스 안의 로컬 GameSave 저장소에 남습니다. 영웅은 게임 서버에 저장되므로 Windows에서처럼 불러옵니다.

## 구성 요소

| 구성 요소 | 저장소 | 라이선스 |
|---|---|---|
| 런처 앱, 빌드 스크립트, Wine 패치 | 이 저장소 | MIT |
| xodus (`macd2`, `macd2-broker`) | [MaC-Dungeons-II/xodus](https://github.com/MaC-Dungeons-II/xodus) (`macos` 브랜치) | GPL-3.0 |
| 런타임 프록시 | [MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox](https://github.com/MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox) (`macos` 브랜치) | LGPL-2.1+ |
| 런타임 어댑터, XCurl 래퍼 | [MaC-Dungeons-II/mcd2-crossover](https://github.com/MaC-Dungeons-II/mcd2-crossover) (`macos` 브랜치) | MIT |
| Wine | CodeWeavers crossover-sources 26.3 + `mac/patches` | LGPL-2.1+ |
| DXMT, GDK-Proton 빌트인, WineGDK, GStreamer, FFmpeg, SDL | 원본 프로젝트, [app/NOTICE.md](app/NOTICE.md) 참고 | 고지 참고 |

앱에는 Microsoft나 Mojang 파일이 들어 있지 않습니다. 게임, GDK 런타임, curl은 첫 실행 때 내려받습니다.

## 빌드

M4 Mac, macOS 27에서 빌드했습니다. `mac/build-runtime.sh`에는 실제로 쓴 단계를 그대로 적었지만, 깨끗한 환경에서 처음부터 다시 돌려 보지는 않았습니다.

1. **Wine 런타임:** `mac/build-runtime.sh`를 실행합니다. 준비할 입력물은 스크립트 머리말에 있습니다. 모두 `~/Games/dungeons2-mac` 아래에 둡니다.
   - `mac/patches/`의 패치를 적용한 CrossOver 소스
   - llvm-mingw
   - FFmpeg 7.1.1
   - GStreamer 1.28.7
   - SDL 2.32.10
   - DXMT 68af85e
   - GDK-Proton 11-7 빌트인

   WineGDK 부분과 런타임 프록시는 `mac/build-store-bridge.sh`가 빌드합니다.
2. **어댑터:** mcd2-crossover 포크를 llvm-mingw로 빌드해 `xgameruntime.dll`과 `XCurl.dll`을 만듭니다.
3. **xodus:** xodus 포크를 `cargo build --release`로 빌드합니다.
4. **앱:** `app/build.sh`를 실행하면 `app/dist/`에 앱이 만들어집니다.
5. **아이콘(선택):** 앱 아이콘(Liquid Glass, Icon Composer 형식)을 다시 만들려면 다음을 실행합니다.

   ```bash
   uv run --no-project --with pillow python app/icon/make_icon.py
   ```

## 알려진 한계

- 비공식이고 시험 범위가 좁습니다. 게임 업데이트로 깨질 수 있습니다.
- 클라우드 저장을 Xbox로 다시 올리지 않습니다. 저장은 로컬 저장소에 남습니다.
- 게임 업데이트는 매번 전체 패키지(약 10GB)로 받습니다. 차분 업데이트는 쓰지 않습니다.

## 감사

다음 프로젝트 위에서 만들었습니다.
- [xodus](https://github.com/xodus-gaming/xodus)
- [Flightdeck](https://github.com/marselnenaj/flightdeck-msfs-2024-linux-xbox)
- [mcd2-crossover](https://github.com/Wanzho/mcd2-crossover)
- [WineGDK](https://github.com/Sightem/WineGDK)
- [GDK-Proton](https://github.com/LukasPAH/GDK-Proton-Custom)
- [DXMT](https://github.com/3Shain/dxmt)
- CodeWeavers CrossOver 소스와 Wine 프로젝트
