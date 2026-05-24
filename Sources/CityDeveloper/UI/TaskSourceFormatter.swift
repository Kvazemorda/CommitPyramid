import Foundation

/// Превращает строку `UnitState.taskSource` в человекочитаемое описание
/// для отображения в инспекторе квартала.
///
/// Форматы source-ключей (см. NotesWatcher, GitWatcher, TasksJsonlWatcher, MockEventSource):
///   • `git:<repoId>:<sha>` (`#N` суффикс для веса > 1)
///   • `notes:<specId>:<lineHash>`
///   • `mock:<id>:<counter>`
///   • `nil` — событие из tasks.jsonl без явного source-ключа
enum TaskSourceFormatter {

    /// - Parameters:
    ///   - taskSource: значение поля UnitState.taskSource (может быть nil)
    ///   - settings: текущие настройки (для маппинга repoId/specId → путь)
    ///   - tasksJsonlPath: путь к настроенному tasks.jsonl
    /// - Returns: short — для основной строки, full — для tooltip (.help)
    static func format(
        taskSource: String?,
        settings: AppSettings,
        tasksJsonlPath: URL
    ) -> (short: String, full: String) {
        guard let raw = taskSource, !raw.isEmpty else {
            return (
                short: "tasks.jsonl (\(tasksJsonlPath.lastPathComponent))",
                full: tasksJsonlPath.path
            )
        }

        // Разрезаем максимум на 3 части — source-id может содержать ':' внутри hash.
        let parts = raw.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard let kind = parts.first else {
            return (short: raw, full: raw)
        }

        switch kind {
        case "git":
            // git:<repoId>:<sha>(#N)
            guard parts.count == 3 else { return (short: raw, full: raw) }
            let repoId = parts[1]
            let shaRaw = parts[2]
            let sha = shaRaw.split(separator: "#").first.map(String.init) ?? shaRaw
            let shortSha = String(sha.prefix(7))
            if let repo = settings.gitRepos.first(where: { $0.id == repoId }) {
                let name = repo.path.lastPathComponent
                return (
                    short: "git: \(name)@\(shortSha)",
                    full: "\(repo.path.path)\nкоммит \(sha)\nbranch \(repo.branch)"
                )
            }
            return (
                short: "git: <удалённый репо>@\(shortSha)",
                full: "Репозиторий удалён из настроек.\nrepoId=\(repoId)\nкоммит \(sha)"
            )

        case "notes":
            // notes:<specId>:<lineHash>
            guard parts.count >= 2 else { return (short: raw, full: raw) }
            let specId = parts[1]
            if let spec = settings.notesSources.first(where: { $0.id == specId }) {
                return (
                    short: "Заметки: \(spec.path.lastPathComponent)",
                    full: "\(spec.path.path)\nтип: \(spec.kind.rawValue), режим: \(spec.mode.rawValue)"
                )
            }
            return (
                short: "Заметки: <удалённый источник>",
                full: "Источник заметок удалён из настроек.\nspecId=\(specId)"
            )

        case "mock":
            return (short: "mock", full: raw)

        default:
            return (short: raw, full: raw)
        }
    }
}
