import Foundation

struct TaskRecord: Codable {
    let ts: Date
    let project: String
    let title: String
    let taskId: String?
    let source: String?
    let version: Int?

    enum CodingKeys: String, CodingKey {
        case ts, project, title
        case taskId = "task_id"
        case source, version
    }

    func validate() -> ValidationResult {
        if project.trimmingCharacters(in: .whitespaces).isEmpty {
            return .invalid("empty project")
        }
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            return .invalid("empty title")
        }
        if let v = version, v > 1 {
            return .invalid("unsupported version: \(v)")
        }
        var trimmedTitle = title
        if title.count > 500 {
            trimmedTitle = String(title.prefix(500)) + "…"
        }
        return .valid(trimmedTitle: trimmedTitle)
    }

    enum ValidationResult {
        case valid(trimmedTitle: String)
        case invalid(String)
    }
}
