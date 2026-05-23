import Foundation

// MARK: - Errors

enum GitCLIError: Error {
    case notFound
    case timeout
    case exitCode(Int32, String)
}

// MARK: - GitCLI

/// Synchronous Process wrapper for running git commands.
///
/// All arguments are passed as separate array elements — never interpolated
/// into a shell string. This prevents injection from user-supplied paths.
///
/// Thread safety: `run` is synchronous and re-entrant; callers on the same
/// serial queue are serialised by the queue itself.
struct GitCLI {

    /// Primary git path on macOS (Xcode CLI tools / system git).
    static let defaultGitPath = "/usr/bin/git"

    /// Cached resolved git path. Populated on first call.
    private static var resolvedGitPath: String? = nil
    private static let resolveLock = NSLock()

    // MARK: - Path resolution

    /// Returns the path to the git binary, trying `defaultGitPath` first,
    /// then falling back to `which git` via Process.
    /// Returns `nil` if git is not found anywhere.
    static func resolveGitPath() -> String? {
        resolveLock.lock()
        defer { resolveLock.unlock() }
        if let cached = resolvedGitPath { return cached }

        // Check default path first (fastest path, no subprocess)
        if FileManager.default.isExecutableFile(atPath: defaultGitPath) {
            resolvedGitPath = defaultGitPath
            return defaultGitPath
        }

        // Fallback: `which git`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["git"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { return nil }
        resolvedGitPath = path
        return path
    }

    // MARK: - Run

    /// Runs a git command synchronously with the given arguments.
    ///
    /// - Parameters:
    ///   - args: Arguments **excluding** the git binary name itself.
    ///   - cwd: Working directory for the process.
    ///   - timeout: Maximum wall-clock time in seconds (default 10).
    /// - Returns: Tuple of `(stdout: Data, stderr: String, exitCode: Int32)`.
    /// - Throws:
    ///   - `GitCLIError.notFound` if git binary cannot be located.
    ///   - `GitCLIError.timeout` if the process exceeds `timeout`.
    ///   - `GitCLIError.exitCode` if the process exits with a non-zero code.
    @discardableResult
    static func run(
        args: [String],
        cwd: URL,
        timeout: TimeInterval = 10
    ) throws -> (stdout: Data, stderr: String, exitCode: Int32) {
        guard let gitPath = resolveGitPath() else {
            throw GitCLIError.notFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = args
        process.currentDirectoryURL = cwd

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        // Inherit a minimal environment to avoid polluting git with host env vars.
        // Keep HOME and PATH so git can find its config and helpers.
        var env: [String: String] = [:]
        if let home = ProcessInfo.processInfo.environment["HOME"] { env["HOME"] = home }
        if let path = ProcessInfo.processInfo.environment["PATH"] { env["PATH"] = path }
        env["GIT_TERMINAL_PROMPT"] = "0"   // prevent git from hanging on auth prompts
        process.environment = env

        try process.run()

        // Timeout handling via DispatchWorkItem
        var timedOut = false
        let timeoutItem = DispatchWorkItem {
            timedOut = true
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        // Read stdout/stderr before waitUntilExit to avoid pipe-full deadlock.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()
        timeoutItem.cancel()

        if timedOut {
            throw GitCLIError.timeout
        }

        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
        let code = process.terminationStatus

        if code != 0 {
            throw GitCLIError.exitCode(code, stderrStr)
        }

        return (stdout: stdoutData, stderr: stderrStr, exitCode: code)
    }
}
