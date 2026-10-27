# How the GDK layers fit together

**English** · [한국어](architecture.ko.md)

Minecraft Dungeons II (Launcher/Store edition) is a GDK title. It loads `xgameruntime.dll` from its own folder and gets every Xbox service through it: users, Store, saves, networking, task queues. HTTP goes through `XCurl.dll`. On a Mac, both are replaced in `Dungeons/Binaries/WinGDK`, and a helper process runs next to the game.

```
Dungeons-WinGDK-Shipping.exe
 ├─ xgameruntime.dll            1. runtime (Flightdeck fork)
 │   └─ xgameruntime_original.dll  2. Microsoft GDK runtime 2604.4.7897 (genuine)
 └─ XCurl.dll                   3. XCurl wrapper (same fork)
     └─ curl-compat.dll + curl-ca-bundle.crt   curl.se's libcurl 8.22.0 (downloaded)

 xodus_store_test.dll / .so  ──── /tmp/macd2.sock ──── macd2-broker (xodus service)
 (Wine builtin, loaded by 1)
```

Layers 1 and 3 come from the [Flightdeck fork](https://github.com/MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox) (`macos` branch) and are built by `mac/build-store-bridge.sh`. Layer 2 and curl are downloaded from nuget.org and curl.se (SHA-256 pinned). The launcher copies all of them over the game folder before every launch (`overlayLayer`).

## Who answers what

| GDK API | Answered by | Notes |
|---|---|---|
| XUser, XGame (sign-in, Xbox Live tokens and signatures) | 1 → xodus user runtime (`xodus_store_test.dll`) → `macd2-broker` | The genuine runtime can't sign in under Wine. With `XODUS_USER_RUNTIME=1` the runtime hands these to the xodus user runtime, which signs in and makes the tokens and signatures itself. No session file is written. |
| XStore (license, entitlements, package updates) | 1 → xodus store module → `macd2-broker` | Ownership comes from the Microsoft-signed license token for the signed-in account. Nothing is hard-coded. |
| XGameSave | 1, local store | Saves are kept in `C:\gamesave` in the prefix (`XODUS_LOCAL_GAMESAVE=1`) and stay on the Mac; they are not uploaded to the Xbox cloud. Users come from the xodus user runtime, so handles match. |
| XNetworking (TLS policy per URL, used by libHttpClient's websockets) | 1 | Answered by the runtime itself. |
| XThreading (XAsync, task queues), everything else | 2. genuine runtime | The runtime forwards unknown classes unchanged. |
| XCurl (the title's HTTP) | 3 | See below. |

## Changes in the Flightdeck fork

Upstream Flightdeck replaces the whole runtime. Here it sits in front of the genuine runtime, so a few things changed (`macos` branch):

- **Genuine task queues** (`GenuineAsync.h`/`.cpp`). The game's task queues belong to the genuine runtime. Store, GameSave, NetworkSecurity and license-event async work and queue calls go through the genuine `IXThreadingImpl`. The runtime's own XAsync copy would write into the genuine runtime's memory and crash.
- **Lazy start.** Starting the xodus module during runtime init shut the game down before its window opened. The init arguments are saved and the module starts on first use of Store, GameSave or users (`EnsureStoreModule`).
- **Users from the xodus user runtime.** XUser and XGame go there, and GameSave takes its users from the same place. Two user objects make the game fail with 0041.
- **Title config.** Under Wine the genuine runtime doesn't find the title's `MicrosoftGame.config`. Callers that pass no initialization options get one pointing at it; all three Initialize entry points go through `InitializeApiImplEx2`. This follows mcd2-crossover's adapter.
- **Websockets.** `wss://` is checked like `https://`. Port 0 means 443. Hosts outside the title's policy get TLS 1.2 with no pins (certificates are still verified).
- **Package updates** report "no updates". The launcher installs and updates the game itself.

## XCurl wrapper

`compat/xcurl` in the same fork. `XCurl.dll` forwards to curl.se's libcurl (`curl-compat.dll`) with these fixes:

- Every handle verifies peers and hosts against `curl-ca-bundle.crt`; attempts to lower verification are refused.
- `SSL_CTX` callbacks are refused (the game passes an OpenSSL 1.1 callback; this libcurl uses LibreSSL).
- When the caller's headers carry exactly one Content-Length and no Transfer-Encoding, curl is told the same size, so streamed POSTs aren't sent chunked (PlayFab sign-in rejects that).
- `DllMain` applies an in-memory fix for a use-after-return in Wine's wait queue (`RtlWaitOnAddress`, WineHQ bug 60397).

Its behaviour follows mcd2-crossover's XCurl wrapper (MIT, Copyright (c) 2026 Wanzho), rewritten without its diagnostics. Earlier versions of this launcher shipped that adapter in front of the runtime; it is no longer used, and the launcher removes its leftover files from the game folder.

## Helper processes

- **`macd2-broker`** (xodus service) listens on `/tmp/macd2.sock`. It answers the xodus user runtime (sign-in, tokens) and Store license and entitlement queries using the account's Microsoft-signed license token.
- **`macd2 mac-session --check`** is how the launcher checks sign-in before showing Install or Play. It signs in to the Xbox services and reports only the outcome (exit 0, 77 sign in again, 69 offline). It writes nothing.
- **`macd2 mac-fetch`** downloads and extracts the game package.
- **`macd2 run`** decrypts the game's encrypted executables into a RAM disk and starts Wine. The game's anti-tamper re-reads its own executable, so that copy has to be the real file.

## Minecraft Launcher link (optional)

Off unless the user turns it on in the app (`MCLauncherPatch.swift`, `app/Resources/mclauncher/`).

- The Minecraft Launcher's `ui.zip` is patched for the Dungeons II page only (edits in `patch.json`, injected code `mclauncher-link.js`). The original is kept as `~/Library/Application Support/minecraft/macd2-ui.zip.orig` and put back when the link is turned off. While on, the patch is re-applied when the app starts after a launcher update. Writing it needs macOS App Management permission.
- A per-user LaunchAgent (`io.github.mac-dungeons-ii.link`) has launchd listen on `127.0.0.1:47821` and runs `agent-handler.sh` per request: it answers whether the game is installed and, on Play, runs `open -g -j macd2://play` (the app opens hidden).
- While running, the app itself listens on `127.0.0.1:47822` (`MCLauncherLink.swift`). The launcher page polls its status for the download bar and posts pause, resume, cancel, show, stop and retry.
- Both listeners answer only requests with `Origin: https://mojang` (the launcher page).

## Debugging switches

| Variable | Effect |
|---|---|
| `MACD2_WINEDEBUG` | Overrides `WINEDEBUG` (default `err+all,fixme-all`) |
| `MACD2_MSYNC=0` | Turns off Mach-semaphore sync |
| `XODUS_TRACE_QUERYAPI=1` | Logs every QueryApi call the runtime forwards to the genuine runtime (very noisy) |

These can go in `debug.env` in the data folder (one `KEY=VALUE` per line). Logs are in `~/Library/Application Support/M(a)C Dungeons II/logs`.
