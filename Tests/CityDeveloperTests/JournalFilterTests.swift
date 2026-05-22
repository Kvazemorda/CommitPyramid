import XCTest
@testable import CityDeveloper

final class JournalFilterTests: XCTestCase {

    private let allKinds: [GameEvent.Kind] = GameEvent.Kind.allCases

    /// Фабрика: по одному событию на каждый kind, у всех project="p1",
    /// ts на сутки назад/вперёд от base.
    private func sample() -> [GameEvent] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return allKinds.enumerated().map { (i, kind) in
            GameEvent(
                ts: base.addingTimeInterval(TimeInterval(i) * 60),
                kind: kind, project: "p1",
                title: kind.displayName,
                taskId: nil, source: nil
            )
        }
    }

    private let wideRange = (
        from: Date(timeIntervalSince1970: 0),
        to: Date(timeIntervalSince1970: 2_000_000_000)
    )

    func testAllPresetReturnsAll() {
        let out = JournalFilter.apply(
            events: sample(), projectId: nil,
            dateFrom: wideRange.from, dateTo: wideRange.to,
            kindFilter: .all
        )
        XCTAssertEqual(out.count, 7)
    }

    func testTaskCompletedPreset() {
        let out = JournalFilter.apply(
            events: sample(), projectId: nil,
            dateFrom: wideRange.from, dateTo: wideRange.to,
            kindFilter: .some([.taskCompleted])
        )
        XCTAssertEqual(out.map(\.kind), [.taskCompleted])
    }

    func testUnitBuiltPreset() {
        let out = JournalFilter.apply(
            events: sample(), projectId: nil,
            dateFrom: wideRange.from, dateTo: wideRange.to,
            kindFilter: .some([.unitBuilt])
        )
        XCTAssertEqual(out.map(\.kind), [.unitBuilt])
    }

    func testStageUpPreset() {
        let out = JournalFilter.apply(
            events: sample(), projectId: nil,
            dateFrom: wideRange.from, dateTo: wideRange.to,
            kindFilter: .some([.stageUp])
        )
        XCTAssertEqual(out.map(\.kind), [.stageUp])
    }

    func testDecayPreset() {
        let decay: Set<GameEvent.Kind> = [.decayTick, .fire, .restore, .ruinsCleared]
        let out = JournalFilter.apply(
            events: sample(), projectId: nil,
            dateFrom: wideRange.from, dateTo: wideRange.to,
            kindFilter: .some(decay)
        )
        XCTAssertEqual(Set(out.map(\.kind)), decay)
        XCTAssertEqual(out.count, 4)
    }

    func testEmptySelectionReturnsEmpty() {
        let out = JournalFilter.apply(
            events: sample(), projectId: nil,
            dateFrom: wideRange.from, dateTo: wideRange.to,
            kindFilter: .some([])
        )
        XCTAssertTrue(out.isEmpty)
    }

    func testProjectFilterAndKindCombine() {
        var events = sample()
        // подсадить событие из другого проекта
        events.append(GameEvent(
            ts: Date(timeIntervalSince1970: 1_700_000_999),
            kind: .taskCompleted, project: "p2",
            title: "x", taskId: nil, source: nil
        ))
        let out = JournalFilter.apply(
            events: events, projectId: "p2",
            dateFrom: wideRange.from, dateTo: wideRange.to,
            kindFilter: .some([.taskCompleted])
        )
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.project, "p2")
    }

    func testInvalidDateRangeStillRespectsKind() {
        // dateFrom > dateTo → dateRangeValid = false → диапазон не применяется
        // (текущее поведение `filteredEvents` сохраняем).
        let out = JournalFilter.apply(
            events: sample(), projectId: nil,
            dateFrom: Date(timeIntervalSince1970: 2_000_000_000),
            dateTo: Date(timeIntervalSince1970: 1_500_000_000),
            kindFilter: .some([.fire])
        )
        XCTAssertEqual(out.map(\.kind), [.fire])
    }

    func testSortDescending() {
        let out = JournalFilter.apply(
            events: sample(), projectId: nil,
            dateFrom: wideRange.from, dateTo: wideRange.to,
            kindFilter: .all
        )
        let timestamps = out.map(\.ts)
        XCTAssertEqual(timestamps, timestamps.sorted(by: >))
    }

    /// Событие с ts в середине того же дня, что и dateTo, должно проходить
    /// (т.к. сравнение идёт с `dateTo.endOfDay` — 23:59:59).
    func testEndOfDayBoundary() {
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let midDay = cal.date(byAdding: .hour, value: 14, to: day)!
        let nextDay = cal.date(byAdding: .day, value: 1, to: day)!

        let inside = GameEvent(
            ts: midDay, kind: .taskCompleted, project: "p1",
            title: "in", taskId: nil, source: nil
        )
        let outside = GameEvent(
            ts: cal.date(byAdding: .hour, value: 1, to: nextDay)!,
            kind: .taskCompleted, project: "p1",
            title: "out", taskId: nil, source: nil
        )
        let out = JournalFilter.apply(
            events: [inside, outside], projectId: nil,
            dateFrom: day, dateTo: day,
            kindFilter: .all
        )
        XCTAssertEqual(out.map(\.title), ["in"],
                       "Mid-day event of dateTo must pass, next-day must not")
    }
}
