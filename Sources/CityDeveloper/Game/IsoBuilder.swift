import SpriteKit

enum IsoBuilder {

    // MARK: - Изометрический куб (3 видимые грани)

    struct CubeColors {
        let top: SKColor
        let left: SKColor
        let right: SKColor
        let stroke: SKColor

        static let stoneTier3 = CubeColors(
            top:    SKColor(red: 0.78, green: 0.74, blue: 0.67, alpha: 1.0),
            left:   SKColor(red: 0.62, green: 0.58, blue: 0.52, alpha: 1.0),
            right:  SKColor(red: 0.50, green: 0.47, blue: 0.42, alpha: 1.0),
            stroke: SKColor(red: 0.20, green: 0.18, blue: 0.15, alpha: 0.6)
        )
    }

    static func cube(
        footprint: CGSize,
        height: CGFloat,
        colors: CubeColors,
        strokeWidth: CGFloat = 1
    ) -> SKNode {
        let container = SKNode()
        let w = footprint.width / 2
        let d = footprint.height / 2

        // Левая грань
        let leftPath = CGMutablePath()
        leftPath.move(to: CGPoint(x: -w, y: 0))
        leftPath.addLine(to: CGPoint(x: 0, y: -d))
        leftPath.addLine(to: CGPoint(x: 0, y: height - d))
        leftPath.addLine(to: CGPoint(x: -w, y: height))
        leftPath.closeSubpath()
        let left = SKShapeNode(path: leftPath)
        left.fillColor = colors.left
        left.strokeColor = colors.stroke
        left.lineWidth = strokeWidth
        left.lineJoin = .miter
        container.addChild(left)

        // Правая грань
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: w, y: 0))
        rightPath.addLine(to: CGPoint(x: 0, y: -d))
        rightPath.addLine(to: CGPoint(x: 0, y: height - d))
        rightPath.addLine(to: CGPoint(x: w, y: height))
        rightPath.closeSubpath()
        let right = SKShapeNode(path: rightPath)
        right.fillColor = colors.right
        right.strokeColor = colors.stroke
        right.lineWidth = strokeWidth
        right.lineJoin = .miter
        container.addChild(right)

        // Верхняя грань
        let topPath = CGMutablePath()
        topPath.move(to: CGPoint(x: 0, y: height + d))
        topPath.addLine(to: CGPoint(x: w, y: height))
        topPath.addLine(to: CGPoint(x: 0, y: height - d))
        topPath.addLine(to: CGPoint(x: -w, y: height))
        topPath.closeSubpath()
        let top = SKShapeNode(path: topPath)
        top.fillColor = colors.top
        top.strokeColor = colors.stroke
        top.lineWidth = strokeWidth
        top.lineJoin = .miter
        container.addChild(top)

        return container
    }

    // MARK: - Пирамидальная крыша

    static func pyramidRoof(
        footprint: CGSize,
        peak: CGFloat,
        leftColor: SKColor,
        rightColor: SKColor,
        strokeColor: SKColor
    ) -> SKNode {
        let container = SKNode()
        let w = footprint.width / 2
        let d = footprint.height / 2

        // Левый передний скат (видимый)
        let leftPath = CGMutablePath()
        leftPath.move(to: CGPoint(x: -w, y: 0))
        leftPath.addLine(to: CGPoint(x: 0, y: -d))
        leftPath.addLine(to: CGPoint(x: 0, y: peak))
        leftPath.closeSubpath()
        let left = SKShapeNode(path: leftPath)
        left.fillColor = leftColor
        left.strokeColor = strokeColor
        left.lineWidth = 1
        container.addChild(left)

        // Правый передний скат (видимый)
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: w, y: 0))
        rightPath.addLine(to: CGPoint(x: 0, y: -d))
        rightPath.addLine(to: CGPoint(x: 0, y: peak))
        rightPath.closeSubpath()
        let right = SKShapeNode(path: rightPath)
        right.fillColor = rightColor
        right.strokeColor = strokeColor
        right.lineWidth = 1
        container.addChild(right)

        // Задние грани не рисуем — они невидимы при изометрической проекции
        return container
    }

    // MARK: - Текстура «кирпичная кладка» поверх левой/правой грани куба

    /// Добавляет к ноде куба тонкие линии-намёки на ряды кирпичей/досок.
    /// Вызывать после `cube(...)`.
    static func brickHatch(
        footprint: CGSize,
        height: CGFloat,
        rows: Int = 3,
        color: SKColor
    ) -> SKNode {
        let container = SKNode()
        let w = footprint.width / 2
        let d = footprint.height / 2

        let step = height / CGFloat(rows + 1)
        for i in 1...rows {
            let y = CGFloat(i) * step

            // Линия на левой грани: параллельна нижнему ребру (от (-w, 0) до (0, -d))
            // Сдвигаем её вверх на y.
            let leftLine = SKShapeNode()
            let lp = CGMutablePath()
            lp.move(to: CGPoint(x: -w, y: y))
            lp.addLine(to: CGPoint(x: 0, y: y - d))
            leftLine.path = lp
            leftLine.strokeColor = color
            leftLine.lineWidth = 0.6
            container.addChild(leftLine)

            // Линия на правой грани
            let rightLine = SKShapeNode()
            let rp = CGMutablePath()
            rp.move(to: CGPoint(x: w, y: y))
            rp.addLine(to: CGPoint(x: 0, y: y - d))
            rightLine.path = rp
            rightLine.strokeColor = color
            rightLine.lineWidth = 0.6
            container.addChild(rightLine)
        }

        return container
    }

    // MARK: - Изометрический тайл земли (ромб)

    static func groundTile(
        width: CGFloat,
        height: CGFloat,
        fillColor: SKColor,
        strokeColor: SKColor = SKColor.black.withAlphaComponent(0.15)
    ) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: height / 2))
        path.addLine(to: CGPoint(x: width / 2, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -height / 2))
        path.addLine(to: CGPoint(x: -width / 2, y: 0))
        path.closeSubpath()
        let node = SKShapeNode(path: path)
        node.fillColor = fillColor
        node.strokeColor = strokeColor
        node.lineWidth = 1
        node.lineJoin = .miter
        return node
    }

    // MARK: - Тень под зданием

    static func shadow(width: CGFloat, height: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: height / 2))
        path.addLine(to: CGPoint(x: width / 2, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -height / 2))
        path.addLine(to: CGPoint(x: -width / 2, y: 0))
        path.closeSubpath()
        let node = SKShapeNode(path: path)
        node.fillColor = SKColor.black.withAlphaComponent(0.25)
        node.strokeColor = .clear
        return node
    }
}

extension SKColor {
    func darkened(by amount: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        let ns = self.usingColorSpace(.deviceRGB) ?? self
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        let factor = max(0, 1 - amount)
        return SKColor(red: r * factor, green: g * factor, blue: b * factor, alpha: a)
    }

    func lightened(by amount: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        let ns = self.usingColorSpace(.deviceRGB) ?? self
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        let factor = amount
        return SKColor(
            red: min(1, r + (1 - r) * factor),
            green: min(1, g + (1 - g) * factor),
            blue: min(1, b + (1 - b) * factor),
            alpha: a
        )
    }
}
