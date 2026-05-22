import SwiftUI

struct SidePanelView: View {
    @ObservedObject var engine: CityEngine
    @ObservedObject var bridge: SceneBridge

    // State поднят в ContentView и прокидывается через @Binding
    // (сохраняет значения между переключениями режима)
    @Binding var collapsed: Bool
    @Binding var selectedProject: String?
    @Binding var dateFrom: Date
    @Binding var dateTo: Date
    @Binding var didInitDates: Bool

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy HH:mm"
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = .current
        return f
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = .current
        return f
    }()

    // Проекты, отсортированные по lastActivityAt убыв., при равном — по имени возр.
    private var sortedProjects: [ProjectState] {
        engine.state.projects.values.sorted {
            if $0.lastActivityAt != $1.lastActivityAt {
                return $0.lastActivityAt > $1.lastActivityAt
            }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    // Имена проектов для Picker (алфавитный порядок, ru_RU)
    private var projectNames: [String] {
        engine.state.projects.keys.sorted {
            $0.localizedCompare($1) == .orderedAscending
        }
    }

    // Диапазон дат для DatePicker
    private var minEventDate: Date? {
        engine.events.map(\.ts).min()
    }
    private var maxEventDate: Date? {
        engine.events.map(\.ts).max()
    }

    private var filteredEvents: [GameEvent] {
        let dateRangeValid = dateFrom <= dateTo
        return engine.events
            .sorted { $0.ts > $1.ts }
            .filter { e in
                guard e.kind == .taskCompleted else { return false }
                if let sel = selectedProject, !sel.isEmpty {
                    guard e.project == sel else { return false }
                }
                if dateRangeValid {
                    guard e.ts >= dateFrom && e.ts <= dateTo.endOfDay else { return false }
                }
                return true
            }
    }

    private var isEmpty: Bool {
        engine.events.isEmpty && engine.state.projects.isEmpty
    }

    var body: some View {
        if collapsed {
            collapsedView
        } else {
            expandedView
        }
    }

    // MARK: - Collapsed (20 pt strip)

    private var collapsedView: some View {
        VStack {
            Button(action: { withAnimation(.easeOut(duration: 0.18)) { collapsed = false } }) {
                Image(systemName: "chevron.left.2")
                    .frame(width: 20, height: 20)
                    .foregroundColor(.paletteInkDark)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            Spacer()
        }
        .frame(width: 20)
        .background(.regularMaterial)
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.18)) { collapsed = false }
        }
    }

    // MARK: - Expanded (320 pt panel)

    private var expandedView: some View {
        VStack(spacing: 0) {
            // Header row with collapse button
            HStack {
                Text("ИНСПЕКТОР")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(.paletteInkDark)
                    .textCase(.uppercase)
                Spacer()
                Button(action: { withAnimation(.easeOut(duration: 0.18)) { collapsed = true } }) {
                    Image(systemName: "chevron.right.2")
                        .frame(width: 20, height: 20)
                        .foregroundColor(.paletteInkDark)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    projectsSection
                    Divider()
                    journalSection
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .cornerRadius(10, corners: [.topLeft, .bottomLeft])
        .onAppear {
            initDatesIfNeeded()
        }
        .onChange(of: engine.state.projects.count) {
            checkSelectedProjectStillExists()
        }
    }

    // MARK: - Projects Section

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ПРОЕКТЫ")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(.paletteInkDark)
                .padding(.horizontal, 16)

            if isEmpty || sortedProjects.isEmpty {
                Text("Город пуст")
                    .font(.system(size: 12))
                    .foregroundColor(.paletteInkDark.opacity(0.5))
                    .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(sortedProjects, id: \.id) { project in
                        ProjectCard(project: project) {
                            handleProjectTap(project)
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
        }
    }

    // MARK: - Journal Section

    private var journalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ЖУРНАЛ")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(.paletteInkDark)
                .padding(.horizontal, 16)

            // Filters
            VStack(alignment: .leading, spacing: 6) {
                Picker("Проект", selection: $selectedProject) {
                    Text("Все проекты").tag(String?.none)
                    ForEach(projectNames, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }
                }
                .pickerStyle(.menu)
                .disabled(isEmpty)
                .padding(.horizontal, 16)

                HStack(spacing: 8) {
                    Text("с")
                        .font(.system(size: 11))
                        .foregroundColor(.paletteInkDark.opacity(0.7))
                    DatePicker("", selection: $dateFrom,
                               in: datePicker_minDate...datePicker_maxDate,
                               displayedComponents: .date)
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                        .disabled(isEmpty)

                    Text("по")
                        .font(.system(size: 11))
                        .foregroundColor(.paletteInkDark.opacity(0.7))
                    DatePicker("", selection: $dateTo,
                               in: datePicker_minDate...datePicker_maxDate,
                               displayedComponents: .date)
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                        .disabled(isEmpty)
                }
                .padding(.horizontal, 16)
            }

            // Journal rows
            if isEmpty {
                Text("Событий пока нет")
                    .font(.system(size: 12))
                    .foregroundColor(.paletteInkDark.opacity(0.5))
                    .padding(.horizontal, 16)
            } else if dateFrom > dateTo {
                Text("Диапазон пуст")
                    .font(.system(size: 11))
                    .foregroundColor(.paletteInkDark.opacity(0.5))
                    .padding(.horizontal, 16)
            } else if filteredEvents.isEmpty {
                Text("Нет событий в выбранном диапазоне")
                    .font(.system(size: 11))
                    .foregroundColor(.paletteInkDark.opacity(0.5))
                    .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredEvents) { event in
                        VStack(spacing: 0) {
                            JournalRow(event: event, formatter: Self.dateFormatter)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    handleEventTap(event)
                                }
                            Rectangle()
                                .fill(Color.paletteInkDark.opacity(0.12))
                                .frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - DatePicker range helpers

    private var datePicker_minDate: Date {
        minEventDate ?? Date.distantPast
    }

    private var datePicker_maxDate: Date {
        if let maxDate = maxEventDate {
            return Calendar.current.date(byAdding: .day, value: 1, to: maxDate) ?? maxDate
        }
        return Date.distantFuture
    }

    // MARK: - Logic

    private func initDatesIfNeeded() {
        guard !didInitDates, !engine.events.isEmpty else { return }
        let timestamps = engine.events.map(\.ts)
        dateFrom = timestamps.min() ?? Date()
        dateTo = timestamps.max() ?? Date()
        didInitDates = true
    }

    private func checkSelectedProjectStillExists() {
        if let sel = selectedProject, !sel.isEmpty {
            if engine.state.projects[sel] == nil {
                selectedProject = nil
            }
        }
    }

    private func handleProjectTap(_ project: ProjectState) {
        bridge.focusOn(gridPoint: project.districtOrigin)
    }

    private func handleEventTap(_ event: GameEvent) {
        if let unit = findUnit(for: event, in: engine.state) {
            bridge.focusOnUnit(unit)
        } else if let project = engine.state.projects[event.project] {
            // Fallback: фокус на квартале проекта без открытия инспектора
            bridge.focusOn(gridPoint: project.districtOrigin)
        }
        // Если ни юнит, ни проект не найдены — no-op
    }

    private func findUnit(for event: GameEvent, in state: CityState) -> UnitState? {
        guard let title = event.title, !title.isEmpty else { return nil }
        return state.units.values.first {
            $0.projectId == event.project
            && $0.taskTitle == title
            && abs($0.taskTs.timeIntervalSince(event.ts)) < 1.0
        }
    }
}

// MARK: - Journal Row

private struct JournalRow: View {
    let event: GameEvent
    let formatter: DateFormatter

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(formatter.string(from: event.ts))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.paletteInkDark.opacity(0.6))
                .fixedSize()

            Text(event.project)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.paletteInkDark.opacity(0.8))
                .lineLimit(1)

            Text(event.title ?? "—")
                .font(.system(size: 11))
                .foregroundColor(.paletteInkDark.opacity(0.85))
                .lineLimit(2)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
    }
}

// MARK: - Corner Radius Helper

private extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCorners(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft     = RectCorner(rawValue: 1 << 0)
    static let topRight    = RectCorner(rawValue: 1 << 1)
    static let bottomLeft  = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let all: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

private struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: RectCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl: CGFloat = corners.contains(.topLeft)     ? radius : 0
        let tr: CGFloat = corners.contains(.topRight)    ? radius : 0
        let bl: CGFloat = corners.contains(.bottomLeft)  ? radius : 0
        let br: CGFloat = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - br, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bl),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addQuadCurve(to: CGPoint(x: rect.minX + tl, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
