import Foundation

enum ErrorsLog {

    private static let queue = DispatchQueue(label: "city.errors.io")

    /// Default writer: appends message to the on-disk errors log file asynchronously.
    /// Extracted so tests can replace `writer` with a synchronous capture closure.
    private static let defaultWriter: (String) -> Void = { message in
        queue.async {
            let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if !FileManager.default.fileExists(atPath: AppPaths.errorsLog.path) {
                FileManager.default.createFile(atPath: AppPaths.errorsLog.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: AppPaths.errorsLog) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }

    /// Test seam: replace this closure in setUp / restore in tearDown to capture log messages.
    /// In production this always equals `defaultWriter`.
    static var writer: (String) -> Void = defaultWriter

    static func write(_ message: String) {
        Self.writer(message)
    }

    /// Resets `writer` back to the default file-based implementation.
    /// Call this in tearDown to avoid cross-test pollution.
    static func resetWriter() {
        writer = defaultWriter
    }
}
