import Foundation

enum AppPaths {

    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("CommitPyramid", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static var tasksJsonl:    URL { appSupport.appendingPathComponent("tasks.jsonl") }
    static var eventsJsonl:   URL { appSupport.appendingPathComponent("events.jsonl") }
    static var stateJson:     URL { appSupport.appendingPathComponent("state.json") }
    static var ingestionState: URL { appSupport.appendingPathComponent("ingestion-state.json") }
    static var errorsLog:     URL { appSupport.appendingPathComponent("errors.log") }
    static var catchupState:  URL { appSupport.appendingPathComponent("catchup-state.json") }
    static var worldmapJson:  URL { appSupport.appendingPathComponent("worldmap.json") }
}
