import Foundation

/// Parses conventional-commit prefixes to derive unit category hints.
///
/// Specification (F-19):
///   feat:     → residential   (new building)
///   fix:      → infrastructure (repair)
///   refactor: → production
///   docs:     → social
///   chore / style / wip → ignored (event suppressed)
///   anything else       → nil (UnitPlanner decides, defaults to residential)
///
/// Case-insensitive. Only the first colon segment is considered, so
/// `docs: fix: typo` → prefix `docs`.
enum ConventionalCommit {

    // MARK: - Category mapping

    /// Returns a `UnitCategory` hint for the commit subject, or `nil` if
    /// the prefix is unknown / not a conventional-commit message.
    static func category(from subject: String) -> UnitCategory? {
        guard let prefix = extractPrefix(from: subject) else { return nil }
        switch prefix {
        case "feat":     return .residential
        case "fix":      return .infrastructure
        case "refactor": return .production
        case "docs":     return .social
        default:         return nil
        }
    }

    // MARK: - Ignored prefixes

    /// Returns `true` if the commit should be suppressed entirely when
    /// `categoryByType` is enabled.
    static func isIgnored(_ subject: String) -> Bool {
        guard let prefix = extractPrefix(from: subject) else { return false }
        return ["chore", "style", "wip"].contains(prefix)
    }

    // MARK: - Prefix extraction

    /// Extracts the lowercase conventional-commit prefix (segment before
    /// the first `:`). Handles optional scope `feat(scope):` by stripping
    /// anything in parentheses.
    ///
    ///   "feat: add login"        → "feat"
    ///   "Fix: typo"              → "fix"
    ///   "feat(auth): login"      → "feat"
    ///   "docs: fix: typo"        → "docs"
    ///   "no colon here"          → nil
    private static func extractPrefix(from subject: String) -> String? {
        guard let colonIndex = subject.firstIndex(of: ":") else { return nil }
        var raw = String(subject[subject.startIndex..<colonIndex])
        // Strip optional scope `(...)` e.g. `feat(auth)` → `feat`
        if let parenStart = raw.firstIndex(of: "(") {
            raw = String(raw[raw.startIndex..<parenStart])
        }
        let normalized = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}
