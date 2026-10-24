import Foundation

// The key layout model of wasdmod's editor (Keybinder, configurator.html in
// Wanzho/mcd2-wasd 1.5.1, MIT), ported to Swift: a layout file into the
// editor's state and back, the checklist of the game's own keyboard settings
// to change, and reading and writing those settings (a UE GVAS file). Names,
// rules and output follow the page so files stay interchangeable with it.

// MARK: - Text (the editor's Korean from wasdmod's lang/ko.json)

enum WasdText {
    nonisolated(unsafe) static var table: [String: Any] = [:]

    static func load(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let editor = json["editor"] as? [String: Any] else { return }
        table = editor
    }

    static func fill(_ s: String, _ vars: [String: String]) -> String {
        vars.reduce(s) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }

    static func t(_ s: String, _ vars: [String: String] = [:]) -> String {
        let v = (table[s] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? s
        return fill(v, vars)
    }

    /// One and other forms; Korean has one form, under the "other" key.
    static func tn(_ one: String, _ other: String, _ n: Int, _ vars: [String: String] = [:]) -> String {
        var s = n == 1 ? one : other
        if let v = table[other] as? String, !v.isEmpty { s = v }
        else if let v = table[other] as? [String: String] { s = v["=\(n)"] ?? v["other"] ?? s }
        return fill(s, vars.merging(["n": String(n)]) { a, _ in a })
    }
}

private func T(_ s: String, _ vars: [String: String] = [:]) -> String { WasdText.t(s, vars) }

// MARK: - The game's actions

struct WasdAction {
    let id: String
    var sec: String? = nil      // "act" or "menu"
    var cat: String = ""        // move, action, menu
    var label: String = ""
    var sub: String? = nil
    var move: String? = nil     // [Move] key
    var pad: String? = nil      // controller button
    var kb: String? = nil       // pass, menu, back
    var game: String? = nil     // its name in the game's keyboard settings
    var alsoOk: String? = nil
    var hidden = false
    var opens = false
    var fixedGame: String? = nil
    var note: String? = nil

