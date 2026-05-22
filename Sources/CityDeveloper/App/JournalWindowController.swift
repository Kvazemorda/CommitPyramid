import AppKit
import SwiftUI

/// Контроллер floating-окна журнала событий.
/// Паттерн идентичен `SettingsWindowController`: lazy-NSWindow,
/// проверка `window?.isVisible` для idempotent show, `windowWillClose`
/// обнуляет ссылку.
///
/// Состояние фильтров живёт в `ContentView` (@State) и передаётся через
/// @Binding — закрытие окна не сбрасывает значения, они переживают
/// пересоздание `NSHostingController`.
final class JournalWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(engine: CityEngine,
              bridge: SceneBridge,
              collapsed: Binding<Bool>,
              selectedProject: Binding<String?>,
              dateFrom: Binding<Date>,
              dateTo: Binding<Date>,
              didInitDates: Binding<Bool>) {
        // Idempotent: повторное нажатие при открытом окне = makeKey + deminiaturize.
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            w.deminiaturize(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = SidePanelView(
            engine: engine,
            bridge: bridge,
            collapsed: collapsed,
            selectedProject: selectedProject,
            dateFrom: dateFrom,
            dateTo: dateTo,
            didInitDates: didInitDates
        )
        let host = NSHostingController(rootView: panel)

        let w = NSWindow(contentViewController: host)
        w.title = "Журнал событий"
        w.styleMask = [.titled, .closable, .resizable]
        w.setContentSize(NSSize(width: 480, height: 600))
        w.contentMinSize = NSSize(width: 480, height: 600)
        w.delegate = self

        // Центрирование относительно главного окна приложения (мультимонитор-friendly).
        // Fallback — центр главного экрана.
        if let main = NSApp.mainWindow {
            let m = main.frame
            let size = w.frame.size
            let origin = NSPoint(
                x: m.midX - size.width / 2,
                y: m.midY - size.height / 2
            )
            w.setFrameOrigin(origin)
        } else {
            w.center()
        }

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
