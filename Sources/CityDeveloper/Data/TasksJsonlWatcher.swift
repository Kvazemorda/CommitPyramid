import Foundation

final class TasksJsonlWatcher {

    private var fileURL: URL
    private let engine: CityEngine
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var ingestion: IngestionState
    private let queue = DispatchQueue(label: "city.watcher.io")
    /// F-24: read taskWeightMultiplier when ingesting lines (applies on Reset replay).
    weak var appSettings: AppSettings?

    init(fileURL: URL = AppPaths.tasksJsonl, engine: CityEngine) {
        self.fileURL = fileURL
        self.engine = engine

        if let saved = IngestionState.load(), saved.filePath == fileURL.path {
            self.ingestion = saved
        } else {
            self.ingestion = IngestionState(
                filePath: fileURL.path,
                offsetBytes: 0,
                lastReadTs: .distantPast
            )
        }

        ensureFileExists()
        if ingestion.offsetBytes == 0 { ingestion.save() }
    }

    func start() {
        readTailIfNeeded()
        attachSource()
    }

    func stop() {
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    func restart(at newURL: URL) {
        stop()
        queue.sync {
            let pathChanged = newURL.path != self.fileURL.path
            self.fileURL = newURL
            if pathChanged {
                self.ingestion.offsetBytes = 0
                self.ingestion.filePath = newURL.path
                self.ingestion.save()
            }
        }
        ensureFileExists()
        start()
    }

    private func ensureFileExists() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    private func attachSource() {
        fileDescriptor = open(fileURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            ErrorsLog.write("Watcher: failed to open fd for \(fileURL.path)")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let mask = src.data
            if mask.contains(.delete) || mask.contains(.rename) {
                self.handleFileReplaced()
                return
            }
            self.readTailIfNeeded()
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }
        src.resume()
        self.source = src
    }

    private func handleFileReplaced() {
        stop()
        ingestion.offsetBytes = 0
        ingestion.save()
        ensureFileExists()
        attachSource()
        readTailIfNeeded()
    }

    private func readTailIfNeeded() {
        queue.async { [weak self] in
            guard let self else { return }
            self.readTailNow()
        }
    }

    private func readTailNow() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? UInt64 else { return }

        if size < ingestion.offsetBytes {
            ingestion.offsetBytes = 0
        }
        if size == ingestion.offsetBytes { return }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: ingestion.offsetBytes)
            let data = handle.readDataToEndOfFile()
            let consumed = processChunk(data, startOffset: ingestion.offsetBytes)
            ingestion.offsetBytes += UInt64(consumed)
            ingestion.lastReadTs = Date()
            ingestion.save()
        } catch {
            ErrorsLog.write("Watcher: read failed: \(error)")
        }
    }

    private func processChunk(_ data: Data, startOffset: UInt64) -> Int {
        // Парсим только полные строки (заканчивающиеся \n).
        // Хвост без \n оставляем для следующего тика.
        var i = data.startIndex
        var lineStart = i
        let decoder = JSONDecoder.event

        while i < data.endIndex {
            if data[i] == 0x0a {
                let lineData = data[lineStart..<i]
                handleLine(lineData, decoder: decoder, offset: startOffset + UInt64(lineStart - data.startIndex))
                lineStart = data.index(after: i)
            }
            i = data.index(after: i)
        }
        return lineStart - data.startIndex
    }

    private func handleLine(_ lineData: Data.SubSequence, decoder: JSONDecoder, offset: UInt64) {
        let trimmed = lineData.drop(while: { $0 == 0x20 || $0 == 0x09 })
        guard !trimmed.isEmpty else { return }
        if trimmed.first == 0x23 { return }  // '#' — комментарий

        let bytes = Data(trimmed)
        do {
            let record = try decoder.decode(TaskRecord.self, from: bytes)
            switch record.validate() {
            case .valid(let trimmedTitle):
                // F-24: apply taskWeightMultiplier — repeat ingest N times (≥1) per record.
                let multiplier = appSettings?.taskWeightMultiplier ?? 1.0
                let repeatCount = max(1, Int(round(multiplier)))
                for j in 0..<repeatCount {
                    let suffix = repeatCount > 1 ? "#\(j)" : ""
                    let src = (record.source ?? "tasks:\(record.taskId ?? UUID().uuidString)") + suffix
                    let ts = record.ts.addingTimeInterval(Double(j) * 0.001)
                    DispatchQueue.main.async { [weak self] in
                        self?.engine.ingestTaskCompletion(
                            project: record.project,
                            title: trimmedTitle,
                            taskId: record.taskId,
                            source: src,
                            ts: ts
                        )
                    }
                }
            case .invalid(let reason):
                ErrorsLog.write("Watcher: invalid line at offset \(offset): \(reason)")
            }
        } catch {
            ErrorsLog.write("Watcher: undecodable line at offset \(offset): \(error)")
        }
    }
}
