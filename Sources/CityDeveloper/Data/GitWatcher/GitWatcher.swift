import Foundation
import AppKit

// MARK: - GitCommit (internal transfer object)

private struct GitCommit {
    let sha: String
    let ts: Date
    let subject: String   // first line of commit message, ≤ 255 chars
}

// MARK: - GitWatcher

/// Scans local git repositories for new commits and ingests them as
/// `taskCompleted` events in `CityEngine`.
///
/// Conforms to `EventSource` so `CatchUpScheduler` drives periodic scans.
///
/// Thread model:
/// - All `git` invocations and per-repo state mutations run on `queue`
///   (a serial background queue).
/// - Engine ingestion is dispatched to `DispatchQueue.main`.
/// - `liveScanInFlight` guards against concurrent live + poll scans for
///   the same repo.
final class GitWatcher: EventSource, @unchecked Sendable {

    // MARK: - EventSource

    let id = "git-watcher"

    func scan(since: Date) async throws -> Date {
        let now = Date()
        let repoList: [GitRepoSpec] = await MainActor.run { Array(repos.values) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                for repo in repoList {
                    self.performScan(repo: repo)
                }
                continuation.resume()
            }
        }
        return now
    }

    // MARK: - Dependencies

    weak var engine: CityEngine?

    // MARK: - Private state (all access on `queue`)

    private let queue = DispatchQueue(label: "city.git.io", qos: .utility)

    /// Current repo specs keyed by `spec.id`.
    private var repos: [String: GitRepoSpec] = [:]

    /// DispatchSource per repo watching `.git/refs/heads/<branch>`.
    private var liveSources: [String: DispatchSourceFileSystemObject] = [:]

    /// Set of repo IDs currently being scanned (prevents overlap between
    /// live-trigger and CatchUpScheduler poll).
    private var liveScanInFlight: Set<String> = []

    // MARK: - Git not found flag

    /// Set to `true` on first `GitCLIError.notFound`. Subsequent scans
    /// skip gracefully to avoid spamming the error log.
    private var gitNotFound = false

    // MARK: - Public API

    /// Register a new repository. Attaches a DispatchSource on the branch
    /// ref file (if it exists) and runs an immediate scan.
    func register(_ spec: GitRepoSpec) {
        queue.async { [weak self] in
            guard let self else { return }
            self.repos[spec.id] = spec
            self.attachLiveSource(for: spec)
            self.performScan(repo: spec)
        }
    }

    /// Remove a repository and cancel its live watcher.
    func unregister(id: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.liveSources[id]?.cancel()
            self.liveSources.removeValue(forKey: id)
            self.repos.removeValue(forKey: id)
        }
    }

    // MARK: - Scanning

    private func performScan(repo: GitRepoSpec) {
        guard !gitNotFound else { return }

        // Guard: prevent overlapping scans for the same repo
        guard !liveScanInFlight.contains(repo.id) else { return }
        liveScanInFlight.insert(repo.id)
        defer { liveScanInFlight.remove(repo.id) }

        let fm = FileManager.default
        let repoPath = repo.path
        let gitDir = repoPath.appendingPathComponent(".git")

        // Validate repo exists and is a git repository
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: repoPath.path, isDirectory: &isDir), isDir.boolValue else {
            ErrorsLog.write("GitWatcher: path not found or not a directory — \(repoPath.path)")
            return
        }
        guard fm.fileExists(atPath: gitDir.path) else {
            ErrorsLog.write("GitWatcher: not a git repository — \(repoPath.path)")
            return
        }

        // Optional: git fetch
        if repo.gitFetch {
            do {
                try GitCLI.run(
                    args: ["-C", repoPath.path, "fetch", "origin", repo.branch],
                    cwd: repoPath,
                    timeout: 10
                )
            } catch {
                ErrorsLog.write("GitWatcher: fetch failed for '\(repoPath.lastPathComponent)': \(error)")
                // Continue with local state
            }
        }

        // Compute `--since` timestamp. Use distantPast for first scan;
        // CatchUpScheduler persists lastCheckTs across restarts.
        // We read the catchup state here to get the per-repo ts.
        let since = loadLastCheckTs(repoId: repo.id)

        // git log with null-byte record separator to handle pipes in subjects
        let sinceISO = ISO8601DateFormatter().string(from: since)
        let logArgs: [String] = [
            "-C", repoPath.path,
            "log", repo.branch,
            "--since", sinceISO,
            "--pretty=tformat:%H%n%ct%n%s%x00",
            "--no-merges",
            "-n", "1000"
        ]

        let stdoutData: Data
        do {
            let result = try GitCLI.run(args: logArgs, cwd: repoPath)
            stdoutData = result.stdout
        } catch GitCLIError.notFound {
            gitNotFound = true
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Git не найден"
                alert.informativeText = "Git не найден в системе. Установите Xcode Command Line Tools (xcode-select --install) или Homebrew git."
                alert.alertStyle = .warning
                alert.runModal()
            }
            return
        } catch GitCLIError.exitCode(let code, let stderr) {
            // Exit code 128 is typical when branch doesn't exist yet (empty repo).
            if code == 128 || stderr.contains("does not have any commits") {
                // Empty repo — update timestamp to avoid re-checking
                saveLastCheckTs(repoId: repo.id, ts: Date())
                return
            }
            ErrorsLog.write("GitWatcher: git log failed for '\(repoPath.lastPathComponent)' branch '\(repo.branch)': \(stderr)")
            return
        } catch {
            ErrorsLog.write("GitWatcher: unexpected error scanning '\(repoPath.lastPathComponent)': \(error)")
            return
        }

        // Parse records: null-byte separated, each record = sha\nct\nsubject
        guard let rawString = String(data: stdoutData, encoding: .utf8) else { return }
        let records = rawString.components(separatedBy: "\0").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var commits: [GitCommit] = []
        for record in records {
            let lines = record.components(separatedBy: "\n")
            guard lines.count >= 3 else { continue }
            let sha = lines[0].trimmingCharacters(in: .whitespaces)
            guard !sha.isEmpty, let ct = Double(lines[1].trimmingCharacters(in: .whitespaces)) else { continue }
            let subject = lines[2...].joined(separator: "\n")   // subject may span lines but we just take it
            let ts = Date(timeIntervalSince1970: ct)
            commits.append(GitCommit(sha: sha, ts: ts, subject: String(subject.prefix(255))))
        }

        // git log returns newest-first; sort ascending for stable replay
        commits.sort { $0.ts < $1.ts }

        // Warn if capped at 1000
        if commits.count >= 1000 {
            ErrorsLog.write("GitWatcher: '\(repoPath.lastPathComponent)' returned ≥1000 commits since last scan — import will continue over multiple poll cycles")
        }

        // Process commits
        var lastProcessedTs: Date? = nil
        var prevSha: String? = nil

        for commit in commits {
            // Category/ignore logic
            if repo.categoryByType && ConventionalCommit.isIgnored(commit.subject) {
                prevSha = commit.sha
                continue
            }

            let title = String(commit.subject.prefix(255))

            // Weight by diff
            let weight: Int
            if repo.weightByDiff, let prev = prevSha {
                weight = computeWeight(repo: repo, prevSha: prev, sha: commit.sha)
            } else {
                weight = 1
            }

            // Category hint (appended to title for now, ignored by UnitPlanner)
            // Task spec says: if no field on GameEvent, use title prefix [feat] style
            // We follow the "no field" approach for minimal scope.

            for i in 0..<weight {
                let suffix = weight > 1 ? "#\(i)" : ""
                let sourceKey = "git:\(repo.id):\(commit.sha)\(suffix)"
                let eventTitle = weight > 1 ? "\(title) (\(i + 1)/\(weight))" : title
                let eventTs = commit.ts.addingTimeInterval(Double(i) * 0.001)

                DispatchQueue.main.sync { [weak self] in
                    self?.engine?.ingestTaskCompletionIfUnique(
                        project: repo.projectId,
                        title: eventTitle,
                        taskId: nil,
                        source: sourceKey,
                        ts: eventTs
                    )
                }
            }

            lastProcessedTs = commit.ts
            prevSha = commit.sha
        }

        // Update lastCheckTs to last processed commit ts + 1s (avoids re-processing
        // on next --since which has second granularity). Dedup by source is the backstop.
        if let lastTs = lastProcessedTs {
            let newTs = lastTs.addingTimeInterval(1)
            saveLastCheckTs(repoId: repo.id, ts: newTs)
        } else if !commits.isEmpty {
            // All commits were ignored (e.g. all chore:) — still advance ts
            if let last = commits.last {
                saveLastCheckTs(repoId: repo.id, ts: last.ts.addingTimeInterval(1))
            }
        } else {
            // No commits found — update to now so we don't re-check the same window
            saveLastCheckTs(repoId: repo.id, ts: Date())
        }
    }

    // MARK: - Diff weight

    private func computeWeight(repo: GitRepoSpec, prevSha: String, sha: String) -> Int {
        let diffArgs: [String] = [
            "-C", repo.path.path,
            "diff", "--shortstat",
            "\(prevSha)..\(sha)"
        ]
        do {
            let result = try GitCLI.run(args: diffArgs, cwd: repo.path)
            guard let text = String(data: result.stdout, encoding: .utf8) else { return 1 }
            let lines = parseDiffShortstat(text)
            switch lines {
            case 0...10:   return 1
            case 11...100: return 2
            case 101...500: return 3
            default:       return 5
            }
        } catch {
            // If diff fails, fall back to weight 1
            return 1
        }
    }

    /// Parses `git diff --shortstat` output, returning total insertions + deletions.
    private func parseDiffShortstat(_ text: String) -> Int {
        // Sample: " 2 files changed, 45 insertions(+), 12 deletions(-)"
        var total = 0
        // Match integers preceding "insertion" and "deletion"
        let pattern = #"(\d+)\s+insertion"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            total += Int(text[range]) ?? 0
        }
        let pattern2 = #"(\d+)\s+deletion"#
        if let regex = try? NSRegularExpression(pattern: pattern2),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            total += Int(text[range]) ?? 0
        }
        return total
    }

    // MARK: - Per-repo lastCheckTs (piggybacks on CatchUpState)

    private func loadLastCheckTs(repoId: String) -> Date {
        let state = CatchUpState.load()
        return state.sources["git-repo-\(repoId)"]?.lastCheckTs ?? .distantPast
    }

    private func saveLastCheckTs(repoId: String, ts: Date) {
        var state = CatchUpState.load()
        state.sources["git-repo-\(repoId)"] = CatchUpState.SourceState(lastCheckTs: ts)
        state.save()
    }

    // MARK: - Live DispatchSource

    /// Attaches a `DispatchSource` watching `.git/refs/heads/<branch>` for
    /// write events, triggering an immediate re-scan. Falls back gracefully
    /// to poll-only if the file doesn't exist (packed refs scenario).
    private func attachLiveSource(for spec: GitRepoSpec) {
        let refFile = spec.path
            .appendingPathComponent(".git")
            .appendingPathComponent("refs")
            .appendingPathComponent("heads")
            .appendingPathComponent(spec.branch)

        guard FileManager.default.fileExists(atPath: refFile.path) else {
            // Packed refs — live watch not available; rely on CatchUpScheduler poll
            return
        }

        let fd = open(refFile.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self, let currentSpec = self.repos[spec.id] else { return }
            self.performScan(repo: currentSpec)
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        liveSources[spec.id] = source
    }
}

