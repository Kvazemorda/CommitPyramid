import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings section for managing notes-watcher sources.
///
/// Embedded inside `SettingsView` (passed via `@ObservedObject`).
/// Changes to `settings.notesSources` automatically persist via `settings.save()`.
struct NotesWatcherSection: View {

    @ObservedObject var settings: AppSettings

    /// Called whenever the source list changes so that NotesWatcher
    /// can register/unregister sources at runtime.
    var onSourceAdded:   ((NotesSourceSpec) -> Void)?
    var onSourceRemoved: ((String) -> Void)?   // sourceId

    // MARK: - Local state

    @State private var popoverSourceId: String?        // which row shows «?» popover
    @State private var pendingDeleteMode: PendingDeleteModeAlert?
    @State private var recursiveCheckbox = false

    // MARK: - Body

    var body: some View {
        GroupBox("Notes watcher") {
            VStack(alignment: .leading, spacing: 8) {

                if settings.notesSources.isEmpty {
                    Text("Источники не добавлены. Нажмите «Добавить источник» чтобы подключить .md-файл или папку.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    sourcesList
                }

                HStack {
                    Button("Добавить источник…") { pickSource() }
                    Button("Из Apple Notes…") { pickAppleNotesFolder() }
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(8)
        }
        // Alert: confirm delete-processed mode
        .alert(
            "Режим delete-processed",
            isPresented: Binding(
                get: { pendingDeleteMode != nil },
                set: { if !$0 { pendingDeleteMode = nil } }
            )
        ) {
            Button("Отмена", role: .cancel) { pendingDeleteMode = nil }
            Button("Понимаю, продолжить", role: .destructive) {
                if let pending = pendingDeleteMode {
                    applyModeChange(sourceId: pending.sourceId, mode: .deleteProcessed)
                }
                pendingDeleteMode = nil
            }
        } message: {
            Text("Режим delete-processed навсегда удалит обработанные строки из ваших заметок.")
        }
    }

    // MARK: - Sources list

    private var sourcesList: some View {
        VStack(spacing: 4) {
            ForEach(settings.notesSources) { spec in
                sourceRow(spec)
                    .padding(.vertical, 2)
                if spec.id != settings.notesSources.last?.id {
                    Divider()
                }
            }
        }
    }

    private func sourceRow(_ spec: NotesSourceSpec) -> some View {
        HStack(spacing: 8) {
            // Kind icon
            Image(systemName: iconName(for: spec.kind))
                .frame(width: 16)
                .help(kindLabel(for: spec.kind))

            // Path (truncated, full path in tooltip)
            Text(spec.path.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(spec.path.path)

            // Mode picker
            Picker("", selection: Binding(
                get: { spec.mode },
                set: { newMode in
                    if newMode == .deleteProcessed {
                        pendingDeleteMode = PendingDeleteModeAlert(sourceId: spec.id)
                    } else {
                        applyModeChange(sourceId: spec.id, mode: newMode)
                    }
                }
            )) {
                Text("sidecar").tag(NotesSourceSpec.ProcessingMode.sidecarDedup)
                Text("delete").tag(NotesSourceSpec.ProcessingMode.deleteProcessed)
            }
            .pickerStyle(.menu)
            .frame(width: 80)

            // «?» docs button
            Button {
                popoverSourceId = (popoverSourceId == spec.id) ? nil : spec.id
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(
                get: { popoverSourceId == spec.id },
                set: { if !$0 { popoverSourceId = nil } }
            )) {
                NotesPatternsPopover()
            }

            // Delete button
            Button {
                removeSource(id: spec.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Удалить источник")
        }
    }

    // MARK: - Actions

    private func pickSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes  = [.init(filenameExtension: "md") ?? .data]
        panel.message = "Выберите файл .md или папку с заметками"

        // Checkbox «включая подпапки» — embed via accessoryView
        let checkbox = NSButton(checkboxWithTitle: "Включая подпапки (рекурсивно)", target: nil, action: nil)
        checkbox.state = .off
        panel.accessoryView = checkbox

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        let kind: NotesSourceSpec.SourceKind
        if isDir.boolValue {
            kind = checkbox.state == .on ? .folderRecursive : .folder
        } else {
            kind = .file
        }

        let spec = NotesSourceSpec(path: url, kind: kind, mode: .sidecarDedup)

        // Avoid duplicates
        guard !settings.notesSources.contains(where: { $0.id == spec.id }) else { return }

        settings.notesSources.append(spec)
        settings.save()
        onSourceAdded?(spec)
    }

    private func pickAppleNotesFolder() {
        // Ask Apple Notes for a list of all folder names via osascript.
        let listScript = "tell application \"Notes\"\nget name of every folder\nend tell"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", listScript]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            ErrorsLog.write("NotesWatcherSection: osascript failed: \(error)")
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8) ?? ""

        // Parse comma-separated list returned by osascript
        let folderNames = raw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !folderNames.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Папки Apple Notes не найдены"
            alert.informativeText = "Убедитесь, что приложение Notes запущено и содержит папки."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // Show alert with a popup button listing folder names
        let alert = NSAlert()
        alert.messageText = "Выберите папку Apple Notes"
        alert.addButton(withTitle: "Выбрать")
        alert.addButton(withTitle: "Отмена")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        for name in folderNames {
            popup.addItem(withTitle: name)
        }
        alert.accessoryView = popup

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let selectedFolder = popup.titleOfSelectedItem ?? folderNames[0]
        guard let url = URL(string: "apple-notes:///\(selectedFolder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? selectedFolder)") else { return }

        let spec = NotesSourceSpec(path: url, kind: .appleNoteFolder, mode: .sidecarDedup)

        // Avoid duplicates
        guard !settings.notesSources.contains(where: { $0.id == spec.id }) else { return }

        settings.notesSources.append(spec)
        settings.save()
        onSourceAdded?(spec)
    }

    private func removeSource(id: String) {
        settings.notesSources.removeAll { $0.id == id }
        settings.save()
        onSourceRemoved?(id)
    }

    private func applyModeChange(sourceId: String, mode: NotesSourceSpec.ProcessingMode) {
        guard let idx = settings.notesSources.firstIndex(where: { $0.id == sourceId }) else { return }
        let existing = settings.notesSources[idx]
        settings.notesSources[idx] = NotesSourceSpec(path: existing.path, kind: existing.kind, mode: mode)
        settings.save()
    }

    // MARK: - Helpers

    private func iconName(for kind: NotesSourceSpec.SourceKind) -> String {
        switch kind {
        case .file:            return "doc.text"
        case .folder:          return "folder"
        case .folderRecursive: return "folder.badge.plus"
        case .appleNoteFolder: return "note.text"
        }
    }

    private func kindLabel(for kind: NotesSourceSpec.SourceKind) -> String {
        switch kind {
        case .file:            return "Файл"
        case .folder:          return "Папка"
        case .folderRecursive: return "Папка (рекурсивно)"
        case .appleNoteFolder: return "Apple Notes папка"
        }
    }
}

// MARK: - Alert model

private struct PendingDeleteModeAlert {
    let sourceId: String
}
