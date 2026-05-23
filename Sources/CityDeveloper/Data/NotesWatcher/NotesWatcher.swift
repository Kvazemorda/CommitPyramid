import Foundation

/// Watches file/folder sources for markdown task completions and ingests them
/// into `CityEngine` via `ingestTaskCompletionIfUnique`.
///
/// Conforms to `EventSource` so `CatchUpScheduler` can drive periodic scans.
///
/// Thread model:
/// - All file I/O, sidecar reads/writes and DispatchSource callbacks run on
///   `queue` (a serial background queue).
/// - Engine ingestion is dispatched to `DispatchQueue.main` (sync, so results
///   are visible before the next sidecar write).
final class NotesWatcher: EventSource, @unchecked Sendable {

    // MARK: - EventSource

    let id = "notes-watcher"

    func scan(since: Date) async throws -> Date {
        let now = Date()
        let specList: [NotesSourceSpec] = await MainActor.run { Array(specs.values) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                for spec in specList {
                    self.performScan(spec)
                }
                continuation.resume()
            }
        }
        return now
    }

    // MARK: - Dependencies

    weak var engine: CityEngine?

    // MARK: - Private state (accessed only on `queue`)

    private let queue = DispatchQueue(label: "city.notes.io", qos: .utility)
    private var specs:       [String: NotesSourceSpec]                        = [:]
    private var stateStores: [String: NotesStateStore]                        = [:]
    private var liveSources: [String: DispatchSourceFileSystemObject]         = [:]

    // MARK: - Public API

    /// Register a new source. Opens sidecar, attaches DispatchSource, runs
    /// an immediate scan.
    func register(_ spec: NotesSourceSpec) {
        queue.async { [weak self] in
            guard let self else { return }
            self.specs[spec.id] = spec
            self.stateStores[spec.id] = NotesStateStore(sourceId: spec.id)
            self.attachDispatchSource(for: spec)
            self.performScan(spec)
        }
    }

    /// Remove a source and cancel its live watcher.
    func unregister(id: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.liveSources[id]?.cancel()
            self.liveSources.removeValue(forKey: id)
            self.stateStores.removeValue(forKey: id)
            self.specs.removeValue(forKey: id)
        }
    }

    // MARK: - Scanning

    /// Scan a single source. Called from the IO queue.
    private func performScan(_ spec: NotesSourceSpec) {
        let fm = FileManager.default

        // Resolve which .md files to process
        let mdFiles: [URL]
        switch spec.kind {
        case .file:
            mdFiles = [spec.path]
        case .folder:
            mdFiles = listMarkdownFiles(in: spec.path, recursive: false)
        case .folderRecursive:
            mdFiles = listMarkdownFiles(in: spec.path, recursive: true)
        case .appleNoteFolder:
            scanAppleNotesFolder(spec: spec, stateStore: stateStores[spec.id])
            return
        }

        // Soft-warn for huge vaults
        if mdFiles.count > 500 {
            ErrorsLog.write("NotesWatcher: source '\(spec.path.lastPathComponent)' has \(mdFiles.count) .md files — consider restricting scope")
        }

        guard let stateStore = stateStores[spec.id] else { return }

        for fileURL in mdFiles {
            // Resolve symlinks / check reachability
            guard fm.fileExists(atPath: fileURL.path) else {
                ErrorsLog.write("NotesWatcher: file not found — \(fileURL.path)")
                continue
            }

            guard let readResult = NotesFileReader.read(url: fileURL) else {
                continue // error already logged by NotesFileReader
            }

            // Determine effective mode (downgrade delete-processed for non-UTF-8)
            let effectiveMode: NotesSourceSpec.ProcessingMode
            if spec.mode == .deleteProcessed && !readResult.isUTF8 {
                ErrorsLog.write("NotesWatcher: downgrading delete-processed → sidecar-dedup for non-UTF-8 file '\(fileURL.lastPathComponent)'")
                effectiveMode = .sidecarDedup
            } else {
                effectiveMode = spec.mode
            }

            processFileContent(
                text: readResult.text,
                fileURL: fileURL,
                spec: spec,
                effectiveMode: effectiveMode,
                stateStore: stateStore
            )
        }
    }

    /// Process all lines of a file, ingesting matches and applying post-processing.
    private func processFileContent(
        text: String,
        fileURL: URL,
        spec: NotesSourceSpec,
        effectiveMode: NotesSourceSpec.ProcessingMode,
        stateStore: NotesStateStore
    ) {
        let lines = text.components(separatedBy: .newlines)
        // Track which line indices were matched (for delete-processed)
        var matchedIndices: Set<Int> = []

        for (idx, line) in lines.enumerated() {
            guard let parsed = NotesPatternParser.parse(line) else { continue }

            // Sidecar dedup check
            if effectiveMode == .sidecarDedup && stateStore.contains(parsed.lineHash) {
                continue
            }

            let sourceKey = "notes:\(spec.id):\(parsed.lineHash)"

            // Get file modification time for event timestamp
            let mtime = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date ?? Date()

            // Ingest on main queue (synchronously to ensure dedup before sidecar write).
            // Use the idempotent variant — dedup by source key in events.jsonl.
            DispatchQueue.main.sync { [weak self] in
                self?.engine?.ingestTaskCompletionIfUnique(
                    project: parsed.projectId,
                    title: parsed.title,
                    taskId: nil,
                    source: sourceKey,
                    ts: mtime
                )
            }

            // Post-processing
            switch effectiveMode {
            case .sidecarDedup:
                stateStore.markProcessed(parsed.lineHash)
            case .deleteProcessed:
                matchedIndices.insert(idx)
            }
        }

        // Apply delete-processed: atomic re-write without matched lines
        if effectiveMode == .deleteProcessed && !matchedIndices.isEmpty {
            let remaining = lines.indices
                .filter { !matchedIndices.contains($0) }
                .map { lines[$0] }
            let newContent = remaining.joined(separator: "\n")

            // If the remaining content is blank/whitespace — remove the file
            if newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                } catch {
                    ErrorsLog.write("NotesWatcher: failed to remove empty file \(fileURL.path): \(error)")
                }
            } else {
                guard let data = newContent.data(using: .utf8) else { return }
                do {
                    try data.write(to: fileURL, options: .atomic)
                } catch {
                    ErrorsLog.write("NotesWatcher: failed to write delete-processed to \(fileURL.path): \(error)")
                }
            }
        }
    }

    // MARK: - Directory enumeration

    private func listMarkdownFiles(in directory: URL, recursive: Bool) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else {
            ErrorsLog.write("NotesWatcher: source directory not found — \(directory.path)")
            return []
        }

        if recursive {
            guard let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }

            var result: [URL] = []
            for case let url as URL in enumerator {
                if url.pathExtension.lowercased() == "md" {
                    result.append(url)
                }
            }
            return result
        } else {
            // Non-recursive: immediate children only
            guard let contents = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return contents.filter { $0.pathExtension.lowercased() == "md" }
        }
    }

    // MARK: - Apple Notes scanning

    /// Scans all notes in the named Apple Notes folder and processes them.
    private func scanAppleNotesFolder(spec: NotesSourceSpec, stateStore: NotesStateStore?) {
        guard let stateStore else { return }

        // Extract folder name: apple-notes:///MyFolder → "MyFolder"
        let rawLastComponent = spec.path.lastPathComponent
        let folderName = rawLastComponent.removingPercentEncoding ?? rawLastComponent

        let script = """
        tell application "Notes"
            set output to ""
            try
                set theFolder to folder "\(folderName)"
                repeat with aNote in (notes of theFolder)
                    set output to output & "---NOTESEP---" & (body of aNote) & linefeed
                end repeat
            end try
            return output
        end tell
        """

        guard let raw = runOsascript(script), !raw.isEmpty else { return }

        let parts = raw.components(separatedBy: "---NOTESEP---")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let stripped = stripHTML(trimmed)
            processFileContent(
                text: stripped,
                fileURL: spec.path,
                spec: spec,
                effectiveMode: .sidecarDedup,
                stateStore: stateStore
            )
        }
    }

    /// Writes `script` to a temp file and runs `/usr/bin/osascript`, returning stdout.
    private func runOsascript(_ script: String) -> String? {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("citynotes_\(UUID().uuidString).applescript")
        do {
            try script.write(to: tmpURL, atomically: true, encoding: .utf8)
        } catch {
            ErrorsLog.write("NotesWatcher: failed to write osascript temp file: \(error)")
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = [tmpURL.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()   // suppress stderr noise

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            ErrorsLog.write("NotesWatcher: osascript launch failed: \(error)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    /// Strips HTML tags and decodes common HTML entities from a string.
    private func stripHTML(_ html: String) -> String {
        // Remove everything between < and > (tags)
        var result = html.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        // Decode common HTML entities
        result = result
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        return result
    }

    // MARK: - DispatchSource live mode

    private func attachDispatchSource(for spec: NotesSourceSpec) {
        // Apple Notes sources have no filesystem path — skip DispatchSource setup.
        guard spec.kind != .appleNoteFolder else { return }

        // For all kinds we watch the top-level path: the file itself (.file),
        // or the directory (.folder / .folderRecursive).
        let watchURL = spec.path

        let fd = open(watchURL.path, O_EVTONLY)
        guard fd >= 0 else {
            ErrorsLog.write("NotesWatcher: cannot open \(watchURL.path) for DispatchSource (O_EVTONLY)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            // On delete/rename, cancel the source; it will be recreated on next periodic scan
            let data = source.data
            if data.contains(.delete) || data.contains(.rename) {
                source.cancel()
                self.liveSources.removeValue(forKey: spec.id)
                return
            }
            // Write/extend: re-scan the source
            if let currentSpec = self.specs[spec.id] {
                self.performScan(currentSpec)
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        liveSources[spec.id] = source
    }
}
