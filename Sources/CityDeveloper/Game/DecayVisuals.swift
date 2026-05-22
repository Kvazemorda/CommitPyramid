import SpriteKit

/// Фабрики визуальных overlay'ев для decay-уровней.
/// Используется в GameScene.applyDecayToProject.
enum DecayVisuals {

    // MARK: - Именованные ключи overlay'ев (для безопасного удаления)

    static let overlayKey = "decayOverlay"

    // MARK: - Фабрики по уровню

    /// Создаёт overlay для текущего уровня decay (0 = пусто).
    static func makeOverlay(level: Int, originalKind: UnitKind) -> SKNode? {
        switch level {
        case 1: return decay1Overlay()
        case 2: return decay2Cracks()
        case 3: return decay3FireEmitter()
        case 4: return decay4Ruin(originalKind: originalKind)
        default: return nil
        }
    }

    // MARK: - decay 1: зелёный overlay + общий tone-down через colorBlendFactor

    /// Зелёный полупрозрачный overlay поверх тайла (имитация заросшего газона).
    static func decay1Overlay() -> SKNode {
        let container = SKNode()
        container.name = overlayKey

        // Ромбовидный тайл с nileGreen 25% opacity
        let overlay = IsoBuilder.groundTile(
            width: 60,
            height: 28,
            fillColor: Palette.nileGreen.withAlphaComponent(0.25),
            strokeColor: .clear
        )
        overlay.zPosition = 1
        container.addChild(overlay)

        // Несколько маленьких «пятен» зелени (травинки)
        for (dx, dy) in [(-10.0, 4.0), (8.0, -3.0), (-2.0, 8.0), (14.0, 2.0)] {
            let weed = SKShapeNode(circleOfRadius: 2.5)
            weed.fillColor = Palette.nileGreen.darkened(by: 0.10).withAlphaComponent(0.70)
            weed.strokeColor = .clear
            weed.position = CGPoint(x: dx, y: dy)
            container.addChild(weed)
        }

        return container
    }

    // MARK: - decay 2: трещины SKShapeNode на гранях

    static func decay2Cracks() -> SKNode {
        let container = SKNode()
        container.name = overlayKey

        let crackColor = Palette.inkDark.withAlphaComponent(0.60)

        // Трещина 1 — левая грань
        let c1 = SKShapeNode()
        let p1 = CGMutablePath()
        p1.move(to: CGPoint(x: -18, y: 6))
        p1.addLine(to: CGPoint(x: -8, y: 10))
        p1.addLine(to: CGPoint(x: -14, y: 16))
        c1.path = p1
        c1.strokeColor = crackColor
        c1.lineWidth = 1.0
        c1.zPosition = 2
        container.addChild(c1)

        // Трещина 2 — правая грань
        let c2 = SKShapeNode()
        let p2 = CGMutablePath()
        p2.move(to: CGPoint(x: 16, y: 5))
        p2.addLine(to: CGPoint(x: 10, y: 12))
        p2.addLine(to: CGPoint(x: 18, y: 18))
        c2.path = p2
        c2.strokeColor = crackColor
        c2.lineWidth = 1.0
        c2.zPosition = 2
        container.addChild(c2)

        // Трещина 3 — горизонтальная (на верхней грани)
        let c3 = SKShapeNode()
        let p3 = CGMutablePath()
        p3.move(to: CGPoint(x: -6, y: 20))
        p3.addLine(to: CGPoint(x: 0, y: 24))
        p3.addLine(to: CGPoint(x: 6, y: 22))
        c3.path = p3
        c3.strokeColor = crackColor
        c3.lineWidth = 0.8
        c3.zPosition = 2
        container.addChild(c3)

        return container
    }

    // MARK: - decay 3: процедурный fire + smoke (анимированные SKSpriteNode)

    /// Создаёт визуальный эффект пожара/дыма без использования .sks-файлов.
    /// Используем несколько SKShapeNode с fade/scale анимацией вместо SKEmitterNode,
    /// т.к. SKEmitterNode требует .sks-ресурс или сложную ручную инициализацию.
    static func decay3FireEmitter() -> SKNode {
        let container = SKNode()
        container.name = overlayKey

        // Создаём частицы огня (анимированные узлы)
        for i in 0..<5 {
            let fireParticle = makeFireParticle(index: i)
            container.addChild(fireParticle)
        }

        // Создаём частицы дыма
        for i in 0..<3 {
            let smokeParticle = makeSmokeParticle(index: i)
            container.addChild(smokeParticle)
        }

        return container
    }

    private static func makeFireParticle(index: Int) -> SKNode {
        let radius: CGFloat = 2.5 + CGFloat(index % 3) * 0.8  // детерминировано по индексу
        let shape = SKShapeNode(circleOfRadius: radius)
        shape.fillColor = Palette.fireOrange.withAlphaComponent(0.85)
        shape.strokeColor = .clear
        shape.zPosition = 10

        // Позиция с небольшим разбросом
        let baseOffsets: [(CGFloat, CGFloat)] = [(-6, 10), (4, 14), (-2, 18), (8, 10), (0, 22)]
        let offset = baseOffsets[index % baseOffsets.count]
        shape.position = CGPoint(x: offset.0, y: offset.1)

        // Анимация: pulse + fade loop с разным delay для каждой частицы
        let delay = Double(index) * 0.18
        let pulse = SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.group([
                SKAction.sequence([
                    SKAction.scale(to: 1.4, duration: 0.3),
                    SKAction.scale(to: 0.7, duration: 0.3),
                ]),
                SKAction.sequence([
                    SKAction.fadeAlpha(to: 1.0, duration: 0.2),
                    SKAction.fadeAlpha(to: 0.4, duration: 0.4),
                ])
            ]),
        ])
        shape.run(SKAction.repeatForever(pulse))
        return shape
    }

    private static func makeSmokeParticle(index: Int) -> SKNode {
        let shape = SKShapeNode(circleOfRadius: 4.0)
        shape.fillColor = Palette.smokeGrey.withAlphaComponent(0.45)
        shape.strokeColor = .clear
        shape.zPosition = 11

        let baseOffsets: [(CGFloat, CGFloat)] = [(-4, 26), (2, 32), (8, 28)]
        let offset = baseOffsets[index % baseOffsets.count]
        shape.position = CGPoint(x: offset.0, y: offset.1)
        shape.alpha = 0

        // Анимация: rise, expand, fade
        let delay = Double(index) * 0.5
        let rise = SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.group([
                SKAction.sequence([
                    SKAction.fadeIn(withDuration: 0.4),
                    SKAction.fadeOut(withDuration: 1.0),
                ]),
                SKAction.sequence([
                    SKAction.scale(to: 1.8, duration: 1.4),
                    SKAction.scale(to: 1.0, duration: 0.0),
                ]),
                SKAction.moveBy(x: 0, y: 8, duration: 1.4),
            ]),
            SKAction.moveBy(x: 0, y: -8, duration: 0.0),  // сброс позиции
        ])
        shape.run(SKAction.repeatForever(rise))
        return shape
    }

    // MARK: - decay 4: руины

    /// Использует UnitSprites.makeRuin (TASK-009 готов).
    static func decay4Ruin(originalKind: UnitKind) -> SKNode {
        let node = UnitSprites.makeRuin(originalKind: originalKind)
        node.name = overlayKey
        return node
    }
}
