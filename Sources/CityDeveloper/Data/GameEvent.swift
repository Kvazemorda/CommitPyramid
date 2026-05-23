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
        /// TASK-034: визуальная эволюция юнита по порогу F-16.
        /// title = "<unitId.uuidString>|<from.rawValue>|<to.rawValue>"
        case unitEvolved   = "unit_evolved"
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

// MARK: - TASK-034 payload parser

extension GameEvent {
    /// Парсит title события `.unitEvolved` формата "<uuid>|<fromRaw>|<toRaw>".
    /// Возвращает nil если title отсутствует или формат не распознан.
    static func unitEvolvedPayload(from title: String?) -> (unitId: UUID, from: UnitKind, to: UnitKind)? {
        guard let title else { return nil }
        let parts = title.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              let uid = UUID(uuidString: String(parts[0])),
              let fromKind = UnitKind(rawValue: String(parts[1])),
              let toKind   = UnitKind(rawValue: String(parts[2]))
        else { return nil }
        return (uid, fromKind, toKind)
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
