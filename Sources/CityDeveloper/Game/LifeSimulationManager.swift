import SpriteKit

/// Менеджер лёгкой симуляции жизни квартала (F-05).
/// Owned by GameScene. Держит weak-ссылки на engine и scene.
/// Не пишет никаких событий в EventLog — это инвариант.
final class LifeSimulationManager {

    weak var engine: CityEngine?
    weak var scene: GameScene?

    /// root-нода анимаций для каждого юнита (по UUID).
    /// При detach — одним removeFromParent удаляется вся анимация.
    private(set) var attached: [UUID: SKNode] = [:]

    /// Snapshot UUID юнитов из последнего тика — для cleanup удалённых юнитов.
    private var snapshot: Set<UUID> = []

    // MARK: - Жизненный цикл

    func start() {
        scheduleTick()
    }

    func stop() {
        scene?.removeAction(forKey: "lifeSimTick")
    }

    private func scheduleTick() {
        let action = SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: 2.0),
            SKAction.run { [weak self] in self?.tick() }
        ]))
        scene?.run(action, withKey: "lifeSimTick")
    }

    // MARK: - Триггер: новый юнит

    /// Вызывается из GameScene.placeUnit после drawUnit.
    func handleUnitBuilt(_ unit: UnitState, _ project: ProjectState) {
        guard shouldAnimate(unit: unit, project: project) else { return }
        let delay = Double.random(in: 0...10)
        scene?.run(SKAction.wait(forDuration: delay), completion: { [weak self] in
            self?.attachAnimation(to: unit)
        })
    }

    // MARK: - tick: обновление по stage/decay

    private func tick() {
        guard let engine = engine else { return }
        var currentIds = Set<UUID>()

        for (_, unit) in engine.state.units {
            guard let project = engine.state.projects[unit.projectId] else { continue }
            currentIds.insert(unit.id)
            let isAttached = attached[unit.id] != nil
            let shouldAnim = shouldAnimate(unit: unit, project: project)
            if shouldAnim && !isAttached {
                attachAnimation(to: unit)
            } else if !shouldAnim && isAttached {
                detachAnimation(from: unit.id)
            }
        }

        // Cleanup: юниты удалённые из state
        for id in Array(attached.keys) where !currentIds.contains(id) {
            detachAnimation(from: id)
        }

        snapshot = currentIds
    }

    // MARK: - Условие анимации

    /// Все типы кроме .road анимируются при stage >= 2 и decay < 2.
    private func shouldAnimate(unit: UnitState, project: ProjectState) -> Bool {
        guard unit.kind != .road else { return false }
        return project.stage >= 2 && project.decayLevel < 2
    }

    // MARK: - Attach / Detach

    private func attachAnimation(to unit: UnitState) {
        guard let scene = scene,
              let unitNode = scene.unitNode(for: unit.id),
              attached[unit.id] == nil  // не дублировать
        else { return }

        let anim: SKNode
        switch unit.kind {
        case .workshop:  anim = makeWorkshopAnimation()
        case .warehouse: anim = makeWarehouseTradingStacks()
        case .market:    anim = makeMarketAnimation()
        case .raw:       anim = makeRawPitCycle()
        case .shack:     anim = makeShackAnimation()
        case .house:     anim = makeHouseAnimation()
        case .villa:     anim = makeVillaAnimation()
        case .well:      anim = makeWellAnimation()
        case .forum:     anim = makeForumAnimation()
        case .temple:    anim = makeTempleAnimation()
        case .obelisk:   anim = makeObeliskAnimation()
        case .road:      return  // road исключён
        default:         return  // TODO TASK-032/TASK-040: анимации для новых юнитов
        }

        anim.name = "lifeSimAnim"
        unitNode.addChild(anim)
        attached[unit.id] = anim
    }

    /// Снимает анимацию с fade-out 1 сек. Удаление из словаря — в completion handler.
    private func detachAnimation(from id: UUID) {
        guard let node = attached[id] else { return }
        node.removeAllActions()
        node.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 1.0),
            SKAction.run { [weak self] in self?.attached.removeValue(forKey: id) },
            SKAction.removeFromParent()
        ]))
        // НЕ удаляем из словаря сразу — completion handler делает это после fade
    }

    // MARK: - Workshop: дым из трубы + периодические искры

    private func makeWorkshopAnimation() -> SKNode {
        let container = SKNode()

        // Дым: несколько анимированных частиц поднимающихся вверх
        for i in 0..<4 {
            let smokeParticle = Self.makeSmokeParticle(index: i, offsetX: -6, baseY: 36)
            container.addChild(smokeParticle)
        }

        // Искры с интервалом 5-15 сек
        let sparkSequence = SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: Double.random(in: 5...15)),
            SKAction.run { [weak container] in
                guard let container = container else { return }
                let burst = LifeSimulationManager.makeSparkBurst(at: CGPoint(x: -6, y: 38))
                container.addChild(burst)
            }
        ]))
        container.run(sparkSequence)
        return container
    }

    // MARK: - Warehouse: анимированные «торговые» штабели

    private func makeWarehouseTradingStacks() -> SKNode {
        let container = SKNode()
        for x in [-6, 6] {
            let stack = IsoBuilder.cube(
                footprint: CGSize(width: 3, height: 2),
                height: 4,
                colors: .init(
                    top:   Palette.ochre.lightened(by: 0.05).darkened(by: 0.10),
                    left:  Palette.ochre.darkened(by: 0.10),
                    right: Palette.ochre.darkened(by: 0.25),
                    stroke: Palette.inkDark.withAlphaComponent(0.5)
                )
            )
            // Поверх плоской крыши склада (height ~18-20, topShade на y=height)
            stack.position = CGPoint(x: CGFloat(x), y: 24)

            let waitDuration = Double.random(in: 10...30)
            let pause = Double.random(in: 2...5)
            let pulse = SKAction.repeatForever(SKAction.sequence([
                SKAction.wait(forDuration: waitDuration),
                SKAction.fadeOut(withDuration: 0.5),
                SKAction.wait(forDuration: pause),
                SKAction.fadeIn(withDuration: 0.5)
            ]))
            stack.run(pulse)
            container.addChild(stack)
        }
        return container
    }

    // MARK: - Market: колышущиеся флажки + силуэт торговца

    private func makeMarketAnimation() -> SKNode {
        let container = SKNode()

        // 2 флажка над тентом
        for x in [-10, 10] {
            let flag = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 5, height: 3))
            flag.fillColor = Palette.clay
            flag.strokeColor = Palette.inkDark.withAlphaComponent(0.6)
            flag.lineWidth = 0.5
            flag.position = CGPoint(x: CGFloat(x), y: 28)
            let swayDuration = Double.random(in: 0.8...1.2)
            let sway = SKAction.repeatForever(SKAction.sequence([
                SKAction.rotate(byAngle: 0.17, duration: swayDuration),
                SKAction.rotate(byAngle: -0.34, duration: swayDuration),
                SKAction.rotate(byAngle: 0.17, duration: swayDuration)
            ]))
            flag.run(sway)
            container.addChild(flag)
        }

        // Силуэт торговца раз в 8-12 сек
        let traderCycle = SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: Double.random(in: 8...12)),
            SKAction.run { [weak container] in
                guard let container = container else { return }
                let trader = LifeSimulationManager.makeTraderSilhouette()
                trader.position = CGPoint(x: 0, y: 6)
                trader.alpha = 0
                container.addChild(trader)
                trader.run(SKAction.sequence([
                    SKAction.fadeIn(withDuration: 0.3),
                    SKAction.wait(forDuration: Double.random(in: 2...3)),
                    SKAction.fadeOut(withDuration: 0.3),
                    SKAction.removeFromParent()
                ]))
            }
        ]))
        container.run(traderCycle)
        return container
    }

    // MARK: - Raw pit: цикл наполнение → опустошение

    private func makeRawPitCycle() -> SKNode {
        let container = SKNode()

        var dots: [SKShapeNode] = []
        for i in 0..<3 {
            let d = SKShapeNode(circleOfRadius: 2)
            d.fillColor = Palette.ochre.darkened(by: 0.20)
            d.strokeColor = Palette.inkDark
            d.lineWidth = 0.5
            d.position = CGPoint(x: CGFloat(i - 1) * 6, y: 4)
            d.alpha = 0
            container.addChild(d)
            dots.append(d)
        }

        let randomOffset = Double.random(in: 0...10)
        let cycle = SKAction.repeatForever(SKAction.sequence([
            SKAction.run {
                for (i, dot) in dots.enumerated() {
                    dot.run(SKAction.sequence([
                        SKAction.wait(forDuration: 0.2 * Double(i)),
                        SKAction.fadeIn(withDuration: 0.6)
                    ]))
                }
            },
            SKAction.wait(forDuration: 2.0 + 4.0),   // 2 сек stagger + 4 сек видны
            SKAction.run {
                for dot in dots {
                    dot.run(SKAction.fadeOut(withDuration: 0.6))
                }
            },
            SKAction.wait(forDuration: 2.0 + 2.0)    // 2 сек fade + 2 сек пауза
        ]))
        container.run(SKAction.sequence([
            SKAction.wait(forDuration: randomOffset),
            cycle
        ]))
        return container
    }

    // MARK: - Shack: тонкий дымок + иногда огонёк костерка

    private func makeShackAnimation() -> SKNode {
        let container = SKNode()

        // Тонкий дымок из крыши (пика ~y=22 + bodyHeight=14, над серединой)
        for i in 0..<3 {
            let smokeParticle = Self.makeSmokeParticle(index: i, offsetX: 0, baseY: 28)
            container.addChild(smokeParticle)
        }

        // Иногда огонёк костерка перед входом (раз в 15-30 сек)
        let campfireCycle = SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: Double.random(in: 15...30)),
            SKAction.run { [weak container] in
                guard let container = container else { return }
                let fire = LifeSimulationManager.makeCampfire(at: CGPoint(x: 4, y: -4))
                container.addChild(fire)
                fire.run(SKAction.sequence([
                    SKAction.wait(forDuration: Double.random(in: 3...6)),
                    SKAction.fadeOut(withDuration: 0.5),
                    SKAction.removeFromParent()
                ]))
            }
        ]))
        container.run(campfireCycle)
        return container
    }

    // MARK: - House: тонкий дымок из трубы/крыши

    private func makeHouseAnimation() -> SKNode {
        let container = SKNode()
        // house height ~18+tier*2, roof на y~height, пик ~+18; дым над пиком крыши
        for i in 0..<3 {
            let smokeParticle = Self.makeSmokeParticle(index: i, offsetX: 2, baseY: 32)
            container.addChild(smokeParticle)
        }
        return container
    }

    // MARK: - Villa: тонкий дымок из крыши

    private func makeVillaAnimation() -> SKNode {
        let container = SKNode()
        // villa height ~22+tier*2, roof peak ~+24
        for i in 0..<4 {
            let smokeParticle = Self.makeSmokeParticle(index: i, offsetX: 1, baseY: 40)
            container.addChild(smokeParticle)
        }
        return container
    }

    // MARK: - Well: рябь на воде

    private func makeWellAnimation() -> SKNode {
        let container = SKNode()

        // Лёгкая рябь: кольцо scale-анимация на позиции воды
        let rippleCycle = SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: Double.random(in: 3...7)),
            SKAction.run { [weak container] in
                guard let container = container else { return }
                let ripple = SKShapeNode(circleOfRadius: 3)
                ripple.fillColor = .clear
                ripple.strokeColor = Palette.skyNight.withAlphaComponent(0.6)
                ripple.lineWidth = 0.8
                ripple.position = CGPoint(x: 0, y: 3)
                ripple.alpha = 0.8
                container.addChild(ripple)
                ripple.run(SKAction.sequence([
                    SKAction.group([
                        SKAction.scale(to: 2.2, duration: 1.0),
                        SKAction.fadeOut(withDuration: 1.0)
                    ]),
                    SKAction.removeFromParent()
                ]))
            }
        ]))
        container.run(rippleCycle)
        return container
    }

    // MARK: - Forum: 1-2 силуэт-фигурки у колонн

    private func makeForumAnimation() -> SKNode {
        let container = SKNode()

        // Появляются 1-2 фигурки раз в 8-15 сек на 2-3 сек
        let figureCycle = SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: Double.random(in: 8...15)),
            SKAction.run { [weak container] in
                guard let container = container else { return }
                let count = Int.random(in: 1...2)
                let positions: [CGFloat] = [-14, 14, 0]
                for i in 0..<count {
                    let figure = LifeSimulationManager.makeSilhouetteFigure(
                        at: CGPoint(x: positions[i % positions.count], y: 6)
                    )
                    figure.alpha = 0
                    container.addChild(figure)
                    figure.run(SKAction.sequence([
                        SKAction.fadeIn(withDuration: 0.4),
                        SKAction.wait(forDuration: Double.random(in: 2...3)),
                        SKAction.fadeOut(withDuration: 0.4),
                        SKAction.removeFromParent()
                    ]))
                }
            }
        ]))
        container.run(figureCycle)
        return container
    }

    // MARK: - Temple: мерцающий огонёк у входа

    private func makeTempleAnimation() -> SKNode {
        let container = SKNode()

        // Тёплый огонёк у основания входа
        let flame = SKShapeNode(circleOfRadius: 2.5)
        flame.fillColor = Palette.fireOrange.withAlphaComponent(0.85)
        flame.strokeColor = .clear
        flame.position = CGPoint(x: 0, y: 7)

        // Мерцание
        let flicker = SKAction.repeatForever(SKAction.sequence([
            SKAction.group([
                SKAction.fadeAlpha(to: 1.0, duration: 0.2),
                SKAction.scale(to: 1.2, duration: 0.2)
            ]),
            SKAction.group([
                SKAction.fadeAlpha(to: 0.5, duration: 0.3),
                SKAction.scale(to: 0.8, duration: 0.3)
            ]),
            SKAction.group([
                SKAction.fadeAlpha(to: 0.9, duration: 0.15),
                SKAction.scale(to: 1.0, duration: 0.15)
            ]),
            SKAction.group([
                SKAction.fadeAlpha(to: 0.6, duration: 0.25),
                SKAction.scale(to: 0.9, duration: 0.25)
            ])
        ]))
        flame.run(flicker)
        container.addChild(flame)

        // Тёплый ореол
        let glow = SKShapeNode(circleOfRadius: 5)
        glow.fillColor = Palette.fireOrange.withAlphaComponent(0.15)
        glow.strokeColor = .clear
        glow.position = CGPoint(x: 0, y: 7)
        container.addChild(glow)

        return container
    }

    // MARK: - Obelisk: силуэт паломника + блик от шпиля

    private func makeObeliskAnimation() -> SKNode {
        let container = SKNode()

        // Блик на шпиле (раз в 8-15 сек)
        let glintCycle = SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: Double.random(in: 8...15)),
            SKAction.run { [weak container] in
                guard let container = container else { return }
                let glint = SKShapeNode(circleOfRadius: 3)
                glint.fillColor = Palette.sandLight.withAlphaComponent(0.9)
                glint.strokeColor = .clear
                // Позиция вершины шпиля: base=6, column=36, cap=8 → tip ~y=50+
                glint.position = CGPoint(x: 0, y: 52)
                glint.alpha = 0
                container.addChild(glint)
                glint.run(SKAction.sequence([
                    SKAction.group([
                        SKAction.fadeIn(withDuration: 0.15),
                        SKAction.scale(to: 1.5, duration: 0.15)
                    ]),
                    SKAction.group([
                        SKAction.fadeOut(withDuration: 0.4),
                        SKAction.scale(to: 0.5, duration: 0.4)
                    ]),
                    SKAction.removeFromParent()
                ]))
            }
        ]))
        container.run(glintCycle)

        // Силуэт паломника у основания (раз в 12-20 сек на 3-5 сек)
        let pilgrimCycle = SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: Double.random(in: 12...20)),
            SKAction.run { [weak container] in
                guard let container = container else { return }
                let pilgrim = LifeSimulationManager.makeSilhouetteFigure(
                    at: CGPoint(x: Int.random(in: -12...12), y: 0)
                )
                pilgrim.alpha = 0
                container.addChild(pilgrim)
                pilgrim.run(SKAction.sequence([
                    SKAction.fadeIn(withDuration: 0.5),
                    SKAction.wait(forDuration: Double.random(in: 3...5)),
                    SKAction.fadeOut(withDuration: 0.5),
                    SKAction.removeFromParent()
                ]))
            }
        ]))
        container.run(pilgrimCycle)

        return container
    }

    // MARK: - Вспомогательные фабрики (статические — используются внутри closures)

    /// Процедурная частица дыма (поднимается вверх, fade-in → fade-out, loop).
    private static func makeSmokeParticle(index: Int, offsetX: CGFloat, baseY: CGFloat) -> SKNode {
        let shape = SKShapeNode(circleOfRadius: 3.5)
        shape.fillColor = Palette.smokeGrey.withAlphaComponent(0.35)
        shape.strokeColor = .clear
        shape.zPosition = 5

        let xJitter: CGFloat = CGFloat(index % 3 - 1) * 2.0
        shape.position = CGPoint(x: offsetX + xJitter, y: baseY)
        shape.alpha = 0

        let delay = Double(index) * 0.55
        let rise = SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.group([
                SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.45, duration: 0.4),
                    SKAction.wait(forDuration: 0.6),
                    SKAction.fadeOut(withDuration: 0.8),
                ]),
                SKAction.sequence([
                    SKAction.scale(to: 1.6, duration: 1.8),
                    SKAction.scale(to: 1.0, duration: 0.0),
                ]),
                SKAction.sequence([
                    SKAction.moveBy(x: 0, y: 10, duration: 1.8),
                    SKAction.moveBy(x: 0, y: -10, duration: 0.0),
                ]),
            ]),
        ])
        shape.run(SKAction.repeatForever(rise))
        return shape
    }

    /// Одиночный burst искр (временный узел — добавляется и удаляется).
    private static func makeSparkBurst(at position: CGPoint) -> SKNode {
        let burst = SKNode()
        burst.position = position

        for _ in 0..<5 {
            let spark = SKShapeNode(circleOfRadius: 1.2)
            spark.fillColor = Palette.fireOrange
            spark.strokeColor = .clear

            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 8...20)
            let dx = cos(angle) * speed
            let dy = sin(angle) * speed
            spark.position = .zero

            spark.run(SKAction.sequence([
                SKAction.group([
                    SKAction.moveBy(x: dx, y: dy, duration: 0.5),
                    SKAction.fadeOut(withDuration: 0.5),
                ]),
                SKAction.removeFromParent()
            ]))
            burst.addChild(spark)
        }

        burst.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.6),
            SKAction.removeFromParent()
        ]))
        return burst
    }

    /// Силуэт человеческой фигурки: тело (прямоугольник) + голова (кружок).
    private static func makeSilhouetteFigure(at position: CGPoint) -> SKNode {
        let figure = SKNode()
        figure.position = position

        let body = SKShapeNode(rect: CGRect(x: -2, y: 0, width: 4, height: 10))
        body.fillColor = Palette.clay.withAlphaComponent(0.6)
        body.strokeColor = Palette.inkDark.withAlphaComponent(0.4)
        body.lineWidth = 0.5

        let head = SKShapeNode(circleOfRadius: 2)
        head.fillColor = Palette.clay.withAlphaComponent(0.6)
        head.strokeColor = .clear
        head.position = CGPoint(x: 0, y: 12)

        figure.addChild(body)
        figure.addChild(head)
        return figure
    }

    /// Силуэт торговца (аналогичен figuresilhouette).
    private static func makeTraderSilhouette() -> SKNode {
        let trader = SKNode()

        let body = SKShapeNode(rect: CGRect(x: -2, y: 0, width: 4, height: 10))
        body.fillColor = Palette.clay.withAlphaComponent(0.6)
        body.strokeColor = Palette.inkDark.withAlphaComponent(0.5)
        body.lineWidth = 0.5

        let head = SKShapeNode(circleOfRadius: 2)
        head.fillColor = Palette.clay.withAlphaComponent(0.6)
        head.strokeColor = .clear
        head.position = CGPoint(x: 0, y: 12)

        trader.addChild(body)
        trader.addChild(head)
        return trader
    }

    /// Маленький костерок (3 оранжевых кружка + анимация).
    private static func makeCampfire(at position: CGPoint) -> SKNode {
        let fire = SKNode()
        fire.position = position

        for i in 0..<3 {
            let particle = SKShapeNode(circleOfRadius: 1.5)
            particle.fillColor = Palette.fireOrange.withAlphaComponent(0.80)
            particle.strokeColor = .clear
            let offsets: [(CGFloat, CGFloat)] = [(-1.5, 0), (0, 2), (1.5, 0)]
            particle.position = CGPoint(x: offsets[i].0, y: offsets[i].1)

            let delay = Double(i) * 0.12
            let pulse = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.repeatForever(SKAction.sequence([
                    SKAction.group([
                        SKAction.scale(to: 1.3, duration: 0.2),
                        SKAction.fadeAlpha(to: 1.0, duration: 0.2)
                    ]),
                    SKAction.group([
                        SKAction.scale(to: 0.7, duration: 0.3),
                        SKAction.fadeAlpha(to: 0.5, duration: 0.3)
                    ])
                ]))
            ])
            particle.run(pulse)
            fire.addChild(particle)
        }
        return fire
    }
}
