import AppKit
import SpriteKit
import SwiftUI
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {

    private(set) var cityWindow: CityWindow!
    private var modeManager: WindowModeManager!
    private var statusBarController: StatusBarController!
    private var engine: CityEngine!
    private var decayEngine: DecayEngine!
    private var watcher: TasksJsonlWatcher!
    private var scene: GameScene!
    private var hotkey: GlobalHotkey!
    private var bridge: SceneBridge!
    private var appSettings: AppSettings!
    private var settingsWindowController: SettingsWindowController!
    private var journalWindowController: JournalWindowController!
    private var catchUpScheduler: CatchUpScheduler?
    private var notesWatcher: NotesWatcher!
    private var gitWatcher: GitWatcher!
    private var worldMapProvider: WorldMapProvider!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.migrateLegacyApplicationSupport()

        let screen = NSScreen.main ?? NSScreen.screens.first!

        appSettings = AppSettings.load()
        ErrorsLog.write("DataSources: settings=\(appSettings.dataDirectory.path) | tasks=\(appSettings.tasksJsonlPath.path) | worldmap=\(appSettings.dataDirectory.appendingPathComponent("worldmap.json").path) | events=\(appSettings.dataDirectory.appendingPathComponent("events.jsonl").path) | state=\(appSettings.dataDirectory.appendingPathComponent("state.json").path)")

        // TASK-026: бутстрап шумовой карты мира до создания GameScene.
        // Синхронно на main-thread; при первом запуске ≤50 мс (256×256 Perlin, M-серия).
        worldMapProvider = WorldMapProvider(
            seedStore: WorldSeedStore.self,
            mapStore: WorldMapStore(url: appSettings.dataDirectory.appendingPathComponent("worldmap.json"))
        )

        let snapshotStore = SnapshotStore(url: appSettings.dataDirectory.appendingPathComponent("state.json"))
        engine = CityEngine(
            eventLog: EventLog(fileURL: appSettings.dataDirectory.appendingPathComponent("events.jsonl")),
            snapshotStore: snapshotStore
        )

        decayEngine = DecayEngine()
        decayEngine.cityEngine = engine

        scene = GameScene()
        scene.size = screen.frame.size
        scene.scaleMode = .resizeFill
        scene.engine = engine
        scene.worldMap = worldMapProvider.map

        engine.onUnitBuilt = { [weak self] unit, project in
            self?.scene?.placeUnit(unit, project: project)
        }
        engine.onProjectCreated = { [weak self] project in
            self?.scene?.markDistrict(project: project)
        }
        engine.onDecayChanged = { [weak self] projectId in
            self?.scene?.applyDecayToProject(projectId)
        }
        // F-06 ruin-priority: атомарная замена руины новым проектом (визуальная анимация расчистки).
        engine.onProjectRuinsCleared = { [weak self] oldProjectId, newProject in
            self?.scene?.handleRuinsCleared(oldProjectId: oldProjectId, newProject: newProject)
        }
        // TASK-019 F-08: визуальная подмена tier при stage-up квартала.
        // Callback срабатывает только при live-тике (silent=false в CityEngine).
        engine.onProjectStageChanged = { [weak self] projectId, oldStage, newStage in
            self?.scene?.handleProjectStageChanged(projectId: projectId, oldStage: oldStage, newStage: newStage)
        }
        // TASK-034 F-16: визуальная эволюция юнита по порогу.
        // Callback срабатывает только при live-тике (silent=false в CityEngine).
        engine.onUnitEvolved = { [weak self] uid, from, to, projectId in
            self?.scene?.handleUnitEvolved(unitId: uid, from: from, to: to, projectId: projectId)
        }

        bridge = SceneBridge()
        bridge.scene = scene
        scene.bridge = bridge

        cityWindow = CityWindow.makeBehindWindow(on: screen)
        modeManager = WindowModeManager(window: cityWindow)

        journalWindowController = JournalWindowController()

        let hostingView = NSHostingView(
            rootView: ContentView(
                scene: scene,
                engine: engine,
                modeManager: modeManager,
                bridge: bridge,
                journalController: journalWindowController,
                appSettings: appSettings,
                tasksJsonlPath: appSettings.tasksJsonlPath
            )
        )
        hostingView.frame = screen.frame
        cityWindow.contentView = hostingView

        // Pause/resume SpriteKit при смене режима (F-05 behind-mode)
        modeManager.onModeChange = { [weak self] isExplore in
            guard let view = self?.cityWindow.contentView?.findSpriteKitView() else { return }
            view.isPaused = !isExplore
        }

        if ProcessInfo.processInfo.environment["CITY_START_EXPLORE"] != nil {
            modeManager.enterExploreMode()
        } else {
            modeManager.enterBehindMode()
        }

        // TASK-025: bench-режим — спавн N синтетических юнитов для замера FPS.
        // Юниты не попадают в engine.state. Задержка 0.5 сек гарантирует, что didMove(to:) уже отработал.
        if let raw = ProcessInfo.processInfo.environment["CITY_BENCH_UNITS"],
           let n = Int(raw), n > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.scene.spawnBenchUnits(count: n)
            }
        }

        cityWindow.orderFront(nil)

        statusBarController = StatusBarController(modeManager: modeManager)

        hotkey = GlobalHotkey()
        hotkey.onPress = { [weak self] in self?.modeManager.toggle() }
        let ok = hotkey.register(keyCode: appSettings.hotkeyKeyCode, modifiers: appSettings.hotkeyModifiers)
        if !ok {
            NSLog("CommitPyramid: global hotkey is unavailable (already taken?)")
        }

        watcher = TasksJsonlWatcher(fileURL: appSettings.tasksJsonlPath, engine: engine)
        watcher.appSettings = appSettings
        watcher.start()

        // F-20: catch-up scheduler (watcher infrastructure for F-18/F-19).
        // In smoke mode (CITY_SMOKE_CATCHUP=1) a mock source is registered.
        let scheduler = CatchUpScheduler(engine: engine, appSettings: appSettings)
        if ProcessInfo.processInfo.environment["CITY_SMOKE_CATCHUP"] == "1" {
            let mock = MockEventSource(engine: engine)
            scheduler.register(mock)
        }

        // F-18: Notes/folder watcher. Register persisted sources, then register
        // the watcher itself with CatchUpScheduler for periodic scans.
        notesWatcher = NotesWatcher()
        notesWatcher.engine = engine
        notesWatcher.appSettings = appSettings
        for spec in appSettings.notesSources {
            notesWatcher.register(spec)
        }
        scheduler.register(notesWatcher)

        // F-19: Git watcher. Register persisted repositories, then register
        // the watcher itself with CatchUpScheduler for periodic scans.
        gitWatcher = GitWatcher()
        gitWatcher.engine = engine
        gitWatcher.appSettings = appSettings
        for repo in appSettings.gitRepos {
            gitWatcher.register(repo)
        }
        scheduler.register(gitWatcher)

        scheduler.start()
        catchUpScheduler = scheduler

        settingsWindowController = SettingsWindowController()
        statusBarController.onSettingsRequested = { [weak self] in
            guard let self = self else { return }
            self.settingsWindowController.show(
                settings: self.appSettings,
                notesWatcher: self.notesWatcher,
                gitWatcher: self.gitWatcher,
                appDelegate: self,
                onSave: { self.applySettings() }
            )
        }

        decayEngine.start()

        NSLog("CommitPyramid started. Data root: \(AppPaths.appSupport.path)")
    }

    private func applySettings() {
        watcher.restart(at: appSettings.tasksJsonlPath)
        engine.relocateEventLog(to: appSettings.dataDirectory)
        engine.relocateSnapshotStore(to: appSettings.dataDirectory)
        engine.saveSnapshot()
        hotkey.unregister()
        let ok = hotkey.register(keyCode: appSettings.hotkeyKeyCode, modifiers: appSettings.hotkeyModifiers)
        if !ok {
            // Revert to default
            appSettings.hotkeyKeyCode = UInt32(kVK_ANSI_G)
            appSettings.hotkeyModifiers = UInt32(cmdKey | optionKey)
            appSettings.save()
            let fallbackOk = hotkey.register(keyCode: appSettings.hotkeyKeyCode, modifiers: appSettings.hotkeyModifiers)
            let alertText = fallbackOk
                ? "Hotkey конфликт. Восстановлена комбинация ⌘⌥G."
                : "Hotkey конфликт. Не удалось восстановить комбинацию. Переназначьте hotkey вручную в Настройках."
            let alert = NSAlert()
            alert.messageText = "Конфликт hotkey"
            alert.informativeText = alertText
            alert.runModal()
        }
    }

    // MARK: - BUG-005: Reset & Rebuild

    /// Сбрасывает весь state города и запускает re-scan всех источников начиная с `replaySince`.
    /// Вызывается из SettingsView после подтверждения пользователя.
    @MainActor
    func resetCity(replaySince: Date) {
        // 1. Stop scheduler and decay engine.
        catchUpScheduler?.stop()
        decayEngine?.stop()

        let fm = FileManager.default
        let dataDir = appSettings.dataDirectory

        // 2. Delete state files (including ingestion-state so tasks replay from offset 0).
        let filesToDelete: [URL] = [
            dataDir.appendingPathComponent("events.jsonl"),
            dataDir.appendingPathComponent("state.json"),
            AppPaths.catchupState,
            AppPaths.ingestionState,
            dataDir.appendingPathComponent("worldmap.json"),
        ]
        for url in filesToDelete {
            try? fm.removeItem(at: url)
        }

        // 3. Delete notes-state directory contents.
        let notesStateDir = AppPaths.appSupport.appendingPathComponent("notes-state", isDirectory: true)
        if let items = try? fm.contentsOfDirectory(at: notesStateDir, includingPropertiesForKeys: nil) {
            for item in items { try? fm.removeItem(at: item) }
        }

        // 4. Set a new random world seed so the map regenerates with fresh biomes.
        let newSeed = Int64(bitPattern: UInt64.random(in: .min ... .max))
        WorldSeedStore.saveSeed(newSeed)

        // 5. Rebuild engine on a clean slate.
        let snapshotStore = SnapshotStore(url: dataDir.appendingPathComponent("state.json"))
        engine = CityEngine(
            eventLog: EventLog(fileURL: dataDir.appendingPathComponent("events.jsonl")),
            snapshotStore: snapshotStore
        )
        decayEngine.cityEngine = engine

        // 6. Rebuild world map with the new seed (file deleted → provider regenerates).
        worldMapProvider = WorldMapProvider(
            seedStore: WorldSeedStore.self,
            mapStore: WorldMapStore(url: dataDir.appendingPathComponent("worldmap.json"))
        )

        // 7. Reconnect engine callbacks (same closures as in applicationDidFinishLaunching).
        engine.onUnitBuilt = { [weak self] unit, project in
            self?.scene?.placeUnit(unit, project: project)
        }
        engine.onProjectCreated = { [weak self] project in
            self?.scene?.markDistrict(project: project)
        }
        engine.onDecayChanged = { [weak self] projectId in
            self?.scene?.applyDecayToProject(projectId)
        }
        engine.onProjectRuinsCleared = { [weak self] oldProjectId, newProject in
            self?.scene?.handleRuinsCleared(oldProjectId: oldProjectId, newProject: newProject)
        }
        engine.onProjectStageChanged = { [weak self] projectId, oldStage, newStage in
            self?.scene?.handleProjectStageChanged(projectId: projectId, oldStage: oldStage, newStage: newStage)
        }
        engine.onUnitEvolved = { [weak self] uid, from, to, projectId in
            self?.scene?.handleUnitEvolved(unitId: uid, from: from, to: to, projectId: projectId)
        }

        // 8. Reconnect scene to new engine and new world map, then reload.
        scene.engine = engine
        scene.worldMap = worldMapProvider.map
        scene.resetScene()

        // 9. Pre-seed CatchUpState с replaySince для ВСЕХ ключей: глобальные
        //    идентификаторы watcher'ов И per-source ключи (git-repo-<id>,
        //    notes-source-<id>). Иначе GitWatcher.performScan читает per-repo
        //    ключ, который после удаления файла = .distantPast — git log с
        //    устаревшим --since может вернуть подозрительно мало результатов.
        var freshState = CatchUpState(version: CatchUpState.currentVersion, sources: [:])
        freshState.sources[notesWatcher.id] = .init(lastCheckTs: replaySince)
        freshState.sources[gitWatcher.id]   = .init(lastCheckTs: replaySince)
        for repo in appSettings.gitRepos {
            freshState.sources["git-repo-\(repo.id)"] = .init(lastCheckTs: replaySince)
        }
        for spec in appSettings.notesSources {
            freshState.sources["notes-source-\(spec.id)"] = .init(lastCheckTs: replaySince)
        }
        freshState.save()

        // 10. Пересоздаём watcher'ы и заново регистрируем все репо/notes-источники.
        //     Старые инстансы держат через [weak self] свои DispatchSource'ы и
        //     отпускаются вместе с присваиванием новой ссылки. register() триггерит
        //     немедленный performScan каждого источника, который теперь увидит
        //     replaySince в CatchUpState → подтянет всю историю до этой даты.
        notesWatcher = NotesWatcher()
        notesWatcher.engine = engine
        notesWatcher.appSettings = appSettings
        for spec in appSettings.notesSources {
            notesWatcher.register(spec)
        }

        gitWatcher = GitWatcher()
        gitWatcher.engine = engine
        gitWatcher.appSettings = appSettings
        for repo in appSettings.gitRepos {
            gitWatcher.register(repo)
        }

        // 11. Поднимаем CatchUpScheduler заново на новом engine и watcher'ах.
        let scheduler = CatchUpScheduler(engine: engine, appSettings: appSettings)
        scheduler.register(notesWatcher)
        scheduler.register(gitWatcher)
        scheduler.start()
        catchUpScheduler = scheduler
        decayEngine.start()

        // 12. Перезапускаем tasks.jsonl watcher на новом engine (ingestion-state
        //     удалён в шаге 2 → читает с offset 0).
        watcher.stop()
        watcher = TasksJsonlWatcher(fileURL: appSettings.tasksJsonlPath, engine: engine)
        watcher.appSettings = appSettings
        watcher.start()

        // 13. Снимаем паузу со сцены — Settings-окно отобрало фокус, willResignActive
        //     поставил isPaused=true, и без явного снятия SKView не рисует новый мир
        //     до следующего фокус-цикла.
        scene.view?.isPaused = false
    }

    // MARK: - Legacy Migration

    /// Один раз переносит ~/Library/Application Support/CityDeveloper → CommitPyramid
    /// если старая папка существует и новая ещё не создана.
    /// После переименования проекта в open-source версии.
    private static func migrateLegacyApplicationSupport() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let old = base.appendingPathComponent("CityDeveloper", isDirectory: true)
        let new = base.appendingPathComponent("CommitPyramid", isDirectory: true)
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        do {
            try fm.moveItem(at: old, to: new)
            print("Migrated Application Support: CityDeveloper → CommitPyramid")
        } catch {
            ErrorsLog.write("Failed legacy migration: \(error)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        catchUpScheduler?.stop()
        watcher?.stop()
        decayEngine?.stop()
        if let engine = engine, engine.eventsSinceSnapshot >= 1 {
            engine.saveSnapshot()
        }
    }
}

// MARK: - NSView helper

private extension NSView {
    /// Рекурсивно ищет первый SKView в иерархии subview'ов.
    func findSpriteKitView() -> SKView? {
        if let skView = self as? SKView { return skView }
        for subview in subviews {
            if let found = subview.findSpriteKitView() { return found }
        }
        return nil
    }
}
