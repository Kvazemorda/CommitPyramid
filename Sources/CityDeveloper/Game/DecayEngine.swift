import Foundation

/// Тикер decay-механики.
/// Запускается из AppDelegate после создания CityEngine.
/// При старте делает catch-up: пересчитывает decay для всех проектов.
/// Тикает раз в 3600 секунд (1 час) на main queue.
final class DecayEngine {

    weak var cityEngine: CityEngine?
    private var timer: DispatchSourceTimer?

    // MARK: - Lifecycle

    func start() {
        recomputeAll()   // catch-up при старте
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 3600, repeating: 3600)
        t.setEventHandler { [weak self] in self?.recomputeAll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Расчёт уровня

    /// Детерминированный расчёт уровня decay по числу дней без активности.
    static func computeLevel(daysSinceActivity: Int) -> Int {
        if daysSinceActivity < 14 { return 0 }
        if daysSinceActivity < 29 { return 1 }
        if daysSinceActivity < 57 { return 2 }
        if daysSinceActivity < 91 { return 3 }
        return 4
    }

    // MARK: - recomputeAll

    private func recomputeAll() {
        guard let engine = cityEngine else { return }

        let now = Date()

        for project in engine.state.projects.values {
            // Пропускаем пустые проекты (без задач)
            guard project.taskCount > 0 else { continue }

            // Edge: lastActivityAt в будущем — пропускаем, логируем предупреждение
            let days = Calendar.current.dateComponents(
                [.day],
                from: project.lastActivityAt,
                to: now
            ).day ?? 0

            guard days >= 0 else {
                ErrorsLog.write(
                    "DecayEngine: project '\(project.id)' has lastActivityAt in the future " +
                    "(\(project.lastActivityAt)) > now (\(now)); decay skipped."
                )
                continue
            }

            let newLevel = Self.computeLevel(daysSinceActivity: days)

            // Если текущий уровень выше, чем залогировано — генерируем системные события
            // для каждого пройденного уровня (catch-up при длинном простое)
            if newLevel > project.lastDecayLogged {
                for level in (project.lastDecayLogged + 1)...newLevel {
                    engine.appendSystemEvent(.decayTick, project: project.id)
                    // При переходе 2→3 дополнительно пишем fire
                    if level == 3 {
                        engine.appendSystemEvent(.fire, project: project.id)
                    }
                }
            }
        }
    }
}
