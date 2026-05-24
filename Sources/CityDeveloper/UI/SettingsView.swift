import SwiftUI
import AppKit
import Carbon

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var draftTasksPath: URL
    @State private var draftDataDir: URL
    @State private var draftKeyCode: UInt32
    @State private var draftModifiers: UInt32
    @State private var alertMessage: String? = nil
    @State private var showingRecorder = false

    var onSave: () -> Void
    var onCancel: () -> Void
    /// Optional watcher reference for hot-registration of new sources.
    weak var notesWatcher: NotesWatcher?
    /// Optional git watcher reference for hot-registration of new repos.
    weak var gitWatcher: GitWatcher?
    /// Optional AppDelegate reference for Reset & Rebuild.
    weak var appDelegate: AppDelegate?

    @State private var replaySinceDate: Date = Calendar.current.date(
        byAdding: .month, value: -3, to: Date()) ?? Date()

    init(
        settings: AppSettings,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        notesWatcher: NotesWatcher? = nil,
        gitWatcher: GitWatcher? = nil,
        appDelegate: AppDelegate? = nil
    ) {
        self.settings = settings
        self.onSave = onSave
        self.onCancel = onCancel
        self.notesWatcher = notesWatcher
        self.gitWatcher = gitWatcher
        self.appDelegate = appDelegate
        _draftTasksPath = State(initialValue: settings.tasksJsonlPath)
        _draftDataDir = State(initialValue: settings.dataDirectory)
        _draftKeyCode = State(initialValue: settings.hotkeyKeyCode)
        _draftModifiers = State(initialValue: settings.hotkeyModifiers)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Данные") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("tasks.jsonl:")
                                .frame(width: 100, alignment: .trailing)
                            Text(draftTasksPath.path)
                                .truncationMode(.middle)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Выбрать…") { pickTasks() }
                        }
                        HStack {
                            Text("Папка данных:")
                                .frame(width: 100, alignment: .trailing)
                            Text(draftDataDir.path)
                                .truncationMode(.middle)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Выбрать…") { pickDataDir() }
                        }
                    }
                    .padding(8)
                }

                GroupBox("Hotkey") {
                    HStack {
                        Text("Explore режим:")
                            .frame(width: 100, alignment: .trailing)
                        Text(hotkeyDisplay(keyCode: draftKeyCode, modifiers: draftModifiers))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Изменить…") { showingRecorder = true }
                    }
                    .padding(8)
                }

                GroupBox("Catch-up") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Интервал, мин:")
                                .frame(width: 100, alignment: .trailing)
                            // Live binding: didSet in AppSettings clamps + logs,
                            // CatchUpScheduler reschedules Timer via Combine sink.
                            Stepper(value: $settings.catchUpIntervalMinutes, in: 3...60) {
                                Text("\(settings.catchUpIntervalMinutes)")
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        Text("Как часто проверять источники задач (notes, git). Меньше — быстрее реагирует, больше — экономит ресурсы.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                NotesWatcherSection(
                    settings: settings,
                    onSourceAdded:   { [weak notesWatcher] spec in notesWatcher?.register(spec) },
                    onSourceRemoved: { [weak notesWatcher] id   in notesWatcher?.unregister(id: id) }
                )

                GitWatcherSection(
                    settings: settings,
                    onRepoAdded:   { [weak gitWatcher] spec in gitWatcher?.register(spec) },
                    onRepoRemoved: { [weak gitWatcher] id   in gitWatcher?.unregister(id: id) }
                )

                MapWorldSection(settings: settings)

                TemplateFamilySection(settings: settings)

                GroupBox("Reset & Rebuild") {
                    VStack(alignment: .leading, spacing: 8) {
                        DatePicker("Replay events since:",
                                   selection: $replaySinceDate,
                                   displayedComponents: [.date])
                        Button("Reset city and rebuild") {
                            confirmReset()
                        }
                        .foregroundStyle(.red)
                        Text("This will erase the current city and re-import all completed tasks and commits from your configured sources since the chosen date.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }

                HStack {
                    Spacer()
                    Button("Отмена") { onCancel() }
                    Button("Сохранить") { trySave() }
                        .keyboardShortcut(.return)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 640, minHeight: 480)
        .alert("Ошибка", isPresented: .constant(alertMessage != nil)) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(isPresented: $showingRecorder) {
            HotkeyRecorderView(keyCode: $draftKeyCode, modifiers: $draftModifiers, isPresented: $showingRecorder)
        }
    }

    private func pickTasks() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = []
        panel.message = "Выберите файл tasks.jsonl"
        if panel.runModal() == .OK, let url = panel.url {
            draftTasksPath = url
        }
    }

    private func pickDataDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Выберите папку для данных игры"
        if panel.runModal() == .OK, let url = panel.url {
            draftDataDir = url
        }
    }

    private func trySave() {
        // Validate tasks path
        guard FileManager.default.isReadableFile(atPath: draftTasksPath.path) else {
            alertMessage = "Файл tasks.jsonl не найден или недоступен по пути:\n\(draftTasksPath.path)"
            return
        }
        // Validate data directory write access
        let testFile = draftDataDir.appendingPathComponent(".citydev_write_test")
        guard (try? "test".write(to: testFile, atomically: true, encoding: .utf8)) != nil else {
            alertMessage = "Папка данных недоступна для записи:\n\(draftDataDir.path)"
            return
        }
        try? FileManager.default.removeItem(at: testFile)
        // Apply
        settings.tasksJsonlPath = draftTasksPath
        settings.dataDirectory = draftDataDir
        settings.hotkeyKeyCode = draftKeyCode
        settings.hotkeyModifiers = draftModifiers
        settings.save()
        onSave()
    }

    private func confirmReset() {
        let dateStr = DateFormatter.localizedString(from: replaySinceDate,
                                                    dateStyle: .medium,
                                                    timeStyle: .none)
        let alert = NSAlert()
        alert.messageText = "Reset city?"
        alert.informativeText = "This will erase the current city and rebuild from all event sources since \(dateStr). Continue?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        appDelegate?.resetCity(replaySince: replaySinceDate)
        onCancel() // Close settings window after reset.
    }

    private func hotkeyDisplay(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        let keyName: String
        switch keyCode {
        case UInt32(kVK_ANSI_G): keyName = "G"
        case UInt32(kVK_ANSI_H): keyName = "H"
        case UInt32(kVK_ANSI_J): keyName = "J"
        default: keyName = "(\(keyCode))"
        }
        parts.append(keyName)
        return parts.joined()
    }
}

