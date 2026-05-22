import Foundation

final class SnapshotStore {
    var url: URL

    init(url: URL = AppPaths.stateJson) { self.url = url }

    func load() -> StateSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snap = try? decoder.decode(StateSnapshot.self, from: data),
              snap.version == StateSnapshot.currentVersion else {
            ErrorsLog.write("State snapshot invalid or unsupported version, falling back to full replay")
            return nil
        }
        return snap
    }

    func save(_ snapshot: StateSnapshot) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            ErrorsLog.write("Snapshot save failed: \(error)")
            return false
        }
    }
}
