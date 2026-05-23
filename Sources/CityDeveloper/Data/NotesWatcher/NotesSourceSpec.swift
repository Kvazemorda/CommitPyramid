import Foundation
import CryptoKit

/// Describes a single notes-watcher source (file, folder, or recursive folder).
struct NotesSourceSpec: Codable, Identifiable, Hashable {

    // MARK: - Nested types

    enum SourceKind: String, Codable, CaseIterable {
        case file
        case folder
        case folderRecursive
    }

    enum ProcessingMode: String, Codable, CaseIterable {
        /// After a matched line is successfully ingested, the line is deleted
        /// from the source .md file. UTF-8-only; Latin-1 files auto-downgrade
        /// to sidecarDedup with a warning in ErrorsLog.
        case deleteProcessed
        /// A sidecar JSON file in the app's data directory records SHA-256 hashes
        /// of processed lines. Source files are never modified.
        case sidecarDedup
    }

    // MARK: - Stored properties

    /// Stable identifier: SHA-256(path + kind.rawValue), hex-encoded.
    let id: String

    /// Absolute path to the file or folder.
    var path: URL

    var kind: SourceKind
    var mode: ProcessingMode

    // MARK: - Init (auto-derives id from path + kind)

    init(path: URL, kind: SourceKind, mode: ProcessingMode) {
        self.path = path
        self.kind = kind
        self.mode = mode
        self.id = NotesSourceSpec.stableId(path: path, kind: kind)
    }

    // MARK: - Helpers

    static func stableId(path: URL, kind: SourceKind) -> String {
        let raw = (path.path + kind.rawValue).data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: raw)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