    var both: Bool { pad != nil && kb != nil }
}

enum Wasd {
    static let actions: [WasdAction] = [
        .init(id: "up", sec: "act", cat: "move", label: "Move up", move: "Up"),
        .init(id: "left", sec: "act", cat: "move", label: "Move left", move: "Left"),
        .init(id: "down", sec: "act", cat: "move", label: "Move down", move: "Down"),
        .init(id: "right", sec: "act", cat: "move", label: "Move right", move: "Right"),
        .init(id: "dodge", sec: "act", cat: "move", label: "Directional dodge", sub: "Tap: dodge the way you're moving · hold, move the mouse, let go: dodge that way", move: "DodgeMouse", game: "Directional Dodge"),
        .init(id: "fdodge", sec: "act", cat: "move", label: "Forward dodge", sub: "Quick dodge the way you face", pad: "LB", game: "Forward Dodge"),
        .init(id: "jump", sec: "act", cat: "action", label: "Jump / interact", sub: "On a controller, A is jump and interact; in the game's keyboard settings, interact is on the attack key", pad: "A", game: "Jump"),
        .init(id: "melee", sec: "act", cat: "action", label: "Melee", sub: "In the air: heavy jump attack", pad: "X", game: "Interact, Melee Attack", alsoOk: "jump"),
        .init(id: "ranged", sec: "act", cat: "action", label: "Ranged (bow)", sub: "On a mouse button: hold it to aim at the cursor", pad: "RT", game: "Ranged Attack"),
        .init(id: "art1", sec: "act", cat: "action", label: "Artifact 1", pad: "Y", game: "Artifact 1"),
        .init(id: "art2", sec: "act", cat: "action", label: "Artifact 2", pad: "B", game: "Artifact 2"),
        .init(id: "art3", sec: "act", cat: "action", label: "Artifact 3", pad: "RB", game: "Artifact 3"),
        .init(id: "potion", sec: "act", cat: "action", label: "Health potion", pad: "LT", game: "Health Potion"),
        .init(id: "trail", sec: "act", cat: "action", label: "Guidance trail", pad: "LS", game: "Guidance Trail"),
        .init(id: "tpplayer", sec: "act", cat: "action", label: "Teleport to player", pad: "DLeft", kb: "pass", game: "Teleport To Player"),
        .init(id: "statue", sec: "act", cat: "action", label: "Teleport statue", kb: "pass", game: "Teleport Statue"),
        .init(id: "tp1", sec: "act", cat: "action", label: "Teleport to player 1", kb: "pass", game: "Teleport To Player 1"),
        .init(id: "tp2", sec: "act", cat: "action", label: "Teleport to player 2", kb: "pass", game: "Teleport To Player 2"),
        .init(id: "tp3", sec: "act", cat: "action", label: "Teleport to player 3", kb: "pass", game: "Teleport To Player 3"),
        .init(id: "tp4", sec: "act", cat: "action", label: "Teleport to player 4", kb: "pass", game: "Teleport To Player 4"),
        .init(id: "inventory", sec: "menu", cat: "menu", label: "Inventory", sub: "Tap: full inventory · hold: mini inventory", pad: "DUp", kb: "menu", game: "Inventory, Mini Inventory", opens: true),
        .init(id: "map", sec: "menu", cat: "menu", label: "World map", pad: "Back", kb: "menu", game: "World Map", opens: true),
        .init(id: "wheel", sec: "menu", cat: "menu", label: "Menu wheel", pad: "Start", kb: "menu", game: "Menu Wheel", opens: true),
        .init(id: "quest", sec: "menu", cat: "menu", label: "Quest log / track quest", sub: "Tap: track · hold: quest log", pad: "DRight", kb: "menu", game: "Quest Log, Track Quest"),
        .init(id: "social", sec: "menu", cat: "menu", label: "Social menu", pad: "DDown", kb: "menu", game: "Social Menu", opens: true),
        .init(id: "emotes", sec: "menu", cat: "menu", label: "Emotes", sub: "Hold for the wheel", pad: "RS", kb: "menu", game: "Emotes"),
        .init(id: "collect", sec: "menu", cat: "menu", label: "Collectibles", sub: "Capes, pets, books", kb: "menu", game: "Collectibles"),
        .init(id: "events", sec: "menu", cat: "menu", label: "Event log", kb: "menu", game: "Event Log"),
        .init(id: "esc", sec: "menu", cat: "menu", label: "Game menu / back", sub: "In a menu: back to the controller", kb: "back", fixedGame: "Escape"),
        .init(id: "heavy", game: "Heavy Jump Attack", hidden: true, note: "the mod does it with jump, then melee in the air"),
        .init(id: "root", game: "Root", hidden: true, note: "no controller equivalent"),
    ]
    static let act: [String: WasdAction] = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })

    static let padOrder = ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "Back", "Start", "LS", "RS", "DUp", "DDown", "DLeft", "DRight"]
    static let padLabel = ["A": "Jump / interact", "X": "Melee (in the air: heavy jump attack)", "RT": "Ranged (bow)", "Y": "Artifact 1", "B": "Artifact 2", "RB": "Artifact 3",
                           "LT": "Health potion", "LB": "Forward dodge", "LS": "Guidance trail", "RS": "Emotes", "DUp": "Inventory (tap: full, hold: mini)", "DDown": "Social menu",
                           "DLeft": "Teleport to player", "DRight": "Track quest / quest log", "Back": "World map", "Start": "Menu wheel"]
    static let gameDefaults: [String: [String]] = [
        "dodge": ["R", "Mouse4"], "fdodge": ["Mouse5"], "jump": ["Space"], "melee": ["Mouse1"], "ranged": ["Mouse2"], "art1": ["1"], "art2": ["2"], "art3": ["3"],
        "potion": ["E"], "trail": ["Mouse3"], "statue": ["Z"], "tp1": ["F1"], "tp2": ["F2"], "tp3": ["F3"], "tp4": ["F4"], "inventory": ["I", "Tab"], "map": ["M"], "wheel": ["S"], "quest": ["J"],
        "social": ["F"], "tpplayer": ["X"], "emotes": ["G"], "collect": ["U"], "events": ["K"], "heavy": ["Q", "Mouse4"], "root": ["LShift"],
    ]
    static let moveIds = ["up", "left", "down", "right"]

    // MARK: Mod keys, sliders and switches

    struct ModRow { let id, label, sub: String; let keyOnly: Bool }
    static let modRows: [ModRow] = [
        .init(id: "TypeKey", label: "Typing mode", sub: "For chat: every key goes to the game until you press Esc", keyOnly: true),
        .init(id: "Cursor", label: "Cursor key", sub: "Hold it to show the mouse cursor", keyOnly: true),
        .init(id: "Toggle", label: "Mod on / off", sub: "Turns the mod off until you press it again; your keys then reach the game as they are", keyOnly: false),
        .init(id: "Legend", label: "On-screen key list", sub: "Shows or hides the list of your keys over the game", keyOnly: false),
    ]

    struct Tune { let sec, key, label, sub: String; let min, max, step: Double; let unit: String }
    static let tunes: [Tune] = [
        .init(sec: "Movement", key: "AccelMs", label: "Speed-up time", sub: "How long your movement keys take to get to full speed. 0 ms = full speed at once; higher = a softer start", min: 0, max: 200, step: 5, unit: "ms"),
        .init(sec: "Movement", key: "DecelMs", label: "Stopping time", sub: "How long you keep gliding after you let go. 0 ms = stop at once; higher = a softer stop", min: 0, max: 200, step: 5, unit: "ms"),
        .init(sec: "Movement", key: "TurnMs", label: "Turn time", sub: "A full 180° turn (90° takes half). 0 ms = sharpest; higher = smoother, but it can feel less responsive", min: 0, max: 1000, step: 10, unit: "ms"),
        .init(sec: "Move", key: "DodgeDragPx", label: "Dodge drag distance", sub: "While you hold Directional dodge, moving the mouse this far dodges that way instead of the way you're moving. Lower = a small move is enough; higher = it takes a bigger move", min: 10, max: 150, step: 5, unit: "px"),
        .init(sec: "Move", key: "DodgeFlickMs", label: "Dodge stick time", sub: "How long each dodge pushes the controller's right stick. Lower = quicker dodges back to back, but too short and the game can miss one; higher = more reliable", min: 30, max: 200, step: 10, unit: "ms"),
        .init(sec: "Mouse", key: "MouseModeOnMovePx", label: "Mouse move that brings back the cursor", sub: "How far you move the mouse, while not walking, before the cursor comes back. Lower = a small move does it; higher = it takes a bigger move, so bumps don't. 0 = never (bump correction is then off too)", min: 0, max: 150, step: 5, unit: "px"),
        .init(sec: "Mouse", key: "BumpNudgePct", label: "Bump correction", sub: "A small mouse bump can switch the game's button prompts to keyboard; once the mouse stops, the mod pushes the right stick lightly to switch them back. Lower = a lighter push (lower it if it ever makes you dodge); 0 = off", min: 0, max: 60, step: 5, unit: "%"),
        .init(sec: "Keys", key: "MenuTapMs", label: "Tap vs hold", sub: "Menu keys: a press shorter than this is a tap (the menu opens and the cursor stays), a longer one a hold (a quick overlay like the mini inventory, gone when you let go). Higher = longer presses still count as taps", min: 100, max: 600, step: 25, unit: "ms"),
        .init(sec: "Options", key: "LegendSeconds", label: "Key list at start", sub: "How long the on-screen key list shows when the game starts. 0 = only when you press {legend}", min: 0, max: 60, step: 5, unit: "s"),
    ]

    struct Toggle {
        let sec, key, label, on, off: String
        var defaultOn = false        // read: a missing or other value than "0" is on
        var choice: (on: String, off: String)? = nil
        var writeOn = "1", writeOff = "0"
        func read(_ v: String?) -> Bool {
            if key == "CursorMode" { return (v ?? "").trimmingCharacters(in: .whitespaces).lowercased() == "toggle" }
            return defaultOn ? v != "0" : v == "1"
        }
        func write(_ b: Bool) -> String { b ? writeOn : writeOff }
    }
    static let toggles: [Toggle] = [
        .init(sec: "Mouse", key: "MouseMoveSwitches", label: "When stationary, moving mouse releases cursor",
              on: "When not walking ({move}), moving the mouse releases the cursor so you can click. Walking again automatically captures the cursor.",
              off: "Moving the mouse never brings back the cursor; only the cursor key ({cursor}), a menu key or the mod on / off key ({toggle}) do", defaultOn: true),
        .init(sec: "Keys", key: "CursorMode", label: "Cursor key",
              on: "Press {cursor} once to show the cursor, and again to hide it and go back to the controller (an open menu keeps it)",
              off: "The cursor shows only while you hold {cursor}; letting go hides it and goes back to the controller, like Genshin (an open menu keeps it)",
              choice: ("Toggle", "Long press"), writeOn: "Toggle", writeOff: "Hold"),
        .init(sec: "Mouse", key: "CursorFromMiddle", label: "Cursor reappears in the middle",
              on: "When moving the mouse brings the cursor back, it appears in the middle of the game window",
              off: "When moving the mouse brings the cursor back, it appears where the mouse moved it (menus and the cursor key always put it in the middle)"),
        .init(sec: "Mouse", key: "BowAimsWithMouse", label: "Aim bow with",
              on: "Holding a mouse button that's on {bow} switches the game to keyboard and mouse, so the bow aims at the cursor; your movement keys wait until you let go",
              off: "A mouse button on {bow} presses the controller's RT like any other key, so the bow aims the way your character faces",
              choice: ("Mouse", "WASD")),
        .init(sec: "Mouse", key: "KeepCursorInWindow", label: "Keep the mouse inside the game window while playing",
              on: "While you play, the hidden cursor can't leave the game window (the mod puts it back in the middle while you walk), so a click can't land in another app",
              off: "The hidden cursor can drift out of the game window, so a click can land in another app or on the desktop"),
        .init(sec: "Options", key: "Legend", label: "On-screen key list",
              on: "A list of your keys shows over the game when it starts, for a moment after you save a layout, and when you press {legend}",
              off: "The key list never shows over the game, even when you press {legend}"),
        .init(sec: "Options", key: "BlockOtherKeys", label: "Block inactive keys",
              on: "While you play, keys this layout doesn't use never reach the game, so a stray press can't switch it to keyboard mode",
              off: "Keys this layout doesn't use reach the game, and pressing one can switch it to keyboard mode"),
        .init(sec: "Options", key: "TypingBanner", label: "Show the typing banner",
              on: "While you type, a banner at the top of the game says so. You can also close it with its ×.",
              off: "While you type, only the amber frame around the game shows.", defaultOn: true),
        .init(sec: "Options", key: "OffBanner", label: "Show the \"wasdmod off\" banner",
              on: "While the mod is off, a banner at the top of the game says so. You can also close it with its ×.",
              off: "No banner shows while the mod is off.", defaultOn: true),
    ]
    static func toggle(_ key: String) -> Toggle { toggles.first { $0.key == key }! }

    // MARK: Key names

    static let aliases: [String: String] = [
        "esc": "Escape", "escape": "Escape", "return": "Enter", "enter": "Enter", "grave": "Backtick", "tilde": "Backtick", "backtick": "Backtick", "space": "Space", "tab": "Tab",
        "shift": "LShift", "lshift": "LShift", "leftshift": "LShift", "rshift": "RShift", "rightshift": "RShift",
        "ctrl": "LCtrl", "control": "LCtrl", "lctrl": "LCtrl", "leftctrl": "LCtrl", "lcontrol": "LCtrl", "leftcontrol": "LCtrl", "rctrl": "RCtrl", "rightctrl": "RCtrl", "rcontrol": "RCtrl", "rightcontrol": "RCtrl",
        "alt": "LAlt", "lalt": "LAlt", "leftalt": "LAlt", "option": "LAlt", "loption": "LAlt", "leftoption": "LAlt", "ralt": "RAlt", "rightalt": "RAlt", "roption": "RAlt", "rightoption": "RAlt",
        "backspace": "Backspace", "capslock": "CapsLock",
        "up": "Up", "down": "Down", "left": "Left", "right": "Right", "mouse1": "Mouse1", "mouse2": "Mouse2", "mouse3": "Mouse3", "mouse4": "Mouse4", "mouse5": "Mouse5",
    ]
    static let vkNames: [Int: String] = [
        0x20: "Space", 0x0D: "Enter", 0x1B: "Escape", 0x09: "Tab", 0x10: "LShift", 0x11: "LCtrl", 0x12: "LAlt", 0x08: "Backspace", 0x14: "CapsLock",
        0xA0: "LShift", 0xA1: "RShift", 0xA2: "LCtrl", 0xA3: "RCtrl", 0xA4: "LAlt", 0xA5: "RAlt",
        0x26: "Up", 0x28: "Down", 0x25: "Left", 0x27: "Right", 0x01: "Mouse1", 0x02: "Mouse2", 0x04: "Mouse3", 0x05: "Mouse4", 0x06: "Mouse5", 0xC0: "Backtick",
    ]
    static let prettyNames: [String: String] = [
        "Up": "↑", "Down": "↓", "Left": "←", "Right": "→", "Escape": "Esc", "Backtick": "`", "Mouse1": "Left click", "Mouse2": "Right click",
        "Mouse3": "Middle click", "Mouse4": "Side 4 (back)", "Mouse5": "Side 5 (front)", "CapsLock": "Caps Lock", "?": "?",
        "LShift": "Left Shift", "RShift": "Right Shift", "LCtrl": "Left Ctrl", "RCtrl": "Right Ctrl", "LAlt": "Left Alt", "RAlt": "Right Alt",
    ]
    static func pretty(_ k: String) -> String { prettyNames[k].map { T($0) } ?? k }
    static func isMouse(_ k: String?) -> Bool { guard let k else { return false }; return k.count == 6 && k.hasPrefix("Mouse") && ("1"..."5").contains(String(k.last!)) }
    static func isArrow(_ k: String) -> Bool { ["Up", "Down", "Left", "Right"].contains(k) }

    static func normKey(_ raw: String?) -> String? {
        let v = (raw ?? "").trimmingCharacters(in: .whitespaces)
        if v.isEmpty || v.lowercased() == "none" { return nil }
        if v == "?" { return "?" }
        if v.lowercased() == "fn" { return nil }
        if v.count == 1 { return v.first!.isLowercase && v.first!.isASCII ? v.uppercased() : v }
        let lower = v.lowercased()
        if let a = aliases[lower] { return a }
        if lower.hasPrefix("f"), let n = Int(lower.dropFirst()), lower.count <= 3, (1...12).contains(n) { return "F\(n)" }
        var n: Int? = nil
        if lower.hasPrefix("0x"), lower.count > 2, let x = Int(lower.dropFirst(2), radix: 16) { n = x }
        else if (2...3).contains(v.count), v.allSatisfy(\.isNumber), let x = Int(v) { n = x }
        if let n {
            if let name = vkNames[n] { return name }
            if (0x41...0x5A).contains(n) || (0x30...0x39).contains(n) { return String(UnicodeScalar(UInt8(n))) }
            if (0x70...0x7B).contains(n) { return "F\(n - 0x6F)" }
        }
        return v
    }

    static func uniq(_ a: [String]) -> [String] { var seen = Set<String>(); return a.filter { seen.insert($0).inserted } }
    static func splitKeys(_ s: String?) -> [String] {
        uniq((s ?? "").split(separator: ",", omittingEmptySubsequences: false).compactMap { normKey(String($0)) }.filter { $0 != "?" })
    }

    // MARK: INI

    typealias Ini = [String: [(String, String)]]

    static func parseIni(_ text: String) -> Ini {
        var out: Ini = [:]
        var sec: String? = nil
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]"), line.count > 2 {
                let s = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                sec = s
                if out[s] == nil { out[s] = [] }
                continue
            }
            guard let i = line.firstIndex(of: "="), let sec else { continue }
            out[sec, default: []].append((String(line[..<i]).trimmingCharacters(in: .whitespaces), String(line[line.index(after: i)...]).trimmingCharacters(in: .whitespaces)))
        }
        return out
    }
    static func get(_ ini: Ini, _ sec: String, _ key: String) -> String? {
        (ini[sec] ?? []).last { $0.0.lowercased() == key.lowercased() }?.1
    }
}

