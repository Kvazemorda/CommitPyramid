import Foundation
import Combine

final class CityEngine: ObservableObject {

    @Published private(set) var state = CityState()
    @Published private(set) var events: [GameEvent] = []
    private let eventLog: EventLog
    private let unitPlanner = UnitPlanner()
    private let districtPlanner = DistrictPlanner()

    private let snapshotStore: SnapshotStore
    var eventsSinceSnapshot: Int = 0
    private(set) var lastSnapshotEventIndex: Int = -1

    var onUnitBuilt: ((UnitState, ProjectState) -> Void)?
    var onProjectCreated: ((ProjectState) -> Void)?
    var onDecayChanged: ((String) -> Void)?

    private var periodicSnapshotTimer: DispatchSourceTimer?

    init(eventLog: EventLog = EventLog(), snapshotStore: SnapshotStore = SnapshotStore()) {
        self.eventLog = eventLog
        self.snapshotStore = snapshotStore
        replayFromLog()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 3600, repeating: 3600)
        timer.setEventHandler { [weak self] in self?.checkPeriodicSnapshot() }
        timer.resume()
        self.periodicSnapshotTimer = timer
    }

    func relocateEventLog(to newDirectory: URL) {
        eventLog.relocate(to: newDirectory)
    }

    func relocateSnapshotStore(to directory: URL) {
        snapshotStore.url = directory.appendingPathComponent("state.json")
    }

    /// Записывает системное событие в лог, применяет к state и триггерит визуальные колбэки.
    /// Вызывается из DecayEngine на main queue.
    func appendSystemEvent(_ kind: GameEvent.Kind, project: String) {
        let e = GameEvent(ts: Date(), kind: kind, project: project)
        eventLog.append(e)
        apply(e, silent: false)
        lastSnapshotEventIndex += 1
        eventsSinceSnapshot += 1
        if eventsSinceSnapshot >= 500 { saveSnapshot() }
    }

    func ingestTaskCompletion(project: String, title: String, taskId: String?, source: String?, ts: Date) {
        let event = GameEvent(
            ts: ts,
            kind: .taskCompleted,
            project: project,
            title: title,
            taskId: taskId,
            source: source
        )
        eventLog.append(event)
        events.append(event)
        apply(event)
        lastSnapshotEventIndex += 1
        eventsSinceSnapshot += 1
        if eventsSinceSnapshot >= 500 { saveSnapshot() }
    }

    private func replayFromLog() {
        if let snap = snapshotStore.load() {
            let all = eventLog.readAll()
            // Edge case: пустой лог + snap с lastEventIndex == -1
            if all.isEmpty && snap.lastEventIndex == -1 {
                state = snap.cityState
                lastSnapshotEventIndex = -1
                return
            }
            // Верифицируем: lastEventId соответствует событию по индексу
            if snap.lastEventIndex >= 0 && snap.lastEventIndex < all.count
               && all[snap.lastEventIndex].id == snap.lastEventId {
                state = snap.cityState
                lastSnapshotEventIndex = snap.lastEventIndex
                let tail = eventLog.readSince(index: snap.lastEventIndex)
                for e in tail { apply(e, silent: true) }
                lastSnapshotEventIndex = all.count - 1
                events = eventLog.readAll()
                return
            } else {
                ErrorsLog.write("Snapshot event mismatch, falling back to full replay")
            }
        }
        // Fallback: full replay
        let allEvents = eventLog.readAll()
        for e in allEvents { apply(e, silent: true) }
        lastSnapshotEventIndex = allEvents.count - 1
        events = allEvents
        if !allEvents.isEmpty { saveSnapshot() }
    }

    func saveSnapshot() {
        let all = eventLog.readAll()
        let idx = lastSnapshotEventIndex
        let lastId = (idx >= 0 && idx < all.count) ? all[idx].id : nil
        let snap = StateSnapshot(
            version: StateSnapshot.currentVersion,
            snapshotTs: Date(),
            lastEventIndex: idx,
            lastEventId: lastId,
            cityState: state
        )
        if snapshotStore.save(snap) { eventsSinceSnapshot = 0 }
    }

    private func checkPeriodicSnapshot() {
        guard let snap = snapshotStore.load() else { saveSnapshot(); return }
        if Date().timeIntervalSince(snap.snapshotTs) >= 86400 && eventsSinceSnapshot > 0 {
            saveSnapshot()
        }
    }

    private func apply(_ event: GameEvent, silent: Bool = false) {
        switch event.kind {
        case .taskCompleted:
            applyTaskCompleted(event, silent: silent)
        case .decayTick:
            guard var project = state.projects[event.project] else { break }
            project.decayLevel = min(4, project.decayLevel + 1)
            project.lastDecayLogged = max(project.lastDecayLogged, project.decayLevel)
            state.projects[event.project] = project
            if !silent { onDecayChanged?(event.project) }
        case .fire:
            // Визуальный сигнал — decay уже на уровне 3 через decayTick.
            // При replay просто триггерим onDecayChanged для обновления visual'а.
            if !silent { onDecayChanged?(event.project) }
        case .restore:
            guard var project = state.projects[event.project] else { break }
            project.decayLevel = 0
            project.lastDecayLogged = 0
            state.projects[event.project] = project
            if !silent { onDecayChanged?(event.project) }
        case .unitBuilt, .stageUp, .ruinsCleared:
            break
        }
    }

    private func applyTaskCompleted(_ event: GameEvent, silent: Bool) {
        let projectKey = event.project
        var project: ProjectState
        var isNewProject = false

        if let existing = state.projects[projectKey] {
            project = existing
            // Restore при возврате к проекту с decay 1-3.
            // decay == 4 (руины) — restore не происходит (F-06).
            if !silent && project.decayLevel > 0 && project.decayLevel < 4 {
                appendSystemEvent(.restore, project: projectKey)
                // Перечитать актуальный state после apply(.restore), который обнулил decayLevel
                if let restored = state.projects[projectKey] {
                    project = restored
                }
            }
            project.lastActivityAt = event.ts
            project.taskCount += 1
        } else {
            isNewProject = true
            let origin = districtPlanner.allocateNextOrigin(currentIndex: state.nextDistrictIndex)
            state.nextDistrictIndex += 1
            project = ProjectState(
                id: projectKey,
                name: projectKey,
                createdAt: event.ts,
                lastActivityAt: event.ts,
                taskCount: 1,
                stage: 0,
                decayLevel: 0,
                lastDecayLogged: 0,
                districtOrigin: origin,
                unitIds: []
            )
        }

        let kind = unitPlanner.nextUnitKind(forTaskIndex: project.taskCount, stage: project.stage)
        let position = unitPlanner.nextPosition(
            origin: project.districtOrigin,
            taskIndex: project.taskCount
        )

        let unit = UnitState(
            id: UUID(),
            projectId: projectKey,
            kind: kind,
            position: position,
            tier: project.stage,
            decayLevel: 0,
            taskTitle: event.title,
            taskTs: event.ts,
            taskSource: event.source
        )
        state.units[unit.id] = unit
        project.unitIds.append(unit.id)

        let newStage = StageRules.computeStage(
            taskCount: project.taskCount,
            ageDays: max(1, Calendar.current.dateComponents([.day], from: project.createdAt, to: event.ts).day ?? 1)
        )
        if newStage > project.stage {
            project.stage = newStage
        }

        state.projects[projectKey] = project

        if !silent {
            if isNewProject {
                onProjectCreated?(project)
            }
            onUnitBuilt?(unit, project)
        }
    }
}
