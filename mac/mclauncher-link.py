"""Link Minecraft Launcher's Dungeons II page to M(a)C Dungeons II (experimental).

The Mac Minecraft Launcher marks Dungeons II "Not playable on this device": its
UI (CEF, launcher.bundle/Contents/Resources/ui.zip, page https://mojang) takes
`playable` from the native platform check. For dungeons2 only, this patches
the UI so that
- the game is playable and the button reads Play;
- Play posts to http://127.0.0.1:47821/play, where a per-user LaunchAgent
  (launchd socket activation; nothing runs until a request, and only requests
  from https://mojang are honoured) opens M(a)C Dungeons II.app hidden. The
  launcher drops non-http popups, so macd2:// cannot be opened directly;
- while the app runs, its state (from http://127.0.0.1:47822, MCLauncherLink.swift)
  shows in the launcher's own download bar and Play button, as Java Edition's
  downloads do;
- the "not playable" alert and "Where is the play button" panel point to this
  project instead (mclauncher-link.js holds the injected code and texts).
Ownership (`ownsGame`) is untouched: the button still needs the account's own
Dungeons II entitlement.

The launcher's executable signature is left as is; only the sealed resource
ui.zip changes. The launcher's updater replaces ui.zip on its next update, so
run this again afterwards. Writing inside another app's bundle needs the
terminal app to be allowed under System Settings > Privacy & Security > App
Management.

  uv run --no-project python mac/mclauncher-link.py           # patch (and the agent)
  uv run --no-project python mac/mclauncher-link.py --agent   # the agent only
  uv run --no-project python mac/mclauncher-link.py --restore # original UI, agent removed
"""
import re
import shutil
import sys
import zipfile
from pathlib import Path

MC = Path.home() / "Library/Application Support/minecraft"
UI = MC / "launcher/launcher.bundle/Contents/Resources/ui.zip"
BACKUP = MC / "macd2-ui.zip.orig"
MARK = "/*macd2-link*/"

PORT = 47821
INIT = MARK + (Path(__file__).with_name("mclauncher-link.js").read_text().replace("__PORT__", str(PORT))) + "\n"

# Dungeons II only: the bottom "can not be played on this device" alert and the
# "Where is the play button!?" panel point to this project instead.
NOTICES = [
    ("return n.hasPlatformSupport?null:a.createElement(c.ZT,{id:`IncompatibleDeviceAlert_${t}`",
     'if("dungeons2"===t)return a.createElement(c.ZT,{id:"IncompatibleDeviceAlert_macd2",isOpen:!i,'
     'message:a.createElement(a.Fragment,null,window.__macd2T("banner")," ",a.createElement("a",'
     '{href:window.__macd2Repo,className:"external-link external-link-light",target:"_blank",'
     'rel:"noopener noreferrer"},window.__macd2T("repo"))),onClose:()=>l(!0),severity:"Info",position:"Bottom"});'
     "return n.hasPlatformSupport?null:a.createElement(c.ZT,{id:`IncompatibleDeviceAlert_${t}`"),
    ("{ownsGame:r,title:o}=(0,Ae.Vt)(l);return a.createElement(Bt,{message:(0,u.YW)(e,{osx:",
     '{ownsGame:r,title:o}=(0,Ae.Vt)(l);if("dungeons2"===l)return a.createElement(Bt,{message:'
     'a.createElement(a.Fragment,null,a.createElement("strong",null,window.__macd2T("head"))," ",'
     'window.__macd2T("body"))},a.createElement(Wt,null,a.createElement(m.z9,{theme:n,typeramp:i,'
     'href:window.__macd2Repo,target:"_blank",rel:"noopener noreferrer",ariaLabel:window.__macd2T("repo")},'
     'window.__macd2T("repo"))));return a.createElement(Bt,{message:(0,u.YW)(e,{osx:'),
]