// MARK: - Editor state

struct WasdCustomEntry: Equatable {
    var name: String
    var keys: [String]
    var game: String?
}

struct WasdState: Equatable {
    var keys: [String: [String]] = [:]
    var mode: [String: String] = [:]            // "kb" or "pad", for actions with both
    var game: [String: [String?]] = [:]         // the game's keys: two columns, "?" unknown
    var mod: [String: [String]] = [:]
    var num: [String: Double] = [:]
    var opt: [String: Bool] = [:]
    var optionsRaw: [[String]] = []             // [key, value] in [Options] order
    var customOn = false
    var customPass: [WasdCustomEntry] = []
    var customMenu: [WasdCustomEntry] = []

    static func knownGame(_ arr: [String?]?) -> [String] { (arr ?? []).compactMap { $0 }.filter { $0 != "?" } }
    func gameSlots(_ a: WasdAction) -> [String] { a.fixedGame.map { [$0] } ?? Self.knownGame(game[a.id]) }
    func firstGame(_ a: WasdAction) -> String? { a.fixedGame ?? Self.knownGame(game[a.id]).first }
    func okGameKeys(_ a: WasdAction) -> [String] {
        a.alsoOk.map { Wasd.uniq((keys[a.id] ?? []) + (keys[$0] ?? [])) } ?? keys[a.id] ?? []
    }
    func padAllowed(_ a: WasdAction) -> Bool { a.id == "inventory" || opt["ControllerMenus"] == true }
    func route(_ a: WasdAction) -> String {
        a.hidden ? "none" : a.move != nil ? "move" : a.both ? (mode[a.id] ?? "kb") : a.pad != nil ? "pad" : "kb"
    }
    func modKeys(_ id: String) -> [String] { mod[id] ?? [] }
    /// Customization entries in effect: (kind, entry).
    var customInEffect: [(String, WasdCustomEntry)] { customOn ? customPass.map { ("pass", $0) } + customMenu.map { ("menu", $0) } : [] }
}

