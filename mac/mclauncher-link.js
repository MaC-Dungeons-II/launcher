// Injected at the top of Minecraft Launcher's main bundle by mclauncher-link.py.
// Dungeons II only: Play goes to M(a)C Dungeons II, whose state then replaces
// the Play button (from the app's http://127.0.0.1:47822/status).
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
      repo: "저장소 바로가기", stop: "게임 종료", show: "M(a)C Dungeons II 열기", retry: "다시 시도",
    },
    en: {
      banner: "Minecraft Dungeons II runs on this Mac through M(a)C Dungeons II, an unofficial port.",
      head: "Playing on Mac",
      body: "Play starts the game through M(a)C Dungeons II, an unofficial port not affiliated with Mojang or Microsoft. Please report problems on our repository.",
      repo: "Open our repo", stop: "Quit game", show: "Open M(a)C Dungeons II", retry: "Try again",
    },
  };
  function t(k) { return (korean() ? TEXT.ko : TEXT.en)[k]; }
  window.__macd2Repo = "https://github.com/MaC-Dungeons-II/launcher";
  window.__macd2T = t;

  // Play: a launchd agent on PORT opens the app (the launcher drops macd2:// popups)
  window.__macd2 = function () {
    console.log("macd2: play");
    fetch("http://127.0.0.1:__PORT__/play", { method: "POST", mode: "no-cors" })
      .catch(function (e) { console.log("macd2: " + e); });
    return Promise.resolve();
  };
  function post(cmd) {
    fetch(APP + "/" + cmd, { method: "POST" }).catch(function (e) { console.log("macd2: " + e); });
  }

  var Status = null;
  // R is the page's React (passed from the patched button module)
  window.__macd2Wrap = function (R, productId, button) {
    if (productId !== "dungeons2") return button;
    if (!Status) Status = makeStatus(R);
    return R.createElement(Status, { button: button });
  };

  function makeStatus(R) {
    var h = R.createElement;
    return function (props) {
      var st = R.useState(null), s = st[0], set = st[1];
      R.useEffect(function () {
        var alive = true, timer = 0;
        function tick() {
          fetch(APP + "/status", { cache: "no-store" })
            .then(function (r) { return r.json(); })
            .then(function (j) { if (alive) set(j); return 1000; },
                  function () { if (alive) set(null); return 3000; })   // app not running
            .then(function (ms) { if (alive) timer = setTimeout(tick, ms); });
        }
        tick();
        return function () { alive = false; clearTimeout(timer); };
      }, []);
      if (!s || s.stage === "idle") return props.button;

      var action = s.stage === "playing" ? "stop" : s.stage === "failed" ? "retry"
                 : s.stage === "working" ? null : "show";
      var pct = typeof s.progress === "number" ? Math.max(0, Math.min(100, s.progress * 100)) : null;
      return h("div", {
        "data-testid": "macd2-status",
        style: { display: "flex", flexDirection: "column", gap: "6px", width: "360px", maxWidth: "90vw",
                 padding: "10px 16px", boxSizing: "border-box", background: "#1e1e1f",
                 border: "2px solid #3c8527", color: "#fff", fontFamily: '"Noto Sans", sans-serif' }
      },
        h("div", { style: { display: "flex", alignItems: "center", gap: "12px" } },
          h("div", { style: { flex: "1 1 auto", fontSize: "15px", fontWeight: 600, overflow: "hidden",
                              textOverflow: "ellipsis", whiteSpace: "nowrap" } }, s.status),
          action && h("button", {
            type: "button", onClick: function () { post(action); },
            style: { flex: "0 0 auto", background: "#3c8527", color: "#fff", border: "none",
                     padding: "4px 10px", fontSize: "13px", cursor: "pointer" }
          }, t(action))),
        pct !== null && h("div", { style: { height: "6px", background: "#48494a" } },
          h("div", { style: { height: "100%", width: pct + "%", background: "#3c8527",
                              transition: "width .5s" } })),
        s.detail && h("div", { style: { fontSize: "12px", color: "#b1b2b5", overflow: "hidden",
                                        textOverflow: "ellipsis", whiteSpace: "nowrap" },
                               title: s.detail }, s.detail));
    };
  }
})();
