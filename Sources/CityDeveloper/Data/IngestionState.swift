import Foundation

struct IngestionState: Codable {
    var filePath: String
    var offsetBytes: UInt64
    var lastReadTs: Date

    static func load() -> IngestionState? {
        guard let data = try? Data(contentsOf: AppPaths.ingestionState) else { return nil }
        return try? JSONDecoder.event.decode(IngestionState.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder.event.encode(self) else { return }
        try? data.write(to: AppPaths.ingestionState, options: .atomic)
    }
}
