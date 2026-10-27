# GDK 계층 구조

[English](architecture.md) · **한국어**

Minecraft Dungeons II(Launcher/Store판)는 GDK 타이틀입니다. 게임 폴더의 `xgameruntime.dll`을 불러와 사용자, Store, 저장, 네트워크, 작업 큐 같은 Xbox 기능을 전부 그걸 통해 씁니다. HTTP는 `XCurl.dll`을 거칩니다. Mac에서는 `Dungeons/Binaries/WinGDK`의 이 두 DLL을 바꿔 넣고, 보조 프로세스 하나를 게임 옆에 띄웁니다.

```
Dungeons-WinGDK-Shipping.exe
 ├─ xgameruntime.dll            1. 런타임 (Flightdeck 포크)
 │   └─ xgameruntime_original.dll  2. Microsoft GDK 런타임 2604.4.7897 (정품)
 └─ XCurl.dll                   3. XCurl 래퍼 (같은 포크)
     └─ curl-compat.dll + curl-ca-bundle.crt   curl.se libcurl 8.22.0 (내려받음)

 xodus_store_test.dll / .so  ──── /tmp/macd2.sock ──── macd2-broker (xodus 서비스)
 (Wine 빌트인, 1이 불러옴)
```

1, 3번은 [Flightdeck 포크](https://github.com/MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox)(`macos` 브랜치)에서 나오며 `mac/build-store-bridge.sh`로 빌드합니다. 2번과 curl은 nuget.org와 curl.se에서 받고 SHA-256으로 확인합니다. 런처는 실행할 때마다 이 파일들을 게임 폴더에 덮어씁니다(`overlayLayer`).

## 누가 무엇을 처리하나

| GDK API | 처리하는 곳 | 설명 |
|---|---|---|
| XUser, XGame (로그인, Xbox Live 토큰과 서명) | 1 → xodus 사용자 런타임(`xodus_store_test.dll`) → `macd2-broker` | 정품 런타임은 Wine에서 로그인하지 못합니다. `XODUS_USER_RUNTIME=1`이면 런타임이 이 호출을 xodus 사용자 런타임에 넘기고, 사용자 런타임이 직접 로그인해서 토큰과 서명을 만듭니다. 세션 파일은 쓰지 않습니다. |
| XStore (라이선스, 보유 목록, 패키지 업데이트) | 1 → xodus store 모듈 → `macd2-broker` | 소유권은 로그인한 계정의 Microsoft 서명 라이선스 토큰으로 확인합니다. 고정 응답은 없습니다. |
| XGameSave | 1, 로컬 저장소 | 프리픽스의 `C:\gamesave`에 저장합니다(`XODUS_LOCAL_GAMESAVE=1`). 저장은 Mac에만 남고 Xbox 클라우드로 올리지 않습니다. 사용자 핸들이 맞도록 xodus 사용자 런타임의 사용자를 씁니다. |
| XNetworking (URL별 TLS 정책, libHttpClient 웹소켓이 사용) | 1 | 런타임이 직접 응답합니다. |
| XThreading (XAsync, 작업 큐), 그 밖의 전부 | 2. 정품 런타임 | 런타임이 모르는 클래스는 그대로 넘깁니다. |
| XCurl (게임의 HTTP) | 3 | 아래 참고. |

## Flightdeck 포크의 변경

원래 Flightdeck은 런타임 전체를 대신합니다. 여기서는 정품 런타임 앞에 놓이기 때문에 몇 가지를 바꿨습니다(`macos` 브랜치).

- **정품 작업 큐 사용** (`GenuineAsync.h`/`.cpp`): 게임의 작업 큐는 정품 런타임 소유입니다. Store, GameSave, NetworkSecurity, 라이선스 이벤트의 비동기 작업과 큐 호출은 정품 `IXThreadingImpl`로 처리합니다. 런타임 자체의 XAsync를 쓰면 정품 런타임 메모리에 써서 크래시가 납니다.
- **지연 시작:** 런타임 초기화 때 xodus 모듈을 띄우면 게임 창이 뜨기 전에 게임이 종료됐습니다. 그래서 초기화 인자만 저장해 두고, Store, GameSave, 사용자 기능을 처음 쓸 때 시작합니다(`EnsureStoreModule`).
- **사용자는 xodus 사용자 런타임에서:** XUser와 XGame을 그쪽으로 보내고, GameSave도 같은 곳의 사용자를 씁니다. 사용자 객체가 두 개가 되면 게임이 0041 오류로 실패합니다.
- **타이틀 설정:** Wine에서는 정품 런타임이 게임의 `MicrosoftGame.config`를 찾지 못합니다. 초기화 옵션 없이 부르면 이 파일을 가리키는 옵션을 넣어 주고, Initialize 진입점 세 개를 모두 `InitializeApiImplEx2`로 모읍니다. mcd2-crossover 어댑터의 방식을 따랐습니다.
- **웹소켓:** `wss://`는 `https://`와 같은 정책으로 확인합니다. 포트 0은 443입니다. 게임 정책에 없는 호스트에는 TLS 1.2, 핀 없음을 적용합니다(인증서는 그대로 검증합니다).
- **패키지 업데이트:** "업데이트 없음"으로 응답합니다. 게임 설치와 업데이트는 런처가 직접 합니다.

## XCurl 래퍼

같은 포크의 `compat/xcurl`입니다. `XCurl.dll`은 curl.se의 libcurl(`curl-compat.dll`)로 호출을 넘기면서 다음을 고칩니다.

- 모든 핸들이 `curl-ca-bundle.crt`로 서버와 호스트를 검증합니다. 검증을 낮추려는 설정은 거부합니다.
- `SSL_CTX` 콜백은 거부합니다(게임은 OpenSSL 1.1용 콜백을 넘기지만 이 libcurl은 LibreSSL을 씁니다).
- 호출 측 헤더에 Content-Length가 정확히 하나 있고 Transfer-Encoding이 없으면 curl에도 같은 크기를 알려 줍니다. 그래야 스트리밍 POST가 chunked로 나가지 않습니다(PlayFab 로그인이 이를 거부함).
- `DllMain`에서 Wine 대기 큐(`RtlWaitOnAddress`)의 use-after-return 문제(WineHQ 버그 60397)를 메모리에서 고칩니다.

동작은 mcd2-crossover의 XCurl 래퍼(MIT, Copyright (c) 2026 Wanzho)를 따랐고, 진단 기능은 빼고 다시 썼습니다. 이전 버전의 런처는 이 어댑터를 런타임 앞에 두었지만 지금은 쓰지 않으며, 런처가 게임 폴더에 남은 파일을 지웁니다.

## 보조 프로세스

- **`macd2-broker`**(xodus 서비스): `/tmp/macd2.sock`에서 대기합니다. xodus 사용자 런타임(로그인, 토큰)과 Store 라이선스·보유 목록 질의에 계정의 Microsoft 서명 라이선스 토큰으로 응답합니다.
- **`macd2 mac-session --check`**: 런처가 설치·플레이 버튼을 보여 주기 전에 로그인을 확인할 때 씁니다. Xbox 서비스에 로그인해 보고 결과만 알립니다(종료 코드 0, 77 다시 로그인, 69 오프라인). 아무것도 쓰지 않습니다.
- **`macd2 mac-fetch`**: 게임 패키지를 내려받아 풉니다.
- **`macd2 run`**: 암호화된 게임 실행 파일을 RAM 디스크에 풀고 Wine을 실행합니다. 게임의 변조 방지 코드가 자기 실행 파일을 다시 읽기 때문에, 이 사본이 실제 파일이어야 합니다.

## Minecraft Launcher 연결 (선택)

사용자가 앱에서 켜지 않으면 동작하지 않습니다(`MCLauncherPatch.swift`, `app/Resources/mclauncher/`).

- Minecraft Launcher의 `ui.zip`에서 Dungeons II 화면 부분만 고칩니다(수정 내용은 `patch.json`, 넣는 코드는 `mclauncher-link.js`). 원본은 `~/Library/Application Support/minecraft/macd2-ui.zip.orig`로 보관하고, 연결을 끄면 되돌립니다. 켜져 있는 동안 런처가 업데이트되면 다음에 앱이 시작할 때 다시 적용합니다. 이 파일을 쓰려면 macOS 앱 관리 권한이 필요합니다.
- 사용자별 LaunchAgent(`io.github.mac-dungeons-ii.link`)로 launchd가 `127.0.0.1:47821`에서 대기하고, 요청마다 `agent-handler.sh`를 실행합니다. 게임 설치 여부에 답하고, 플레이 요청이면 `open -g -j macd2://play`로 앱을 숨긴 채 엽니다.
- 앱이 실행 중일 때는 앱이 직접 `127.0.0.1:47822`에서 대기합니다(`MCLauncherLink.swift`). 런처 화면이 다운로드 막대에 쓸 상태를 가져가고, 일시 정지·이어 받기·취소·창 보기·중지·다시 시도를 요청합니다.
- 두 곳 모두 `Origin: https://mojang`(런처 화면)인 요청에만 응답합니다.

## 디버깅용 환경 변수

| 변수 | 효과 |
|---|---|
| `MACD2_WINEDEBUG` | `WINEDEBUG`를 바꿉니다(기본 `err+all,fixme-all`). |
| `MACD2_MSYNC=0` | Mach 세마포어 동기화를 끕니다. |
| `XODUS_TRACE_QUERYAPI=1` | 런타임이 정품 런타임으로 넘기는 QueryApi 호출을 전부 기록합니다(양이 매우 많음). |

데이터 폴더의 `debug.env`에 한 줄에 하나씩 `KEY=VALUE`로 적어도 됩니다. 로그는 `~/Library/Application Support/M(a)C Dungeons II/logs`에 있습니다.
