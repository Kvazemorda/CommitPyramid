import SpriteKit

enum Direction: CaseIterable {
    case north
    case east
    case south
    case west
}

enum RoadConnector {
    static func roadVariant(neighbours: Set<Direction>) -> SKNode {
        switch neighbours.count {
        case 0:
            return makeSingleSegment()
        case 1:
            return makeSingleSegment()
        case 2:
            // Проверяем противоположные направления (прямая линия)
            if neighbours == [.north, .south] || neighbours == [.east, .west] {
                return makeStraight(neighbours: neighbours)
            } else {
                // Поворот (соседи в углах)
                return makeCurve(neighbours: neighbours)
            }
        case 3:
            return makeTJunction(neighbours: neighbours)
        case 4:
            return makeCross()
        default:
            return makeSingleSegment()
        }
    }

    // MARK: - Базовый вариант: одиночный сегмент

    private static func makeSingleSegment() -> SKNode {
        let node = SKNode()
        let tile = IsoBuilder.groundTile(
            width: 58,
            height: 28,
            fillColor: Palette.sandMid.darkened(by: 0.08),
            strokeColor: Palette.inkDark.withAlphaComponent(0.3)
        )
        tile.position = CGPoint(x: 0, y: 1)
        node.addChild(tile)
        return node
    }

    // MARK: - Прямая линия (N-S или E-W)

    private static func makeStraight(neighbours: Set<Direction>) -> SKNode {
        let node = SKNode()

        // Центральный сегмент
        let centerTile = IsoBuilder.groundTile(
            width: 58,
            height: 28,
            fillColor: Palette.sandMid.darkened(by: 0.08),
            strokeColor: Palette.inkDark.withAlphaComponent(0.3)
        )
        centerTile.position = CGPoint(x: 0, y: 1)
        node.addChild(centerTile)

        // Добавляем полоски вдоль дороги для визуального усиления
        if neighbours == [.north, .south] {
            // Вертикальная линия
            let stripe = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -2, y: 12))
            path.addLine(to: CGPoint(x: 2, y: 12))
            stripe.path = path
            stripe.strokeColor = Palette.inkDark.withAlphaComponent(0.4)
            stripe.lineWidth = 1
            node.addChild(stripe)
        } else if neighbours == [.east, .west] {
            // Горизонтальная линия
            let stripe = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 20, y: 0))
            path.addLine(to: CGPoint(x: 20, y: 4))
            stripe.path = path
            stripe.strokeColor = Palette.inkDark.withAlphaComponent(0.4)
            stripe.lineWidth = 1
            node.addChild(stripe)
        }

        return node
    }

    // MARK: - Поворот (угловой стык)

    private static func makeCurve(neighbours: Set<Direction>) -> SKNode {
        let node = SKNode()

        // Центральный тайл
        let centerTile = IsoBuilder.groundTile(
            width: 58,
            height: 28,
            fillColor: Palette.sandMid.darkened(by: 0.08),
            strokeColor: Palette.inkDark.withAlphaComponent(0.3)
        )
        centerTile.position = CGPoint(x: 0, y: 1)
        node.addChild(centerTile)

        // Добавляем маленькие маркеры в углах для визуального обозначения поворота
        var corner = CGPoint.zero
        if neighbours.contains(.north) && neighbours.contains(.east) {
            corner = CGPoint(x: 15, y: -8)
        } else if neighbours.contains(.east) && neighbours.contains(.south) {
            corner = CGPoint(x: 15, y: 8)
        } else if neighbours.contains(.south) && neighbours.contains(.west) {
            corner = CGPoint(x: -15, y: 8)
        } else if neighbours.contains(.north) && neighbours.contains(.west) {
            corner = CGPoint(x: -15, y: -8)
        }

        let marker = SKShapeNode(circleOfRadius: 1.5)
        marker.fillColor = Palette.inkDark.withAlphaComponent(0.5)
        marker.strokeColor = .clear
        marker.position = corner
        node.addChild(marker)

        return node
    }

    // MARK: - T-перекрёсток

    private static func makeTJunction(neighbours: Set<Direction>) -> SKNode {
        let node = SKNode()

        // Центральный тайл
        let centerTile = IsoBuilder.groundTile(
            width: 58,
            height: 28,
            fillColor: Palette.sandMid.darkened(by: 0.08),
            strokeColor: Palette.inkDark.withAlphaComponent(0.3)
        )
        centerTile.position = CGPoint(x: 0, y: 1)
        node.addChild(centerTile)

        // Маркер отсутствующего направления
        if !neighbours.contains(.north) {
            let marker = SKShapeNode(circleOfRadius: 2)
            marker.fillColor = Palette.ochre.withAlphaComponent(0.4)
            marker.strokeColor = .clear
            marker.position = CGPoint(x: 0, y: -12)
            node.addChild(marker)
        } else if !neighbours.contains(.south) {
            let marker = SKShapeNode(circleOfRadius: 2)
            marker.fillColor = Palette.ochre.withAlphaComponent(0.4)
            marker.strokeColor = .clear
            marker.position = CGPoint(x: 0, y: 12)
            node.addChild(marker)
        } else if !neighbours.contains(.east) {
            let marker = SKShapeNode(circleOfRadius: 2)
            marker.fillColor = Palette.ochre.withAlphaComponent(0.4)
            marker.strokeColor = .clear
            marker.position = CGPoint(x: 20, y: 0)
            node.addChild(marker)
        } else if !neighbours.contains(.west) {
            let marker = SKShapeNode(circleOfRadius: 2)
            marker.fillColor = Palette.ochre.withAlphaComponent(0.4)
            marker.strokeColor = .clear
            marker.position = CGPoint(x: -20, y: 0)
            node.addChild(marker)
        }

        return node
    }

    // MARK: - Крест (все 4 направления)

    private static func makeCross() -> SKNode {
        let node = SKNode()

        // Центральный тайл
        let centerTile = IsoBuilder.groundTile(
            width: 58,
            height: 28,
            fillColor: Palette.sandMid.darkened(by: 0.08),
            strokeColor: Palette.inkDark.withAlphaComponent(0.3)
        )
        centerTile.position = CGPoint(x: 0, y: 1)
        node.addChild(centerTile)

        // Добавляем маркеры на каждом углу для визуального обозначения креста
        for pos in [
            CGPoint(x: 0, y: -12),   // north
            CGPoint(x: 20, y: 0),    // east
            CGPoint(x: 0, y: 12),    // south
            CGPoint(x: -20, y: 0)    // west
        ] {
            let marker = SKShapeNode(circleOfRadius: 1.5)
            marker.fillColor = Palette.clay.withAlphaComponent(0.5)
            marker.strokeColor = .clear
            marker.position = pos
            node.addChild(marker)
        }

        return node
    }
}
