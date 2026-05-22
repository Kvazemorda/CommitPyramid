import SpriteKit

/// Фабрика визуала юнита: тайл-земля + тень + куб + крыша + декорации.
enum UnitSprites {

    static let tileWidth: CGFloat = 64
    static let tileHeight: CGFloat = 32

    static func makeNode(unit: UnitState) -> SKNode {
        let container = SKNode()

        // 1. Тень
        let shadow = IsoBuilder.shadow(width: tileWidth - 4, height: tileHeight - 2)
        shadow.position = CGPoint(x: 4, y: -2)
        shadow.zPosition = -2
        container.addChild(shadow)

        // 2. Тайл-земля под юнитом
        let groundColor = groundColor(for: unit.kind)
        let ground = IsoBuilder.groundTile(
            width: tileWidth - 2,
            height: tileHeight - 1,
            fillColor: groundColor,
            strokeColor: SKColor.black.withAlphaComponent(0.25)
        )
        ground.zPosition = -1
        container.addChild(ground)

        // 3. Само здание (или плоский объект)
        switch unit.kind {
        case .road:
            container.addChild(makeRoad())
        case .well:
            container.addChild(makeWell())
        case .raw:
            container.addChild(makeRawPit())
        case .shack:
            container.addChild(makeShack(tier: unit.tier))
        case .house:
            container.addChild(makeHouse(tier: unit.tier))
        case .villa:
            container.addChild(makeVilla(tier: unit.tier))
        case .warehouse:
            container.addChild(makeWarehouse(tier: unit.tier))
        case .workshop:
            container.addChild(makeWorkshop(tier: unit.tier))
        case .market:
            container.addChild(makeMarket(tier: unit.tier))
        case .forum:
            container.addChild(makeForum(tier: unit.tier))
        case .temple:
            container.addChild(makeTemple(tier: unit.tier))
        case .obelisk:
            container.addChild(makeObelisk(tier: unit.tier))
        }

        return container
    }

    // MARK: - Тайл-земля под юнитом

    private static func groundColor(for kind: UnitKind) -> SKColor {
        switch kind {
        case .raw:           return Palette.clay.darkened(by: 0.15)        // вспаханное
        case .road:          return Palette.sandMid
        case .well:          return Palette.sandLight
        case .market, .forum: return Palette.sandLight.darkened(by: 0.05)  // мощёная плошадь
        case .temple, .obelisk: return Palette.parchment                   // светлый камень
        default:             return Palette.sandLight
        }
    }

    // MARK: - Жилые