extension Wasd {
    static let defaultIni = """
    [Move]
    Up=W
    Left=A
    Down=S
    Right=D
    DodgeMouse=R, Mouse4
    DodgeDragPx=40
    DodgeFlickMs=80
    [Movement]
    AccelMs=45
    DecelMs=35
    TurnMs=110
    [Buttons]
    A=Space
    B=2
    X=Mouse1
    Y=1
    LB=Mouse5
    RB=3
    LT=E
    RT=Mouse2
    Back=None
    Start=None
    LS=Mouse3
    RS=None
    DUp=None
    DDown=None
    DLeft=None
    DRight=None
    [Mouse]
    KeepCursorInWindow=1
    MouseModeOnMovePx=40
    MouseMoveSwitches=1
    CursorFromMiddle=0
    BumpNudgePct=30
    BowAimsWithMouse=1
    [Keys]
    MenuKeys=I, M, J, F, G, U, K, Escape
    BackKeys=Escape
    MouseAfter=None
    MenuTapMs=300
    TypeKey=T
    PassKeys=Z, F1, F2, F3, F4, X
    Cursor=LAlt
    CursorMode=Hold
    Toggle=Backtick
    Legend=F9
    [Remap]
    Tab=S
    [Modes]
    inventory=Keyboard
    map=Keyboard
    wheel=Keyboard
    quest=Keyboard
    social=Keyboard
    tpplayer=Keyboard
    emotes=Keyboard
    [Options]
    BlockOtherKeys=1
    DetectTextBoxes=1
    TypedCharacters=0
    Legend=1
    LegendSeconds=15
    TypingBanner=1
    OffBanner=1
    Language=Auto
    RequireFocus=1
    AlwaysConnected=1
    Log=1
    """

    // MARK: Layout file -> state (stateFromIni)

