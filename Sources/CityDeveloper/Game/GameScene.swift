import SpriteKit
import AppKit
import Carbon.HIToolbox

final class GameScene: SKScene {

    weak var engine: CityEngine?
    weak var bridge: SceneBridge?
    weak var appSettings: AppSettings?

    private let world = SKNode()

    /// Internal accessor for CitizenManager to attach citizen nodes.
    var worldNode: SKNode { world }
    private let cameraNode = SKCameraNode()
    private let tileWidth: CGFloat = 64
    private let tileHeight: CGFloat = 32

    // MARK: - Camera zoom/pan constants (TASK-029)
    /// Размер карты в тайлах по стороне. F-15; AC-2.
    /// После TASK-028/030: заменить на чтение из источника биом-карты (один computed-property).
    private let mapTilesPerSide: Int = 256
    /// Минимальный масштаб cameraNode (ближний зум, детальный план). AC-1.
    /// ВНИМАНИЕ: меньшее xScale = бо́льший зум-ин (ближе). 0.15 — нижняя граница.
    private let minZoomIn: CGFloat = 0.15

    private var didAttach = false
    private var unitNodes: [UUID: SKNode] = [:]
    private var districtNodes: [String: SKNode] = [:]

    // MARK: - Debug overlay (TASK-025)
    private var debugOverlayEnabled: Bool = false

    private var inspector: SKNode?
    private static let unitIdKey = "unitId"
    /// Ключ userData для хранения projectId ноды юнита.
    /// Используется в handleRuinsCleared для быстрого поиска нод старого проекта.
    static let projectIdKey = "projectId"

    var lifeSim: LifeSimulationManager?
    var citizenManager: CitizenManager?

    /// Шумовая карта мира (TASK-026). Задаётся из AppDelegate после создания сцены.
    var worldMap: NoiseMap?

    /// Рендер биомов (TASK-028). Хранится для rebuild при TASK-030 (сброс карты).
    private var biomeRenderer: BiomeRenderer?

    /// F-21: сеть дорог (магистраль + ветки кварталов).
    let roadNetwork = RoadNetwork()
    /// Визуальные ноды дорог по grid-координате (для cleanup при reset).
    private var roadNodes: [GridPoint: SKNode] = [:]
    /// Биом-ридер, кэшированный для (re)build дорожной сети.
    private var biomeReader: BiomeMapReader?

