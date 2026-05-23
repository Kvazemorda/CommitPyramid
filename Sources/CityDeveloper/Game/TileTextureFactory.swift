import SpriteKit
import AppKit

// MARK: - Edge

/// Направление перехода к соседнему биому (NE/NW/SE/SW относительно центра ромба).
enum Edge: Hashable {
    case ne, nw, se, sw
}

// MARK: - TileTextureFactory (TASK-028)

/// Фабрика растровых текстур 64×32 pt (128×64 px @2x Retina) для биом-тайлов.
/// Кэш-static var — создаётся один раз на запуск, не растёт между сценами.
enum TileTextureFactory {

    // MARK: - Размеры

    private static let logicalSize = CGSize(width: 64, height: 32)
    private static let pixelSize   = CGSize(width: 128, height: 64) // @2x

    // MARK: - Кэши

    private static var solidCache:      [BiomeKind: SKTexture] = [:]
    private static var transitionCache: [String: SKTexture]    = [:]
    private static var gradientCache:   [String: SKTexture]    = [:]

    // MARK: - Публичный API

    /// Сплошная текстура ромба для указанного биома.
    static func texture(for biome: BiomeKind) -> SKTexture {
        if let cached = solidCache[biome] { return cached }
        let tex = makeSolidTexture(color: biome.fillColor)
        solidCache[biome] = tex
        return tex
    }

    /// Переходная текстура: ромб с заливкой `from`, и альфа-полосой цвета `to` вдоль ребра `edge`.
    static func transitionTexture(from a: BiomeKind, to b: BiomeKind, edge: Edge) -> SKTexture {
        let key = "\(a.rawValue)_\(b.rawValue)_\(edge)"
        if let cached = transitionCache[key] { return cached }
        let tex = makeTransitionTexture(from: a.fillColor, to: b.fillColor, edge: edge)
        transitionCache[key] = tex
        return tex
    }

    /// Альфа-градиентная текстура: ромб с линейным градиентом от `color` (opaque на ребре edge)
    /// до прозрачного на противоположной стороне. Используется в overlay-слое.
    static func alphaGradientTexture(color: SKColor, edge: Edge) -> SKTexture {
        let key = "\(color.description)_\(edge)"
        if let cached = gradientCache[key] { return cached }
        let tex = makeAlphaGradientTexture(color: color, edge: edge)
        gradientCache[key] = tex
        return tex
    }

    // MARK: - Внутренняя реализация

