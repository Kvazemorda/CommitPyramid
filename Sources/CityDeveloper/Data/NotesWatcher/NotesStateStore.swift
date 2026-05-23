import Foundation
import CryptoKit

/// Sidecar dedup store for a single notes source.
///
/// Stored in:
///   `~/Library/Application Support/CityDeveloper/notes-state/<sourceId>.json`
///
/// JSON format: `{ "<lineHash>": "<ISO8601 timestamp>" }`
///
/// All reads and writes are performed on the caller's queue (the watcher's
/// serial IO queue), so no extra locking is needed.
final class NotesStateStore {

    // MARK: - Properties

    private let url: URL
    private var store: [String: String] = [:]   // lineHash → ISO8601 string

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Init

    init(sourceId: String) {
        let dir = AppPaths.appSupport.appendingPathComponent("notes-state", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.url = dir.appendingPathComponent("\(sourceId).json")
        load()
    }

    // MARK: - Public API

    /// Returns `true` if the line hash has been processed before.
    func contains(_ lineHash: String) -> Bool {
        store[lineHash] != nil
    }

    /// Record a line hash as processed at the given date.
    func markProcessed(_ lineHash: String, at date: Date = Date()) {
        store[lineHash] = Self.iso8601.string(from: date)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            ErrorsLog.write("NotesStateStore: corrupt sidecar at \(url.path) — resetting")
            store = [:]
            return
        }
        store = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
