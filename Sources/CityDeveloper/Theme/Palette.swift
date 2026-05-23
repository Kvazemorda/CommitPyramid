import SpriteKit
import SwiftUI

enum Palette {
    static let sandLight = SKColor(red: 0.91, green: 0.83, blue: 0.64, alpha: 1.0)
    static let sandMid   = SKColor(red: 0.83, green: 0.71, blue: 0.51, alpha: 1.0)
    static let ochre     = SKColor(red: 0.76, green: 0.60, blue: 0.33, alpha: 1.0)
    static let clay      = SKColor(red: 0.71, green: 0.35, blue: 0.24, alpha: 1.0)
    static let nileGreen = SKColor(red: 0.29, green: 0.40, blue: 0.25, alpha: 1.0)
    static let stone     = SKColor(red: 0.55, green: 0.51, blue: 0.46, alpha: 1.0)
    static let skyDay    = SKColor(red: 0.96, green: 0.88, blue: 0.64, alpha: 1.0)
    static let skyDusk   = SKColor(red: 0.77, green: 0.44, blue: 0.29, alpha: 1.0)
    static let skyNight  = SKColor(red: 0.11, green: 0.16, blue: 0.31, alpha: 1.0)
    static let fireOrange = SKColor(red: 0.91, green: 0.36, blue: 0.17, alpha: 1.0)
    static let smokeGrey  = SKColor(red: 0.36, green: 0.34, blue: 0.32, alpha: 1.0)
    static let inkDark    = SKColor(red: 0.16, green: 0.15, blue: 0.13, alpha: 1.0)
    static let parchment  = SKColor(red: 0.95, green: 0.89, blue: 0.77, alpha: 1.0)
    /// Тёмное дерево — «древняя» палитра: брёвна, доски, балки.
    static let warmBrown  = SKColor(red: 0.48, green: 0.30, blue: 0.16, alpha: 1.0)

    // MARK: - Биомные токены (TASK-028, updated BUG-006)
    /// Насыщенная лесная зелень — биом «Лес». Ярче nileGreen для визуальной различимости.
    static let forestGreen  = SKColor(red: 0.13, green: 0.45, blue: 0.15, alpha: 1.0)
    /// Холодный серый — биом «Горы». Светлее rockBrown для чёткого контраста.
    static let mountainGrey = SKColor(red: 0.62, green: 0.62, blue: 0.65, alpha: 1.0)
    /// Тёплый коричнево-бежевый — биом «Камни» (предгорье).
    static let rockBrown    = SKColor(red: 0.68, green: 0.54, blue: 0.36, alpha: 1.0)
    /// Яркая голубая вода — биом «Река».
    static let riverBlue    = SKColor(red: 0.30, green: 0.60, blue: 0.90, alpha: 1.0)
    /// Насыщенный морской синий — биом «Море».
    static let seaTeal      = SKColor(red: 0.15, green: 0.40, blue: 0.68, alpha: 1.0)

    // Semantic tokens
    static let success = NSColor(red: 0.290, green: 0.561, blue: 0.243, alpha: 1.0)
    static let warning = NSColor(red: 0.831, green: 0.608, blue: 0.165, alpha: 1.0)
    static let danger  = NSColor(red: 0.706, green: 0.227, blue: 0.125, alpha: 1.0)
    static let info    = NSColor(red: 0.235, green: 0.416, blue: 0.549, alpha: 1.0)
}

extension Color {
    static let paletteSuccess = Color(Palette.success)
    static let paletteWarning = Color(Palette.warning)
    static let paletteDanger  = Color(Palette.danger)
    static let paletteInfo    = Color(Palette.info)
    static let paletteParchment = Color(red: 0.95, green: 0.89, blue: 0.77)
    static let paletteSandLight = Color(red: 0.91, green: 0.83, blue: 0.64)
    static let paletteInkDark   = Color(red: 0.16, green: 0.15, blue: 0.13)
}
