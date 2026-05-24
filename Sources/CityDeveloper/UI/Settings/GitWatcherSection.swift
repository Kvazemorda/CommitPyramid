import SwiftUI
import AppKit

/// Settings section for managing git-repository watch sources.
///
/// Embedded inside `SettingsView` after `NotesWatcherSection`.
/// Changes to `settings.gitRepos` automatically persist via `settings.save()`.
struct GitWatcherSection: View {

    @ObservedObject var settings: AppSettings

    /// Called when a new repo is added so `GitWatcher` can register it live.
    var onRepoAdded:   ((GitRepoSpec) -> Void)?
    /// Called when a repo is removed so `GitWatcher` can unregister it.
    var onRepoRemoved: ((String) -> Void)?   // repoId

    // MARK: - Local state

    /// Alert message for non-git-repo selection
    @State private var alertMessage: String? = nil
    /// Сообщение об успешном сканировании / без находок.
    @State private var scanResultMessage: String? = nil

    // MARK: - Body

    var body: some View {
        GroupBox("Git watcher") {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Вес коммита:")
                        Slider(value: $settings.commitWeightMultiplier, in: 0.05...2.0, step: 0.05)
                            .onChange(of: settings.commitWeightMultiplier) { _ in settings.save() }
                        Text(String(format: "×%.2f", settings.commitWeightMultiplier))
                            .monospacedDigit().frame(width: 50)
                    }
                }
                .help("Множитель количества юнитов на один коммит. 0.1 = почти всегда 1 юнит. 1.0 = 1-5 юнитов по размеру diff. Применяется при следующем Reset.")
                .padding(.bottom, 4)

