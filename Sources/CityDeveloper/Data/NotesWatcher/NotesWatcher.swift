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

    // MARK: - DispatchSource live mode

    private func attachDispatchSource(for spec: NotesSourceSpec) {
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
