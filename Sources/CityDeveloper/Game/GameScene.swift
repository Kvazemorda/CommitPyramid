import SpriteKit
import AppKit

final class GameScene: SKScene {

    weak var engine: CityEngine?
    weak var bridge: SceneBridge?

    private let world = SKNode()

    /// Internal accessor for CitizenManager to attach citizen nodes.
    var worldNode: SKNode { world }
    private let cameraNode = SKCameraNode()
    private let tileWidth: CGFloat = 64
    private let tileHeight: CGFloat = 32

    private var didAttach = false
    private var unitNodes: [UUID: SKNode] = [:]
    private var districtNodes: [String: SKNode] = [:]

    private var inspector: SKNode?
    private static let unitIdKey = "unitId"

    var lifeSim: LifeSimulationManager?
    var citizenManager: CitizenManager?

    override func didMove(to view: SKView) {
        backgroundColor = Palette.skyDay
        scaleMode = .resizeFill

        camera = cameraNode
        cameraNode.position = .zero
        addChild(cameraNode)

        let lawn = SKSpriteNode(color: Palette.nileGreen, size: CGSize(width: 8000, height: 8000))
        lawn.position = .zero
        lawn.zPosition = -1000
        world.addChild(lawn)

        addChild(world)

        let watermark = SKLabelNode(text: "CityDeveloper")
        watermark.fontName = "Helvetica-Bold"
        watermark.fontSize = 14
        watermark.fontColor = Palette.inkDark.withAlphaComponent(0.35)
        watermark.position = CGPoint(x: 0, y: -10)
        watermark.zPosition = -500
        world.addChild(watermark)

        didAttach = true

        if let engine {
            for project in engine.state.projects.values {
                drawDistrictMarker(for: project)
            }
            for unit in engine.state.units.values {
                if let project = engine.state.projects[unit.projectId] {
                    drawUnit(unit, project: project)
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
            self.drawDistrictMarker(for: project)
        }
    }

    private func drawUnit(_ unit: UnitState, project: ProjectState) {
        let pos = isoPosition(grid: unit.position)
        let node = UnitSprites.makeNode(unit: unit)
        node.position = pos
        node.zPosition = -CGFloat(unit.position.x + unit.position.y)
        node.userData = NSMutableDictionary()
        node.userData?[Self.unitIdKey] = unit.id

        let appearScale: CGFloat = 0.4
        node.setScale(appearScale)
        node.alpha = 0
        world.addChild(node)
        unitNodes[unit.id] = node

        let group = SKAction.group([
            SKAction.fadeIn(withDuration: 0.4),
            SKAction.scale(to: 1.0, duration: 0.5),
        ])
        group.timingMode = .easeOut
        node.run(group)

        // При replay — применяем decay overlay сразу если проект имеет decayLevel > 0
        if let project = engine?.state.projects[unit.projectId], project.decayLevel > 0 {
            applyDecay(level: project.decayLevel, toUnit: unit, animated: false)
        }
    }

    // MARK: - Decay visual

    /// Вызывается из AppDelegate через engine.onDecayChanged.
    /// Обновляет визуал всех юнитов данного проекта согласно текущему decayLevel.
    func applyDecayToProject(_ projectId: String) {
        guard let engine else { return }
        guard let project = engine.state.projects[projectId] else { return }
        let level = project.decayLevel

        for unitId in project.unitIds {
            guard let unit = engine.state.units[unitId] else { continue }
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
    }

    func isoPosition(grid: GridPoint) -> CGPoint {
        let gx = CGFloat(grid.x)
        let gy = CGFloat(grid.y)
        let x = (gx - gy) * (tileWidth / 2)
        let y = (gx + gy) * (tileHeight / 2)
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
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStarted = false }
        if dragMoved { return }
        handleClick(at: event.location(in: self))
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        let factor: CGFloat = 1.0 - delta * 0.02
        let newScale = max(0.3, min(3.0, cameraNode.xScale * factor))
        cameraNode.xScale = newScale
        cameraNode.yScale = newScale
    }

    // MARK: - Инспектор

    private func handleClick(at location: CGPoint) {
        let hits = nodes(at: location)
        for node in hits {
            var current: SKNode? = node
            while let n = current {
                if n === inspector { return }
                if let uid = n.userData?[Self.unitIdKey] as? UUID,
                   let unit = engine?.state.units[uid],
                   let project = engine?.state.projects[unit.projectId] {
                    showInspector(near: location, unit: unit, project: project)
                    return
                }
                current = n.parent
            }
        }
        hideInspector()
    }

    func showInspector(near anchor: CGPoint, unit: UnitState, project: ProjectState) {
        hideInspector()
        let panel = InspectorPanel.build(unit: unit, project: project)
        let unitNode = unitNodes[unit.id]
        let anchorWorld = unitNode?.position ?? anchor
        panel.position = CGPoint(x: anchorWorld.x + 80, y: anchorWorld.y + 40)
        panel.zPosition = 100000
        world.addChild(panel)
        inspector = panel
        bridge?.selectedUnitInfo = (unit, project)
    }

    private func hideInspector() {
        inspector?.removeFromParent()
        inspector = nil
        bridge?.selectedUnitInfo = nil
    }

    // MARK: - Публичные API для SceneBridge

    /// Плавно перемещает камеру к изометрической позиции gridPoint.
    func focusCamera(on grid: GridPoint, duration: TimeInterval) {
        let target = isoPosition(grid: grid)
        let move = SKAction.move(to: target, duration: duration)
        move.timingMode = .easeOut
        cameraNode.run(move)
    }

    /// Показывает попап-инспектор для юнита по UUID.
    /// Если юнит не найден — no-op (без падения).
    func showInspector(forUnitId id: UUID) {
        guard let unit = engine?.state.units[id],
              let project = engine?.state.projects[unit.projectId] else { return }
        let pos = unitNodes[id]?.position ?? isoPosition(grid: unit.position)
        showInspector(near: pos, unit: unit, project: project)
    }

    /// Возвращает корневую ноду юнита по UUID (для LifeSimulationManager).
    func unitNode(for id: UUID) -> SKNode? {
        unitNodes[id]
    }
}
