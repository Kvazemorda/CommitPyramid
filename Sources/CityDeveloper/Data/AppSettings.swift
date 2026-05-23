import Foundation
import Carbon

final class AppSettings: ObservableObject {
    @Published var tasksJsonlPath: URL
    @Published var dataDirectory: URL
    @Published var hotkeyKeyCode: UInt32
    @Published var hotkeyModifiers: UInt32
    @Published var catchUpIntervalMinutes: Int = 5 {
        didSet {
            if catchUpIntervalMinutes < 3 || catchUpIntervalMinutes > 60 {
                catchUpIntervalMinutes = min(max(catchUpIntervalMinutes, 3), 60)
                ErrorsLog.write("AppSettings: catchUpIntervalMinutes clamped to \(catchUpIntervalMinutes)")
            }
        }
    }

    private static let key = "com.outbyte.citydeveloper.settings"

    init(
        tasksJsonlPath: URL,
        dataDirectory: URL,
        hotkeyKeyCode: UInt32,
        hotkeyModifiers: UInt32,
        catchUpIntervalMinutes: Int = 5
    ) {
        self.tasksJsonlPath = tasksJsonlPath
        self.dataDirectory = dataDirectory
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        // Clamp on init without triggering didSet (field not yet observed).
        self.catchUpIntervalMinutes = min(max(catchUpIntervalMinutes, 3), 60)
    }

    static func load() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data),
           decoded.version >= 1 {
            // Migrate: for v1 files catchUpIntervalMinutes is nil → default 5.
            // We never reject version >= 1 to avoid resetting existing settings.
            let interval = max(3, min(60, decoded.catchUpIntervalMinutes ?? 5))
            return AppSettings(
                tasksJsonlPath: decoded.tasksJsonlPath,
                dataDirectory: decoded.dataDirectory,
                hotkeyKeyCode: decoded.hotkeyKeyCode,
                hotkeyModifiers: decoded.hotkeyModifiers,
                catchUpIntervalMinutes: interval
            )
        }
        return AppSettings(
            tasksJsonlPath: AppPaths.tasksJsonl,
            dataDirectory: AppPaths.appSupport,
            hotkeyKeyCode: UInt32(kVK_ANSI_G),
            hotkeyModifiers: UInt32(cmdKey | optionKey)
        )
    }

    func save() {
        let clampedInterval = min(max(catchUpIntervalMinutes, 3), 60)
        let p = Persisted(
            version: 2,
            tasksJsonlPath: tasksJsonlPath,
            dataDirectory: dataDirectory,
            hotkeyKeyCode: hotkeyKeyCode,
            hotkeyModifiers: hotkeyModifiers,
            catchUpIntervalMinutes: clampedInterval
        )
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: AppSettings.key)
        }
    }

    private struct Persisted: Codable {
        let version: Int
        let tasksJsonlPath: URL
        let dataDirectory: URL
        let hotkeyKeyCode: UInt32
        let hotkeyModifiers: UInt32
        // Optional for forward-compatible migration from v1.
        let catchUpIntervalMinutes: Int?
    }
}