    static func state(from text: String) -> WasdState {
        let ini = parseIni(text), def = parseIni(defaultIni)
        func val(_ sec: String, _ key: String) -> String? { get(ini, sec, key) ?? get(def, sec, key) }
        var st = WasdState()
        func parseGame(_ v: String?) -> [String?]? {
            guard let v else { return nil }
            return v.split(separator: ",", omittingEmptySubsequences: false).prefix(2).map { raw -> String? in
                let x = raw.trimmingCharacters(in: .whitespaces)
                if x.isEmpty || x == "-" || x.lowercased() == "none" { return nil }
                return x == "?" ? "?" : normKey(x)
            }
        }
        for a in actions where a.game != nil {
            st.game[a.id] = parseGame(get(ini, "GameKeys", a.id)) ?? (gameDefaults[a.id] ?? ["?"]).map { $0 }
        }
        let buttons = Dictionary(uniqueKeysWithValues: padOrder.map { ($0, splitKeys(val("Buttons", $0))) })
        let menuKeys = splitKeys(val("Keys", "MenuKeys")), passKeys = splitKeys(val("Keys", "PassKeys")), backKeys = splitKeys(val("Keys", "BackKeys"))
        var usedDirect = Set<String>()
        var remaps: [(String, String)] = (ini["Remap"] ?? def["Remap"] ?? []).compactMap { f, t in
            guard let f = normKey(f), let t = normKey(t) else { return nil }
            return (f, t)
        }
        func takeRemaps(_ test: ((String, String)) -> Bool) -> [String] {
            let hit = remaps.filter(test)
            remaps = remaps.filter { !test($0) }
            return hit.map(\.0)
        }
        if get(ini, "GameKeys", "ranged") == nil,
           let r = remaps.first(where: { (buttons["RT"] ?? []).contains($0.0) && isMouse($0.0) && isMouse($0.1) }) {
            st.game["ranged"] = [r.1]
        }
        for a in actions {
            if a.hidden { st.keys[a.id] = []; continue }
            if let m = a.move {
                let k = splitKeys(val("Move", m))
                st.keys[a.id] = a.cat == "move" && a.id != "dodge" ? Array(k.prefix(1)) : k
                continue
            }
            let padKeys = a.pad.flatMap { buttons[$0] } ?? []
            if a.kb == nil {
                st.keys[a.id] = a.id == "fdodge" ? uniq(padKeys + splitKeys(val("Move", "Dodge"))) : padKeys
                continue
            }
            let slots = st.gameSlots(a)
            var kbKeys: [String] = []
            if !slots.isEmpty {
                let direct = (menuKeys + passKeys + backKeys).filter { slots.contains($0) }
                direct.forEach { usedDirect.insert($0) }
                kbKeys = uniq(direct + takeRemaps { slots.contains($0.1) })
            }
            let saved = get(ini, "Modes", a.id)
            let mode = !a.both ? (a.pad != nil ? "pad" : "kb") : saved.map { $0.lowercased().hasPrefix("c") ? "pad" : "kb" } ?? (padKeys.isEmpty ? "kb" : "pad")
            if a.both { st.mode[a.id] = mode }
            st.keys[a.id] = uniq(mode == "pad" ? padKeys + kbKeys : kbKeys + padKeys)
        }
        let bow = act["ranged"]!
        _ = takeRemaps { (st.keys["ranged"] ?? []).contains($0.0) && isMouse($0.0) && $0.1 == st.firstGame(bow) }
        readCustom(&st, ini, pass: passKeys.filter { !usedDirect.contains($0) }, menu: menuKeys.filter { !usedDirect.contains($0) },
                   remaps: remaps, instant: splitKeys(val("Keys", "InstantKeys")))
        for id in ["TypeKey", "Cursor", "Toggle", "Legend"] { st.mod[id] = splitKeys(val("Keys", id)) }
        for tu in tunes { st.num[tu.key] = Double(val(tu.sec, tu.key) ?? "") ?? .nan }
        for o in toggles { st.opt[o.key] = o.read(val(o.sec, o.key)) }
        st.optionsRaw = (def["Options"] ?? []).map { [$0.0, val("Options", $0.0) ?? "undefined"] }
        if let cm = get(ini, "Modes", "ControllerMenus") { st.opt["ControllerMenus"] = cm == "1" }
        else { st.opt["ControllerMenus"] = actions.contains { $0.both && $0.id != "inventory" && st.mode[$0.id] == "pad" } }
        return st
    }

    private static func readCustom(_ st: inout WasdState, _ ini: Ini, pass: [String], menu: [String], remaps: [(String, String)], instant: [String]) {
        for (k, v) in ini["Custom"] ?? [] {
            if k.lowercased() == "on" { st.customOn = v.trimmingCharacters(in: .whitespaces) == "1"; continue }
            let kind = k.lowercased()
            guard kind == "pass" || kind == "menu" else { continue }
            let parts = v.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let g = normKey(parts.count > 2 ? parts[2] : "")
            let e = WasdCustomEntry(name: parts.first ?? "", keys: Array(splitKeys(parts.count > 1 ? parts[1] : "").prefix(3)), game: g == "?" ? nil : g)
            if kind == "pass" { st.customPass.append(e) } else { st.customMenu.append(e) }
        }
        var sent = Set<String>()
        if st.customOn {
            for e in st.customPass { for k in e.keys { sent.insert("pass \(k) \(e.game ?? k)") } }
            for e in st.customMenu { for k in e.keys { sent.insert("menu \(k) \(e.game ?? k)") } }
        }
        let atoms = pass.map { ("pass", $0, $0) } + menu.map { ("menu", $0, $0) } + remaps.map { (instant.contains($0.1) ? "pass" : "menu", $0.0, $0.1) }
        for (kind, k, g) in atoms where !sent.contains("\(kind) \(k) \(g)") {
            let e = WasdCustomEntry(name: "", keys: [k], game: g == k ? nil : g)
            if kind == "pass" { st.customPass.append(e) } else { st.customMenu.append(e) }
            st.customOn = true
        }
    }

    // MARK: State -> layout file (iniText)