    override func didMove(to view: SKView) {
        // За краями тайл-карты — цвет травы (fallback при pan/zoom за границу).
        // Lawn — временная подложка; заменена BiomeRenderer (TASK-028).
        // Реальные границы карты (256×256 тайлов) = 16384×8192 px — учтены в worldBoundsInScene.
        backgroundColor = Palette.nileGreen
        scaleMode = .resizeFill

        camera = cameraNode
        cameraNode.position = .zero
        addChild(cameraNode)

        // TASK-028: рендер биомов через BiomeRenderer (SKTileMapNode + overlay).
        // Если NoiseMap доступна — классифицируем биомы и строим рендер.
        // Fallback при отсутствии worldMap — Palette.nileGreen backgroundColor (уже выше).
        if let noiseMap = worldMap {
            do {
                let biomeMap = try BiomeClassifier.classify(world: noiseMap)

                // BUG-006: логируем распределение биомов для диагностики тюнинга классификатора.
                let dist = biomeMap.cells.reduce(into: [BiomeKind: Int]()) { $0[$1, default: 0] += 1 }
                let total = biomeMap.cells.count
                let distStr = BiomeKind.allCases
                    .compactMap { b -> String? in
                        guard let cnt = dist[b] else { return nil }
                        let pct = String(format: "%.1f%%", Double(cnt) / Double(total) * 100)
                        return "\(b.rawValue):\(pct)"
                    }
                    .joined(separator: " ")
                ErrorsLog.write("BiomeDistribution [\(dist.count) kinds]: \(distStr)")

                let renderer = BiomeRenderer(map: biomeMap)
                renderer.attach(to: world)
                biomeRenderer = renderer
                // TASK-035 F-16: передаём биом-карту в CityEngine для UnitPlanner.
                engine?.biomeReader = biomeMap
                biomeReader = biomeMap

                // Бесшовный фон за краями тайл-карты: большой спрайт цвета доминантного
                // краевого биома — убирает «ромб с зелёным фоном» при отдалении.
                let edgeColor = dominantEdgeBiomeColor(biomeMap, cols: mapTilesPerSide, rows: mapTilesPerSide)
                backgroundColor = edgeColor
                let bg = SKSpriteNode(color: edgeColor, size: CGSize(width: 400_000, height: 400_000))
                bg.zPosition = -2000
                world.addChild(bg)
            } catch {
                ErrorsLog.write("GameScene: BiomeClassifier failed (\(error)) — fallback to plain background")
            }
        } else {
            ErrorsLog.write("GameScene: worldMap is nil — biome tile map skipped, using plain nileGreen background")
        }

        addChild(world)

        didAttach = true

        // F-21: построить магистраль ПОСЛЕ biomeRenderer и до восстановления юнитов,
        // чтобы существующие кварталы (из snapshot) получили свои ветки.
        buildRoadNetwork()
        engine?.roadNetwork = roadNetwork
        engine?.syncRoadNetworkPlans()

        if let engine {
            for project in engine.state.projects.values {
                drawDistrictMarker(for: project)
            }
            for unit in engine.state.units.values {
                if let project = engine.state.projects[unit.projectId] {
                    drawUnit(unit, project: project, animated: false)
                }
            }
        }

        // Инициализация LifeSimulationManager (F-05)
        let sim = LifeSimulationManager()
        sim.engine = engine
        sim.scene = self
        lifeSim = sim
        sim.start()

        // Инициализация CitizenManager (F-10) с задержкой 1.5 сек
        let cm = CitizenManager()
        cm.engine = engine
        cm.scene = self
        cm.roadNetwork = roadNetwork
        citizenManager = cm
        run(SKAction.sequence([
            SKAction.wait(forDuration: 1.5),
            SKAction.run { [weak cm] in cm?.start() }
        ]))

        // При уходе в фон — замораживаем анимации.
        // Возобновление — через WindowModeManager.onModeChange (единственный источник истины).
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak view] _ in
            view?.isPaused = true
        }

        // TASK-025: debug overlay через env-флаг (CITY_DEBUG_OVERLAY=1)
        if ProcessInfo.processInfo.environment["CITY_DEBUG_OVERLAY"] != nil {
            setDebugOverlay(enabled: true)
        }
    }

    // MARK: - Debug overlay toggle (TASK-025)

    private func setDebugOverlay(enabled: Bool) {
        debugOverlayEnabled = enabled
        view?.showsFPS = enabled
        view?.showsDrawCount = enabled
        view?.showsNodeCount = enabled
    }

    /// Хоткей ⌘⌥F — toggle debug overlay (FPS / drawCount / nodeCount).
    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_ANSI_F,
           event.modifierFlags.contains([.command, .option]) {
            setDebugOverlay(enabled: !debugOverlayEnabled)
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - BUG-005: Reset support

    /// Clears all visual nodes and re-draws the city from the current engine state.
    /// Called after AppDelegate.resetCity(replaySince:) rebuilds the engine and worldMap.
    func resetScene() {
        // Remove all children and rebuild from scratch.
        world.removeAllChildren()
        unitNodes.removeAll()
        districtNodes.removeAll()
        inspector = nil

        // F-21: сбрасываем дорожную сеть и её ноды.
        roadNetwork.reset()
        roadNodes.values.forEach { $0.removeFromParent() }
        roadNodes.removeAll()

        lifeSim?.stop()
        lifeSim = nil
        citizenManager?.stop()
        citizenManager = nil
        biomeRenderer = nil
        biomeReader = nil

        // Re-render biome tile map with the new worldMap.
        if let noiseMap = worldMap,
           let biomeMap = try? BiomeClassifier.classify(world: noiseMap) {
            let renderer = BiomeRenderer(map: biomeMap)
            renderer.attach(to: world)
            biomeRenderer = renderer
            engine?.biomeReader = biomeMap
            biomeReader = biomeMap
        }

        // F-21: перестроить дорожную сеть после новой биом-карты.
        buildRoadNetwork()
        engine?.roadNetwork = roadNetwork
        engine?.syncRoadNetworkPlans()

        // Draw any existing state (likely empty after reset, but future-safe).
        if let engine {
            for project in engine.state.projects.values {
                drawDistrictMarker(for: project)
            }
            for unit in engine.state.units.values {
                if let project = engine.state.projects[unit.projectId] {
                    drawUnit(unit, project: project, animated: false)
                }
            }
        }

        // Restart simulation managers.
        let sim = LifeSimulationManager()
        sim.engine = engine
        sim.scene = self
        lifeSim = sim
        sim.start()

        let cm = CitizenManager()
        cm.engine = engine
        cm.scene = self
        cm.roadNetwork = roadNetwork
        citizenManager = cm
        run(SKAction.sequence([
            SKAction.wait(forDuration: 1.5),
            SKAction.run { [weak cm] in cm?.start() }
        ]))
    }

    func placeUnit(_ unit: UnitState, project: ProjectState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.didAttach else { return }
            self.drawUnit(unit, project: project)
            self.lifeSim?.handleUnitBuilt(unit, project)
        }
    }

    func markDistrict(project: ProjectState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.didAttach else { return }
            // План дорог квартала уже сгенерирован в CityEngine.applyTaskCompleted
            // на isNewProject; визуально дорога будет появляться задача за задачей через drawUnit.
            self.drawDistrictMarker(for: project)
        }
    }

    /// F-06 ruin-priority: визуальная анимация расчистки руин при атомарной замене District.
    ///
    /// State уже финальный (старый District удалён в CityEngine.applyTaskCompleted) к моменту
    /// вызова этого метода. Анимация — чисто визуальный слой, в snapshot не попадает.
    ///
    /// Тайминг (≤5 сек, AC): fadeOut 2.0 сек ∥ dust 1.5 сек → wait 2.0 сек → district-маркер.
    /// Итого ~2–2.5 сек на появление маркера — укладывается в окно 3–5 сек с запасом.
    ///
    /// Edge cases:
    /// - Quit во время анимации: state уже финальный, snapshot при terminate сохраняет чистый state.
    ///   При следующем запуске replay восстанавливает state без повтора анимации.
    /// - Две параллельных анимации (два новых проекта в одном tail-чанке): анимации идут на разных
    ///   точках сцены, не пересекаются. State обновлён последовательно до вызова любой анимации.
    /// - Snapshot во время анимации: видит финальное state (новый District создан, старый удалён).
    func handleRuinsCleared(oldProjectId: String, newProject: ProjectState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.didAttach else { return }

            // 1. Найти ноды старого проекта через userData[projectIdKey].
            //    engine.state.units уже подчищен, но ноды на сцене ещё есть — их фейдим.
            let oldNodeEntries = self.unitNodes.filter { (_, node) in
                (node.userData?[Self.projectIdKey] as? String) == oldProjectId
            }

            // fadeOut(2.0 сек) + removeFromParent + очистка из unitNodes
            let fadeOutAction = SKAction.fadeOut(withDuration: 2.0)
            fadeOutAction.timingMode = .easeIn
            for (uid, node) in oldNodeEntries {
                node.run(SKAction.sequence([fadeOutAction, .removeFromParent()]))
                self.unitNodes.removeValue(forKey: uid)
            }

            // 2. Dust-визуал на позиции нового квартала (~1.5 сек).
            //    Несколько частиц серым кругом с scale/fade анимацией.
            let dustPosition = self.isoPosition(grid: newProject.districtOrigin)
            for i in 0..<5 {
                let dustNode = SKSpriteNode(color: .gray, size: CGSize(width: 8, height: 8))
                dustNode.alpha = 0
                let angle = CGFloat(i) * (2 * .pi / 5)
                let radius: CGFloat = 20
                dustNode.position = CGPoint(
                    x: dustPosition.x + cos(angle) * radius,
                    y: dustPosition.y + sin(angle) * radius
                )
                dustNode.zPosition = 5000

                let dustAnim = SKAction.group([
                    SKAction.sequence([
                        SKAction.fadeIn(withDuration: 0.3),
                        SKAction.wait(forDuration: 0.9),
                        SKAction.fadeOut(withDuration: 0.3)
                    ]),
                    SKAction.sequence([
                        SKAction.scale(to: 1.5, duration: 0.75),
                        SKAction.scale(to: 0.5, duration: 0.75)
                    ])
                ])
                self.world.addChild(dustNode)
                dustNode.run(SKAction.sequence([dustAnim, .removeFromParent()]))
            }

            // 3. Удалить старый district-маркер.
            self.districtNodes[oldProjectId]?.removeFromParent()
            self.districtNodes[oldProjectId] = nil

            // 4. После wait(2.0) — нарисовать маркер нового района.
            //    Это ЕДИНСТВЕННЫЙ вызов drawDistrictMarker для нового проекта в ruins-ветке:
            //    CityEngine.applyTaskCompleted не вызывает onProjectCreated в этой ветке.
            self.world.run(SKAction.sequence([
                SKAction.wait(forDuration: 2.0),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    // План дорог переиспользуемого квартала сгенерирован CityEngine.
                    self.drawDistrictMarker(for: newProject)
                }
            ]))
        }
    }

    private func drawUnit(_ unit: UnitState, project: ProjectState, animated: Bool = true) {
        let basePos = isoPosition(grid: unit.position)
        let gridSize = unit.kind.size
        let spanW = CGFloat(gridSize.width)
        let spanH = CGFloat(gridSize.height)
        // For multi-cell footprints, shift the sprite up so its base aligns with
        // the bottom-front corner (anchor = bottom-centre of the full footprint).
        // y-offset accounts for height dimension in isometric space.
        let pos = CGPoint(
            x: basePos.x,
            y: basePos.y + CGFloat(gridSize.height - 1) * tileHeight / 2
        )

        let node = UnitSprites.makeStageNode(unit: unit, stageOverride: project.stage)
        // Scale uniformly by the larger dimension so the sprite fills the footprint.
        let scale = max(spanW, spanH)
        node.setScale(scale)
        node.position = pos
        // z-sort: lower-front corner = (x + y + (w-1) + (h-1)); negate for painter's order.
        node.zPosition = -CGFloat(unit.position.x + unit.position.y + gridSize.width + gridSize.height - 2)
        node.userData = node.userData ?? NSMutableDictionary()
        node.userData?[Self.unitIdKey] = unit.id
        node.userData?[Self.projectIdKey] = unit.projectId

        world.addChild(node)
        unitNodes[unit.id] = node

        if animated {
            node.setScale(scale * 0.4)
            node.alpha = 0
            let group = SKAction.group([
                SKAction.fadeIn(withDuration: 0.4),
                SKAction.scale(to: scale, duration: 0.5),
            ])
            group.timingMode = .easeOut
            node.run(group)
        }

        // При replay — применяем decay overlay сразу если проект имеет decayLevel > 0
        if let project = engine?.state.projects[unit.projectId], project.decayLevel > 0 {
            applyDecay(level: project.decayLevel, toUnit: unit, animated: false)
        }
    }

    // MARK: - Stage tier visual (TASK-019 F-08)

    /// Вызывается из AppDelegate при live-тике stage-up квартала.
    /// При catch-up (replayFromLog) callback не срабатывает — drawUnit уже рисует с целевым stage.
    ///
    /// Edge cases (все явно обработаны в swapStageSprite):
    /// - Руина (ruinNode) — skip, визуал руины приоритетен.
    /// - Legacy-нода без name="building" — skip (старый makeNode без именования).
    /// - 500+ юнитов: все SKAction запускаются параллельно, общее окно ≤0.5 сек.
    func handleProjectStageChanged(projectId: String, oldStage: Int, newStage: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.didAttach,
                  let engine = self.engine,
                  let project = engine.state.projects[projectId] else { return }
            for uid in project.unitIds {
                guard let node = self.unitNodes[uid] else { continue }
                self.swapStageSprite(in: node, newStage: newStage)
            }
        }
    }

    /// TASK-049 F-25: при миграции template — дорисовать новые road-слоты
    /// (slot.role == .road, которые есть в nextTemplate, но не было в currentTemplate).
    /// Пустые тайлы земли других role'ов рендерятся естественно при заполнении
    /// последующими task_completed (через slot-placement в UnitPlanner).
    func handleTemplateMigrated(projectId: String, fromTemplate: String, toTemplate: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.didAttach,
                  let engine = self.engine,
                  let project = engine.state.projects[projectId],
                  let current = DistrictTemplateCatalog.byName(fromTemplate),
                  let next = DistrictTemplateCatalog.byName(toTemplate) else { return }
            let origin = project.districtOrigin
            // Абсолютные координаты road-слотов в каждом template.
            let currentRoadCells: Set<GridPoint> = Set(current.slots
                .filter { $0.role == .road }
                .map { GridPoint(x: origin.x + $0.x, y: origin.y + $0.y) })
            let nextRoadCells: Set<GridPoint> = Set(next.slots
                .filter { $0.role == .road }
                .map { GridPoint(x: origin.x + $0.x, y: origin.y + $0.y) })
            // Diff: новые road-слоты, которых не было раньше.
            let added = Array(nextRoadCells.subtracting(currentRoadCells))
            if !added.isEmpty {
                // drawAddedRoadCells — публичный wrapper уже делает async + didAttach guard;
                // здесь вызываем напрямую т.к. уже на main queue внутри async.
                self.drawRoadCells(added)
            }
        }
    }

    // MARK: - TASK-050 F-25: Era-up visual

    /// TASK-050 F-25: золотая вспышка по контуру квартала на era-up.
    /// Длительность 2 сек: fadeIn 0.3 → wait 1.4 → fadeOut 0.3.
    /// Контур = iso-ромб квартала width×height (4 угла), цвет UI gold.
    func handleEraAdvanced(projectId: String, era: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.didAttach,
                  let engine = self.engine,
                  let project = engine.state.projects[projectId] else { return }
            let template = project.templateName
                .flatMap { DistrictTemplateCatalog.byName($0) }
            let w = template?.width ?? 16
            let h = template?.height ?? 16
            let origin = project.districtOrigin
            // 4 угла квартала в grid-координатах:
            let corners = [
                GridPoint(x: origin.x,           y: origin.y),
                GridPoint(x: origin.x + w - 1,   y: origin.y),
                GridPoint(x: origin.x + w - 1,   y: origin.y + h - 1),
                GridPoint(x: origin.x,           y: origin.y + h - 1),
            ]
            let scenePoints = corners.map { self.isoPosition(grid: $0) }
            let path = CGMutablePath()
            path.move(to: scenePoints[0])
            for i in 1..<scenePoints.count {
                path.addLine(to: scenePoints[i])
            }
            path.closeSubpath()
            let outline = SKShapeNode(path: path)
            outline.strokeColor = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
            outline.lineWidth = 3
            outline.fillColor = .clear
            outline.alpha = 0
            outline.zPosition = 9998
            self.world.addChild(outline)
            outline.run(.sequence([
                .fadeIn(withDuration: 0.3),
                .wait(forDuration: 1.4),
                .fadeOut(withDuration: 0.3),
                .removeFromParent()
            ]))
        }
    }

    /// Заменяет building-child в ноде юнита на категориальный tier-спрайт для newStage.
    /// Cross-fade ≤0.5 сек, параллельно для всех нод квартала.
    private func swapStageSprite(in node: SKNode, newStage: Int) {
        // Guard: руина — skip, визуал руины приоритетен (decay 4).
        if node.childNode(withName: "ruinNode") != nil { return }

        // Guard: нет building-child — legacy-нода без name= (создана старым makeNode).
        guard let oldBuilding = node.childNode(withName: "building") else { return }

        // Получаем unit state по unitId из userData (нужен kind для makeKindBuilding).
        guard let unitId = node.userData?[UnitSprites.unitIdKey] as? UUID,
              let unit = engine?.state.units[unitId.uuidString] else { return }

        // Строим новый building с alpha=0 (TASK-032: kind-specific, а не категориальный).
        let newBuilding = UnitSprites.makeKindBuilding(unit: unit, stage: newStage)
        newBuilding.name = "building"
        newBuilding.alpha = 0
        node.addChild(newBuilding)

        // Параллельный кросс-фейд: fadeOut старого + removeFromParent, fadeIn нового.
        // Общее визуальное окно ≤0.5 сек (AC F-08).
        let fadeOut = SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ])
        fadeOut.timingMode = .easeOut
        let fadeIn = SKAction.fadeIn(withDuration: 0.5)
        fadeIn.timingMode = .easeOut
        oldBuilding.run(fadeOut)
        newBuilding.run(fadeIn)
        // Примечание: decay-overlay (name == DecayVisuals.overlayKey) живёт на parent-контейнере
        // и продолжает накладываться поверх нового building после swap — это ожидаемо.
    }

    // MARK: - Unit evolution visual (TASK-034 F-16)

    /// Вызывается из AppDelegate при live-тике эволюции юнита.
    /// При catch-up (replayFromLog) callback не срабатывает — drawUnit уже рисует с актуальным kind.
    ///
    /// Edge cases:
    /// - Руина (ruinNode) — skip, визуал руины приоритетен.
    /// - Legacy-нода без name="building" — skip.
    /// - state.units[unitId] уже содержит новый kind (apply применился до callback).
    func handleUnitEvolved(unitId: UUID, from: UnitKind, to: UnitKind, projectId: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.didAttach,
                  let engine = self.engine,
                  let unit = engine.state.units[unitId.uuidString],
                  let node = self.unitNodes[unitId] else { return }
            self.swapEvolvedSprite(in: node, unit: unit)
        }
    }

    /// Заменяет building-child в ноде юнита на kind-specific спрайт для нового kind.
    /// Cross-fade ≤0.5 сек, механизм идентичен swapStageSprite (F-08).
    /// Намеренный дубликат ~15 строк — см. комментарий в техразборе TASK-034:
    /// рефакторинг общего helper'а отложен до TASK-036, чтобы не трогать TASK-019-код.
    private func swapEvolvedSprite(in node: SKNode, unit: UnitState) {
        // Guard: руина — skip, визуал руины приоритетен (decay 4).
        if node.childNode(withName: "ruinNode") != nil { return }

        // Guard: нет building-child — legacy-нода без name= (создана старым makeNode).
        guard let oldBuilding = node.childNode(withName: "building") else { return }

        // Строим новый building по актуальному unit.kind (уже содержит to-kind после apply).
        let newBuilding = UnitSprites.makeKindBuilding(unit: unit, stage: unit.tier)
        newBuilding.name = "building"
        newBuilding.alpha = 0
        node.addChild(newBuilding)

        // Параллельный кросс-фейд: fadeOut старого + removeFromParent, fadeIn нового.
        // Общее визуальное окно ≤0.5 сек (AC F-16).
        let fadeOut = SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ])
        fadeOut.timingMode = .easeOut
        let fadeIn = SKAction.fadeIn(withDuration: 0.5)
        fadeIn.timingMode = .easeOut
        oldBuilding.run(fadeOut)
        newBuilding.run(fadeIn)
        // Примечание: decay-overlay живёт на parent-контейнере и остаётся поверх
        // нового building — ожидаемое поведение (декай не сбрасывается эволюцией).
    }

    // MARK: - Decay visual

    /// Вызывается из AppDelegate через engine.onDecayChanged.
    /// Обновляет визуал всех юнитов данного проекта согласно текущему decayLevel.
    func applyDecayToProject(_ projectId: String) {
        guard let engine else { return }
        guard let project = engine.state.projects[projectId] else { return }
        let level = project.decayLevel

        for unitId in project.unitIds {
            guard let unit = engine.state.units[unitId.uuidString] else { continue }
            applyDecay(level: level, toUnit: unit, animated: true)
        }
    }

    /// Применяет (или снимает) decay overlay к ноде конкретного юнита.
    /// - Parameters:
    ///   - level: уровень decay (0 = снять все overlay'и)
    ///   - unit: состояние юнита
    ///   - animated: если true — плавный переход 1.5 сек easeOut; false — мгновенно (replay)
    private func applyDecay(level: Int, toUnit unit: UnitState, animated: Bool) {
        guard let node = unitNodes[unit.id] else { return }

        // decay 4: заменяем всю ноду на руины
        if level == 4 {
            applyRuins(toNode: node, unitKind: unit.kind, animated: animated)
            return
        }

        // Для decay 0-3: удаляем старый overlay, добавляем новый
        node.childNode(withName: DecayVisuals.overlayKey)?.removeFromParent()

        // Tone-down: если decay >= 1 — затемняем базовый узел
        applyToneDown(toNode: node, level: level, animated: animated)

        guard let overlay = DecayVisuals.makeOverlay(level: level, originalKind: unit.kind) else {
            return
        }

        if animated {
            overlay.alpha = 0
            node.addChild(overlay)
            let appear = SKAction.fadeIn(withDuration: 1.5)
            appear.timingMode = .easeOut
            overlay.run(appear)
        } else {
            node.addChild(overlay)
        }
    }

    /// Заменяет ноду юнита на руины (decay 4).
    /// Вся прежняя нода скрывается, поверх размещается руина.
    private func applyRuins(toNode node: SKNode, unitKind: UnitKind, animated: Bool) {
        // Убрать старый overlay (если был)
        node.childNode(withName: DecayVisuals.overlayKey)?.removeFromParent()

        // Если руина уже применена — не дублируем
        if node.childNode(withName: "ruinNode") != nil { return }

        let ruin = DecayVisuals.decay4Ruin(originalKind: unitKind)
        ruin.name = "ruinNode"

        if animated {
            // Скрываем здание, показываем руины
            let hideBuilding = SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.5),
            ])
            // Скрываем все дочерние узлы (само здание)
            for child in node.children {
                if child.name != "ruinNode" {
                    child.run(hideBuilding)
                }
            }
            ruin.alpha = 0
            node.addChild(ruin)
            let appear = SKAction.sequence([
                SKAction.wait(forDuration: 0.3),
                SKAction.fadeIn(withDuration: 1.0),
            ])
            appear.timingMode = .easeOut
            ruin.run(appear)
        } else {
            // При replay — прячем здание сразу, показываем руины
            for child in node.children {
                if child.name != "ruinNode" {
                    child.alpha = 0
                }
            }
            node.addChild(ruin)
        }
    }

    /// Применяет tone-down эффект (затемнение узла) при decay >= 1.
    /// При restore (level == 0) — восстанавливает нормальный цвет.
    private func applyToneDown(toNode node: SKNode, level: Int, animated: Bool) {
        // Tone-down только для decay 1-2; decay 3 — fire/smoke перекрывает, restore (0) — полная яркость
        let targetAlpha: CGFloat = (level == 1 || level == 2) ? 0.88 : 1.0

        if animated {
            // Restore: плавное возвращение к норме (3 сек)
            let duration: TimeInterval = level == 0 ? 3.0 : 1.5
            let fade = SKAction.fadeAlpha(to: targetAlpha, duration: duration)
            fade.timingMode = .easeOut
            // Затемняем дочерние элементы здания (не overlay)
            for child in node.children where child.name != DecayVisuals.overlayKey && child.name != "ruinNode" {
                child.run(fade, withKey: "decayTone")
            }
        } else {
            for child in node.children where child.name != DecayVisuals.overlayKey && child.name != "ruinNode" {
                child.alpha = targetAlpha
            }
        }
    }

    // MARK: - F-21: Road network rendering

    /// Строит магистраль на основе текущего biomeReader. No-op если ридер не задан.
    private func buildRoadNetwork() {
        guard let br = biomeReader else { return }
        roadNetwork.buildMainRoad(
            cols: mapTilesPerSide,
            rows: mapTilesPerSide,
            biomeReader: br
        )
        drawRoadCells(roadNetwork.mainRoadCells)
    }

    /// Возвращает fillColor доминантного биома вдоль периметра карты.
    private func dominantEdgeBiomeColor(_ map: BiomeMapReader, cols: Int, rows: Int) -> SKColor {
        var counts: [BiomeKind: Int] = [:]
        let step = max(1, cols / 32)  // сэмплируем ~32 точки на сторону
        for x in stride(from: 0, to: cols, by: step) {
            counts[map.biome(atX: x, y: 0), default: 0] += 1
            counts[map.biome(atX: x, y: rows - 1), default: 0] += 1
        }
        for y in stride(from: 0, to: rows, by: step) {
            counts[map.biome(atX: 0, y: y), default: 0] += 1
            counts[map.biome(atX: cols - 1, y: y), default: 0] += 1
        }
        let dominant = counts.max(by: { $0.value < $1.value })?.key ?? .meadow
        return dominant.fillColor
    }

    /// Рисует клетки магистрали тем же визуалом, что и road-юниты квартала:
    /// тайл-земля (sandMid) + дорожное пятно сверху. Без тени.
    private func drawRoadCells(_ cells: [GridPoint]) {
        for cell in cells where roadNodes[cell] == nil {
            let node = UnitSprites.makeRoadCellNode()
            node.position = isoPosition(grid: cell)
            node.zPosition = -CGFloat(cell.x + cell.y) - 0.5
            world.addChild(node)
            roadNodes[cell] = node
        }
    }

    /// BUG-017/018: Публичный entry-point — вызывается из engine.onRoadCellsAdded
    /// когда реактивный extendDistrictPlan добавил клетки. Async на main, чтобы
    /// не задерживать ingest-цикл.
    func drawAddedRoadCells(_ cells: [GridPoint]) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.didAttach else { return }
            self.drawRoadCells(cells)
        }
    }

    private func drawDistrictMarker(for project: ProjectState) {
        if districtNodes[project.id] != nil { return }

        let label = SKLabelNode(text: project.name)
        label.fontName = "Helvetica-Bold"
        label.fontSize = 12
        label.fontColor = Palette.inkDark.withAlphaComponent(0.85)

        let bg = SKShapeNode(rectOf: CGSize(width: label.frame.width + 16, height: 22), cornerRadius: 6)
        bg.fillColor = Palette.parchment.withAlphaComponent(0.85)
        bg.strokeColor = Palette.inkDark.withAlphaComponent(0.3)
        bg.lineWidth = 1

        let container = SKNode()
        container.addChild(bg)
        container.addChild(label)
        container.position = isoPosition(grid: project.districtOrigin).applying(.init(translationX: 0, y: 70))
        container.zPosition = 9999
        world.addChild(container)
        districtNodes[project.id] = container

        if appSettings?.previewTemplateSilhouette == true,
           let templateName = project.templateName,
           let template = DistrictTemplateCatalog.byName(templateName) {
            drawTemplateSilhouette(project: project, template: template)
        }
    }

    private func drawTemplateSilhouette(project: ProjectState, template: DistrictTemplate) {
        let container = SKNode()
        container.zPosition = 5000  // поверх маркера, ниже UI
        container.alpha = 0.0
        let origin = project.districtOrigin
        for slot in template.slots {
            let path = CGMutablePath()
            for dx in 0..<slot.footprint.width {
                for dy in 0..<slot.footprint.height {
                    let cell = GridPoint(x: origin.x + slot.x + dx, y: origin.y + slot.y + dy)
                    let pos = isoPosition(grid: cell)
                    // diamond вокруг pos (геометрия идентична diamondPath())
                    path.move(to:    CGPoint(x: pos.x,                     y: pos.y + tileHeight / 2))
                    path.addLine(to: CGPoint(x: pos.x + tileWidth / 2,     y: pos.y))
                    path.addLine(to: CGPoint(x: pos.x,                     y: pos.y - tileHeight / 2))
                    path.addLine(to: CGPoint(x: pos.x - tileWidth / 2,     y: pos.y))
                    path.closeSubpath()
                }
            }
            let shape = SKShapeNode(path: path)
            shape.strokeColor = .systemBlue
            shape.fillColor = SKColor.systemBlue.withAlphaComponent(0.3)
            shape.lineWidth = 1.5
            container.addChild(shape)
        }
        world.addChild(container)
        let seq = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.2),
            SKAction.wait(forDuration: 2.6),
            SKAction.fadeAlpha(to: 0.0, duration: 0.2),
            SKAction.removeFromParent()
        ])
        container.run(seq)
    }

    func isoPosition(grid: GridPoint) -> CGPoint {
        let gx = CGFloat(grid.x)
        let gy = CGFloat(grid.y)
        // SKTileMapNode .isometric центрирует ромб на tileMap.position (.zero):
        //   тайл (col,row) рисуется при (col-row)*tw/2, (col+row - (rows-1))*th/2.
        // Подгоняем isoPosition под ту же систему: вычитаем (rows-1)*th/2.
        let centerOffsetY = CGFloat(mapTilesPerSide - 1) * tileHeight / 2
        let x = (gx - gy) * (tileWidth / 2)
        let y = (gx + gy) * (tileHeight / 2) - centerOffsetY
        return CGPoint(x: x, y: y)
    }

    private func diamondPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: tileHeight / 2))
        path.addLine(to: CGPoint(x: tileWidth / 2, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -tileHeight / 2))
        path.addLine(to: CGPoint(x: -tileWidth / 2, y: 0))
        path.closeSubpath()
        return path
    }

    // MARK: - Камера: pan / zoom

    // MARK: Camera bounds helpers (TASK-029)

    /// Мировые границы изометрической карты в координатах сцены.
    /// Центрирован по (0,0), как существующий биом-рендер.
    /// Размер: 256 тайлов → ширина 256*tileWidth=16384, высота 256*tileHeight=8192.
    /// После TASK-028/030: заменить mapTilesPerSide на computed из BiomeRenderer/worldMap.
    private var worldBoundsInScene: CGRect {
        let w = CGFloat(mapTilesPerSide) * tileWidth
        let h = CGFloat(mapTilesPerSide) * tileHeight
        return CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    }

    /// Зум-аут, при котором карта плотно ВПИСАНА в окно по короткой стороне —
    /// фон за ромбом не виден, по длинной стороне карта может выходить за экран
    /// (пан довешивает обзор). Используем min(fitX,fitY) (fill-mode), не max (fit-mode).
    /// Safe-fallback 13.0: 256 тайлов при tileHeight=32 на окне ~800 px.
    private var maxZoomOut: CGFloat {
        guard let view = view, view.bounds.width > 0, view.bounds.height > 0 else {
            return 13.0
        }
        let fitX = worldBoundsInScene.width  / view.bounds.width
        let fitY = worldBoundsInScene.height / view.bounds.height
        return min(fitX, fitY)
    }

    /// Чистая функция: возвращает позицию камеры, ограниченную так,
    /// чтобы visible-rect пересекался с миром минимум на 1 тайл. AC-4.
    /// Если карта вписывается в окно на текущем зуме — центрируем по оси.
    private func clampedPosition(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        guard let view = view else { return point }
        let visibleW = view.bounds.width  * scale
        let visibleH = view.bounds.height * scale
        let world = worldBoundsInScene
        var p = point
        if visibleW >= world.width {
            p.x = world.midX
        } else {
            let lo = world.minX - visibleW / 2 + tileWidth
            let hi = world.maxX + visibleW / 2 - tileWidth
            p.x = min(hi, max(lo, p.x))
        }
        if visibleH >= world.height {
            p.y = world.midY
        } else {
            let lo = world.minY - visibleH / 2 + tileHeight
            let hi = world.maxY + visibleH / 2 - tileHeight
            p.y = min(hi, max(lo, p.y))
        }
        return p
    }

    /// Удобный shortcut: подтянуть текущую позицию камеры под её текущий scale.
    private func clampCameraPosition() {
        cameraNode.position = clampedPosition(cameraNode.position, scale: cameraNode.xScale)
    }

    // MARK: Camera event handlers

    private var dragStarted = false
    private var dragMoved = false

    override func mouseDown(with event: NSEvent) {
        dragStarted = true
        dragMoved = false
    }

    override func mouseDragged(with event: NSEvent) {
        if dragStarted { dragMoved = true }
        cameraNode.position.x -= event.deltaX
        cameraNode.position.y += event.deltaY
        clampCameraPosition()
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStarted = false }
        if dragMoved { return }
        handleClick(at: event.location(in: self))
    }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas {
            // Two-finger trackpad → PAN
            cameraNode.position.x -= event.scrollingDeltaX
            cameraNode.position.y += event.scrollingDeltaY
            clampCameraPosition()
        } else {
            // Mouse wheel → ZOOM
            let delta = event.scrollingDeltaY
            let factor: CGFloat = 1.0 - delta * 0.02
            // Защита от NaN / Inf при экстремально быстром скролле. AC edge-case.
            guard factor.isFinite, factor > 0 else { return }
            let raw = cameraNode.xScale * factor
            let newScale = min(maxZoomOut, max(minZoomIn, raw))
            cameraNode.xScale = newScale
            cameraNode.yScale = newScale
            clampCameraPosition()
        }
    }

    /// Pinch / magnify (трекпад). AC-1,5.
    /// event.magnification > 0 — пальцы раздвинуты (зум-ин, уменьшаем xScale).
    /// Если направление инвертировано при ручной проверке — поменять знак.
    override func magnify(with event: NSEvent) {
        let factor: CGFloat = 1.0 - event.magnification
        guard factor.isFinite, factor > 0 else { return }
        let raw = cameraNode.xScale * factor
        let newScale = min(maxZoomOut, max(minZoomIn, raw))
        cameraNode.xScale = newScale
        cameraNode.yScale = newScale
        clampCameraPosition()
    }

    /// Один раз при первом валидном размере окна — отъезжаем на maxZoomOut,
    /// чтобы пользователь сразу видел всю карту.
    private var didInitialFit = false

    /// Пересчёт ограничений при изменении размера окна (resize / fullscreen). AC edge-case.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if !didInitialFit, let v = view, v.bounds.width > 0, v.bounds.height > 0 {
            cameraNode.xScale = maxZoomOut
            cameraNode.yScale = maxZoomOut
            cameraNode.position = .zero
            didInitialFit = true
        } else {
            let s = min(maxZoomOut, max(minZoomIn, cameraNode.xScale))
            cameraNode.xScale = s
            cameraNode.yScale = s
        }
        clampCameraPosition()
    }

    // MARK: - Инспектор

    private func handleClick(at location: CGPoint) {
        let hits = nodes(at: location)
        for node in hits {
            var current: SKNode? = node
            while let n = current {
                if n === inspector { return }
                if let uid = n.userData?[Self.unitIdKey] as? UUID,
                   let unit = engine?.state.units[uid.uuidString],
                   let project = engine?.state.projects[unit.projectId] {
                    showInspector(near: location, unit: unit, project: project)
                    return
                }
                current = n.parent
            }
        }
        hideInspector()

        // F-17: district diamond hit-test для пустых клеток квартала.
        // Выполняем только если кнопка моста и движок доступны.
        guard let engine = engine, let bridge = bridge else { return }

        var bestMatch: (projectId: String, dist: CGFloat)?
        for project in engine.state.projects.values where project.decayLevel < 4 {
            let center = isoPosition(grid: project.districtOrigin)
            let radius = max(2, Int(ceil(sqrt(Double(max(project.unitIds.count, 4))))))
            if isPointInDistrictDiamond(point: location, center: center, gridRadius: radius) {
                let dist = hypot(location.x - center.x, location.y - center.y)
                if bestMatch == nil || dist < bestMatch!.dist {
                    bestMatch = (project.id, dist)
                }
            }
        }

        if let match = bestMatch {
            // Переводим scene-координаты → координаты SKView (NSView, origin top-left).
            let viewPoint = self.view?.convert(location, from: self) ?? location
            bridge.inputRequest.send(.init(projectId: match.projectId, viewPoint: viewPoint))
        }
    }

    /// Изометрический diamond hit-test для квартала проекта.
    /// - Parameters:
    ///   - point: точка в координатах scene (SKScene)
    ///   - center: isoPosition центра квартала (districtOrigin) в координатах scene
    ///   - gridRadius: радиус в тайлах (минимум 2)
    private func isPointInDistrictDiamond(point: CGPoint, center: CGPoint, gridRadius: Int) -> Bool {
        // Diamond в изометрии: |dx|/(r*tw/2) + |dy|/(r*th/2) ≤ 1
        let tileW: CGFloat = 64, tileH: CGFloat = 32
        let dx = abs(point.x - center.x)
        let dy = abs(point.y - center.y)
        let nx = dx / (CGFloat(gridRadius) * tileW / 2)
        let ny = dy / (CGFloat(gridRadius) * tileH / 2)
        return nx + ny <= 1.0
    }

    func showInspector(near anchor: CGPoint, unit: UnitState, project: ProjectState) {
        hideInspector()
        // BUG-001: SpriteKit InspectorPanel отключён — используем SwiftUI InspectorOverlayCard.
        // let panel = InspectorPanel.build(unit: unit, project: project)
        // let unitNode = unitNodes[unit.id]
        // let anchorWorld = unitNode?.position ?? anchor
        // panel.position = CGPoint(x: anchorWorld.x + 80, y: anchorWorld.y + 40)
        // panel.zPosition = 100000
        // world.addChild(panel)
        // inspector = panel
        bridge?.selectedUnitInfo = (unit, project)
    }

    private func hideInspector() {
        // BUG-001: SpriteKit InspectorPanel отключён; inspector всегда nil.
        // inspector?.removeFromParent()
        // inspector = nil
        bridge?.selectedUnitInfo = nil
    }

    // MARK: - Публичные API для SceneBridge

    /// Плавно перемещает камеру к изометрической позиции gridPoint.
    /// Целевая точка ограничена clampedPosition — анимация уходит сразу к допустимой позиции. AC-4.
    func focusCamera(on grid: GridPoint, duration: TimeInterval) {
        let target = clampedPosition(isoPosition(grid: grid), scale: cameraNode.xScale)
        let move = SKAction.move(to: target, duration: duration)
        move.timingMode = .easeOut
        cameraNode.run(move)
    }

    /// Показывает попап-инспектор для юнита по UUID.
    /// Если юнит не найден — no-op (без падения).
    func showInspector(forUnitId id: UUID) {
        guard let unit = engine?.state.units[id.uuidString],
              let project = engine?.state.projects[unit.projectId] else { return }
        let pos = unitNodes[id]?.position ?? isoPosition(grid: unit.position)
        showInspector(near: pos, unit: unit, project: project)
    }

    /// Возвращает корневую ноду юнита по UUID (для LifeSimulationManager).
    func unitNode(for id: UUID) -> SKNode? {
        unitNodes[id]
    }

    // MARK: - Bench (TASK-025)

    /// Спавнит ровно `count` синтетических юнитов в радиусе 60 тайлов от центра.
    /// Детерминирован при одинаковом seed. Юниты НЕ попадают в engine.state — чисто визуальная нагрузка.
    func spawnBenchUnits(count: Int, seed: UInt64 = 42) {
        guard didAttach else { return }
        var rng = SeededGenerator(seed: seed)
        let kinds = UnitKind.allCases
        let stages = [1, 2, 3, 4, 5]
        let benchProject = ProjectState(
            id: "__bench__", name: "Bench",
            createdAt: Date(), lastActivityAt: Date(),
            taskCount: count, stage: 3, decayLevel: 0,
            lastDecayLogged: 0, districtOrigin: GridPoint(x: 0, y: 0),
            unitIds: [],
            templateName: nil,        // bench: visual-only, шаблон не используется
            templateFamily: nil,
            eraLevel: 0
        )
        for _ in 0..<count {
            let x = rng.nextInt(in: -60...60)
            let y = rng.nextInt(in: -60...60)
            let kind = kinds[rng.nextIndex(upTo: kinds.count)]
            let tier = stages[rng.nextIndex(upTo: stages.count)]
            let unit = UnitState(
                id: UUID(), projectId: benchProject.id,
                kind: kind, position: GridPoint(x: x, y: y),
                tier: tier, decayLevel: 0,
                taskTitle: nil, taskTs: Date(), taskSource: "bench"
            )
            drawUnit(unit, project: benchProject)
        }
    }
}

// MARK: - SeededGenerator (TASK-025)

/// Минимальный LCG-генератор для детерминированного bench-режима.
/// Не использует arc4random — одинаковый seed даёт одинаковую последовательность.
fileprivate struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        // LCG параметры (Knuth): m=2^64, a=6364136223846793005, c=1442695040888963407
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    mutating func nextIndex(upTo count: Int) -> Int {
        Int(next() % UInt64(count))
    }
}
