import Foundation
import Combine

/// Periodic scheduler that drives all registered `EventSource` instances.
///
/// Lifecycle:
/// 1. `start()` — runs immediate scan of all registered sources, then starts
///    periodic Timer at `appSettings.catchUpIntervalMinutes` interval.
/// 2. `register(_:)` — adds a source and immediately scans it.
/// 3. `unregister(id:)` — removes a source; next timer tick skips it.
/// 4. `stop()` — cancels Timer and Combine subscription.
///
/// Thread-safety: all public methods and timer events are dispatched on `.main`.
@MainActor
final class CatchUpScheduler {
    private weak var engine: CityEngine?
    private weak var appSettings: AppSettings?
    private var sources: [String: EventSource] = [:]
    private var state: CatchUpState = .load()
    private var timer: DispatchSourceTimer?
    private var isScanning: Bool = false
    private var settingsSub: AnyCancellable?

    init(engine: CityEngine, appSettings: AppSettings) {
        self.engine = engine
        self.appSettings = appSettings
    }

    /// Register a new source. Triggers an immediate scan for that source.
    func register(_ source: EventSource) {
        sources[source.id] = source
        // Immediate scan for newly registered source (outside of general start() scan).
        Task { [weak self] in await self?.scanOne(source) }
    }

    /// Remove a source. Its last_check_ts remains in the state file.
    func unregister(id: String) {
        sources.removeValue(forKey: id)
    }

    /// Start the scheduler: immediate scan of all sources, then periodic Timer.
    func start() {
        // 1. Immediate scan for all currently registered sources.
        let allSources = Array(sources.values)
        Task { [weak self] in
            guard let self else { return }
            for src in allSources { await self.scanOne(src) }
        }

        // 2. Subscribe to interval changes → reschedule Timer automatically.
        if let settings = appSettings {
            settingsSub = settings.$catchUpIntervalMinutes
                .dropFirst() // skip initial value; timer is started below
                .sink { [weak self] _ in
                    self?.rescheduleTimer()
                }
        }

        // 3. Start the timer.
        rescheduleTimer()
    }

    /// Stop the scheduler, cancel timer and subscriptions.
    func stop() {
        timer?.cancel()
        timer = nil
        settingsSub?.cancel()
        settingsSub = nil
    }

    // MARK: - Private

    private func rescheduleTimer() {
        timer?.cancel()
        timer = nil

        let minutes = appSettings?.catchUpIntervalMinutes ?? 5
        let intervalSecs = minutes * 60

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(
            deadline: .now() + .seconds(intervalSecs),
            repeating: .seconds(intervalSecs)
        )
        t.setEventHandler { [weak self] in self?.onTimerFire() }
        t.resume()
        timer = t
    }

    private func onTimerFire() {
        guard !isScanning else {
            ErrorsLog.write("CatchUpScheduler: skip timer tick — previous scan still running")
            return
        }
        let allSources = Array(sources.values)
        Task { [weak self] in
            guard let self else { return }
            self.isScanning = true
            defer { self.isScanning = false }
            for src in allSources { await self.scanOne(src) }
        }
    }

    private func scanOne(_ source: EventSource) async {
        let now = Date()
        let rawSince = state.sources[source.id]?.lastCheckTs ?? .distantPast
        // Guard against clock-skew: lastCheckTs must not be in the future.
        let effectiveSince = min(rawSince, now)

        do {
            let newTs = try await source.scan(since: effectiveSince)
            // Clamp: returned timestamp must not be in the future.
            let safeTs = min(newTs, Date())
            state.sources[source.id] = .init(lastCheckTs: safeTs)
            state.save()
        } catch {
            ErrorsLog.write("CatchUpScheduler: scan '\(source.id)' failed: \(error)")
            // lastCheckTs NOT updated → retry on next tick.
        }
    }
}
