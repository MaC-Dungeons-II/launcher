// Injected at the top of Minecraft Launcher's main bundle by mclauncher-link.py.
// Dungeons II only: Play goes to M(a)C Dungeons II, whose state (from the app's
// http://127.0.0.1:47822/status) then drives the Play button and the
// launcher's own download bar, as Minecraft: Java Edition's downloads do.
(function () {
  var APP = "http://127.0.0.1:47822";
  // the launcher's own language setting (CEF runs with --lang=en-US)
  function korean() {
    try { return /^ko/i.test(window.appData.launcherSettings.locale); } catch (e) { return false; }
  }
  var TEXT = {
    ko: {
      banner: "Minecraft Dungeons II는 비공식 Mac 포팅 런처 M(a)C Dungeons II를 통해 실행돼요.",
      head: "Mac에서 플레이하기",
      body: "플레이를 누르면 비공식 포팅 런처 M(a)C Dungeons II가 게임을 실행해요. Mojang·Microsoft와 관계없는 프로젝트라, 문제는 저장소에 알려 주세요.",
      repo: "저장소 바로가기", starting: "M(a)C Dungeons II 시작 중",
    },
    en: {
      banner: "Minecraft Dungeons II runs on this Mac through M(a)C Dungeons II, an unofficial port.",
      head: "Playing on Mac",
      body: "Play starts the game through M(a)C Dungeons II, an unofficial port not affiliated with Mojang or Microsoft. Please report problems on our repository.",
      repo: "Open our repo", starting: "Starting M(a)C Dungeons II",
    },
  };
  function t(k) { return (korean() ? TEXT.ko : TEXT.en)[k]; }
  window.__macd2Repo = "https://github.com/MaC-Dungeons-II/launcher";
  window.__macd2T = t;

  // M(a)C Dungeons II's state, shared by the Play button and the download bar.
  // Polled from the app while anything shows it; `pending` covers the seconds
  // between Play and the app answering.
  var AGENT = "http://127.0.0.1:__PORT__";
  // installed: from the app while it runs, else from the agent (Play / Install)
  var state = { app: null, pending: 0, installed: true }, listeners = [], timer = 0;
  function emit() { listeners.slice().forEach(function (f) { f(state); }); }
  function poll() {
    clearTimeout(timer);
    if (!listeners.length) { timer = 0; return; }
    fetch(APP + "/status", { cache: "no-store" })
      .then(function (r) { return r.json(); })
      .then(function (j) {
        state = { app: j, pending: j.stage === "idle" ? state.pending : 0, installed: !!j.installed };
        return 1000;
      }, function () {
        state = { app: null, pending: state.pending, installed: state.installed };
        return fetch(AGENT + "/installed", { cache: "no-store" })   // not running (yet)
          .then(function (r) { return r.json(); })
          .then(function (j) { state.installed = !!j.installed; }, function () {})
          .then(function () { return state.pending ? 1000 : 3000; });
      })
      .then(function (ms) {
        if (state.pending && Date.now() - state.pending > 30000) state.pending = 0;
        emit();
        timer = setTimeout(poll, ms);
      });
  }
  function subscribe(f) {
    listeners.push(f);
    if (!timer) poll();
    return function () { listeners = listeners.filter(function (g) { return g !== f; }); };
  }
  function useAppState(R, on) {
    var st = R.useState(state), set = st[1];
    R.useEffect(function () { return on ? subscribe(set) : undefined; }, [on]);
    return on ? st[0] : null;
  }

  window.__macd2Installed = function () { return state.installed; };

  // Play: a launchd agent on PORT opens the app (the launcher drops macd2:// popups)
  window.__macd2 = function () {
    console.log("macd2: play");
    state = { app: state.app, pending: Date.now() };
    emit();
    fetch(AGENT + "/play", { method: "POST", mode: "no-cors" })
      .catch(function (e) { console.log("macd2: " + e); });
    if (!timer && listeners.length) poll();
    return Promise.resolve();
  };

  // The Play button's instance state while the app works or the game runs
  // (Downloading and Running disable it, as for Minecraft: Java Edition).
  window.__macd2Use = function (R, productId) {
    var s = useAppState(R, productId === "dungeons2");
    if (!s) return null;
    if (s.pending) return "Downloading";
    if (!s.app) return null;
    if (s.app.stage === "working") return "Downloading";
    if (s.app.stage === "playing") return "Running";
    return null;
  };

  // The launcher's own download bar (`Bar`, as for other products' downloads)
  function downloadData(s) {
    var a = s.app, t = a && a.transfer;
    var base = { id: "macd2", productId: "dungeons2", intent: t && t.update ? "Update" : "Install",
                 progress: a && typeof a.progress === "number" ? a.progress : 0,
                 currentBytes: 0, totalBytes: 0 };
    if (s.pending && (!a || a.stage === "idle"))
      return Object.assign(base, { state: "Preparing", note: t_("starting") });
    if (!a) return null;
    switch (a.stage) {
      case "working":
        if (t && t.phase === "download")
          return Object.assign(base, { state: "Downloading", currentBytes: t.done, totalBytes: t.total });
        return Object.assign(base, { state: t ? "Finalizing" : "Preparing", note: a.status });
      case "paused":
        return Object.assign(base, { state: "Paused", currentBytes: t ? t.done : 0, totalBytes: t ? t.total : 0 });
      case "needsLogin":
      case "needsConsent":
        return Object.assign(base, { state: "Pending", note: a.status });
      case "failed":
        return Object.assign(base, { state: "Errored", note: a.status });
      default:
        return null;
    }
  }
  function t_(k) { return t(k); }
  function post(cmd) {
    fetch(APP + "/" + cmd, { method: "POST" }).catch(function (e) { console.log("macd2: " + e); });
  }
  var Bar = null;
  window.__macd2Bar = function (R, DownloadBar) {
    if (!Bar) Bar = function () {
      var s = useAppState(R, true);
      var d = s && downloadData(s);
      if (!d) return null;
      // pause, resume and cancel act on the game download only
      var transfer = d.state === "Downloading" || d.state === "Paused";
      return R.createElement(DownloadBar, {
        downloadData: d, interruptible: transfer, fixed: true,
        isCancelEnabled: function (st) { return st === "Downloading" || st === "Paused"; },
        onPause: function () { post("pause"); },
        onResume: function () { post("resume"); },
        onCancel: function () { post("cancel"); },
        // the app's own words stand alone (patched bar text, see mclauncher-link.py)
        additionalStateText: function () { return d.note ? { macd2: true, text: d.note } : null; },
      });
    };
    return R.createElement(Bar, { key: "macd2ProgressBar" });
  };
})();
