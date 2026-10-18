# Rosetta 없이 돌리기

[English](arm64-migration.md) · **한국어**

## 왜 필요한가

앱의 Wine 런타임은 x86_64이고 Rosetta 2로 돌아갑니다. Apple 계획은 다음과 같습니다.

- macOS 27이 Rosetta를 온전히 지원하는 마지막 버전입니다.
- macOS 28(2027년 가을 예상)부터는 "오래되고 관리되지 않는 게임을 위한 일부 기능"만 남습니다. Wine 기반 앱이 여기에 들어간다는 말은 없습니다.
- 지금 런타임은 macOS 28에서 동작하지 않는다고 보고 준비합니다.

## 지금 Rosetta가 필요한 부분

| 부분 | 아키텍처 | 전환 후 |
|---|---|---|
| 런처(`MaCDungeons`), `macd2`, `macd2-broker` | arm64 | 그대로 |
| Wine Unix 쪽, DXMT `winemetal.so`, GStreamer, FFmpeg, SDL, gnutls, freetype | x86_64 | arm64로 다시 빌드 |
| Wine PE DLL, DXMT PE DLL | x86_64 (Windows) | ARM64EC/ARM64X 빌드 |
| 게임, GDK 런타임, mcd2 어댑터, Flightdeck 프록시 | x86_64 (Windows) | 그대로. ARM64 Wine 프로세스 안에서 FEX가 에뮬레이션 |

## 목표 구성

macOS용 ARM64 Wine에서 **FEX**가 ARM64EC 방식으로 x86_64 코드를 에뮬레이션합니다. CodeWeavers가 CrossOver Preview(2026년 7월)로 낸 방식과 같습니다. macOS 26.5 이상이 필요합니다(x18 ABI, 4K 페이지 실행, 스레드별 TSO).

덤으로, 2026-10-18 측정 결과: 게임의 변조 방지 코드가 64비트에서 존재하지 않는 명령어(AAM, AAD, `push es`, `pusha`)를 일부러 실행하고 자기 예외 처리기로 해석합니다. 플레이 중 **초당 약 10,000번**이고, 직접 `syscall`도 초당 수백 번입니다. Rosetta에서는 이 하나하나가 Rosetta 예외 처리 스레드, 신호, Wine 처리기를 거쳐서 코어 하나를 계속 씁니다. FEX에서는 에뮬레이터가 바로 Windows 예외를 만들어서 이 왕복 대부분이 사라집니다.

## 구성 요소 현황 (2026년 10월)

- **macOS용 ARM64 Wine:** CodeWeavers는 Wine 쪽(LGPL)을 2027년 초 CrossOver 27 소스와 함께 공개한다고 밝혔습니다. 공식 Wine에는 준비 작업만 들어가 있습니다.
- **macOS용 FEX:** 공식 지원이 없습니다. 커뮤니티 포트(`dbc-hbin/FEX-darwin`)가 있지만 검증되지 않았습니다.
- **DXMT:** ARM64EC 지원이 들어갔고(PR #202, #209), 앱에 넣은 빌드(50102f9)에도 포함돼 있습니다. CI가 arm64 Unix 쪽을 패키징하지 않아서 `winemetal.so`는 소스에서 빌드해야 합니다.
- **커뮤니티 완성 런타임**(Hadron, neutron): **쓰지 않습니다.** 소스와 빌드 과정을 확인할 수 없는 바이너리는 실행하지 않습니다.

## 이 저장소에서 이미 준비한 것

- 런처가 번들 안 폴더(`lib/wine/aarch64-unix`인지 `x86_64-unix`인지)를 보고 런타임 아키텍처를 판단합니다. x86_64 런타임일 때만 Rosetta를 확인하고, 없으면 설치 방법을 안내합니다.
- 빌드 스크립트는 아키텍처에 따라 달라지는 이름을 모두 `HOST_ARCH`(기본값 `x86_64`)에서 만듭니다. 다른 값이면 arm64 런타임을 빌드할 수 있을 때까지 이 문서를 안내하고 멈춥니다.

## 소스가 공개되면 할 일

1. CrossOver 27 소스로 ARM64 Wine을 빌드하고(`HOST_ARCH=arm64`, `aarch64-unix`/`aarch64-windows`), 검증한 소스로 macOS용 FEX를 빌드합니다.
2. Wine 패치를 옮깁니다.
   - `wine-dll-file-map.patch`(로더): 암호화된 실행 파일에 필요합니다.
   - `winemac-icon-mask.patch`: Dock 아이콘
   - `wine-vulkan-soname-fallback.patch`: 필요 없어질 수 있습니다.
3. Unix 쪽 의존성을 arm64로 다시 빌드합니다.
   - GStreamer: 공식 패키지가 universal이라 `bundle-gstreamer.sh`에 `HOST_ARCH`만 주면 됩니다.
   - FFmpeg, SDL, gnutls, freetype
   - DXMT의 `winemetal.so`: 소스에서 빌드합니다.
4. ARM64 Wine에서 `MACD2_VIEW` RAM 디스크 방식을 확인합니다. 게임의 변조 방지 코드가 자기 실행 파일을 다시 읽는데, FEX에서 어떻게 동작할지 모릅니다.
5. 종료 감지 기준값을 확인합니다. x86_64 Wine에서 잰 값(플레이 중 약 100~130개, 종료 후 8개)이라, FEX가 스레드를 더 만들 수 있습니다.
6. 같은 설정(60fps 페이싱, 같은 해상도)으로 x86_64 런타임과 비교합니다. CPU, GPU, 프레임 시간, 로딩 시간을 봅니다.

## 결정 시점

- **CrossOver 27 소스가 공개되면:** 브랜치에서 1~6을 시작합니다.
- **macOS 28 베타 전(2027년 6월 무렵):** arm64 런타임이 준비되지 않았으면 사용자에게 macOS 27에 머물라고 안내합니다.
- **하지 않을 것:** 에뮬레이션 문제를 피하려고 "게임 보유" 응답을 고정하거나 라이선스 확인을 건너뛰지 않습니다.

## 출처

- [Apple Developer Forums: Rosetta 2 in 2027/macOS 28](https://developer.apple.com/forums/thread/787530)
- [CodeWeavers: CrossOver Preview, ARM64 on Mac (2026-07-31)](https://www.codeweavers.com/blog/mjohnson/2026/7/31/crossover-preview-the-right-to-bear-arm64-on-mac)
- [현황 요약이 있는 추적 이슈 (cities-skylines-2-macos #16)](https://github.com/macgameport/cities-skylines-2-macos/issues/16)
