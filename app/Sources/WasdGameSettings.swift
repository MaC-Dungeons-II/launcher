import CryptoKit
import Foundation

// The game's own keyboard settings for wasdmod's key layouts. The Launcher
// edition keeps them as a GameSave container ("EnhancedInputUserSettings",
// a UE GVAS file in blob "Data") in the local save store the Flightdeck proxy
// writes, drive_c/gamesave/<account>/state.bin, which the game creates the
// first time it saves its settings. The game holds the store while it runs
// and writes it from memory, so a change asked for while playing waits in
// <data>/wasdmod/pending-controls.json and is written once the game has
// closed (the launcher offers to restart it right away).

@MainActor
extension Launcher {
    static let controlsContainer = "EnhancedInputUserSettings"

    var wasdPendingFile: URL { wasdData.appendingPathComponent("pending-controls.json") }

    /// With several accounts, the newest store that has the settings.
    func gameControlsStore() -> URL? {
        let root = prefix.appendingPathComponent("drive_c/gamesave")
        let stores = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? [])
            .map { root.appendingPathComponent($0).appendingPathComponent("state.bin") }
            .filter { fm.fileExists(atPath: $0.path) }
            .sorted { modificationDate($0) > modificationDate($1) }
        return stores.first { url in
            guard let data = try? Data(contentsOf: url), let state = LocalSaveStore.decode(data) else { return false }
            return state.blob(Self.controlsContainer) != nil
        }
    }

    private func modificationDate(_ url: URL) -> Date {
        ((try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? .distantPast
    }

    func readGameControls() -> WasdControls.Parsed? {
        guard let url = gameControlsStore(), let data = try? Data(contentsOf: url),
              let gvas = LocalSaveStore.decode(data)?.blob(Self.controlsContainer) else { return nil }
        return WasdControls.parse(gvas)
    }

    var pendingGameControls: [WasdWant] {
        guard let data = try? Data(contentsOf: wasdPendingFile) else { return [] }
        return (try? JSONDecoder().decode([WasdWant].self, from: data)) ?? []
    }

    /// The game's keys per row as they are, or will be once a waiting change
    /// is written. nil: the game hasn't saved its settings yet.
    func gameKeys() -> [String: [String?]]? {
        guard let ctl = readGameControls() else { return nil }
        var keys = WasdControls.keys(ctl)
        for w in pendingGameControls { keys[w.id] = w.keys }
        return keys
    }

    enum ControlsResult { case written, waiting, failed(String) }

    /// The editor's "change them for me": now, or after the game has closed.
    func setGameControls(_ want: [WasdWant]) -> ControlsResult {
        guard readGameControls() != nil else {
            return .failed("게임 설정이 아직 저장되지 않았어요. 게임의 설정 › 조작 › 키보드에서 아무 키나 한 번 바꿔 주세요.")
        }
        if gameRunning {
            var merged = pendingGameControls.filter { w in !want.contains { $0.id == w.id } }
            merged += want
            do {
                try fm.createDirectory(at: wasdData, withIntermediateDirectories: true)
                try JSONEncoder().encode(merged).write(to: wasdPendingFile, options: .atomic)
            } catch {
                return .failed(error.localizedDescription)
            }
            offerRestart("게임 키 설정은 게임이 꺼져 있을 때만 바꿀 수 있어요. 게임에 종료 신호를 보내고, 닫히면 키 설정을 바꾼 뒤 바로 다시 실행해요.")
            return .waiting
        }
        if let error = writeGameControls(want) { return .failed(error) }
        resaveWasdLayoutForGame()
        return .written
    }

    /// A change that waited for the game to close. Called when the game has
    /// ended and before a launch.
    func applyPendingGameControls() {
        let pending = pendingGameControls
        guard !pending.isEmpty, !gameRunning else { return }
        if let error = writeGameControls(pending) {
            appendGameLog("launcher: couldn't change the in-game controls: \(error)")
        } else {
            appendGameLog("launcher: changed the in-game controls (\(pending.count) rows)")
        }
        try? fm.removeItem(at: wasdPendingFile)
        resaveWasdLayoutForGame()
    }

    /// Replaces only the settings container, the way the proxy commits a
    /// save (next generation, the container's time, checksum, atomic rename).
    /// The store also has the game's other saves, so it is copied to
    /// <data>/wasdmod/backups first (the last ten), and the result must decode
    /// with every other container unchanged. nil when it worked.
    func writeGameControls(_ want: [WasdWant]) -> String? {
        guard let url = gameControlsStore(), let original = try? Data(contentsOf: url),
              var state = LocalSaveStore.decode(original),
              let gvas = state.blob(Self.controlsContainer), let ctl = WasdControls.parse(gvas) else {
            return "게임 설정 파일을 읽지 못했어요."
        }
        let before = state
        let written = WasdControls.write(ctl, want)
        state.setBlob(Self.controlsContainer, written, now: UInt64(Date().timeIntervalSince1970))
        let encoded = LocalSaveStore.encode(state)
        let others = { (s: LocalSaveStore.State) in s.containers.filter { $0.key != Self.controlsContainer } }
        guard let check = LocalSaveStore.decode(encoded), check.blob(Self.controlsContainer) == written,
              WasdControls.parse(written) != nil, others(check) == others(before) else {
            return "게임 설정 파일을 안전하게 고치지 못해서 그대로 뒀어요."
        }
        do {
            let backups = wasdData.appendingPathComponent("backups")
            try fm.createDirectory(at: backups, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try original.write(to: backups.appendingPathComponent("state-\(stamp).bin"))
            let old = ((try? fm.contentsOfDirectory(atPath: backups.path)) ?? []).filter { $0.hasPrefix("state-") }.sorted().dropLast(10)
            for name in old { try? fm.removeItem(at: backups.appendingPathComponent(name)) }
            try encoded.write(to: url, options: .atomic)
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    /// The layout in use saved again with the game's keys as they are, so the
    /// mod sends the keys the game has (as the editor's apps do).
    func resaveWasdLayoutForGame() {
        guard let real = gameKeys() else { return }
        let file = wasdData.appendingPathComponent(wasdLayout)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        var st = Wasd.state(from: text)
        let was = Wasd.iniText(st)
        for (id, g) in real { st.game[id] = g }
        let now = Wasd.iniText(st)
        if now != was { try? Data(now.utf8).write(to: file, options: .atomic) }
    }
}

/// The local GameSave store the Flightdeck proxy keeps (GameSaveLocalCore.cpp):
/// "XDLOCAL1", u32 version 1, u64 generation, u32 container count, then per
/// container its name, display name, u64 modified (Unix seconds) and blobs
/// (name, u32 size, bytes); strings are u32 length + UTF-8; little-endian;
/// a SHA-256 of everything before it at the end. Containers stay in order.
enum LocalSaveStore {
    struct Container: Equatable {
        var key: String
        var display: String
        var modified: UInt64
        var blobs: [Blob]
    }
    struct Blob: Equatable {
        var key: String
        var bytes: Data
    }
    struct State {
        var generation: UInt64
        var containers: [Container]

        func blob(_ name: String) -> Data? {
            containers.first { $0.key == name }?.blobs.first { $0.key == "Data" }?.bytes
        }

        mutating func setBlob(_ name: String, _ bytes: Data, now: UInt64) {
            guard let i = containers.firstIndex(where: { $0.key == name }),
                  let j = containers[i].blobs.firstIndex(where: { $0.key == "Data" }) else { return }
            containers[i].blobs[j].bytes = bytes
            containers[i].modified = now
            generation += 1
        }
    }

    private static let magic = Array("XDLOCAL1".utf8)

    static func decode(_ data: Data) -> State? {
        let all = [UInt8](data)
        guard all.count >= 56, Array(all.prefix(8)) == magic else { return nil }
        let body = Array(all.dropLast(32))
        guard Array(SHA256.hash(data: body)) == Array(all.suffix(32)) else { return nil }
        var at = 8
        func take(_ n: Int) -> [UInt8]? {
            guard n >= 0, at + n <= body.count else { return nil }
            defer { at += n }
            return Array(body[at..<at + n])
        }
        func u32() -> UInt32? { take(4).map { $0.enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) } } }
        func u64() -> UInt64? { take(8).map { $0.enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * $1.offset) } } }
        func text() -> String? { u32().flatMap { take(Int($0)) }.flatMap { String(bytes: $0, encoding: .utf8) } }
        guard u32() == 1, let generation = u64(), let count = u32(), count <= 4096 else { return nil }
        var containers: [Container] = []
        for _ in 0..<count {
            guard let key = text(), let display = text(), let modified = u64(), let n = u32(), n <= 65536 else { return nil }
            var blobs: [Blob] = []
            for _ in 0..<n {
                guard let name = text(), let size = u32(), let bytes = take(Int(size)) else { return nil }
                blobs.append(Blob(key: name, bytes: Data(bytes)))
            }
            containers.append(Container(key: key, display: display, modified: modified, blobs: blobs))
        }
        return at == body.count ? State(generation: generation, containers: containers) : nil
    }

    static func encode(_ state: State) -> Data {
        var out = magic
        func u32(_ v: UInt32) { out += (0..<4).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
        func u64(_ v: UInt64) { out += (0..<8).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
        func text(_ s: String) { let b = Array(s.utf8); u32(UInt32(b.count)); out += b }
        u32(1)
        u64(state.generation)
        u32(UInt32(state.containers.count))
        for c in state.containers {
            text(c.key)
            text(c.display)
            u64(c.modified)
            u32(UInt32(c.blobs.count))
            for b in c.blobs {
                text(b.key)
                u32(UInt32(b.bytes.count))
                out += [UInt8](b.bytes)
            }
        }
        out += Array(SHA256.hash(data: out))
        return Data(out)
    }
}
