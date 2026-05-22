import SpriteKit

enum InspectorPanel {

    static func build(unit: UnitState, project: ProjectState) -> SKNode {
        let container = SKNode()

        let projectLabel = SKLabelNode(text: project.name)
        projectLabel.fontName = "Helvetica-Bold"
        projectLabel.fontSize = 13
        projectLabel.fontColor = Palette.inkDark
        projectLabel.horizontalAlignmentMode = .left

        let kindLabel = SKLabelNode(text: russianKind(unit.kind) + ", stage \(unit.tier)")
        kindLabel.fontName = "Helvetica"
        kindLabel.fontSize = 10
        kindLabel.fontColor = Palette.inkDark.withAlphaComponent(0.6)
        kindLabel.horizontalAlignmentMode = .left

        let titleText = unit.taskTitle ?? "(без названия)"
        let titleLabel = SKLabelNode(text: titleText)
        titleLabel.fontName = "Helvetica"
        titleLabel.fontSize = 12
        titleLabel.fontColor = Palette.inkDark
        titleLabel.horizontalAlignmentMode = .left
        titleLabel.numberOfLines = 0
        titleLabel.preferredMaxLayoutWidth = 240
        titleLabel.lineBreakMode = .byWordWrapping

        let dateLabel = SKLabelNode(text: formatted(unit.taskTs))
        dateLabel.fontName = "Helvetica"
        dateLabel.fontSize = 10
        dateLabel.fontColor = Palette.inkDark.withAlphaComponent(0.5)
        dateLabel.horizontalAlignmentMode = .left

        let padding: CGFloat = 12
        let lineSpacing: CGFloat = 6

        let leftX: CGFloat = 0
        var cursorY: CGFloat = 0

        dateLabel.position    = CGPoint(x: leftX, y: cursorY); cursorY += dateLabel.frame.height + lineSpacing
        titleLabel.position   = CGPoint(x: leftX, y: cursorY); cursorY += titleLabel.frame.height + lineSpacing
        kindLabel.position    = CGPoint(x: leftX, y: cursorY); cursorY += kindLabel.frame.height + lineSpacing
        projectLabel.position = CGPoint(x: leftX, y: cursorY); cursorY += projectLabel.frame.height

        let contentWidth = max(
            projectLabel.frame.width,
            titleLabel.frame.width,
            kindLabel.frame.width,
            dateLabel.frame.width
        )
        let totalHeight = cursorY
        let bgWidth = contentWidth + padding * 2
        let bgHeight = totalHeight + padding * 2

        let bg = SKShapeNode(
            rect: CGRect(x: -padding, y: -padding, width: bgWidth, height: bgHeight),
            cornerRadius: 6
        )
        bg.fillColor = Palette.parchment.withAlphaComponent(0.96)
        bg.strokeColor = Palette.inkDark.withAlphaComponent(0.5)
        bg.lineWidth = 1

        let shadow = SKShapeNode(
            rect: CGRect(x: -padding + 3, y: -padding - 3, width: bgWidth, height: bgHeight),
            cornerRadius: 6
        )
        shadow.fillColor = Palette.inkDark.withAlphaComponent(0.2)
        shadow.strokeColor = .clear
        shadow.zPosition = -1

        container.addChild(shadow)
        container.addChild(bg)
        container.addChild(projectLabel)
        container.addChild(kindLabel)
        container.addChild(titleLabel)
        container.addChild(dateLabel)

        return container
    }

    private static func russianKind(_ kind: UnitKind) -> String {
        switch kind {
        case .shack:     return "Лачуга"
        case .house:     return "Дом"
        case .villa:     return "Вилла"
        case .well:      return "Колодец"
        case .road:      return "Дорога"
        case .warehouse: return "Склад"
        case .workshop:  return "Мастерская"
        case .raw:       return "Сырьевая яма"
        case .market:    return "Рынок"
        case .forum:     return "Форум"
        case .temple:    return "Храм"
        case .obelisk:   return "Обелиск"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy HH:mm"
        f.locale = Locale(identifier: "ru_RU")
        return f
    }()

    private static func formatted(_ date: Date) -> String {
        return dateFormatter.string(from: date)
    }
}
