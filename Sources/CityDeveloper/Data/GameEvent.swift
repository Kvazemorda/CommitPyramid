import Foundation

struct GameEvent: Codable, Identifiable {

    enum Kind: String, Codable, CaseIterable {
        case taskCompleted = "task_completed"
        case unitBuilt     = "unit_built"
        case stageUp       = "stage_up"
        case decayTick     = "decay_tick"
        case fire          = "fire"
        case restore       = "restore"
        case ruinsCleared  = "ruins_cleared"
    }

    let id: UUID
    let ts: Date
    let kind: Kind
    let project: String
    let title: String?
    let taskId: String?
    let source: String?

    init(
        id: UUID = UUID(),
        ts: Date = Date(),
        kind: Kind,
        project: String,
        title: String? = nil,
        taskId: String? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.ts = ts
        self.kind = kind
        self.project = project
        self.title = title
        self.taskId = taskId
        self.source = source
    }
}

extension JSONEncoder {
    static var event: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }
}

extension JSONDecoder {
    static var event: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