LABEL = "io.github.mac-dungeons-ii.link"
AGENT = Path.home() / f"Library/LaunchAgents/{LABEL}.plist"
HANDLER = Path.home() / "Library/Application Support/M(a)C Dungeons II/mclauncher-link.sh"
# stdin/stdout are the accepted connection (inetd mode)
HANDLER_SH = r"""#!/bin/zsh
origin= method= target=
IFS=' ' read -r method target _
while IFS= read -r line; do
  line=${line%$'\r'}
  [[ -z $line ]] && break
  [[ ${line:l} == origin:* ]] && origin=${line#*: }
done
cors=$'Access-Control-Allow-Origin: https://mojang\r\nAccess-Control-Allow-Private-Network: true\r\nAccess-Control-Allow-Methods: GET, POST\r\n'
if [[ $origin != https://mojang ]]; then
  printf 'HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'
  exit 0
fi
if [[ $method == GET && $target == /installed ]]; then
  # whether the game is installed, for the button's Play/Install (app not running)
  exe="${0:h}/game/Dungeons/Binaries/WinGDK/Dungeons-WinGDK-Shipping.exe"
  body='{"installed":false}'; [[ -f $exe ]] && body='{"installed":true}'
  printf 'HTTP/1.1 200 OK\r\n%sContent-Type: application/json\r\nCache-Control: no-store\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' "$cors" ${#body} "$body"
  exit 0
fi
printf 'HTTP/1.1 204 No Content\r\n%sContent-Length: 0\r\nConnection: close\r\n\r\n' "$cors"
if [[ $method == POST && $target == /play ]]; then
  # hidden: Minecraft Launcher shows the app's state (MCLauncherLink.swift)
  /usr/bin/open -g -j macd2://play
fi
"""
AGENT_PLIST = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>{LABEL}</string>
    <key>ProgramArguments</key><array><string>/bin/zsh</string><string>{HANDLER}</string></array>
    <key>inetdCompatibility</key><dict><key>Wait</key><false/></dict>
    <key>Sockets</key>
    <dict>
        <key>Listener</key>
        <dict>
            <key>SockNodeName</key><string>127.0.0.1</string>
            <key>SockServiceName</key><string>{PORT}</string>
            <key>SockType</key><string>stream</string>
        </dict>
    </dict>