                if settings.gitRepos.isEmpty {
                    Text("Репозитории не добавлены. Нажмите «Добавить репозиторий» чтобы подключить локальный git-репо, или «Сканировать папку…» чтобы массово найти все .git внутри указанного каталога.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    reposList
                }

                HStack {
                    Button("Добавить репозиторий…") { pickRepository() }
                    Button("Сканировать папку…") { scanFolder() }
                        .help("Выбрать корневую папку и найти в ней все git-репозитории (поиск .git до 3 уровней вложенности). Найденные репо добавятся в список с дефолтными настройками.")
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(8)
        }
        .alert(
            "Не git-репозиторий",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .alert(
            "Сканирование",
            isPresented: Binding(
                get: { scanResultMessage != nil },
                set: { if !$0 { scanResultMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { scanResultMessage = nil }
        } message: {
            Text(scanResultMessage ?? "")
        }
    }

    // MARK: - Repos list

    private var reposList: some View {
        VStack(spacing: 4) {
            ForEach($settings.gitRepos) { $repo in
                repoRow(repo: $repo)
                    .padding(.vertical, 2)
                if repo.id != settings.gitRepos.last?.id {
                    Divider()
                }
            }
        }
    }

    private func repoRow(repo: Binding<GitRepoSpec>) -> some View {
        HStack(spacing: 8) {
            // Folder icon
            Image(systemName: "folder.badge.gearshape")
                .frame(width: 18)
                .help(repo.wrappedValue.path.path)

            // Path (truncated)
            Text(repo.wrappedValue.path.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(repo.wrappedValue.path.path)

            // projectId TextField
            TextField("projectId", text: repo.projectId)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .help("Идентификатор проекта / квартала в городе")
                .onChange(of: repo.wrappedValue.projectId) { _ in
                    settings.save()
                }

            // Branch Picker
            BranchPicker(repoPath: repo.wrappedValue.path, selection: repo.branch)
                .frame(width: 80)
                .onChange(of: repo.wrappedValue.branch) { _ in
                    settings.save()
                }

            // Toggles
            VStack(alignment: .leading, spacing: 2) {
                Toggle("git fetch", isOn: repo.gitFetch)
                    .font(.caption)
                    .toggleStyle(.checkbox)
                    .help("Перед каждым сканом запускает `git fetch origin <branch>` — подтягивает свежие коммиты из remote. Включай если хочешь видеть чужие коммиты автоматически, без ручного pull. Минус: требует сеть и пару секунд на каждый цикл.")
                    .onChange(of: repo.wrappedValue.gitFetch) { _ in settings.save() }

                Toggle("вес по diff", isOn: repo.weightByDiff)
                    .font(.caption)
                    .toggleStyle(.checkbox)
                    .help("Количество юнитов на коммит зависит от размера diff: ≤10 строк → 1 юнит, 11–100 → 2, 101–500 → 3, 500+ → 5. Крупные коммиты строят больше зданий. Без галки — каждый коммит = ровно 1 юнит.")
                    .onChange(of: repo.wrappedValue.weightByDiff) { _ in settings.save() }
            }

            // Delete button
            Button {
                removeRepo(id: repo.wrappedValue.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Удалить репозиторий")
        }
    }

    // MARK: - Actions

    private func pickRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles        = false
        panel.canChooseDirectories  = true
        panel.allowsMultipleSelection = false
        panel.message = "Выберите папку с git-репозиторием"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Validate: must have .git directory
        let gitDir = url.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            alertMessage = "Папка «\(url.lastPathComponent)» не является git-репозиторием (.git не найден)."
            return
        }

        // Auto-resolve projectId and branch
        let projectId = GitWatcher.resolveProjectId(at: url)
        let branch    = GitWatcher.defaultBranch(at: url)

        let spec = GitRepoSpec(path: url, projectId: projectId, branch: branch)

        // Avoid duplicate paths
        guard !settings.gitRepos.contains(where: { $0.path == url }) else { return }

        settings.gitRepos.append(spec)
        settings.save()
        onRepoAdded?(spec)
    }

    private func removeRepo(id: String) {
        settings.gitRepos.removeAll { $0.id == id }
        settings.save()
        onRepoRemoved?(id)
    }

    /// Сканирует выбранную папку до 3 уровней вглубь, ищет `.git` и регистрирует
    /// каждый найденный репо со стандартными настройками. Дубликаты по path — skip.
    private func scanFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles        = false
        panel.canChooseDirectories  = true
        panel.allowsMultipleSelection = false
        panel.message = "Выберите корневую папку — внутри найдём все git-репозитории"

        guard panel.runModal() == .OK, let rootURL = panel.url else { return }

        let fm = FileManager.default
        let rootPath = rootURL.path
        var found: [URL] = []

        // Обход в глубину до 3 уровней. Skip скрытые папки кроме самой `.git`,
        // skip симлинки, чтобы не уйти в кольцо.
        func walk(_ dir: URL, depth: Int) {
            if depth > 3 { return }
            let gitDir = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: gitDir.path, isDirectory: &isDir), isDir.boolValue {
                // Это репо — добавляем и НЕ ныряем внутрь (вложенные git'ы под .git не интересуют).
                found.append(dir)
                return
            }
            guard let items = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return }
            for item in items {
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                walk(item, depth: depth + 1)
            }
        }
        walk(rootURL, depth: 0)

        let existingPaths = Set(settings.gitRepos.map { $0.path.standardizedFileURL.path })
        var addedCount = 0
        var skippedDup = 0
        for repoURL in found {
            let std = repoURL.standardizedFileURL.path
            if existingPaths.contains(std) { skippedDup += 1; continue }
            let projectId = GitWatcher.resolveProjectId(at: repoURL)
            let branch    = GitWatcher.defaultBranch(at: repoURL)
            let spec = GitRepoSpec(path: repoURL, projectId: projectId, branch: branch)
            settings.gitRepos.append(spec)
            onRepoAdded?(spec)
            addedCount += 1
        }
        if addedCount > 0 { settings.save() }

        if found.isEmpty {
            scanResultMessage = "В папке «\(rootURL.lastPathComponent)» git-репозитории не найдены (глубина поиска — 3 уровня).\n\nПуть: \(rootPath)"
        } else {
            var msg = "Найдено репозиториев: \(found.count). Добавлено: \(addedCount)."
            if skippedDup > 0 { msg += " Пропущено дублей: \(skippedDup)." }
            scanResultMessage = msg
        }
    }
}

// MARK: - BranchPicker

/// A `Picker` that lazily loads the list of local branches for a given repo.
private struct BranchPicker: View {
    let repoPath: URL
    @Binding var selection: String

    @State private var branches: [String] = []
    @State private var loadedPath: URL? = nil

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(effectiveBranches, id: \.self) { branch in
                Text(branch).tag(branch)
            }
        }
        .pickerStyle(.menu)
        .font(.caption)
        .onAppear { loadBranchesIfNeeded() }
        .onChange(of: repoPath) { _ in loadBranchesIfNeeded() }
    }

    /// Branches to display: loaded list or [selection] fallback while loading.
    private var effectiveBranches: [String] {
        if branches.isEmpty { return [selection] }
        // Ensure current selection is in the list even if branch was renamed
        var result = branches
        if !result.contains(selection) { result.insert(selection, at: 0) }
        return result
    }

    private func loadBranchesIfNeeded() {
        guard loadedPath != repoPath else { return }
        loadedPath = repoPath
        DispatchQueue.global(qos: .utility).async {
            guard let result = try? GitCLI.run(
                args: ["-C", repoPath.path, "branch", "--list", "--format=%(refname:short)"],
                cwd: repoPath
            ) else { return }
            let text = String(data: result.stdout, encoding: .utf8) ?? ""
            let parsed = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            DispatchQueue.main.async {
                self.branches = parsed
            }
        }
    }
}
