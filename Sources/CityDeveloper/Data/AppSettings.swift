import Foundation
import Carbon

final class AppSettings: ObservableObject {
    @Published var tasksJsonlPath: URL
    @Published var dataDirectory: URL
    @Published var hotkeyKeyCode: UInt32
    @Published var hotkeyModifiers: UInt32

    private static let key = "com.outbyte.citydeveloper.settings"

    init(tasksJsonlPath: URL, dataDirectory: URL, hotkeyKeyCode: UInt32, hotkeyModifiers: UInt32) {
        self.tasksJsonlPath = tasksJsonlPath
        self.dataDirectory = dataDirectory
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
    }

    static func load() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data),
           decoded.version == 1 {
            return AppSettings(
                tasksJsonlPath: decoded.tasksJsonlPath,
                dataDirectory: decoded.dataDirectory,
                hotkeyKeyCode: decoded.hotkeyKeyCode,
                hotkeyModifiers: decoded.hotkeyModifiers
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
        let p = Persisted(
            version: 1,
            tasksJsonlPath: tasksJsonlPath,
            dataDirectory: dataDirectory,
            hotkeyKeyCode: hotkeyKeyCode,
            hotkeyModifiers: hotkeyModifiers
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
    }
}
