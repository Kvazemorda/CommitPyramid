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

    init(
        settings: AppSettings,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        notesWatcher: NotesWatcher? = nil,
        gitWatcher: GitWatcher? = nil
    ) {
        self.settings = settings
        self.onSave = onSave
        self.onCancel = onCancel
        self.notesWatcher = notesWatcher
        self.gitWatcher = gitWatcher
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
