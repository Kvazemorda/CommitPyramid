import Foundation

final class SnapshotStore {
    var url: URL

    init(url: URL = AppPaths.stateJson) { self.url = url }

    func load() -> StateSnapshot? {
        // «Файл не существует» — штатная ситуация (первый запуск), без записи в errors.log.
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        guard let data = try? Data(contentsOf: url) else {
            ErrorsLog.write("Snapshot read failed: file exists but is unreadable at \(url.path). Falling back to full replay.")
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let snap = try decoder.decode(StateSnapshot.self, from: data)
            guard snap.version == StateSnapshot.currentVersion else {
                ErrorsLog.write("Snapshot version \(snap.version) ≠ current \(StateSnapshot.currentVersion); full replay.")
                return nil
            }
            return snap
        } catch {
            // Типичная причина: state.json сохранён со старым UnitKind rawValue,
            // которого нет в текущей версии, либо повреждён вручную.
            ErrorsLog.write("Snapshot decode failed (unknown UnitKind rawValue or schema mismatch): \(error). Falling back to full replay.")
            return nil
        }
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
