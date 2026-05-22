import AppKit

final class StatusBarController {

    private let statusItem: NSStatusItem
    private let modeManager: WindowModeManager
    var onSettingsRequested: (() -> Void)?

    init(modeManager: WindowModeManager) {
        self.modeManager = modeManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "🏛"
            button.toolTip = "CityDeveloper"
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let exploreItem = NSMenuItem(
            title: "Открыть город (Explore)",
            action: #selector(toggleMode),
            keyEquivalent: "g"
        )
        exploreItem.keyEquivalentModifierMask = [.command, .option]
        exploreItem.target = self
        menu.addItem(exploreItem)

        let settingsItem = NSMenuItem(
            title: "Настройки…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Выйти",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleMode() {
        modeManager.toggle()
    }

    @objc private func openSettings() {
        onSettingsRequested?()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
