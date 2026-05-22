import AppKit
import Combine

enum WindowMode {
    case behind
    case explore
}

final class WindowModeManager: ObservableObject {

    private weak var window: NSWindow?
    private(set) var currentMode: WindowMode = .behind
    @Published private(set) var isExplore: Bool = false

    /// Вызывается при каждой смене режима. Bool = isExplore (true = explore, false = behind).
    var onModeChange: ((Bool) -> Void)?

    init(window: NSWindow) {
        self.window = window
    }

    func toggle() {
        switch currentMode {
        case .behind:  enterExploreMode()
        case .explore: enterBehindMode()
        }
    }

    func enterBehindMode() {
        guard let window else { return }
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.ignoresMouseEvents = true
        window.orderBack(nil)
        currentMode = .behind
        isExplore = false
        onModeChange?(false)
    }

    func enterExploreMode() {
        guard let window else { return }
        window.level = .normal
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        currentMode = .explore
        isExplore = true
        onModeChange?(true)
    }
}
