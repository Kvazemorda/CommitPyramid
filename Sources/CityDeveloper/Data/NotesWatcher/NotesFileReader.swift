import Foundation

/// Result of reading a .md file.
struct NotesFileReadResult {
    /// Full text content of the file.
    let text: String
    /// `true` if the file was decoded as UTF-8; `false` means Latin-1 fallback.
    let isUTF8: Bool
}

/// Reads a .md file with UTF-8 → Latin-1 fallback.
///
/// Rules:
/// - Attempt UTF-8 first.
/// - On failure, attempt Latin-1 (ISO 8859-1).
/// - If both fail, log the error and return nil.
/// - `delete-processed` mode is only safe for UTF-8 files (`isUTF8 == true`).
enum NotesFileReader {

    /// Read a file, returning its text and encoding flag.
    /// Returns `nil` if the file cannot be decoded with either encoding.
    static func read(url: URL) -> NotesFileReadResult? {
        // Attempt 1: UTF-8
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return NotesFileReadResult(text: text, isUTF8: true)
        }

        // Attempt 2: Latin-1 fallback
        if let text = try? String(contentsOf: url, encoding: .isoLatin1) {
            ErrorsLog.write("NotesFileReader: Latin-1 fallback for \(url.lastPathComponent)")
            return NotesFileReadResult(text: text, isUTF8: false)
        }

        // Both failed
        ErrorsLog.write("NotesFileReader: cannot decode \(url.path) (tried UTF-8 and Latin-1)")
        return nil
    }
}