</dict>
</plist>
"""


def install_agent() -> None:
    import os
    import subprocess
    HANDLER.parent.mkdir(parents=True, exist_ok=True)
    HANDLER.write_text(HANDLER_SH)
    AGENT.parent.mkdir(parents=True, exist_ok=True)
    AGENT.write_text(AGENT_PLIST)
    domain = f"gui/{os.getuid()}"
    subprocess.run(["launchctl", "bootout", f"{domain}/{LABEL}"], capture_output=True)
    subprocess.run(["launchctl", "bootstrap", domain, str(AGENT)], check=True)
    print("agent:", AGENT)


def remove_agent() -> None:
    import os
    import subprocess
    subprocess.run(["launchctl", "bootout", f"gui/{os.getuid()}/{LABEL}"], capture_output=True)
    for f in (AGENT, HANDLER):
        f.unlink(missing_ok=True)
PLAYABLE_OLD = "updatePlayable:(e,t)=>{e.productGameConfigs[t.payload.productId].playable=t.payload.value}"
PLAYABLE_NEW = ('updatePlayable:(e,t)=>{e.productGameConfigs[t.payload.productId].playable='
                '"dungeons2"===t.payload.productId||t.payload.value}')
# The play/install/update button (every product page uses this one component):
# for Dungeons II it reports the game as installed, so the button reads Play,
# and any press opens our app instead of the Store install flow.
BUTTON = [
    ("F=!!X&&X.isInstalled", 'F="dungeons2"===e?window.__macd2Installed():!!X&&X.isInstalled'),
    ("_=(0,c.useCallback)(((e,a)=>{(0,r.YW)(Q,{play:",
     '_=(0,c.useCallback)(((e,a)=>{if("dungeons2"===Y.productId)return void window.__macd2();(0,r.YW)(Q,{play:'),
    # while M(a)C Dungeons II works or the game runs, the button shows it (mclauncher-link.js)
    ("const E=({productId:e,versionId:t,render:a})=>{var E,h,b,x,C,w,y,M,f,v;",
     "const E=({productId:e,versionId:t,render:a})=>{var E,h,b,x,C,w,y,M,f,v;const MD=window.__macd2Use(c,e);"),
    ('a(_,J,L,O,F))};a.d(t,["A",0,E])', 'a(_,MD||J,L,O,F))};a.d(t,["A",0,E])'),
]
# the download bar's text: an additionalStateText of {macd2, text} replaces the
# phase word ("Preparing …") instead of following it
BAR_TEXT = ('return u?r.createElement(r.Fragment,null,_," ",u(s)):_}),[s,u,_,i,n])',
            'const U=u&&u(s);return U&&U.macd2?U.text:u?r.createElement(r.Fragment,null,_," ",U):_}),[s,u,_,i,n])')
# the app's progress in the launcher's download bar (every product's bar is listed here)
BAR = ("return n.createElement(n.Fragment,null,t)}},2735(",
       "return n.createElement(n.Fragment,null,t,window.__macd2Bar(n,s.M))}},2735(")
ROUTED = re.compile(r"\b(play|download|hardRepair):([A-Za-z$_][\w$]*)\.(launchProduct|installProduct|repairProduct),")


def patch_button(src: str) -> str:
    changed = False
    if all(old in src for old, _ in BUTTON):
        for old, new in BUTTON:
            src = src.replace(old, new, 1)
        changed = True
    if BAR_TEXT[0] in src:
        src = src.replace(*BAR_TEXT, 1)
        changed = True
    if BAR[0] in src:
        src = src.replace(*BAR, 1)
        changed = True
    for old, new in NOTICES:
        if old in src:
            src = src.replace(old, new, 1)
            changed = True
    return src if not changed or src.startswith(MARK) else MARK + src


def patch_js(src: str, main: bool) -> str:
    if PLAYABLE_OLD not in src or not ROUTED.search(src):
        return src
    src = src.replace(PLAYABLE_OLD, PLAYABLE_NEW, 1)
    src = ROUTED.sub(lambda m: f'{m[1]}:(p,...a)=>"dungeons2"===p?window.__macd2():{m[2]}.{m[3]}(p,...a),', src)
    # the helper goes in the page's main bundle (index.html loads it; it has no
    # "use strict" prologue to displace); other chunks get only the marker
    return (INIT if main else MARK) + src


def main() -> int:
    if "--agent" in sys.argv:   # the agent alone (no write inside the launcher bundle)
        install_agent()
        return 0
    if "--restore" in sys.argv:
        remove_agent()
        if not BACKUP.exists():
            print("no backup to restore", file=sys.stderr)
            return 1
        shutil.copy2(BACKUP, UI)
        print("restored", UI)
        return 0

    with zipfile.ZipFile(UI) as z:
        patched_now = any(MARK in z.read(n).decode("utf-8", "replace")[:64]
                          for n in z.namelist() if re.search(r"/js/app\.[0-9a-f]+\.bundle\.js$", n))
    if not patched_now:
        shutil.copy2(UI, BACKUP)   # the launcher's own (an update replaces ui.zip)
    elif not BACKUP.exists():
        print("ui.zip is patched but the original backup is missing", file=sys.stderr)
        return 1

    tmp = MC / "macd2-ui.zip.patched"
    patched = []
    with zipfile.ZipFile(BACKUP) as zin, zipfile.ZipFile(tmp, "w") as zout:
        for info in zin.infolist():
            data = zin.read(info)
            if info.filename.endswith(".js") and "launcher-language" not in info.filename:
                text = data.decode("utf-8")
                new = patch_button(patch_js(text, "/js/app." in info.filename))
                if new != text:
                    data = new.encode("utf-8")
                    patched.append(info.filename)
            zout.writestr(info, data, compress_type=info.compress_type)
    if not any("/app." in p for p in patched) or len(patched) < 5:
        tmp.unlink()
        print("the launcher UI changed; patch anchors not found", file=sys.stderr)
        return 1
    install_agent()
    shutil.copyfile(tmp, UI)   # in place: macOS App Management must allow this terminal
    tmp.unlink()
    print("patched:", *patched, sep="\n  ")
    print("backup:", BACKUP)
    return 0


if __name__ == "__main__":
    sys.exit(main())