struct HotkeyRecorderView: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @Binding var isPresented: Bool
    @State private var monitor: Any? = nil
    @State private var recordedDisplay = "Ожидание..."

    var body: some View {
        VStack(spacing: 20) {
            Text("Нажмите новую комбинацию клавиш")
                .font(.headline)
            Text(recordedDisplay)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .padding()
                .frame(minWidth: 200)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            HStack {
                Button("Отмена") {
                    removeMonitor()
                    isPresented = false
                }
            }
        }
        .padding(30)
        .onAppear { startMonitor() }
        .onDisappear { removeMonitor() }
    }

    private func startMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags
            var carbonMods: UInt32 = 0
            if mods.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if mods.contains(.option) { carbonMods |= UInt32(optionKey) }
            if mods.contains(.control) { carbonMods |= UInt32(controlKey) }
            if mods.contains(.shift) { carbonMods |= UInt32(shiftKey) }
            // Require at least one modifier
            guard carbonMods != 0 else { return event }
            keyCode = UInt32(event.keyCode)
            modifiers = carbonMods
            recordedDisplay = displayFor(code: keyCode, mods: carbonMods)
            removeMonitor()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isPresented = false }
            return nil
        }
    }

    private func removeMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func displayFor(code: UInt32, mods: UInt32) -> String {
        var p: [String] = []
        if mods & UInt32(cmdKey) != 0 { p.append("⌘") }
        if mods & UInt32(optionKey) != 0 { p.append("⌥") }
        if mods & UInt32(controlKey) != 0 { p.append("⌃") }
        if mods & UInt32(shiftKey) != 0 { p.append("⇧") }
        switch code {
        case UInt32(kVK_ANSI_G): p.append("G")
        case UInt32(kVK_ANSI_H): p.append("H")
        default: p.append("(\(code))")
        }
        return p.joined()
    }
}

// TASK-051 F-25: секция выбора стиля города (templateFamily + silhouette debug toggle).
private struct TemplateFamilySection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        GroupBox(label: Label("Стиль города", systemImage: "building.columns")) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Стиль:", selection: $settings.templateFamily) {
                    Text("Auto (по биому)").tag("auto")
                    Text("Mixed (рандом на проект)").tag("mixed")
                    ForEach(availableFamilies, id: \.self) { f in
                        Text(humanName(f)).tag(f)
                    }
                }
                .pickerStyle(.menu)
                Toggle(
                    "Превью контура шаблона при создании квартала (debug)",
                    isOn: $settings.previewTemplateSilhouette
                )
                Text("Влияет только на новые проекты. Существующие кварталы сохраняют свой стиль.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var availableFamilies: [String] {
        DistrictTemplateCatalog.availableFamilies().sorted()
    }

    private func humanName(_ family: String) -> String {
        switch family {
        case "egyptian": return "Египет"
        case "roman":    return "Рим"
        case "greek":    return "Греция"
        default:         return family.capitalized
        }
    }
}

// TASK-030a F-15: секция инициализации карты мира (seed + reset button).
private struct MapWorldSection: View {
    @ObservedObject var settings: AppSettings
    @State private var newSeedText: String = ""
    @State private var showResetConfirm: Bool = false
    @State private var isResetDisabled: Bool = false

    var body: some View {
        GroupBox(label: Label("Карта мира", systemImage: "map")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Текущий seed: \(settings.mapSeed)")
                    .font(.system(.body, design: .monospaced))
                HStack {
                    TextField("Новый seed (пусто = случайный)", text: $newSeedText)
                        .textFieldStyle(.roundedBorder)
                    Button("Сбросить карту") {
                        showResetConfirm = true
                    }
                    .tint(.red)
                    .disabled(isResetDisabled || !isValidSeedInput)
                }
                Text("Карта пересоберётся, кварталы переразместятся. Лог событий сохранится.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .alert("Сбросить карту мира?", isPresented: $showResetConfirm) {
            Button("Сбросить", role: .destructive) {
                applyReset()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Карта будет пересоздана с seed \(displaySeed). Кварталы переразместятся. Лог задач не меняется. Продолжить?")
        }
    }

    private var displaySeed: String {
        let parsed = MapSeedValidator.parse(newSeedText)
        if parsed == nil && !newSeedText.isEmpty { return "?" }
        return parsed.map(String.init) ?? "случайным"
    }

    private var isValidSeedInput: Bool {
        newSeedText.isEmpty || MapSeedValidator.parse(newSeedText) != nil
    }

    private func applyReset() {
        let newSeed = MapSeedValidator.parse(newSeedText) ?? 0
        settings.mapSeed = newSeed
        settings.save()
        ErrorsLog.write("[map-reinit] requested: seed=\(newSeed)")
        newSeedText = ""
        isResetDisabled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isResetDisabled = false
        }
    }
}
