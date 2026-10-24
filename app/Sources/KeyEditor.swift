import AppKit
import SwiftUI

// The key layout editor: wasdmod's Keybinder rebuilt in SwiftUI on the ported
// model (WasdModel.swift). Layouts are the files in <data>/wasdmod; the game's
// own keyboard settings are read from and written to its save store
// (WasdGameSettings.swift), after the game has closed when it is running.

private func T(_ s: String, _ vars: [String: String] = [:]) -> String { WasdText.t(s, vars) }
private func TN(_ one: String, _ other: String, _ n: Int, _ vars: [String: String] = [:]) -> String { WasdText.tn(one, other, n, vars) }
/// The page marks bold parts with <b>; plain text here.
private func plain(_ s: String) -> String { s.replacingOccurrences(of: "<b>", with: "").replacingOccurrences(of: "</b>", with: "") }

// MARK: - Window

@MainActor
final class KeyEditor: NSObject, NSWindowDelegate {
    private unowned let launcher: Launcher
    private var window: NSWindow?
    private var model: WasdEditorModel?

    init(launcher: Launcher) {
        self.launcher = launcher
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        WasdText.load(from: launcher.wasdBundle.appendingPathComponent("ko.json"))
        let model = WasdEditorModel(launcher: launcher)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "키 배치 편집기 (wasdmod)"
        window.contentView = NSHostingView(rootView: WasdEditorView(model: model))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.model = model
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model?.confirmLeave() ?? true
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
        model = nil
        window = nil
    }
}

// MARK: - Model

struct CaptureTarget: Identifiable {
    enum Kind { case keys(row: String), modKeys(row: String), move(row: String), game(action: String, slot: Int) }
    let id = UUID()
    let kind: Kind
    let rowName: String
    var kbRoute = false
    var keyOnly = false
}

@MainActor
final class WasdEditorModel: ObservableObject {
    unowned let launcher: Launcher
    @Published private(set) var file: String
    @Published var state = WasdState()
    @Published private(set) var base = ""
    @Published private(set) var real: [String: [String?]]? = nil
    @Published var status = ""
    @Published var capture: CaptureTarget? = nil
    @Published var captureMessage = ""
    @Published var showRecs = false
    private var watch: Timer?
    private var storeStamp = ""

