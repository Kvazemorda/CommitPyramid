import AppKit
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(
        settings: AppSettings,
        notesWatcher: NotesWatcher? = nil,
        gitWatcher: GitWatcher? = nil,
        onSave: @escaping () -> Void
    ) {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(
            settings: settings,
            onSave: { [weak self] in onSave(); self?.window?.close() },
            onCancel: { [weak self] in self?.window?.close() },
            notesWatcher: notesWatcher,
            gitWatcher: gitWatcher
        )
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "Настройки CityDeveloper"
        w.styleMask = [.titled, .closable]
        w.setContentSize(NSSize(width: 720, height: 600))
        w.minSize = NSSize(width: 640, height: 480)
        w.center()
        w.delegate = self
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
