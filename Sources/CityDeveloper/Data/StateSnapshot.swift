import Foundation

struct StateSnapshot: Codable {
    let version: Int
    let snapshotTs: Date
    let lastEventIndex: Int      // 0-based; -1 если в логе ещё ничего нет
    let lastEventId: UUID?       // nil если lastEventIndex == -1
    let cityState: CityState

    static let currentVersion = 1
}
