import Foundation
import CryptoKit

/// Parsed result of a single markdown line.
struct ParsedTask {
    /// Project identifier: `[A-Za-z0-9_-]+`, not a reserved word.
    let projectId: String
    /// Task title, trimmed, 1…500 characters.
    let title: String
    /// SHA-256 of the raw (untrimmed) source line, hex-encoded.
    let lineHash: String
    /// Template number 1…4 (for debugging / tests).
    let templateNumber: Int
}

/// Parses individual markdown lines against 4 built-in patterns.
///
/// Priority: 1 → 2 → 3 → 4. First match wins.
enum NotesPatternParser {

    // MARK: - Reserved project IDs (case-insensitive)

    private static let reserved: Set<String> = ["project", "system", "null", "none"]

    // MARK: - Compiled regexes (lazy static — compiled once)

    /// Pattern 1: `- [x] [project: <id>] <title>`
    private static let pattern1 = try! NSRegularExpression(
        pattern: #"^- \[x\] \[project: ([A-Za-z0-9_\-]+)\] (.+)$"#
    )

    /// Pattern 2: `- [x] <title> #<project>`
    private static let pattern2 = try! NSRegularExpression(
        pattern: #"^- \[x\] (.+) #([A-Za-z0-9_\-]+)\s*$"#
    )

    /// Pattern 3: `~~<title>~~ #<project>`
    private static let pattern3 = try! NSRegularExpression(
        pattern: #"^~~(.+?)~~ #([A-Za-z0-9_\-]+)\s*$"#
    )

    /// Pattern 4: `- [x] <project>: <title>` (reserved words excluded)
    private static let pattern4 = try! NSRegularExpression(
        pattern: #"^- \[x\] ([A-Za-z0-9_\-]+): (.+)$"#
    )

    // MARK: - Public API

    /// Parse a single raw line (without trailing newline).
    /// Returns `nil` if no pattern matches.
    static func parse(_ line: String) -> ParsedTask? {
        let hash = sha256(line)

        if let result = match(pattern1, in: line, groupOrder: (project: 1, title: 2)) {
            return ParsedTask(projectId: result.project, title: result.title,
                              lineHash: hash, templateNumber: 1)
        }
        if let result = match(pattern2, in: line, groupOrder: (project: 2, title: 1)) {
            return ParsedTask(projectId: result.project, title: result.title,
                              lineHash: hash, templateNumber: 2)
        }
        if let result = match(pattern3, in: line, groupOrder: (project: 2, title: 1)) {
            return ParsedTask(projectId: result.project, title: result.title,
                              lineHash: hash, templateNumber: 3)
        }
        if let result = match(pattern4, in: line, groupOrder: (project: 1, title: 2),
                              checkReserved: true) {
            return ParsedTask(projectId: result.project, title: result.title,
                              lineHash: hash, templateNumber: 4)
        }

        return nil
    }

    // MARK: - Private helpers

    private static func match(
        _ regex: NSRegularExpression,
        in line: String,
        groupOrder: (project: Int, title: Int),
        checkReserved: Bool = false
    ) -> (project: String, title: String)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = regex.firstMatch(in: line, range: range) else { return nil }

        guard
            let projectRange = Range(m.range(at: groupOrder.project), in: line),
            let titleRange   = Range(m.range(at: groupOrder.title),   in: line)
        else { return nil }

        let projectId = String(line[projectRange])
        let title     = String(line[titleRange]).trimmingCharacters(in: .whitespaces)

        // Validate: projectId must be non-empty after trimming
        guard !projectId.isEmpty, !title.isEmpty else { return nil }

        // Pattern 4 reserved-word filter
        if checkReserved && reserved.contains(projectId.lowercased()) { return nil }

        // title max 500 chars
        let safeTitle = title.count <= 500 ? title : String(title.prefix(500))

        return (projectId, safeTitle)
    }

    private static func sha256(_ text: String) -> String {
        let data = text.data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
