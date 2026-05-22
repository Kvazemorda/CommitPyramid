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
    /// Вызывается при повышении stage квартала (TASK-019 F-08 визуальная часть).
    /// Параметры: projectId, oldStage, newStage.
    /// Срабатывает только при live-тике (!silent); при replayFromLog (silent=true) — нет.
    var onProjectStageChanged: ((String, Int, Int) -> Void)?
    /// Вызывается при атомарной замене руины новым проектом (F-06 ruin-priority).
    /// oldProjectId — projectId удалённого District-руин; newProject — свежесозданный ProjectState.
    /// Анимация расчистки — чисто визуальная (не event-sourced), запускается в GameScene.
    var onProjectRuinsCleared: ((String, ProjectState) -> Void)?

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
        // F-06: хранит oldProjectId руины при атомарной замене; nil = размещение на свежем лугу.
        var ruinsClearedFrom: String? = nil

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
            // F-06 ruin-priority: если на карте есть зоны руин — занять старшую атомарно.
            // Edge case «возрождение projectId»: pickRuinForNewProject(excluding: projectKey)
            // гарантирует, что проект не занимает сам себя; его руина не является кандидатом.
            // Edge case «два новых проекта в одном тике»: обрабатываются последовательно на
            // main-queue; второй видит уже обновлённый state (первая руина удалена).
            let origin: GridPoint

            if let ruin = pickRuinForNewProject(excluding: projectKey) {
                // Шаги 1–4 (атомарный state-переход):
                // 1. Запомнить origin и oldProjectId руины.
                let reusedOrigin = ruin.districtOrigin
                let oldProjectId = ruin.id

                // 2–3. Удалить все UnitState руины, затем сам ProjectState.
                //      После этого state уже не содержит старого District —
                //      snapshot, сделанный после, увидит финальное состояние.
                for uid in ruin.unitIds {
                    state.units.removeValue(forKey: uid)
                }
                state.projects.removeValue(forKey: oldProjectId)

                // 4. Использовать origin руины; НЕ инкрементируем nextDistrictIndex
                //    (счётчик спирали не должен двигаться при переиспользовании участка).
                origin = reusedOrigin
                ruinsClearedFrom = oldProjectId
            } else {
                // Fallback: стандартная спираль от центра (нет руин на карте).
                origin = districtPlanner.allocateNextOrigin(currentIndex: state.nextDistrictIndex)
                state.nextDistrictIndex += 1
            }

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

        // Собираем per-category счётчики для проекта (O(N) по units; до ~100 юнитов — микросекунды).
        // Считаем до добавления нового юнита — счётчики отражают фактическое состояние квартала.
        let projectUnits = state.units.values.filter { $0.projectId == projectKey }
        let residentialCount = projectUnits.filter { $0.kind.category == .residential }.count
        let wellCount        = projectUnits.filter { $0.kind == .well }.count
        let infraCount       = projectUnits.filter { $0.kind.category == .infrastructure }.count
        let productionCount  = projectUnits.filter { $0.kind.category == .production }.count
        let socialCount      = projectUnits.filter { $0.kind.category == .social }.count
        let kind = unitPlanner.nextUnitKind(
            forTaskIndex: project.taskCount,
            stage: project.stage,
            residentialCount: residentialCount,
            wellCount: wellCount,
            infraCount: infraCount,
            productionCount: productionCount,
            socialCount: socialCount
        )
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

        let oldStage = project.stage
        let newStage = StageRules.computeStage(
            taskCount: project.taskCount,
            ageDays: max(1, Calendar.current.dateComponents([.day], from: project.createdAt, to: event.ts).day ?? 1)
        )
        if newStage > project.stage {
            project.stage = newStage
        }

        state.projects[projectKey] = project

        // TASK-019: обновляем unit.tier для всех юнитов проекта при stage-up (атомарно).
        // Включая только что добавленный юнит (project.unitIds уже содержит unit.id).
        if newStage > oldStage {
            for uid in project.unitIds {
                state.units[uid]?.tier = newStage
            }
        }

        if !silent {
            if isNewProject {
                if let oldId = ruinsClearedFrom {
                    // Ruins-ветка: взаимоисключающий callback.
                    // onProjectCreated НЕ вызывается — GameScene нарисует district-маркер
                    // внутри анимации расчистки (handleRuinsCleared, после wait(2.0)).
                    // Двойной вызов drawDistrictMarker исключён guard'ом в GameScene:248.
                    onProjectRuinsCleared?(oldId, project)
                } else {
                    // Свежий луг: обычный callback.
                    onProjectCreated?(project)
                }
            }
            onUnitBuilt?(unit, project)
            // TASK-019: callback stage-up (только при live-тике, после onUnitBuilt).
            if newStage > oldStage {
                onProjectStageChanged?(projectKey, oldStage, newStage)
            }
        }
    }

    /// Детерминированный выбор руины для нового проекта (F-06).
    /// Возвращает кандидата по правилу: ruinedAt (lastActivityAt) asc → unitIds.count desc → id asc.
    /// Использует lastActivityAt как proxy для ruinedAt (не вводим новое поле, нет миграции snapshot).
    /// excluding: исключает projectId нового проекта — защита от самозанятия при возрождении.
    private func pickRuinForNewProject(excluding newProjectId: String) -> ProjectState? {
        state.projects.values
            .filter { $0.decayLevel == 4 && $0.id != newProjectId }
            .sorted { lhs, rhs in
                // Первично: старшая руина (наименьший lastActivityAt = дольше без активности)
                if lhs.lastActivityAt != rhs.lastActivityAt {
                    return lhs.lastActivityAt < rhs.lastActivityAt
                }
                // Вторично: больше юнитов у исходного квартала
                if lhs.unitIds.count != rhs.unitIds.count {
                    return lhs.unitIds.count > rhs.unitIds.count
                }
                // Tiebreaker: лексикографически меньший projectId
                return lhs.id < rhs.id
            }
            .first
    }
}
