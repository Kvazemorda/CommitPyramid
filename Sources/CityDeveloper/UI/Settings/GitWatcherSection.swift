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

    // MARK: - Body

    var body: some View {
        GroupBox("Git watcher") {
            VStack(alignment: .leading, spacing: 8) {
                if settings.gitRepos.isEmpty {
                    Text("Репозитории не добавлены. Нажмите «Добавить репозиторий» чтобы подключить локальный git-репо.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    reposList
                }

                HStack {
                    Button("Добавить репозиторий…") { pickRepository() }
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
                    .help("Выполнять git fetch перед каждым сканом")
                    .onChange(of: repo.wrappedValue.gitFetch) { _ in settings.save() }

                Toggle("вес по diff", isOn: repo.weightByDiff)
                    .font(.caption)
                    .toggleStyle(.checkbox)
                    .help("Количество юнитов пропорционально числу изменённых строк")
                    .onChange(of: repo.wrappedValue.weightByDiff) { _ in settings.save() }

                Toggle("тип коммита", isOn: repo.categoryByType)
                    .font(.caption)
                    .toggleStyle(.checkbox)
                    .help("Категория юнита по conventional-commit префиксу (feat/fix/refactor/docs); chore/style/wip игнорируются")
                    .onChange(of: repo.wrappedValue.categoryByType) { _ in settings.save() }
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
