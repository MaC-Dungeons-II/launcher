# How the GDK layers fit together

**English** · [한국어](architecture.ko.md)

Minecraft Dungeons II (Launcher/Store edition) is a GDK title. It loads `xgameruntime.dll` from its own folder and gets every Xbox service through it: users, Store, saves, networking, task queues. On a Mac, three DLLs are stacked in `Dungeons/Binaries/WinGDK`, plus two helper processes.

```
Dungeons-WinGDK-Shipping.exe
 └─ xgameruntime.dll            1. mcd2-crossover adapter
     └─ xgameruntime-native.dll 2. Flightdeck runtime proxy
         └─ xgameruntime_original.dll  3. Microsoft GDK runtime 2604.4.7897 (genuine)
                                   │
 xodus_store_test.dll / .so  ──── Unix socket ──── macd2-broker (xodus service)
 session.bin  ◄────────────────────────────────── macd2 mac-session --serve
```

The launcher copies layers 1 and 2 over the game folder before every launch (`overlayLayer`). Layer 3 is downloaded from nuget.org on first run (SHA-256 pinned).

## Who answers what

| GDK API | Answered by | Why |
|---|---|---|
| XUser (sign-in, tokens) | 1. adapter | The genuine runtime can't sign in under Wine. The adapter serves one account from `session.bin`, which `macd2 mac-session --serve` keeps fresh. |
| XCurl (HTTP for the title) | 1. adapter's `XCurl.dll` | Wraps curl and attaches Xbox tokens for PlayFab and Minecraft services. |
| XNetworking security info (TLS policy per URL) | 2. proxy, reached via 1 | libHttpClient asks for it before opening WinHTTP websockets. The adapter forwards vtable slots 8–14 to the proxy's exported `MacNetworkingImpl`. |
| XStore (license, entitlements, package updates) | 2. proxy → xodus store module → `macd2-broker` | Ownership comes from the Microsoft-signed license token for the signed-in account. Nothing is hard-coded. |
| XGameSave | 2. proxy, local store | Saves are kept in `C:\gamesave` in the prefix (`XODUS_LOCAL_GAMESAVE=1`). Uses layer 1's XUser so user handles match. |
| XThreading (XAsync, task queues), everything else | 3. genuine runtime | The proxy forwards unknown classes unchanged. |

## Changes the Mac chain needed

Upstream Flightdeck expects to be the outermost runtime. Here it sits between the adapter and the genuine runtime, so a few things changed (`macos` branch of the [Flightdeck fork](https://github.com/MaC-Dungeons-II/flightdeck-msfs-2024-linux-xbox)):

- **Genuine task queues** (`GenuineAsync.h`). The game's task queues belong to the genuine runtime. Store, GameSave and NetworkSecurity async work goes through the genuine `IXThreadingImpl`. The proxy's own XAsync copy would write into the genuine runtime's memory and crash.
- **Lazy Store module.** Starting the xodus store module during runtime init shut the game down before its window opened. The init arguments are saved and the module starts on first Store or GameSave use (`EnsureStoreModule`).
- **GameSave uses the adapter's XUser.** Otherwise there are two user objects and the game fails with 0041.
- **Websockets.** `wss://` is checked like `https://`. Port 0 means 443. Hosts outside the title's policy get TLS 1.2 with no pins (certificates are still verified).
- **Package updates** report "no updates". The launcher installs and updates the game itself.

Adapter changes (`macos` branch of the [mcd2-crossover fork](https://github.com/MaC-Dungeons-II/mcd2-crossover)):
- XNetworking security-info forwarding to the proxy
- `XUserIsStoreUser` reports the signed-in account

## Helper processes

- **`macd2-broker`** (xodus service) listens on `/tmp/macd2.sock`. It answers Store license and entitlement queries using the account's Microsoft-signed license token.
- **`macd2 mac-session --serve`** writes and refreshes the adapter's Xbox session (`session/session.bin`).
- **`macd2 run`** decrypts the game's encrypted executables into a RAM disk and starts Wine. The game's anti-tamper re-reads its own executable, so that copy has to be the real file.

## Debugging switches

| Variable | Effect |
|---|---|
| `MACD2_WINEDEBUG` | Overrides `WINEDEBUG` (default `err+all,fixme-all`) |
| `MACD2_MSYNC=0` | Turns off Mach-semaphore sync |
| `XODUS_TRACE_QUERYAPI=1` | Logs every QueryApi call the proxy forwards to the genuine runtime (very noisy) |

Logs are in `~/Library/Application Support/M(a)C Dungeons II/logs`.