    static func number(_ d: Double?) -> String {
        guard let d, d.isFinite else { return "NaN" }
        return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
    }

    static func iniText(_ st: WasdState) -> String {
        func j(_ a: [String]) -> String { a.isEmpty ? "None" : a.joined(separator: ", ") }
        var L: [String] = []
        L += ["; Keyboard & mouse as a controller for Minecraft Dungeons II.",
              "; Made with Dungeons II Keybinder. Put this file in the game's Win64 folder: a running",
              "; game switches to it within a second. The mod uses the newest of default.txt, author.txt",
              "; and wasdmod*.txt.", ""]
        func moveKeys(_ m: String) -> [String] { st.keys[actions.first { $0.move == m }!.id] ?? [] }
        L += ["[Move]"] + ["Up", "Left", "Down", "Right"].map { "\($0)=" + j(moveKeys($0)) } + ["DodgeMouse=" + j(moveKeys("DodgeMouse")),
              "DodgeDragPx=" + number(st.num["DodgeDragPx"]), "DodgeFlickMs=" + number(st.num["DodgeFlickMs"]), ""]
        L += ["[Movement]", "AccelMs=" + number(st.num["AccelMs"]), "DecelMs=" + number(st.num["DecelMs"]), "TurnMs=" + number(st.num["TurnMs"]), ""]
        func padKeys(_ b: String) -> [String] {
            guard let a = actions.first(where: { $0.pad == b }), st.route(a) == "pad" else { return [] }
            return st.keys[a.id] ?? []
        }
        L += ["[Buttons]"] + padOrder.map { "\($0)=" + j(padKeys($0)) } + [""]
        L += ["[Labels]"] + padOrder.map { "\($0)=" + padLabel[$0]! } + [""]
        var menuKeys: [String] = [], passKeys: [String] = [], remaps: [(String, String)] = [], instant: [String] = []
        let inputKeys = Set(actions.flatMap { st.keys[$0.id] ?? [] } + modRows.flatMap { st.modKeys($0.id) } + st.customInEffect.flatMap { $0.1.keys })
        for a in actions where st.route(a) == "kb" {
            guard let g = st.firstGame(a) else { continue }
            for k in st.keys[a.id] ?? [] {
                if k == g { if a.kb == "pass" { passKeys.append(k) } else { menuKeys.append(k) } }
                else { remaps.append((k, g)) }
            }
            if a.kb == "pass" && (st.keys[a.id] ?? []).contains(where: { $0 != g }) { instant.append(g) }
        }
        for (kind, e) in st.customInEffect {
            let g = e.game ?? e.keys.first ?? ""
            for k in e.keys {
                if k == g { if kind == "pass" { passKeys.append(k) } else { menuKeys.append(k) } }
                else { remaps.append((k, g)); if kind == "pass" { instant.append(g) } }
            }
        }
        let bowGame = st.firstGame(act["ranged"]!)
        if st.opt["BowAimsWithMouse"] == true, isMouse(bowGame), bowGame != "Mouse3", let bowGame {
            for k in st.keys["ranged"] ?? [] where (k == "Mouse4" || k == "Mouse5") && k != bowGame { remaps.append((k, bowGame)) }
        }
        let mouseAfter = actions.filter { $0.opens && st.route($0) == "pad" && !(st.keys[$0.id] ?? []).isEmpty }.compactMap(\.pad)
        let disabled = uniq(actions.flatMap { st.gameSlots($0) }.filter { $0 != "Mouse1" && !inputKeys.contains($0) })
        func tg(_ key: String) -> String { toggle(key).write(st.opt[key] == true) }
        L += ["[Mouse]", "KeepCursorInWindow=" + tg("KeepCursorInWindow"),
              "MouseModeOnMovePx=" + number(st.num["MouseModeOnMovePx"]), "MouseMoveSwitches=" + tg("MouseMoveSwitches"),
              "CursorFromMiddle=" + tg("CursorFromMiddle"),
              "BumpNudgePct=" + number(st.num["BumpNudgePct"]), "BowAimsWithMouse=" + tg("BowAimsWithMouse"), ""]
        L += ["[Keys]", "MenuKeys=" + j(uniq(menuKeys)), "BackKeys=Escape", "MouseAfter=" + j(mouseAfter),
              "MenuTapMs=" + number(st.num["MenuTapMs"]), "TypeKey=" + j(st.modKeys("TypeKey")), "PassKeys=" + uniq(passKeys).joined(separator: ", "),
              "DisabledKeys=" + disabled.joined(separator: ", "), "InstantKeys=" + uniq(instant).joined(separator: ", "),
              "Cursor=" + j(st.modKeys("Cursor")), "CursorMode=" + tg("CursorMode"), "Toggle=" + j(st.modKeys("Toggle")), "Legend=" + j(st.modKeys("Legend")), ""]
        let remapLines = remaps.map { "\($0.0)=\($0.1)" }
        L += ["[Remap]"] + (remapLines.isEmpty ? ["None=None"] : remapLines) + [""]
        L += ["; Keyboard or controller for each menu (for the key layout editor), and the game's",
              "; own keyboard keys (Settings > Controls > Keyboard); the key list names converted keys from them.",
              "[Modes]", "ControllerMenus=" + (st.opt["ControllerMenus"] == true ? "1" : "0")]
            + actions.filter(\.both).map { "\($0.id)=" + (st.mode[$0.id] == "pad" ? "Controller" : "Keyboard") } + [""]
        func slotText(_ arr: [String?]?) -> String {
            var a = Array((arr ?? []).prefix(2))
            while let last = a.last, last == nil { a.removeLast() }
            return a.isEmpty ? "None" : a.map { $0 ?? "-" }.joined(separator: ", ")
        }
        L += ["[GameKeys]"] + actions.filter { $0.game != nil }.map { "\($0.id)=" + slotText(st.game[$0.id]) } + [""]
        if st.customOn {
            func clean(_ s: String) -> String {
                s.replacingOccurrences(of: "|", with: " ").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            }
            L += ["; Customization (for the key layout editor): name | your keys | the game's key.", "[Custom]", "On=1"]
                + st.customPass.map { "Pass=" + clean($0.name) + " | " + $0.keys.joined(separator: ", ") + " | " + ($0.game ?? "") }
                + st.customMenu.map { "Menu=" + clean($0.name) + " | " + $0.keys.joined(separator: ", ") + " | " + ($0.game ?? "") } + [""]
        }
        L += ["[Options]"] + st.optionsRaw.map { kv in
            let k = kv[0]
            if let o = toggles.first(where: { $0.sec == "Options" && $0.key == k }) { return "\(k)=" + o.write(st.opt[k] == true) }
            if k == "LegendSeconds" { return "\(k)=" + number(st.num["LegendSeconds"]) }
            return "\(k)=\(kv[1])"
        }
        return L.joined(separator: "\n") + "\n"
    }

