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
        let screen = NSScreen.main ?? NSScreen.screens.first!

        appSettings = AppSettings.load()

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
                journalController: journalWindowController
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
            NSLog("CityDeveloper: global hotkey is unavailable (already taken?)")
        }

        watcher = TasksJsonlWatcher(fileURL: appSettings.tasksJsonlPath, engine: engine)
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
        for spec in appSettings.notesSources {
            notesWatcher.register(spec)
        }
        scheduler.register(notesWatcher)

        // F-19: Git watcher. Register persisted repositories, then register
        // the watcher itself with CatchUpScheduler for periodic scans.
        gitWatcher = GitWatcher()
        gitWatcher.engine = engine
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
                onSave: { self.applySettings() }
            )
        }

        decayEngine.start()

        NSLog("CityDeveloper started. Data root: \(AppPaths.appSupport.path)")
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
