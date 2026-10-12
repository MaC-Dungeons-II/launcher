# GDK 계층 구조

[English](architecture.md) · **한국어**

Minecraft Dungeons II(Launcher/Store판)는 GDK 타이틀입니다. 게임 폴더의 `xgameruntime.dll`을 불러와 사용자, Store, 저장, 네트워크, 작업 큐 같은 Xbox 기능을 전부 그걸 통해 씁니다. Mac에서는 `Dungeons/Binaries/WinGDK`에 DLL 세 개를 겹쳐 두고, 보조 프로세스 두 개를 같이 띄웁니다.

```
Dungeons-WinGDK-Shipping.exe
 └─ xgameruntime.dll            1. mcd2-crossover 어댑터
     └─ xgameruntime-native.dll 2. Flightdeck 런타임 프록시
         └─ xgameruntime_original.dll  3. Microsoft GDK 런타임 2604.4.7897 (정품)
                                   │
 xodus_store_test.dll / .so  ──── Unix 소켓 ──── macd2-broker (xodus 서비스)
 session.bin  ◄────────────────────────────────── macd2 mac-session --serve
```

1, 2번은 런처가 실행할 때마다 게임 폴더에 덮어씁니다(`overlayLayer`). 3번은 첫 실행 때 nuget.org에서 받고 SHA-256으로 확인합니다.

## 누가 무엇을 처리하나

| GDK API | 처리하는 곳 | 이유 |
|---|---|---|
| XUser (로그인, 토큰) | 1. 어댑터 | 정품 런타임은 Wine에서 로그인하지 못합니다. 어댑터가 `session.bin`의 계정 하나를 제공하고, `macd2 mac-session --serve`가 이 파일을 계속 갱신합니다. |
| XCurl (게임의 HTTP) | 1. 어댑터의 `XCurl.dll` | curl을 감싸서 PlayFab, Minecraft 서비스 요청에 Xbox 토큰을 붙입니다. |
| XNetworking 보안 정보 (URL별 TLS 정책) | 2. 프록시 (1을 거쳐서) | libHttpClient가 WinHTTP 웹소켓을 열기 전에 묻습니다. 어댑터가 vtable 8~14번을 프록시의 `MacNetworkingImpl`로 넘깁니다. |
| XStore (라이선스, 보유 목록, 패키지 업데이트) | 2. 프록시 → xodus store 모듈 → `macd2-broker` | 소유권은 로그인한 계정의 Microsoft 서명 라이선스 토큰으로 확인합니다. 고정 응답은 없습니다. |
| XGameSave | 2. 프록시, 로컬 저장소 | 프리픽스의 `C:\gamesave`에 저장합니다(`XODUS_LOCAL_GAMESAVE=1`). 사용자 핸들이 맞도록 1번의 XUser를 씁니다. |
| XThreading (XAsync, 작업 큐), 그 밖의 전부 | 3. 정품 런타임 | 프록시가 모르는 클래스는 그대로 넘깁니다. |

## Mac 구성에 필요했던 변경

원래 Flightdeck은 자기가 가장 바깥 런타임이라고 가정합니다. 여기서는 어댑터와 정품 런타임 사이에 끼어 있어서 몇 가지를 바꿨습니다([Flightdeck 포크](https://github.com/MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox) `macos` 브랜치).

- **정품 작업 큐 사용** (`GenuineAsync.h`): 게임의 작업 큐는 정품 런타임 소유입니다. Store, GameSave, NetworkSecurity의 비동기 작업은 정품 `IXThreadingImpl`로 처리합니다. 프록시 자체의 XAsync를 쓰면 정품 런타임 메모리에 써서 크래시가 납니다.
- **Store 모듈 지연 시작:** 런타임 초기화 때 xodus store 모듈을 띄우면 게임 창이 뜨기 전에 게임이 종료됐습니다. 그래서 초기화 인자만 저장해 두고, Store나 GameSave를 처음 쓸 때 시작합니다(`EnsureStoreModule`).
- **GameSave는 어댑터의 XUser 사용:** 이렇게 하지 않으면 사용자 객체가 두 개가 되어 0041 오류가 납니다.
- **웹소켓:** `wss://`는 `https://`와 같은 정책으로 확인합니다. 포트 0은 443입니다. 게임 정책에 없는 호스트에는 TLS 1.2, 핀 없음을 적용합니다(인증서는 그대로 검증합니다).
- **패키지 업데이트:** "업데이트 없음"으로 응답합니다. 게임 설치와 업데이트는 런처가 직접 합니다.

어댑터 변경([mcd2-crossover 포크](https://github.com/MaC-Dungeons-II/mcd2-crossover) `macos` 브랜치):
- XNetworking 보안 정보를 프록시로 전달
- `XUserIsStoreUser`가 로그인한 계정을 Store 사용자로 보고

## 보조 프로세스

- **`macd2-broker`**(xodus 서비스): `/tmp/macd2.sock`에서 대기하며, 계정의 Microsoft 서명 라이선스 토큰으로 Store 라이선스와 보유 목록 질의에 응답합니다.
- **`macd2 mac-session --serve`**: 어댑터가 쓰는 Xbox 세션(`session/session.bin`)을 만들고 갱신합니다.
- **`macd2 run`**: 암호화된 게임 실행 파일을 RAM 디스크에 풀고 Wine을 실행합니다. 게임의 변조 방지 코드가 자기 실행 파일을 다시 읽기 때문에, 이 사본이 실제 파일이어야 합니다.

## 디버깅용 환경 변수

| 변수 | 효과 |
|---|---|
| `MACD2_WINEDEBUG` | `WINEDEBUG`를 바꿉니다(기본 `err+all,fixme-all`). |
| `MACD2_MSYNC=0` | Mach 세마포어 동기화를 끕니다. |
| `XODUS_TRACE_QUERYAPI=1` | 프록시가 정품 런타임으로 넘기는 QueryApi 호출을 전부 기록합니다(양이 매우 많음). |

로그는 `~/Library/Application Support/M(a)C Dungeons II/logs`에 있습니다.