    // MARK: The game's keyboard settings to change (recommendations)

    struct Rec: Equatable {
        let action: String
        let slot: Int
        let want: String?
        let was: String?
    }

    static func recommendations(_ st: WasdState) -> [Rec] {
        var out: [Rec] = []
        func known(_ k: String?) -> Bool { k != nil && k != "?" }
        for a in actions where a.game != nil {
            let keys = st.keys[a.id] ?? [], g = st.game[a.id] ?? [], ok = st.okGameKeys(a)
            let g0 = g.count > 0 ? g[0] : nil, g1 = g.count > 1 ? g[1] : nil
            if keys.isEmpty {
                for (i, k) in g.enumerated() where known(k) && !ok.contains(k!) { out.append(Rec(action: a.id, slot: i, want: nil, was: k)) }
                continue
            }
            let firstOk = g0.map { keys.contains($0) } == true || (g0.map { ok.contains($0) } == true && g1.map { keys.contains($0) } == true)
            if !firstOk { out.append(Rec(action: a.id, slot: 0, want: keys.first { !isArrow($0) } ?? keys[0], was: g0)) }
            if known(g1) && !ok.contains(g1!) { out.append(Rec(action: a.id, slot: 1, want: nil, was: g1)) }
        }
        return out
    }

    /// The rows the game's settings file has names for, with both columns as
    /// wanted, in the checklist's order.
    static func gameKeyChanges(_ st: WasdState) -> (want: [WasdWant], n: Int) {
        var want: [WasdWant] = [], n = 0
        for r in recommendations(st) where gameActions[r.action] != nil {
            if !want.contains(where: { $0.id == r.action }) {
                var g = Array((st.game[r.action] ?? []).prefix(2))
                while g.count < 2 { g.append(nil) }
                want.append(WasdWant(id: r.action, keys: g))
            }
            want[want.firstIndex { $0.id == r.action }!].keys[r.slot] = r.want
            n += 1
        }
        return (want, n)
    }

    /// Every key -> the rows that use it (labels).
    static func usage(_ st: WasdState) -> [String: [String]] {
        var map: [String: [String]] = [:]
        for a in actions { for k in st.keys[a.id] ?? [] { map[k, default: []].append(T(a.label)) } }
        for r in modRows { for k in st.modKeys(r.id) { map[k, default: []].append(T(r.label)) } }
        for (kind, e) in st.customInEffect {
            for k in e.keys { map[k, default: []].append(e.name.isEmpty ? T(kind == "pass" ? "Always send to the game" : "Other menu shortcuts") : e.name) }
        }
        return map
    }

    /// "Use in-game controls instead": each row takes the game's keys, except
    /// movement keys (reported back as clashes).
    static func useGameKeys(_ st: inout WasdState) -> (changed: Int, clashes: [(String, String)]) {
        let move = Set(moveIds.flatMap { st.keys[$0] ?? [] })
        var clashes: [(String, String)] = [], n = 0
        for a in actions where a.game != nil && !a.hidden && !moveIds.contains(a.id) {
            let interact = a.alsoOk.flatMap { st.keys[$0] } ?? []
            let sharers = actions.filter { $0.alsoOk == a.id }
            let keep = (st.keys[a.id] ?? []).filter { k in sharers.contains { st.gameSlots($0).contains(k) } }
            let g = WasdState.knownGame(st.game[a.id])
            let ok = uniq(g.filter { !move.contains($0) && !interact.contains($0) } + keep)
            for k in g where move.contains(k) { clashes.append((a.id, k)) }
            if ok.isEmpty || ok == st.keys[a.id] { continue }
            st.keys[a.id] = ok
            n += 1
        }
        return (n, clashes)
    }
}

// MARK: - The game's own keyboard settings (GVAS)

/// One row of the game's keyboard settings to set: both columns.
struct WasdWant: Codable, Equatable {
    var id: String
    var keys: [String?]
}

enum WasdControls {
    static let profile = "/Script/SWCoreGameplay.SWEnhancedPlayerMappableKeyProfile"
    static let keyboard = "SW.Input.Profile.InputType.Keyboard"

    struct Record { var name, key, dev1, dev2: String; var tail: [UInt8]; var slot: Int }
    struct Parsed { let bytes: [UInt8]; let at: Int; let end: Int; let records: [Record] }

