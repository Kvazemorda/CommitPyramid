import SpriteKit
import AppKit

/// Фабрика текстуры и тайл-сета для изометрического лугового слоя.
/// Текстура и тайл-сет кэшируются как static let — создаются один раз,
/// переживают пересоздание GameScene без утечек (strong ref живёт в enum, не в сцене).
enum IsoTileFactory {
    static let tileWidth: CGFloat = 64
    static let tileHeight: CGFloat = 32

    /// Кэш-singleton: текстура ромба-травы 128×64 px (Retina-ready ×2).
    static let grassTexture: SKTexture = makeGrassTexture()

    /// SKTileSet с единственной группой "grass" (isometric).
    static let isometricGrassSet: SKTileSet = makeGrassSet()

    private static func makeGrassTexture() -> SKTexture {
        // 128×64 px = логический 64×32 pt × 2 (Retina)
        let pixelSize = CGSize(width: 128, height: 64)
        let image = NSImage(size: pixelSize)
        image.lockFocus()

        let path = NSBezierPath()
        path.move(to: NSPoint(x: 64, y: 64))   // top
        path.line(to: NSPoint(x: 128, y: 32))  // right
        path.line(to: NSPoint(x: 64, y: 0))    // bottom
        path.line(to: NSPoint(x: 0, y: 32))    // left
        path.close()

        Palette.nileGreen.setFill()
        path.fill()

        image.unlockFocus()

        let texture = SKTexture(image: image)
        // Nearest — ромб плоский, без размытия на стыках
        texture.filteringMode = .nearest
        return texture
    }

    private static func makeGrassSet() -> SKTileSet {
        let tileSize = CGSize(width: tileWidth, height: tileHeight)
        let definition = SKTileDefinition(texture: grassTexture, size: tileSize)
        let group = SKTileGroup(tileDefinition: definition)
        group.name = "grass"
        let set = SKTileSet(tileGroups: [group], tileSetType: .isometric)
        set.defaultTileSize = tileSize
        return set
    }
}
