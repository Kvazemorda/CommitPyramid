import AppKit

final class CityWindow: NSWindow {

    static func makeBehindWindow(on screen: NSScreen) -> CityWindow {
        let window = CityWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.setFrame(screen.frame, display: true)
        return window
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