    static let ueKeys: [String: String] = {
        var m = ["Space": "SpaceBar", "LShift": "LeftShift", "RShift": "RightShift", "LCtrl": "LeftControl", "RCtrl": "RightControl", "LAlt": "LeftAlt", "RAlt": "RightAlt",
                 "Tab": "Tab", "Escape": "Escape", "Enter": "Enter", "Backspace": "BackSpace", "CapsLock": "CapsLock", "Backtick": "Tilde", "Up": "Up", "Down": "Down",
                 "Left": "Left", "Right": "Right", "-": "Hyphen", "=": "Equals", "[": "LeftBracket", "]": "RightBracket", ";": "Semicolon", "'": "Apostrophe",
                 ",": "Comma", ".": "Period", "/": "Slash", "\\": "Backslash", "Mouse1": "LeftMouseButton", "Mouse2": "RightMouseButton",
                 "Mouse3": "MiddleMouseButton", "Mouse4": "ThumbMouseButton", "Mouse5": "ThumbMouseButton2"]
        for (i, n) in ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"].enumerated() { m[String(i)] = n }
        return m
    }()
    static let fromUeKeys: [String: String] = {
        var m = Dictionary(uniqueKeysWithValues: ueKeys.map { ($0.value, $0.key) })
        for (i, n) in ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"].enumerated() { m["NumPad" + n] = String(i) }
        return m
    }()
    private static func letterOrF(_ k: String) -> Bool {
        if k.count == 1, let c = k.unicodeScalars.first, ("A"..."Z").contains(c) { return true }
        if k.hasPrefix("F"), let n = Int(k.dropFirst()), (1...12).contains(n), String(n) == String(k.dropFirst()) { return true }
        return false
    }
    /// nil: a key the game can't take. A nil key is "None".
    static func ueKey(_ k: String?) -> String? {
        guard let k else { return "None" }
        return ueKeys[k] ?? (letterOrF(k) ? k : nil)
    }
    /// .some(nil) = no key; nil = a key the editor has no name for.
    static func fromUe(_ u: String) -> String?? {
        if u == "None" { return .some(nil) }
        if let k = fromUeKeys[u] { return .some(k) }
        return letterOrF(u) ? .some(u) : nil
    }

    static let gameActions: [String: [String]] = [
        "melee": ["PrimaryAction"], "ranged": ["RangedAttack"], "heavy": ["HeavyJumpAttack"], "art1": ["Artifact1"], "potion": ["HealthPotion"],
        "root": ["Root"], "dodge": ["DirectionalDodge"], "fdodge": ["ForwardDodge"], "inventory": ["Inventory", "MiniInventory"], "quest": ["QuestLog", "TrackQuest"],
        "wheel": ["MenuWheel"], "collect": ["IA_OpenUI_Collectibles"], "social": ["SocialMenu"],
    ]

    static func parse(_ data: Data) -> Parsed? {
        let b = [UInt8](data)
        guard b.count > 8, Array(b.prefix(4)) == Array("GVAS".utf8) else { return nil }
        var p = 0
        func i32() -> Int? {
            guard p + 4 <= b.count else { return nil }
            let x = Int32(bitPattern: UInt32(b[p]) | UInt32(b[p + 1]) << 8 | UInt32(b[p + 2]) << 16 | UInt32(b[p + 3]) << 24)
            p += 4
            return Int(x)
        }
        func str() -> String? {
            guard let n = i32(), n > 0, n <= 512, p + n <= b.count, b[p + n - 1] == 0 else { return nil }
            let chars = b[p..<p + n - 1]
            guard chars.allSatisfy({ (32...126).contains($0) }) else { return nil }
            p += n
            return String(decoding: chars, as: UTF8.self)
        }
        let enc = Array(profile.utf8)
        guard let hit = (0..<max(0, b.count - enc.count)).first(where: { i in b[i] == enc[0] && Array(b[i..<i + enc.count]) == enc }) else { return nil }
        let first = hit - 4
        guard first >= 8 else { return nil }
        p = first - 4
        guard let count = i32(), (1...64).contains(count) else { return nil }
        var keyboardProfile: Parsed? = nil
        for _ in 0..<count {
            guard str() == profile, str() != nil else { return nil }
            let at = p
            guard let n = i32(), (0...2000).contains(n) else { return nil }
            var records: [Record] = []
            for _ in 0..<n {
                guard let name = str(), let key = str(), let d1 = str(), let d2 = str(), p + 6 <= b.count else { return nil }
                let tail = Array(b[p..<p + 6])
                p += 6
                guard tail[5] <= 1 else { return nil }
                records.append(Record(name: name, key: key, dev1: d1, dev2: d2, tail: tail, slot: Int(tail[5])))
            }
            let end = p
            guard let id = str() else { return nil }
            if id == keyboard { keyboardProfile = Parsed(bytes: b, at: at, end: end, records: records) }
        }
        return keyboardProfile
    }

    /// The game's keys per row, from the file (a row without changes has its defaults).
    static func keys(_ ctl: Parsed) -> [String: [String?]] {
        var out: [String: [String?]] = [:]
        for (id, names) in gameActions {
            var g: [String?] = (Wasd.gameDefaults[id] ?? []).map { $0 }
            while g.count < 2 { g.append(nil) }
            for r in ctl.records where r.name == names[0] { g[r.slot] = fromUe(r.key) ?? nil }
            out[id] = Array(g.prefix(2))
        }
        return out
    }

    /// The file with these rows set; other changes in it stay as they are.
    static func write(_ ctl: Parsed, _ want: [WasdWant]) -> Data {
        var recs = ctl.records
        let tail5 = recs.first.map { Array($0.tail.prefix(5)) } ?? [0, 0, 0, 0, 0]
        for w in want {
            let id = w.id, keys = w.keys
            for name in gameActions[id] ?? [] {
                for slot in 0...1 {
                    let k = slot < keys.count ? keys[slot] : nil
                    guard let ue = ueKey(k) else { continue }
                    let haveIndex = recs.firstIndex { $0.name == name && $0.slot == slot }
                    let now: String? = haveIndex.map { (fromUe(recs[$0].key) ?? nil) } ?? {
                        let d = Wasd.gameDefaults[id] ?? []
                        return slot < d.count ? d[slot] : nil
                    }()
                    if now == k { continue }
                    if let i = haveIndex { recs[i].key = ue }
                    else { recs.append(Record(name: name, key: ue, dev1: "None", dev2: "None", tail: tail5 + [UInt8(slot)], slot: slot)) }
                }
            }
        }
        var mid: [UInt8] = []
        func i32(_ v: Int) { mid += (0..<4).map { UInt8(truncatingIfNeeded: UInt32(bitPattern: Int32(v)) >> (8 * $0)) } }
        func put(_ s: String) { let u = Array(s.utf8); i32(u.count + 1); mid += u + [0] }
        i32(recs.count)
        for r in recs { put(r.name); put(r.key); put(r.dev1); put(r.dev2); mid += r.tail }
        return Data(ctl.bytes[0..<ctl.at] + mid + ctl.bytes[ctl.end...])
    }
}

extension Wasd {
    static var gameActions: [String: [String]] { WasdControls.gameActions }
}
