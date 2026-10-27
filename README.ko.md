# M(a)C Dungeons II

[English](README.md) · **한국어**

Minecraft Launcher(Microsoft Store)판 **Minecraft Dungeons II**를 Mac에서 실행하는 비공식 런처입니다.

> [!CAUTION]
> 비공식 프로젝트입니다. 사용에 따른 책임은 사용자에게 있습니다. Mojang, Microsoft, Xbox와 관련이 없으며 이들의 승인이나 후원을 받지 않았습니다. Minecraft, Minecraft Dungeons를 비롯해 여기 나오는 상표, 제품명, 회사명, 로고는 각 소유자의 것입니다.

> [!IMPORTANT]
> **게임을 구매한 계정이 있어야 합니다.** 라이선스 확인을 우회하지 않으며, 소유하지 않은 계정으로는 실행되지 않습니다.

## 되는 것

M4 MacBook(macOS 27)에서 확인했습니다: 기존 영웅으로 온라인 플레이, 설정과 저장, 게임 영상, 블루투스 Xbox 컨트롤러. 게임 업데이트로 동작이 깨질 수 있습니다.

아직 안 되는 것: 저장은 Mac에만 남고(Xbox 클라우드 동기화 없음), 게임 업데이트 때마다 전체 패키지를 다시 받습니다.

## 요구 사항

- Apple Silicon Mac(Rosetta 2), macOS 14 이상
- Minecraft Dungeons II를 소유한 Microsoft 계정
- 첫 설치 시 여유 공간 약 25GB

## 설치

1. [Releases](../../releases)에서 `MaC-Dungeons-II.dmg`를 받아 열고, 앱을 Applications로 끌어다 놓습니다.
2. 앱을 엽니다. 공증을 받지 않은 앱이라 처음에는 macOS가 막습니다. **시스템 설정 → 개인정보 보호 및 보안**에서 **그래도 열기**를 누릅니다.

## 플레이

1. Microsoft 계정으로 로그인합니다. Minecraft Launcher 로그인과는 별개입니다.
2. Microsoft GDK 라이선스에 동의합니다(한 번만).
3. **설치**를 누릅니다. 설치가 끝난 뒤에는 **플레이**를 누릅니다.

## Minecraft Launcher에서 플레이 (선택)

Mac용 Minecraft Launcher가 있으면 거기서도 Dungeons II를 시작할 수 있습니다. 앱의 플레이 준비 화면이나 **파일 → Minecraft Launcher 연결…**에서 **Minecraft Launcher에서도 플레이**를 켭니다.

그러면 Minecraft Launcher의 Dungeons II 화면에 설치/플레이 버튼이 생기고, 다운로드도 거기에 표시됩니다. 이 앱은 숨은 채로 돌다가 로그인처럼 직접 해야 할 일이 있을 때만 창을 띄웁니다.

이를 위해 앱이 Minecraft Launcher를 수정하므로, macOS가 **앱 관리** 권한을 허용할지 묻습니다. 스위치를 끄면 Minecraft Launcher가 원래대로 돌아갑니다.

## 삭제

1. Minecraft Launcher 연결을 켰다면 먼저 앱에서 끕니다.
2. 앱을 삭제합니다.
3. `~/Library/Application Support/M(a)C Dungeons II`를 삭제합니다(게임과 저장 데이터).
4. 키체인 접근에서 이름이 "M(a)C Dungeons II"인 항목을 삭제합니다.

연결을 켠 채로 앱을 이미 지웠다면 [Minecraft Launcher 연결 직접 되돌리기](docs/architecture.ko.md#연결-직접-되돌리기)를 참고하세요.

## 개발자용

- 구조: [docs/architecture.ko.md](docs/architecture.ko.md)
- 빌드: [docs/building.ko.md](docs/building.ko.md)

| 구성 요소 | 저장소 | 라이선스 |
|---|---|---|
| 런처 앱, 빌드 스크립트, Wine 패치 | 이 저장소 | MIT (Wine 패치는 LGPL-2.1+) |
| xodus (`macd2`, `macd2-broker`) | [MaC-Dungeons-II/xodus](https://github.com/MaC-Dungeons-II/xodus) | GPL-3.0 |
| 런타임(`xgameruntime.dll`), XCurl 래퍼 | [MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox](https://github.com/MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox) | LGPL-2.1+ (XCurl 래퍼는 MIT) |
| Wine | CodeWeavers crossover-sources 26.3 | LGPL-2.1+ |
| DXMT, GDK-Proton, WineGDK, GStreamer, FFmpeg, SDL | [app/NOTICE.md](app/NOTICE.md) 참고 | 각 프로젝트 |

이 저장소와 릴리스에는 Microsoft·Mojang 파일이 없습니다. 게임과 GDK 런타임은 앱이 직접 내려받습니다.

## 감사

- [xodus](https://github.com/xodus-gaming/xodus) — Microsoft 로그인, 라이선스, 패키지 다운로드
- [Flightdeck](https://github.com/marselnenaj/flightdeck-msfs-2024-linux-xbox) — GDK 런타임 프록시, Store 브로커
- [mcd2-crossover](https://github.com/Wanzho/mcd2-crossover)(Wanzho) — 정품 런타임을 처음 쓸 수 있게 해 준 초기 어댑터. XCurl 수정, Wine 대기 큐 수정, 타이틀 설정 기본값, XUser 인터페이스 구조는 이 작업을 따랐습니다.
- [WineGDK](https://github.com/Sightem/WineGDK), [GDK-Proton](https://github.com/LukasPAH/GDK-Proton-Custom) — GDK 빌트인
- [DXMT](https://github.com/3Shain/dxmt) — Direct3D 11 → Metal
- CodeWeavers, Wine 프로젝트
