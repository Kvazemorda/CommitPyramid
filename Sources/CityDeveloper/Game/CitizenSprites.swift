import SpriteKit

enum CitizenSprites {

    // MARK: - Палитра цветов туник (прямой массив)

    static let tunicColors: [SKColor] = [
        Palette.clay,
        Palette.ochre,
        Palette.sandMid,
        Palette.nileGreen,
        Palette.parchment
    ]

    // MARK: - Фабрика жителя

    static func makeCitizen(seed: Int) -> SKNode {
        let node = SKNode()

        // Выбираем цвет туники по seed (детерминизм)
        let tunicColor = tunicColors[abs(seed) % tunicColors.count]

        // MARK: Туника (тело)

        let body = IsoBuilder.cube(
            footprint: CGSize(width: 6, height: 4),
            height: 10,
            colors: .init(
                top: tunicColor.lightened(by: 0.05),
                left: tunicColor,
                right: tunicColor.darkened(by: 0.15),
                stroke: Palette.inkDark.withAlphaComponent(0.5)
            )
        )
        body.position = .zero
        node.addChild(body)

        // MARK: Голова

        let head = IsoBuilder.cube(
            footprint: CGSize(width: 4, height: 3),
            height: 4,
            colors: .init(
                top: Palette.sandLight,
                left: Palette.sandMid,
                right: Palette.sandMid.darkened(by: 0.15),
                stroke: Palette.inkDark.withAlphaComponent(0.5)
            )
        )
        head.position = CGPoint(x: 0, y: 10)
        node.addChild(head)

        // Отключаем touch-события для пропускания кликов на объекты позади
        node.isUserInteractionEnabled = false

        // MARK: Анимация ходьбы (4 кадра sway)

        let sway = SKAction.sequence([
            SKAction.rotate(toAngle: 0.05, duration: 0.2),
            SKAction.rotate(toAngle: 0, duration: 0.2),
            SKAction.rotate(toAngle: -0.05, duration: 0.2),
            SKAction.rotate(toAngle: 0, duration: 0.2)
        ])
        node.run(SKAction.repeatForever(sway))

        return node
    }
}