    /// Создаёт сплошной ромб заданного цвета.
    private static func makeSolidTexture(color: SKColor) -> SKTexture {
        let image = NSImage(size: pixelSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        let path = diamondPath()
        color.setFill()
        path.fill()

        // Тонкий stroke для визуальной чёткости стыков
        let stroke = color.blended(withFraction: 0.35, of: .black) ?? color
        stroke.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    /// Создаёт переходный ромб: base-цвет + полоса цвета `to` у ребра `edge`.
    private static func makeTransitionTexture(from base: SKColor, to other: SKColor, edge: Edge) -> SKTexture {
        let image = NSImage(size: pixelSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        // Шаг 1: base-заливка
        let basePath = diamondPath()
        base.setFill()
        basePath.fill()

        // Шаг 2: клип к ромбу, рисуем треугольную полосу у ребра
        let clipPath = diamondPath()
        clipPath.addClip()

        let strip = edgeStripPath(edge: edge, pixelSize: pixelSize)
        other.withAlphaComponent(0.55).setFill()
        strip.fill()

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    /// Создаёт ромб с альфа-градиентом от edge (opaque) к центру (transparent).
    private static func makeAlphaGradientTexture(color: SKColor, edge: Edge) -> SKTexture {
        let image = NSImage(size: pixelSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            let fallbackImage = NSImage(size: pixelSize)
            let tex = SKTexture(image: fallbackImage)
            return tex
        }

        // Клип к ромбу
        let diamond = diamondCGPath()
        ctx.addPath(diamond)
        ctx.clip()

        // Определяем направление градиента по ребру
        let (startPt, endPt) = gradientPoints(edge: edge, size: pixelSize)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            CGColor(red: r, green: g, blue: b, alpha: 0.65),
            CGColor(red: r, green: g, blue: b, alpha: 0.0)
        ] as CFArray

        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) else {
            return SKTexture(image: image)
        }

        ctx.drawLinearGradient(gradient, start: startPt, end: endPt, options: [])

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    // MARK: - Вспомогательные функции ромба

    /// NSBezierPath ромба 128×64 px.
    private static func diamondPath() -> NSBezierPath {
        let w = pixelSize.width
        let h = pixelSize.height
        let path = NSBezierPath()
        path.move(to: NSPoint(x: w / 2, y: h))     // top
        path.line(to: NSPoint(x: w, y: h / 2))     // right
        path.line(to: NSPoint(x: w / 2, y: 0))     // bottom
        path.line(to: NSPoint(x: 0, y: h / 2))     // left
        path.close()
        return path
    }

    /// CGPath ромба для Core Graphics clip.
    private static func diamondCGPath() -> CGPath {
        let w = pixelSize.width
        let h = pixelSize.height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: w / 2, y: h))
        path.addLine(to: CGPoint(x: w, y: h / 2))
        path.addLine(to: CGPoint(x: w / 2, y: 0))
        path.addLine(to: CGPoint(x: 0, y: h / 2))
        path.closeSubpath()
        return path
    }

    /// Треугольная полоса у ребра ромба (примерно 35% площади).
    private static func edgeStripPath(edge: Edge, pixelSize: CGSize) -> NSBezierPath {
        let w = pixelSize.width
        let h = pixelSize.height
        let mid = h / 2

        let path = NSBezierPath()
        switch edge {
        case .ne: // правый верх: top→right→mid-right
            path.move(to: NSPoint(x: w / 2, y: h))
            path.line(to: NSPoint(x: w, y: mid))
            path.line(to: NSPoint(x: w * 0.65, y: mid))
            path.line(to: NSPoint(x: w / 2, y: h * 0.65))
        case .nw: // левый верх: top→left→mid-left
            path.move(to: NSPoint(x: w / 2, y: h))
            path.line(to: NSPoint(x: 0, y: mid))
            path.line(to: NSPoint(x: w * 0.35, y: mid))
            path.line(to: NSPoint(x: w / 2, y: h * 0.65))
        case .se: // правый низ: bottom→right→mid-right
            path.move(to: NSPoint(x: w / 2, y: 0))
            path.line(to: NSPoint(x: w, y: mid))
            path.line(to: NSPoint(x: w * 0.65, y: mid))
            path.line(to: NSPoint(x: w / 2, y: h * 0.35))
        case .sw: // левый низ: bottom→left→mid-left
            path.move(to: NSPoint(x: w / 2, y: 0))
            path.line(to: NSPoint(x: 0, y: mid))
            path.line(to: NSPoint(x: w * 0.35, y: mid))
            path.line(to: NSPoint(x: w / 2, y: h * 0.35))
        }
        path.close()
        return path
    }

    /// Начало и конец линейного градиента для ребра.
    private static func gradientPoints(edge: Edge, size: CGSize) -> (CGPoint, CGPoint) {
        let w = size.width, h = size.height
        switch edge {
        case .ne: return (CGPoint(x: w, y: h),      CGPoint(x: w / 2, y: h / 2))
        case .nw: return (CGPoint(x: 0, y: h),      CGPoint(x: w / 2, y: h / 2))
        case .se: return (CGPoint(x: w, y: 0),      CGPoint(x: w / 2, y: h / 2))
        case .sw: return (CGPoint(x: 0, y: 0),      CGPoint(x: w / 2, y: h / 2))
        }
    }
}

// MARK: - BiomeKind: fill color

extension BiomeKind {
    /// Цвет заливки биома — из Palette (TASK-028).
    var fillColor: SKColor {
        switch self {
        case .meadow:   return Palette.nileGreen
        case .desert:   return Palette.sandLight
        case .forest:   return Palette.forestGreen
        case .mountain: return Palette.mountainGrey
        case .stone:    return Palette.rockBrown
        case .river:    return Palette.riverBlue
        case .sea:      return Palette.seaTeal
        }
    }
}
