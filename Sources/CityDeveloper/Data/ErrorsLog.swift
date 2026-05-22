import Foundation

enum ErrorsLog {

    private static let queue = DispatchQueue(label: "city.errors.io")

    static func write(_ message: String) {
        queue.async {
            let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if !FileManager.default.fileExists(atPath: AppPaths.errorsLog.path) {
                FileManager.default.createFile(atPath: AppPaths.errorsLog.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: AppPaths.errorsLog) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }
}