    init(launcher: Launcher) {
        self.launcher = launcher
        launcher.refreshWasdLayouts()
        file = launcher.wasdLayout
        load(file)
        watch = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkGame() }
        }
    }

    func stop() { watch?.invalidate() }

    var dirty: Bool { Wasd.iniText(state) != base }
    var isPreset: Bool { ["default.txt", "author.txt"].contains(file) }
    var recs: [Wasd.Rec] { Wasd.recommendations(state) }
    var canSet: Int { real == nil ? 0 : Wasd.gameKeyChanges(state).n }

    // MARK: Layouts

    func load(_ name: String) {
        let text = (try? String(contentsOf: launcher.wasdData.appendingPathComponent(name), encoding: .utf8)) ?? Wasd.defaultIni
        var st = Wasd.state(from: text)
        real = launcher.gameKeys()
        storeStamp = currentStamp()
        overlayReal(&st)
        file = name
        state = st
        base = Wasd.iniText(st)
    }

    /// The game's real keys on the rows its settings file has names for.
    private func overlayReal(_ st: inout WasdState) {
        guard let real else { return }
        for (id, g) in real { st.game[id] = g }
    }

    private func currentStamp() -> String {
        guard let url = launcher.gameControlsStore(),
              let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "" }
        return "\((a[.size] as? Int) ?? 0):\(((a[.modificationDate] as? Date) ?? .distantPast).timeIntervalSince1970)"
    }

    /// The game changed its keys (or saved them for the first time) while the editor is open.
    private func checkGame() {
        let stamp = currentStamp()
        guard stamp != storeStamp, capture == nil else { return }
        storeStamp = stamp
        let next = launcher.gameKeys()
        guard next != real else { return }
        let wasDirty = dirty
        real = next
        overlayReal(&state)
        if !wasDirty { base = Wasd.iniText(state) }
        status = T("The game's keyboard settings changed, so the in-game controls here now match.", ["ingame": T("in-game controls")])
    }

    func select(_ name: String) {
        guard name != file, confirmLeave() else { return }
        load(name)
        launcher.wasdLayout = name
        status = ""
    }

    /// Unsaved changes: save, discard or stay.
    func confirmLeave() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "저장하지 않은 변경 사항이 있어요"
        alert.informativeText = "\(Launcher.wasdLayoutTitle(file))의 변경 사항을 저장할까요?"
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "저장 안 함")
        alert.addButton(withTitle: "취소")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    /// A preset is saved as a new layout of the player's own.
    @discardableResult
    func save() -> Bool {
        if isPreset {
            guard let name = askName(title: "새 키 배치로 저장", initial: "내 배치") else { return false }
            return write(to: newFileName(), name: name)
        }
        return write(to: file, name: nil)
    }

    func saveAsNew() {
        guard let name = askName(title: "새 키 배치", initial: Launcher.wasdLayoutTitle(file) + " 복사본") else { return }
        write(to: newFileName(), name: name)
    }

    @discardableResult
    private func write(to target: String, name: String?) -> Bool {
        do {
            try FileManager.default.createDirectory(at: launcher.wasdData, withIntermediateDirectories: true)
            try Data(Wasd.iniText(state).utf8).write(to: launcher.wasdData.appendingPathComponent(target), options: .atomic)
        } catch {
            status = error.localizedDescription
            return false
        }
        if let name { Launcher.setWasdLayoutName(target, name) }
        launcher.refreshWasdLayouts()
        file = target
        base = Wasd.iniText(state)
        launcher.wasdLayout = target
        status = launcher.wasdEnabled ? "저장했어요. 게임에서 이 배치를 써요." : "저장했어요. 메뉴의 조작 › WASD 조작을 켜면 이 배치를 써요."
        return true
    }

    func discard() {
        load(file)
        status = ""
    }

    func deleteLayout() {
        guard !isPreset else { return }
        let alert = NSAlert()
        alert.messageText = "\(Launcher.wasdLayoutTitle(file)) 배치를 지울까요?"
        alert.addButton(withTitle: "지우기")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.removeItem(at: launcher.wasdData.appendingPathComponent(file))
        Launcher.setWasdLayoutName(file, nil)
        launcher.refreshWasdLayouts()
        base = ""
        load(launcher.wasdLayout)
    }

    /// ASCII file names: the mod finds layouts with the game's ANSI file APIs.
    private func newFileName() -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        var name = "wasdmod-\(stamp).txt"
        var n = 1
        while FileManager.default.fileExists(atPath: launcher.wasdData.appendingPathComponent(name).path) {
            n += 1
            name = "wasdmod-\(stamp)-\(n).txt"
        }
        return name
    }

    private func askName(title: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "키 배치 이름"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "취소")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? initial : name
    }

    // MARK: The game's own keyboard settings

    func applyGame() {
        let change = Wasd.gameKeyChanges(state)
        guard change.n > 0 else { return }
        let alert = NSAlert()
        alert.messageText = T("Change them for me")
        alert.informativeText = "게임 키보드 설정에서 키 \(change.n)개를 이 배치에 맞게 바꿔요. 원래 설정은 백업해 둬요."
        alert.addButton(withTitle: T("Change them for me"))
        alert.addButton(withTitle: T("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let result = launcher.setGameControls(change.want)
        switch result {
        case .written, .waiting:
            let wasDirty = dirty
            real = launcher.gameKeys()
            storeStamp = currentStamp()
            overlayReal(&state)
            if !wasDirty { base = Wasd.iniText(state) }
            if case .written = result {
                status = T("Done: the in-game controls now match this layout. The game uses them the next time it starts.")
            } else {
                status = "게임이 꺼지면 게임 키 설정을 바꿔요. 다시 시작하면 바로 적용돼요."
            }
        case .failed(let message):
            status = T("Couldn't change the in-game controls: {error}", ["error": message])
        }
    }

    func useGameKeys() {
        let r = Wasd.useGameKeys(&state)
        status = r.changed > 0 ? T("Copied the in-game controls into this layout.") : T("This layout already has the in-game controls.")
        if let c = r.clashes.first, let a = Wasd.act[c.0] {
            status += " " + T("{action}: the game uses {key}, which is one of your movement keys, so this layout keeps its own key. Change {action} in the game (Settings › Controls › Keyboard) to another key.",
                              ["action": T(a.game ?? a.label), "key": Wasd.pretty(c.1)])
        }
    }

    /// "Done": the player changed it in the game by hand.
    func markDone(_ r: Wasd.Rec) {
        var g = state.game[r.action] ?? []
        while g.count <= r.slot { g.append(nil) }
        g[r.slot] = r.want
        state.game[r.action] = g
    }

    func markAllDone() { for r in recs { markDone(r) } }

    func recLine(_ r: Wasd.Rec) -> String {
        let a = Wasd.act[r.action]!
        let vars = ["action": T(a.game ?? a.label), "key": r.want.map(Wasd.pretty) ?? ""]
        let s: String
        if r.want == nil { s = r.slot == 1 ? "<b>{action}</b>: second key → <b>clear it</b>" : "<b>{action}</b>: first key → <b>clear it</b>" }
        else { s = r.slot == 1 ? "<b>{action}</b>: second key → <b>{key}</b>" : "<b>{action}</b>: first key → <b>{key}</b>" }
        return plain(T(s, vars))
    }

    // MARK: Keys

    func keys(_ id: String) -> [String] { state.keys[id] ?? [] }

    func setKeys(_ id: String, _ keys: [String]) { state.keys[id] = keys }

    func setMode(_ id: String, _ mode: String) { state.mode[id] = mode }

    func setControllerMenus(_ on: Bool) {
        state.opt["ControllerMenus"] = on
        if !on { for a in Wasd.actions where a.both && !state.padAllowed(a) { state.mode[a.id] = "kb" } }
    }

    func startCapture(_ target: CaptureTarget) {
        captureMessage = ""
        capture = target
    }

    /// A key or mouse button from the capture sheet (the page's take()).
    func take(_ key: String) {
        guard let tgt = capture else { return }
        let current: [String]
        switch tgt.kind {
        case .game(let id, let slot):
            var g = state.game[id] ?? []
            while g.count <= slot { g.append(nil) }
            g[slot] = key
            state.game[id] = g
            capture = nil
            return
        case .move(let id):
            state.keys[id] = [key]
            capture = nil
            return
        case .keys(let id): current = keys(id)
        case .modKeys(let id): current = state.modKeys(id)
        }
        if current.contains(key) { captureMessage = T("{key} is already on this row.", ["key": Wasd.pretty(key)]); return }
        if tgt.kbRoute && Wasd.isMouse(key) { captureMessage = T("A mouse button can't send a keyboard shortcut. Pick a key, or switch this row to the controller."); return }
        if tgt.keyOnly && Wasd.isMouse(key) { captureMessage = T("{row} needs a key on the keyboard: the mod doesn't notice a mouse button for it.", ["row": tgt.rowName]); return }
        if tgt.kbRoute && (key == "=" || key == ";") { captureMessage = T("That key can't be sent to the game. Pick another."); return }
        switch tgt.kind {
        case .keys(let id): state.keys[id] = current + [key]
        case .modKeys(let id): state.mod[id] = current + [key]
        default: break
        }
        capture = nil
    }

    func refuse(_ message: String) { captureMessage = message }

    // MARK: Text helpers

    func joinedKeys(_ keys: [String]) -> String { keys.isEmpty ? T("none") : keys.map(Wasd.pretty).joined(separator: ", ") }

    var textVars: [String: String] {
        ["move": joinedKeys(Wasd.moveIds.flatMap(keys)), "cursor": joinedKeys(state.modKeys("Cursor")),
         "toggle": joinedKeys(state.modKeys("Toggle")), "legend": joinedKeys(state.modKeys("Legend")), "bow": joinedKeys(keys("ranged"))]
    }
}

// MARK: - Views

private enum Palette {
    static let move = Color(red: 0.33, green: 0.62, blue: 0.95)
    static let action = Color(red: 0.36, green: 0.75, blue: 0.45)
    static let menu = Color(red: 0.75, green: 0.52, blue: 0.95)
    static let mod = Color(red: 0.95, green: 0.62, blue: 0.25)
    static let warn = Color(red: 0.93, green: 0.55, blue: 0.13)
    static func cat(_ c: String) -> Color { ["move": move, "action": action, "menu": menu][c] ?? mod }
}

struct WasdEditorView: View {
    @ObservedObject var model: WasdEditorModel
    @ObservedObject private var launcher: Launcher

    init(model: WasdEditorModel) {
        self.model = model
        launcher = model.launcher
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !launcher.wasdEnabled { offNote }
                    if !model.recs.isEmpty { mismatch }
                    conflicts
                    section("act", T("Movement & Actions"), T("These press the virtual controller, so the game stays in controller mode while you fight."))
                    menuSection
                    modSection
                    optionsSection
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 860, minHeight: 600)
        .sheet(item: $model.capture) { target in
            CaptureSheet(model: model, target: target)
        }
    }

    // MARK: Bars

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("키 배치", selection: Binding(get: { model.file }, set: { model.select($0) })) {
                ForEach(launcher.wasdLayouts, id: \.self) { Text(Launcher.wasdLayoutTitle($0)).tag($0) }
            }
            .frame(maxWidth: 320)
            Button("새 배치…") { model.saveAsNew() }
            if !model.isPreset { Button("지우기…") { model.deleteLayout() } }
            Spacer()
            if model.dirty {
                Text("저장하지 않은 변경 사항").font(.callout).foregroundStyle(.secondary)
                Button("되돌리기") { model.discard() }
            }
            Button(model.isPreset ? "새 배치로 저장…" : "저장") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.dirty && !model.isPreset)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Text(model.status.isEmpty ? "공식·추천 배치를 고치면 새 배치로 저장돼요." : model.status)
                .font(.callout)
                .foregroundStyle(model.status.isEmpty ? .secondary : .primary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var offNote: some View {
        HStack {
            Image(systemName: "info.circle")
            Text("WASD 조작이 꺼져 있어요. 메뉴의 조작 › WASD 조작 (wasdmod)을 켜야 게임에서 이 배치를 써요.")
            Spacer()
            Button("켜기") { launcher.wasdEnabled = true }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
    }

    // MARK: The game's keyboard settings

    private var mismatch: some View {
        let recs = model.recs, n = recs.count, canSet = model.canSet
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text("!").font(.system(size: 26, weight: .heavy)).foregroundStyle(Palette.warn)
                VStack(alignment: .leading, spacing: 6) {
                    Text(TN("Change {n} setting in the game, or you're playing with two layouts", "Change {n} settings in the game, or you're playing with two layouts", n))
                        .font(.title3.weight(.bold)).foregroundStyle(Palette.warn)
                    Text(T("The mod turns your keys into controller buttons only while you play. In menus, with the cursor and while aiming the bow with the mouse, the game reads its own keyboard settings: your keys may do nothing there, and the button prompts show the game's keys. Until you change those settings (Settings › Controls › Keyboard), the mod blocks the game's old keys. Once they match your layout, keyboard mode and controller mode use the same keys."))
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    if model.real == nil {
                        Text("게임이 키 설정을 아직 저장하지 않아서 자동으로 바꿀 수 없어요. 게임의 설정 › 조작 › 키보드에서 아무 키나 한 번 바꾸면 여기서 바꿀 수 있어요.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else if canSet < n {
                        Text("\(canSet)개는 \"\(T("Change them for me"))\"로 바꿀 수 있고, 나머지 \(n - canSet)개는 게임에서 직접 바꾼 뒤 \"\(T("Done"))\"을 눌러 주세요.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    if canSet > 0 {
                        Button(T("Change them for me")) { model.applyGame() }
                            .buttonStyle(.borderedProminent).tint(Palette.warn)
                    }
                    Button(model.showRecs ? "목록 숨기기" : T("Show what to change")) { model.showRecs.toggle() }
                }
            }
            if model.showRecs {
                Divider()
                ForEach(Array(recs.enumerated()), id: \.offset) { _, r in
                    HStack {
                        Text(model.recLine(r))
                        Text(r.was.map { T("now: {key}", ["key": Wasd.pretty($0)]) } ?? T("now: empty"))
                            .foregroundStyle(.secondary)
                        if let note = Wasd.act[r.action]?.note { Text("(\(T(note)))").foregroundStyle(.secondary) }
                        Spacer()
                        Button(T("Done")) { model.markDone(r) }.help(T("I changed it in the game"))
                    }
                    .font(.callout)
                }
                HStack {
                    Button(T("Mark all as done")) { model.markAllDone() }
                    Button(T("Use in-game controls instead")) { model.useGameKeys() }
                        .help(T("Copies the keys from the game's keyboard settings into this layout"))
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.warn.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.warn, lineWidth: 1.5))
    }

    @ViewBuilder private var conflicts: some View {
        let bad = Wasd.usage(model.state).filter { $0.value.count > 1 }.sorted { $0.key < $1.key }
        if !bad.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(TN("{n} key does two things", "{n} keys do two things", bad.count)).font(.headline).foregroundStyle(.red)
                Text(TN("Pressing this key does both jobs at once. Give each job its own key: the clashing keys have a red outline below.",
                        "Pressing one of these keys does both jobs at once. Give each job its own key: the clashing keys have a red outline below.", bad.count))
                    .font(.callout)
                ForEach(bad, id: \.key) { k, rows in
                    Text("\(Wasd.pretty(k)): \(rows.joined(separator: ", "))").font(.callout)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.7)))
        }
    }

    // MARK: Sections

    private func section(_ sec: String, _ title: String, _ info: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title, info)
            ForEach(Wasd.actions.filter { $0.sec == sec }, id: \.id) { a in
                ActionRow(model: model, action: a)
                Divider()
            }
            tuneGroup(["AccelMs", "DecelMs", "TurnMs", "DodgeDragPx", "DodgeFlickMs"])
        }
    }

    private var menuSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(T("Menus"), T("These press the keyboard, so the cursor is free to click a menu. Pressing Esc captures the cursor again."))
            Toggle(isOn: Binding(get: { model.state.opt["ControllerMenus"] == true }, set: { model.setControllerMenus($0) })) {
                VStack(alignment: .leading) {
                    Text(T("Allow controller input for menus"))
                    Text(model.state.opt["ControllerMenus"] == true
                         ? T("Menus and Teleport to player can each use the controller: pick Keyboard or Controller on their rows")
                         : T("Menus use the game's keyboard shortcuts; only the inventory can be switched to the controller"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            Divider()
            ForEach(Wasd.actions.filter { $0.sec == "menu" }, id: \.id) { a in
                ActionRow(model: model, action: a)
                Divider()
            }
            tuneGroup(["MenuTapMs"])
        }
    }

    private var modSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(T("Mod keys"), "wasdmod 자체를 조작하는 키예요.")
            ForEach(Wasd.modRows, id: \.id) { r in
                ModRowView(model: model, row: r)
                Divider()
            }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("옵션", "마우스, 커서, 화면 표시 설정이에요.")
            ForEach(Wasd.toggles, id: \.key) { o in ToggleRow(model: model, toggle: o) }
            tuneGroup(["MouseModeOnMovePx", "BumpNudgePct", "LegendSeconds"])
        }
    }

    private func sectionHeader(_ title: String, _ info: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.weight(.bold))
            Text(info).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func tuneGroup(_ keys: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Wasd.tunes.filter { keys.contains($0.key) }, id: \.key) { tu in
                TuneRow(model: model, tune: tu)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: Rows

private struct KeyChips: View {
    let keys: [String]
    let max: Int
    let clashes: Set<String>
    var swap = false
    let add: () -> Void
    let remove: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { k in
                HStack(spacing: 4) {
                    Text(Wasd.pretty(k)).font(.system(.callout, design: .rounded).weight(.semibold))
                    if !swap {
                        Button { remove(k) } label: { Image(systemName: "xmark").font(.caption2) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(clashes.contains(k) ? Color.red : Color.clear, lineWidth: 1.5))
                .contentShape(Rectangle())
                .onTapGesture { if swap { add() } }
                .help(swap ? "클릭해서 바꾸기" : "")
            }
            if keys.count < max {
                Button(T("+ key"), action: add).controlSize(.small)
            }
        }
    }
}

private struct ActionRow: View {
    @ObservedObject var model: WasdEditorModel
    let action: WasdAction

    var body: some View {
        let a = action, st = model.state, label = T(a.label)
        let route = st.route(a), g = st.firstGame(a)
        let clashes = Set(Wasd.usage(st).filter { $0.value.count > 1 }.keys)
        let single = Wasd.moveIds.contains(a.id)
        HStack(alignment: .center, spacing: 12) {
            Rectangle().fill(Palette.cat(a.cat)).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.body.weight(.medium))
                if let sub = a.sub, !(a.id == "ranged" && st.opt["BowAimsWithMouse"] != true) {
                    Text(T(sub)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 230, alignment: .leading)
            routeCell.frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                KeyChips(keys: model.keys(a.id), max: single ? 1 : 3, clashes: clashes, swap: single,
                         add: {
                             model.startCapture(CaptureTarget(kind: single ? .move(row: a.id) : .keys(row: a.id), rowName: label, kbRoute: route == "kb"))
                         },
                         remove: { k in model.setKeys(a.id, model.keys(a.id).filter { $0 != k }) })
                if route == "kb", g == nil, !model.keys(a.id).isEmpty {
                    Text(T("set the game's key →")).font(.caption).foregroundStyle(Palette.warn)
                }
            }
            Spacer(minLength: 8)
            GameCell(model: model, action: a)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private var routeCell: some View {
        let a = action, st = model.state
        if a.move != nil {
            Text(a.id == "dodge" ? T("R-stick") : T("L-stick")).font(.caption).foregroundStyle(.secondary)
        } else if a.both && st.padAllowed(a) {
            Picker("", selection: Binding(get: { st.mode[a.id] ?? "kb" }, set: { model.setMode(a.id, $0) })) {
                Text(T("Keyboard")).tag("kb")
                Text(T("Controller")).tag("pad")
            }
            .pickerStyle(.segmented).labelsHidden()
        } else if st.route(a) == "pad", let pad = a.pad {
            Text(padName(pad)).font(.caption).foregroundStyle(.secondary)
        } else {
            Text(T("Keyboard")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private func padName(_ b: String) -> String {
    let names = ["LS": "L-stick click", "RS": "R-stick click", "DUp": "D-pad ↑", "DDown": "D-pad ↓", "DLeft": "D-pad ←", "DRight": "D-pad →", "Back": "View", "Start": "Menu"]
    return names[b].map { T($0) } ?? b
}

/// The game's own keys for a row: both columns of Settings › Controls › Keyboard.
private struct GameCell: View {
    @ObservedObject var model: WasdEditorModel
    let action: WasdAction

    var body: some View {
        let a = action, st = model.state
        HStack(spacing: 4) {
            if let fixed = a.fixedGame {
                Text("게임").font(.caption).foregroundStyle(.secondary)
                Text(Wasd.pretty(fixed)).font(.callout)
            } else if let game = a.game {
                // Rows the game's settings file has names for come from the game itself.
                let fromGame = model.real != nil && WasdControls.gameActions[a.id] != nil
                let g = st.game[a.id] ?? [], keys = model.keys(a.id), ok = st.okGameKeys(a)
                Text("게임").font(.caption).foregroundStyle(.secondary)
                ForEach(0..<2, id: \.self) { i in
                    let k: String? = i < g.count ? g[i] : nil
                    let color: Color = k == nil || k == "?" ? .secondary : (keys.contains(k!) || ok.contains(k!)) ? Palette.action : Palette.warn
                    let vars = ["action": T(game), "key": k.map(Wasd.pretty) ?? ""]
                    Button {
                        model.startCapture(CaptureTarget(kind: .game(action: a.id, slot: i),
                                                         rowName: i == 1 ? T("{action} (second key)", vars) : T(game)))
                    } label: {
                        Text(k.map(Wasd.pretty) ?? "–")
                            .font(.callout.weight(.medium)).foregroundStyle(color)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5).stroke(color.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .disabled(fromGame)
                    .help(fromGame ? "게임 설정에서 읽은 키예요"
                          : i == 1 ? T("Second key the game has for {action} (Settings › Controls › Keyboard). Click to change.", vars)
                          : T("First key the game has for {action} (Settings › Controls › Keyboard). Click to change.", vars))
                }
            }
        }
        .frame(width: 220, alignment: .trailing)
    }
}

private struct ModRowView: View {
    @ObservedObject var model: WasdEditorModel
    let row: Wasd.ModRow

    var body: some View {
        let clashes = Set(Wasd.usage(model.state).filter { $0.value.count > 1 }.keys)
        let sub = row.id == "Cursor" && model.state.opt["CursorMode"] == true ? "Press it to show the mouse cursor, again to hide it" : row.sub
        HStack(spacing: 12) {
            Rectangle().fill(Palette.mod).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(T(row.label)).font(.body.weight(.medium))
                Text(T(sub)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 380, alignment: .leading)
            KeyChips(keys: model.state.modKeys(row.id), max: 3, clashes: clashes,
                     add: { model.startCapture(CaptureTarget(kind: .modKeys(row: row.id), rowName: T(row.label), keyOnly: row.keyOnly)) },
                     remove: { k in model.state.mod[row.id] = model.state.modKeys(row.id).filter { $0 != k } })
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct ToggleRow: View {
    @ObservedObject var model: WasdEditorModel
    let toggle: Wasd.Toggle

    var body: some View {
        let on = model.state.opt[toggle.key] == true
        let binding = Binding(get: { model.state.opt[toggle.key] == true }, set: { model.state.opt[toggle.key] = $0 })
        VStack(alignment: .leading, spacing: 3) {
            if let choice = toggle.choice {
                HStack {
                    Text(T(toggle.label))
                    Picker("", selection: binding) {
                        Text(T(choice.on)).tag(true)
                        Text(T(choice.off)).tag(false)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                }
            } else {
                Toggle(T(toggle.label), isOn: binding)
            }
            Text(T(on ? toggle.on : toggle.off, model.textVars)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TuneRow: View {
    @ObservedObject var model: WasdEditorModel
    let tune: Wasd.Tune

    var body: some View {
        let value = model.state.num[tune.key] ?? tune.min
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(T(tune.label)).frame(width: 230, alignment: .leading)
                Slider(value: Binding(get: { value.isFinite ? value : tune.min }, set: { model.state.num[tune.key] = ($0 / tune.step).rounded() * tune.step }),
                       in: tune.min...tune.max)
                Text("\(Wasd.number(value)) \(tune.unit)").monospacedDigit().frame(width: 70, alignment: .trailing)
            }
            Text(T(tune.sub, model.textVars)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Key capture

private struct CaptureSheet: View {
    @ObservedObject var model: WasdEditorModel
    let target: CaptureTarget

    var body: some View {
        let forGame: Bool = { if case .game = target.kind { return true }; return false }()
        VStack(spacing: 14) {
            Text(forGame ? T("The game's key for {row}", ["row": target.rowName]) : T("Press a key for {row}", ["row": target.rowName]))
                .font(.title3.weight(.bold))
            KeyCatcherView(onKey: { model.take($0) }, onRefuse: { model.refuse($0) })
                .frame(width: 420, height: 150)
                .overlay(
                    Text(forGame ? T("Press the key the game has for this in Settings › Controls › Keyboard, or click a mouse button in this box.")
                                 : "키를 누르거나, 이 상자 안에서 마우스 버튼을 클릭하세요.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary).padding().allowsHitTesting(false)
                )
                .background(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6])))
            if !model.captureMessage.isEmpty {
                Text(model.captureMessage).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center)
            }
            Button(T("Cancel")) { model.capture = nil }
        }
        .padding(24)
        .frame(width: 480)
    }
}

/// Takes the next key press, or a mouse button clicked inside it, by
/// physical key (so the input source, such as Korean, doesn't matter).
private struct KeyCatcherView: NSViewRepresentable {
    let onKey: (String) -> Void
    let onRefuse: (String) -> Void

    func makeNSView(context: Context) -> Catcher {
        let v = Catcher()
        v.onKey = onKey
        v.onRefuse = onRefuse
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        return v
    }

    func updateNSView(_ v: Catcher, context: Context) {
        v.onKey = onKey
        v.onRefuse = onRefuse
    }

    final class Catcher: NSView {
        var onKey: (String) -> Void = { _ in }
        var onRefuse: (String) -> Void = { _ in }
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        static let codes: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Enter", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "Backtick", 51: "Backspace", 53: "Escape", 76: "Enter",
            82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            123: "Left", 124: "Right", 125: "Down", 126: "Up",
        ]
        static let modifiers: [UInt16: (String, NSEvent.ModifierFlags)] = [
            56: ("LShift", .shift), 60: ("RShift", .shift), 59: ("LCtrl", .control), 62: ("RCtrl", .control),
            58: ("LAlt", .option), 61: ("RAlt", .option), 57: ("CapsLock", .capsLock),
        ]

        override func keyDown(with event: NSEvent) {
            if event.isARepeat { return }
            if let k = Self.codes[event.keyCode] { onKey(k) }
            else if event.keyCode == 63 { onRefuse(T("The game can't see fn, so it can't be bound. Pick another key.")) }
            else { onRefuse(T("The mod can't use {key}. Try another key.", ["key": event.charactersIgnoringModifiers ?? "?"])) }
        }

        override func flagsChanged(with event: NSEvent) {
            if event.keyCode == 54 || event.keyCode == 55 { onRefuse(T("⌘ Command is kept for system shortcuts and can't be bound.")); return }
            if event.keyCode == 63 { onRefuse(T("The game can't see fn, so it can't be bound. Pick another key.")); return }
            guard let (name, flag) = Self.modifiers[event.keyCode] else { return }
            if event.modifierFlags.contains(flag) || event.keyCode == 57 { onKey(name) }
        }

        // ⌘ shortcuts never reach the game's keys.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
            if event.modifierFlags.contains(.command) { onRefuse(T("⌘ Command is kept for system shortcuts and can't be bound.")); return true }
            return super.performKeyEquivalent(with: event)
        }

        override func mouseDown(with event: NSEvent) { onKey("Mouse1") }
        override func rightMouseDown(with event: NSEvent) { onKey("Mouse2") }
        override func otherMouseDown(with event: NSEvent) {
            switch event.buttonNumber {
            case 2: onKey("Mouse3")
            case 3: onKey("Mouse4")
            case 4: onKey("Mouse5")
            default: break
            }
        }
    }
}