// MARK: - projectId auto-resolution

extension GitWatcher {

    /// Resolves the best `projectId` for a newly added repository by parsing
    /// the remote `origin` URL. Falls back to the directory name.
    static func resolveProjectId(at path: URL) -> String {
        do {
            let result = try GitCLI.run(
                args: ["-C", path.path, "remote", "get-url", "origin"],
                cwd: path
            )
            let remote = String(data: result.stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !remote.isEmpty, let parsed = parseRepoName(from: remote) {
                return parsed
            }
        } catch {
            // No remote or error — fall through to directory name
        }
        return path.lastPathComponent
    }

    /// Parses a repository name from an SSH or HTTPS remote URL.
    ///
    /// Handles:
    ///   git@github.com:owner/repo.git   → "repo"
    ///   https://github.com/owner/repo   → "repo"
    ///   https://github.com/owner/repo.git → "repo"
    private static func parseRepoName(from remote: String) -> String? {
        // Single regex covering both SSH and HTTPS formats.
        // The repo name is the final path segment, optionally ending with .git.
        let pattern = #"[:/]([A-Za-z0-9_.\-]+?)(\.git)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: remote, range: NSRange(remote.startIndex..., in: remote)),
              let range = Range(match.range(at: 1), in: remote)
        else { return nil }
        let name = String(remote[range])
        return name.isEmpty ? nil : name
    }
}

// MARK: - Branch auto-pick

extension GitWatcher {

    /// Returns the best default branch for the repository at `path`:
    /// `main` if present, then `master`, then the first local branch.
    /// Returns empty string if no branches exist (fresh repo).
    static func defaultBranch(at path: URL) -> String {
        do {
            let result = try GitCLI.run(
                args: ["-C", path.path, "branch", "--list", "--format=%(refname:short)"],
                cwd: path
            )
            let text = String(data: result.stdout, encoding: .utf8) ?? ""
            let branches = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if branches.contains("main")   { return "main" }
            if branches.contains("master") { return "master" }
            return branches.first ?? "main"
        } catch {
            return "main"
        }
    }
}
