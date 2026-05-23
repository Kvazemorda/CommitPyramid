import Foundation

/// Protocol every catch-up event source must conform to.
protocol EventSource: AnyObject {
    /// Stable identifier for the source (used as key in catchup-state.json).
    var id: String { get }

    /// Scan for new events since `since`.
    /// - Returns: new `lastCheckTs` to persist (typically the timestamp of
    ///   the newest event found, or `Date()` if nothing was found).
    /// - Throws: any error prevents `lastCheckTs` from being updated.
    func scan(since: Date) async throws -> Date
}

// MARK: - Mock (smoke / dev only)

/// Mock implementation used in smoke-testing (CITY_SMOKE_CATCHUP=1).
/// On every `scan()` call it ingests one synthetic task-completion event.
final class MockEventSource: EventSource {
    let id: String
    let projectId: String
    let titlePrefix: String
    private weak var engine: CityEngine?
    private var counter = 0

    init(
        id: String = "mock",
        projectId: String = "mock-project",
        titlePrefix: String = "Mock task",
        engine: CityEngine
    ) {
        self.id = id
        self.projectId = projectId
        self.titlePrefix = titlePrefix
        self.engine = engine
    }

    func scan(since: Date) async throws -> Date {
        let now = Date()
        counter += 1
        await MainActor.run {
            engine?.ingestTaskCompletion(
                project: projectId,
                title: "\(titlePrefix) #\(counter)",
                taskId: nil,
                source: "mock:\(id):\(counter)",
                ts: now
            )
        }
        return now
    }
}
