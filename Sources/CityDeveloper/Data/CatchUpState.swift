import Foundation

struct CatchUpState: Codable {
    var version: Int
    var sources: [String: SourceState]

    struct SourceState: Codable {
        var lastCheckTs: Date
    }

    static let currentVersion = 1

    static func load() -> CatchUpState {
        guard
            let data = try? Data(contentsOf: AppPaths.catchupState),
            let decoded = try? JSONDecoder.event.decode(CatchUpState.self, from: data)
        else {
            return CatchUpState(version: currentVersion, sources: [:])
        }
        return decoded
    }

    func save() {
        // Pretty-printed for easy manual inspection via jq / grep.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: AppPaths.catchupState, options: .atomic)
    }
}
