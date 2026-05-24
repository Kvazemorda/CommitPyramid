import Foundation
import CryptoKit

/// Describes a single git repository watched by `GitWatcher`.
///
/// Stored in `AppSettings.gitRepos` (UserDefaults via JSON). All fields
/// except `id` are user-editable or auto-populated at add time.
struct GitRepoSpec: Codable, Identifiable, Hashable {

    // MARK: - Identity

    /// Stable identifier: SHA-256(path + remoteUrl + projectId), hex-encoded.
    /// Changes only when the user edits `projectId` — intentional (a new
    /// projectId represents a semantically different mapping).
    let id: String

    // MARK: - Location

    /// Absolute path to the repository root (must contain `.git`).
    var path: URL

    // MARK: - User-configurable

    /// Name of the city district that receives units from this repo.
    /// Auto-populated from the remote origin URL or directory name.
    var projectId: String

    /// Branch to scan. Defaults to `main`, then `master`, then first branch.
    var branch: String

    // MARK: - Options

    /// If true, runs `git fetch <remote> <branch>` before each scan.
    /// Off by default — fetch требует сети и времени.
    var gitFetch: Bool = false

    /// If true, weights each commit by the number of changed lines (1..5 юнитов).
    /// Включено по умолчанию — крупные коммиты строят больше зданий.
    var weightByDiff: Bool = true

    // MARK: - Init

    init(
        path: URL,
        projectId: String,
        branch: String,
        remoteUrl: String? = nil,
        gitFetch: Bool = false,
        weightByDiff: Bool = true
    ) {
        self.path = path
        self.projectId = projectId
        self.branch = branch
        self.gitFetch = gitFetch
        self.weightByDiff = weightByDiff
        self.id = GitRepoSpec.stableId(path: path, remoteUrl: remoteUrl, projectId: projectId)
    }

    // MARK: - Stable ID

    static func stableId(path: URL, remoteUrl: String?, projectId: String) -> String {
        let raw = (path.path + (remoteUrl ?? "") + projectId).data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: raw)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
