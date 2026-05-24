import Foundation
import Carbon

final class AppSettings: ObservableObject {
    @Published var tasksJsonlPath: URL
    @Published var dataDirectory: URL
    @Published var hotkeyKeyCode: UInt32
    @Published var hotkeyModifiers: UInt32
    /// F-18 Notes/folder watcher sources. Empty array by default (backward-compat).
    @Published var notesSources: [NotesSourceSpec] = []
    /// F-19 Git watcher repositories. Empty array by default (backward-compat).
    @Published var gitRepos: [GitRepoSpec] = []
    @Published var catchUpIntervalMinutes: Int = 5 {
        didSet {
            if catchUpIntervalMinutes < 3 || catchUpIntervalMinutes > 60 {
                catchUpIntervalMinutes = min(max(catchUpIntervalMinutes, 3), 60)
                ErrorsLog.write("AppSettings: catchUpIntervalMinutes clamped to \(catchUpIntervalMinutes)")
            }
        }
    }
    /// F-24: multiplier applied to git-commit weight during performScan.
    /// Range 0.05…2.0, default 0.1 (≈1 unit per commit regardless of diff size).
    /// didSet guard защищает от бесконечной рекурсии — переприсваиваем ТОЛЬКО
    /// если значение реально выходит за пределы (иначе Swift всегда зовёт didSet
    /// при любом set, включая один и тот же value → stack overflow).
    @Published var commitWeightMultiplier: Double = 0.1 {
        didSet {
            let clamped = min(max(commitWeightMultiplier, 0.05), 2.0)
            if clamped != commitWeightMultiplier { commitWeightMultiplier = clamped }
        }
    }
    /// F-24: multiplier for notes/tasks.jsonl ingestion weight during performScan.
    /// Range 0.5…5.0, default 1.0 (1 unit per closed task).
    @Published var taskWeightMultiplier: Double = 1.0 {
        didSet {
            let clamped = min(max(taskWeightMultiplier, 0.5), 5.0)
            if clamped != taskWeightMultiplier { taskWeightMultiplier = clamped }
        }
    }
    // F-25: District templates
    @Published var templateFamily: String = "auto"
    @Published var previewTemplateSilhouette: Bool = false
    /// TASK-030a F-15: seed карты мира. 0 = «случайный при первом старте/reinit».
    @Published var mapSeed: UInt64 = 0

    private static let key = "com.commitpyramid.app.settings"
    private static let legacyKey = "com.outbyte.citydeveloper.settings"

    init(
        tasksJsonlPath: URL,
        dataDirectory: URL,
        hotkeyKeyCode: UInt32,
        hotkeyModifiers: UInt32,
        catchUpIntervalMinutes: Int = 5,
        notesSources: [NotesSourceSpec] = [],
        gitRepos: [GitRepoSpec] = [],
        commitWeightMultiplier: Double = 0.1,
        taskWeightMultiplier: Double = 1.0,
        templateFamily: String = "auto",
        previewTemplateSilhouette: Bool = false,
        mapSeed: UInt64 = 0
    ) {
        self.tasksJsonlPath = tasksJsonlPath
        self.dataDirectory = dataDirectory
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.notesSources = notesSources
        self.gitRepos = gitRepos
        // Clamp on init without triggering didSet (field not yet observed).
        self.catchUpIntervalMinutes = min(max(catchUpIntervalMinutes, 3), 60)
        self.commitWeightMultiplier = min(max(commitWeightMultiplier, 0.05), 2.0)
        self.taskWeightMultiplier   = min(max(taskWeightMultiplier,   0.5),  5.0)
        self.templateFamily = templateFamily
        self.previewTemplateSilhouette = previewTemplateSilhouette
        self.mapSeed = mapSeed
    }

    static func load() -> AppSettings {
        // One-time migration from legacy key (open-source rename).
        let ud = UserDefaults.standard
        if ud.data(forKey: key) == nil, let legacyData = ud.data(forKey: legacyKey) {
            ud.set(legacyData, forKey: key)
            ud.removeObject(forKey: legacyKey)
        }
        if let data = ud.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data),
           decoded.version >= 1 {
            // Migrate: for v1 files catchUpIntervalMinutes is nil → default 5.
            // v2+ files: notesSources is optional → default [] for backward-compat.
            // v3+ files: commitWeightMultiplier / taskWeightMultiplier optional → defaults.
            // v4→v5: mapSeed optional → default 0.
            // We never reject version >= 1 to avoid resetting existing settings.
            let interval = max(3, min(60, decoded.catchUpIntervalMinutes ?? 5))
            return AppSettings(
                tasksJsonlPath: decoded.tasksJsonlPath,
                dataDirectory: decoded.dataDirectory,
                hotkeyKeyCode: decoded.hotkeyKeyCode,
                hotkeyModifiers: decoded.hotkeyModifiers,
                catchUpIntervalMinutes: interval,
                notesSources: decoded.notesSources ?? [],
                gitRepos: decoded.gitRepos ?? [],
                commitWeightMultiplier: decoded.commitWeightMultiplier ?? 0.1,
                taskWeightMultiplier: decoded.taskWeightMultiplier ?? 1.0,
                templateFamily: decoded.templateFamily ?? "auto",
                previewTemplateSilhouette: decoded.previewTemplateSilhouette ?? false,
                mapSeed: decoded.mapSeed ?? 0
            )
        }
        return AppSettings(
            tasksJsonlPath: AppPaths.tasksJsonl,
            dataDirectory: AppPaths.appSupport,
            hotkeyKeyCode: UInt32(kVK_ANSI_G),
            hotkeyModifiers: UInt32(cmdKey | optionKey)
        )
    }

    func save() {
        let clampedInterval = min(max(catchUpIntervalMinutes, 3), 60)
        let p = Persisted(
            version: 5,
            tasksJsonlPath: tasksJsonlPath,
            dataDirectory: dataDirectory,
            hotkeyKeyCode: hotkeyKeyCode,
            hotkeyModifiers: hotkeyModifiers,
            catchUpIntervalMinutes: clampedInterval,
            notesSources: notesSources.isEmpty ? nil : notesSources,
            gitRepos: gitRepos.isEmpty ? nil : gitRepos,
            commitWeightMultiplier: commitWeightMultiplier,
            taskWeightMultiplier: taskWeightMultiplier,
            templateFamily: templateFamily,
            previewTemplateSilhouette: previewTemplateSilhouette,
            mapSeed: mapSeed
        )
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: AppSettings.key)
        }
    }

    private struct Persisted: Codable {
        let version: Int
        let tasksJsonlPath: URL
        let dataDirectory: URL
        let hotkeyKeyCode: UInt32
        let hotkeyModifiers: UInt32
        // Optional for forward-compatible migration from v1.
        let catchUpIntervalMinutes: Int?
        // Optional for backward-compat: absent field → [] (added in F-18).
        let notesSources: [NotesSourceSpec]?
        // Optional for backward-compat: absent field → [] (added in F-19).
        let gitRepos: [GitRepoSpec]?
        // Optional for backward-compat: absent field → defaults (added in F-24 / v3).
        let commitWeightMultiplier: Double?
        let taskWeightMultiplier: Double?
        let templateFamily: String?              // optional для v1..v3 backward-compat
        let previewTemplateSilhouette: Bool?     // optional для v1..v3 backward-compat
        let mapSeed: UInt64?                     // optional для v1..v4 backward-compat (added in TASK-030a / v5)
    }
}