    private static func makeShack(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 36, height: 18)
        let bodyHeight: CGFloat = 14
        let body = IsoBuilder.cube(
            footprint: footprint, height: bodyHeight,
            colors: .init(
                top:    Palette.clay.lightened(by: 0.05),
                left:   Palette.clay,
                right:  Palette.clay.darkened(by: 0.15),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(body)
        node.addChild(IsoBuilder.brickHatch(
            footprint: footprint, height: bodyHeight, rows: 2,
            color: Palette.inkDark.withAlphaComponent(0.30)
        ))
        let roof = IsoBuilder.pyramidRoof(
            footprint: footprint, peak: 22,
            leftColor: Palette.smokeGrey.lightened(by: 0.05),
            rightColor: Palette.smokeGrey.darkened(by: 0.10),
            strokeColor: Palette.inkDark.withAlphaComponent(0.6)
        )
        roof.position = CGPoint(x: 0, y: bodyHeight)
        node.addChild(roof)
        return node
    }

    private static func makeHouse(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 40, height: 20)
        let height: CGFloat = 18 + CGFloat(tier) * 2
        let body = IsoBuilder.cube(
            footprint: footprint, height: height,
            colors: .init(
                top:    Palette.sandMid.lightened(by: 0.10),
                left:   Palette.sandMid,
                right:  Palette.sandMid.darkened(by: 0.15),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(body)
        node.addChild(IsoBuilder.brickHatch(
            footprint: footprint, height: height, rows: 3,
            color: Palette.inkDark.withAlphaComponent(0.28)
        ))
        let roof = IsoBuilder.pyramidRoof(
            footprint: footprint, peak: 18,
            leftColor: Palette.clay,
            rightColor: Palette.clay.darkened(by: 0.15),
            strokeColor: Palette.inkDark.withAlphaComponent(0.6)
        )
        roof.position = CGPoint(x: 0, y: height)
        node.addChild(roof)

        // Окошко на правой грани
        let window = SKShapeNode(rect: CGRect(x: -3, y: 0, width: 6, height: 5))
        window.fillColor = Palette.skyNight.withAlphaComponent(0.85)
        window.strokeColor = Palette.inkDark.withAlphaComponent(0.6)
        window.lineWidth = 0.5
        window.position = CGPoint(x: 8, y: height * 0.4)
        node.addChild(window)

        return node
    }

    private static func makeVilla(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 46, height: 24)
        let height: CGFloat = 22 + CGFloat(tier) * 2
        let body = IsoBuilder.cube(
            footprint: footprint, height: height,
            colors: .init(
                top:    Palette.parchment,
                left:   Palette.parchment.darkened(by: 0.10),
                right:  Palette.parchment.darkened(by: 0.25),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(body)
        node.addChild(IsoBuilder.brickHatch(
            footprint: footprint, height: height, rows: 4,
            color: Palette.inkDark.withAlphaComponent(0.22)
        ))
        let roof = IsoBuilder.pyramidRoof(
            footprint: footprint, peak: 24,
            leftColor: Palette.clay.darkened(by: 0.05),
            rightColor: Palette.clay.darkened(by: 0.20),
            strokeColor: Palette.inkDark.withAlphaComponent(0.6)
        )
        roof.position = CGPoint(x: 0, y: height)
        node.addChild(roof)
        // Окошки
        for dx in [-12, 0, 12] {
            let window = SKShapeNode(rect: CGRect(x: -2, y: 0, width: 4, height: 4))
            window.fillColor = Palette.skyNight.withAlphaComponent(0.85)
            window.strokeColor = Palette.inkDark.withAlphaComponent(0.5)
            window.lineWidth = 0.4
            window.position = CGPoint(x: CGFloat(dx), y: height * 0.5)
            node.addChild(window)
        }
        return node
    }

    // MARK: - Инфраструктура

    private static func makeWell() -> SKNode {
        let node = SKNode()
        let stone = SKShapeNode(circleOfRadius: 6)
        stone.fillColor = Palette.stone
        stone.strokeColor = Palette.inkDark
        stone.lineWidth = 1
        stone.position = CGPoint(x: 0, y: 2)
        node.addChild(stone)
        let water = SKShapeNode(circleOfRadius: 4)
        water.fillColor = Palette.skyNight
        water.strokeColor = .clear
        water.position = CGPoint(x: 0, y: 3)
        node.addChild(water)
        return node
    }

    private static func makeRoad() -> SKNode {
        let node = SKNode()
        let path = IsoBuilder.groundTile(
            width: tileWidth - 6,
            height: tileHeight - 4,
            fillColor: Palette.sandMid.darkened(by: 0.08),
            strokeColor: Palette.inkDark.withAlphaComponent(0.3)
        )
        path.position = CGPoint(x: 0, y: 1)
        node.addChild(path)
        return node
    }

    private static func makeRawPit() -> SKNode {
        let node = SKNode()
        let pit = IsoBuilder.groundTile(
            width: tileWidth - 12,
            height: tileHeight - 8,
            fillColor: Palette.clay.darkened(by: 0.3),
            strokeColor: Palette.inkDark
        )
        pit.position = CGPoint(x: 0, y: 1)
        node.addChild(pit)
        // Кучки сырья
        for i in 0..<3 {
            let dot = SKShapeNode(circleOfRadius: 2)
            dot.fillColor = Palette.ochre.darkened(by: 0.2)
            dot.strokeColor = Palette.inkDark
            dot.lineWidth = 0.5
            dot.position = CGPoint(x: CGFloat(i - 1) * 6, y: 3)
            node.addChild(dot)
        }
        return node
    }

    // MARK: - Производство

    private static func makeWarehouse(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 44, height: 22)
        let height: CGFloat = 16 + CGFloat(tier) * 2
        let body = IsoBuilder.cube(
            footprint: footprint, height: height,
            colors: .init(
                top:    Palette.sandLight,
                left:   Palette.sandMid,
                right:  Palette.sandMid.darkened(by: 0.18),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(body)
        node.addChild(IsoBuilder.brickHatch(
            footprint: footprint, height: height, rows: 3,
            color: Palette.inkDark.withAlphaComponent(0.25)
        ))
        // Плоская крыша
        let topShade = IsoBuilder.groundTile(
            width: footprint.width,
            height: footprint.height,
            fillColor: Palette.smokeGrey.darkened(by: 0.20),
            strokeColor: Palette.inkDark
        )
        topShade.position = CGPoint(x: 0, y: height)
        node.addChild(topShade)

        // Декоративные штабели товаров (амфоры/мешки) для tier >= 1
        if tier >= 1 {
            for offset in stride(from: -10, through: 10, by: 8) {
                let stack = IsoBuilder.cube(
                    footprint: CGSize(width: 4, height: 3),
                    height: 5,
                    colors: .init(
                        top: Palette.ochre.lightened(by: 0.05).darkened(by: 0.20),
                        left: Palette.ochre.darkened(by: 0.20),
                        right: Palette.ochre.darkened(by: 0.35),
                        stroke: Palette.inkDark.withAlphaComponent(0.6)
                    )
                )
                stack.position = CGPoint(x: CGFloat(offset), y: height + 3)
                node.addChild(stack)
            }
        }

        return node
    }

    private static func makeWorkshop(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 38, height: 20)
        let height: CGFloat = 16 + CGFloat(tier) * 2
        let body = IsoBuilder.cube(
            footprint: footprint, height: height,
            colors: .init(
                top:    Palette.ochre.lightened(by: 0.10),
                left:   Palette.ochre,
                right:  Palette.ochre.darkened(by: 0.18),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(body)
        node.addChild(IsoBuilder.brickHatch(
            footprint: footprint, height: height, rows: 3,
            color: Palette.inkDark.withAlphaComponent(0.30)
        ))
        let roof = IsoBuilder.pyramidRoof(
            footprint: footprint, peak: 12,
            leftColor: Palette.smokeGrey.lightened(by: 0.05),
            rightColor: Palette.smokeGrey.darkened(by: 0.15),
            strokeColor: Palette.inkDark.withAlphaComponent(0.6)
        )
        roof.position = CGPoint(x: 0, y: height)
        node.addChild(roof)
        // Труба
        let chimney = IsoBuilder.cube(
            footprint: CGSize(width: 6, height: 4),
            height: 8,
            colors: .init(
                top:    Palette.smokeGrey.darkened(by: 0.2),
                left:   Palette.smokeGrey.darkened(by: 0.3),
                right:  Palette.smokeGrey.darkened(by: 0.4),
                stroke: Palette.inkDark.withAlphaComponent(0.7)
            )
        )
        chimney.position = CGPoint(x: -6, y: height + 6)
        node.addChild(chimney)
        return node
    }

    // MARK: - Социальные

    private static func makeMarket(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 44, height: 22)
        let height: CGFloat = 6
        let base = IsoBuilder.cube(
            footprint: footprint, height: height,
            colors: .init(
                top:    Palette.sandLight,
                left:   Palette.sandMid,
                right:  Palette.sandMid.darkened(by: 0.18),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(base)
        // Полосатый навес-тент
        let canopy = IsoBuilder.pyramidRoof(
            footprint: footprint, peak: 16,
            leftColor: Palette.skyDusk,
            rightColor: Palette.skyDusk.darkened(by: 0.15),
            strokeColor: Palette.inkDark.withAlphaComponent(0.7)
        )
        canopy.position = CGPoint(x: 0, y: height + 6)
        node.addChild(canopy)
        // Колонны
        for x in stride(from: -16, through: 16, by: 8) {
            let col = SKShapeNode(rect: CGRect(x: -1, y: 0, width: 2, height: 10))
            col.fillColor = Palette.parchment
            col.strokeColor = Palette.inkDark.withAlphaComponent(0.6)
            col.lineWidth = 0.5
            col.position = CGPoint(x: CGFloat(x), y: height)
            node.addChild(col)
        }
        return node
    }

    private static func makeForum(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 48, height: 24)
        let plat = IsoBuilder.cube(
            footprint: footprint, height: 6,
            colors: .init(
                top:    Palette.parchment,
                left:   Palette.stone,
                right:  Palette.stone.darkened(by: 0.18),
                stroke: Palette.inkDark.withAlphaComponent(0.6)
            )
        )
        node.addChild(plat)
        // Ряд колонн
        for x in stride(from: -18, through: 18, by: 9) {
            let col = IsoBuilder.cube(
                footprint: CGSize(width: 4, height: 3),
                height: 14,
                colors: .init(
                    top:    Palette.parchment,
                    left:   Palette.parchment.darkened(by: 0.10),
                    right:  Palette.parchment.darkened(by: 0.22),
                    stroke: Palette.inkDark.withAlphaComponent(0.6)
                )
            )
            col.position = CGPoint(x: CGFloat(x), y: 6)
            node.addChild(col)
        }
        return node
    }

    private static func makeTemple(tier: Int) -> SKNode {
        let node = SKNode()
        let footprint = CGSize(width: 44, height: 24)
        let plat = IsoBuilder.cube(
            footprint: footprint, height: 6,
            colors: .init(
                top:    Palette.parchment,
                left:   Palette.parchment.darkened(by: 0.10),
                right:  Palette.parchment.darkened(by: 0.25),
                stroke: Palette.inkDark.withAlphaComponent(0.7)
            )
        )
        node.addChild(plat)
        let inner = CGSize(width: 30, height: 16)
        let body = IsoBuilder.cube(
            footprint: inner, height: 22,
            colors: .init(
                top:    Palette.parchment,
                left:   Palette.parchment.darkened(by: 0.12),
                right:  Palette.parchment.darkened(by: 0.28),
                stroke: Palette.inkDark.withAlphaComponent(0.7)
            )
        )
        body.position = CGPoint(x: 0, y: 6)
        node.addChild(body)
        let roof = IsoBuilder.pyramidRoof(
            footprint: inner, peak: 20,
            leftColor: Palette.ochre,
            rightColor: Palette.ochre.darkened(by: 0.20),
            strokeColor: Palette.inkDark.withAlphaComponent(0.7)
        )
        roof.position = CGPoint(x: 0, y: 6 + 22)
        node.addChild(roof)
        return node
    }

    private static func makeObelisk(tier: Int) -> SKNode {
        let node = SKNode()
        // База
        let base = IsoBuilder.cube(
            footprint: CGSize(width: 22, height: 12),
            height: 6,
            colors: .init(
                top:    Palette.stone.lightened(by: 0.10),
                left:   Palette.stone,
                right:  Palette.stone.darkened(by: 0.18),
                stroke: Palette.inkDark
            )
        )
        node.addChild(base)
        // Шпиль (узкий куб + треугольная вершина)
        let column = IsoBuilder.cube(
            footprint: CGSize(width: 8, height: 4),
            height: 36,
            colors: .init(
                top:    Palette.sandMid,
                left:   Palette.sandMid.darkened(by: 0.10),
                right:  Palette.sandMid.darkened(by: 0.22),
                stroke: Palette.inkDark
            )
        )
        column.position = CGPoint(x: 0, y: 6)
        node.addChild(column)
        let cap = IsoBuilder.pyramidRoof(
            footprint: CGSize(width: 8, height: 4),
            peak: 8,
            leftColor: Palette.ochre,
            rightColor: Palette.ochre.darkened(by: 0.20),
            strokeColor: Palette.inkDark
        )
        cap.position = CGPoint(x: 0, y: 6 + 36)
        node.addChild(cap)
        return node
    }

    // MARK: - Руины

    internal static func makeRuin(originalKind: UnitKind) -> SKNode {
        let node = SKNode()

        // Используем детерминированные значения от hashValue
        let h = abs(originalKind.hashValue)

        // Для дорог - плоский слой обломков
        if originalKind == .road {
            let strip = IsoBuilder.groundTile(
                width: tileWidth - 8,
                height: 8,
                fillColor: Palette.stone.darkened(by: 0.20),
                strokeColor: Palette.inkDark
            )
            node.addChild(strip)
            return node
        }

        // Для остальных юнитов: 2-3 коротких куба + трава + трещина
        let chunks = 2 + (h % 2)  // 2 или 3 куба
        let offsets: [(CGFloat, CGFloat)] = [(-8, 4), (6, -2), (0, 6)]

        for i in 0..<chunks {
            if i >= offsets.count { break }
            let offset = offsets[i]
            let chunkHeight = CGFloat(4 + (h % 5))  // Высота 4-8 pt, детерминирована

            let chunk = IsoBuilder.cube(
                footprint: CGSize(width: 8, height: 6),
                height: chunkHeight,
                colors: .init(
                    top: Palette.stone.lightened(by: 0.05).darkened(by: 0.30),
                    left: Palette.stone.darkened(by: 0.30),
                    right: Palette.stone.darkened(by: 0.45),
                    stroke: Palette.inkDark
                )
            )
            chunk.position = CGPoint(x: offset.0, y: offset.1)
            node.addChild(chunk)
        }

        // Заросли травы (3 зеленых кружка)
        let grassCount = 3
        for i in 0..<grassCount {
            let weed = SKShapeNode(circleOfRadius: 1.5)
            weed.fillColor = Palette.nileGreen.darkened(by: 0.15)
            weed.strokeColor = .clear

            // Детерминированные позиции для травы
            let angle = CGFloat(i) * 2.0 * .pi / CGFloat(grassCount)
            let radius: CGFloat = 7.0
            weed.position = CGPoint(
                x: radius * cos(angle),
                y: radius * sin(angle)
            )
            node.addChild(weed)
        }

        // Трещина (линия чёрного цвета)
        let crack = SKShapeNode()
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -8, y: -2))
        p.addLine(to: CGPoint(x: 8, y: 1))
        crack.path = p
        crack.strokeColor = Palette.inkDark.withAlphaComponent(0.4)
        crack.lineWidth = 0.5
        node.addChild(crack)

        return node
    }
}
