import Foundation

final class EventLog {

    private var fileURL: URL
    private let queue = DispatchQueue(label: "city.eventlog.io")
    private var writeHandle: FileHandle?

    init(fileURL: URL = AppPaths.eventsJsonl) {
        self.fileURL = fileURL
        ensureFileExists()
        openForAppend()
    }

    deinit {
        try? writeHandle?.close()
    }

    func append(_ event: GameEvent) {
        queue.sync {
            do {
                var data = try JSONEncoder.event.encode(event)
                data.append(0x0a)
                try writeHandle?.write(contentsOf: data)
            } catch {
                ErrorsLog.write("EventLog append failed: \(error)")
            }
        }
    }

    func readAll() -> [GameEvent] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [] }
        var events: [GameEvent] = []
        events.reserveCapacity(data.count / 200)
        let decoder = JSONDecoder.event

        var start = data.startIndex
        for i in data.indices {
            if data[i] == 0x0a {
                let lineData = data[start..<i]
                if !lineData.isEmpty {
                    if let event = try? decoder.decode(GameEvent.self, from: Data(lineData)) {
                        events.append(event)
                    } else {
                        ErrorsLog.write("EventLog: undecodable line (offset \(start))")
                    }
                }
                start = data.index(after: i)
            }
        }
        if start < data.endIndex {
            let trailing = data[start..<data.endIndex]
            if let event = try? decoder.decode(GameEvent.self, from: Data(trailing)) {
                events.append(event)
            }
        }
        return events
    }

    func readSince(index: Int) -> [GameEvent] {
        let all = readAll()
        if index < 0 { return all }
        if index >= all.count { return [] }
        return Array(all[(index + 1)...])
    }

    func relocate(to newDirectory: URL) {
        queue.sync {
            try? writeHandle?.close()
            writeHandle = nil
            let newURL = newDirectory.appendingPathComponent("events.jsonl")
            if newURL != fileURL && FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.moveItem(at: fileURL, to: newURL)
            }
            fileURL = newURL
            ensureFileExists()
            openForAppend()
        }
    }

    private func ensureFileExists() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    private func openForAppend() {
        do {
            writeHandle = try FileHandle(forWritingTo: fileURL)
            try writeHandle?.seekToEnd()
        } catch {
            ErrorsLog.write("EventLog: failed to open for append: \(error)")
        }
    }
}
