# TASK-023: Git watcher — авто-учёт прироста кода (F-19)

## Связь
- **F-19** Git watcher
- **D-19** из diff.md
- **F-14** AppSettings (UI для списка репо)
- **F-20** Catch-up scheduler (TASK-020 — pre-condition)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Дать пользователю возможность подключить свои локальные git-репозитории, чтобы
каждый новый коммит автоматически становился задачей-юнитом в городе. Это
снимает ручной шаг «закрыл фичу — пиши в журнал»: ты уже фиксируешь работу
через `git commit`, город должен расти сам. Языки/стек не важны — читается
только метадата коммитов через `git log`.

В Settings — список репо (путь + `projectId` + ветка). В минимальной версии:
один коммит = одно событие = один юнит. Опции «вес по diff» и «категория по
conventional-commits» — добавочные тумблеры (по умолчанию выключены).

### Пользовательский сценарий

1. Юзер в Settings → раздел «Git watcher» — кнопка «Добавить репозиторий».
   Открывается `NSOpenPanel` (только папки). Юзер выбирает
   `~/projects/myapp`.
2. Watcher определяет, что это git-репо (`<path>/.git` существует), извлекает
   `projectId` через `git -C <path> remote get-url origin` (если
   `origin` есть и парсится в `<host>:<owner>/<repo>(.git)?` или `<host>/<owner>/<repo>(.git)?`
   — берёт `<repo>` без `.git`). Если `origin` отсутствует / нечитаемый —
   `projectId` = имя последней папки пути (`myapp`).
3. Юзер видит созданную запись в Settings: путь, `projectId` (редактируемый),
   ветка (выбор из `main` / `master` / список локальных, default `main` если
   есть, иначе `master`, иначе первая локальная). Опции (галочки): `git fetch`
   перед сканом, «вес по diff», «категория по типу коммита». Все выкл по
   умолчанию.
4. Юзер делает коммит в `main` локально (`git commit -m "feat: добавил
   профиль пользователя"`).
5. В течение ≤ 5 секунд (или при immediate-scan при старте после простоя)
   watcher через `git log <branch> --since <last_check_ts> --pretty=format:"%H|%ct|%s"`
   получает новый коммит, создаёт событие
   `GameEvent.taskCompleted(project: "myapp", title: "feat: добавил профиль
   пользователя", ts: <commit ts>, source: "git:<repoId>:<sha>")`.
6. На карте появляется юнит в квартале `myapp`.
7. Юзер делает второй коммит того же sha (например, после `git reset --soft`
   + `git commit --amend`) — sha другой → новое событие. Если sha повторяется
   (теоретически невозможно для git) — dedup по `source`-ключу в `events.jsonl`.

### Acceptance criteria

- [ ] **Settings UI секция «Git watcher»:** Form/Section с кнопкой
      «Добавить репозиторий» и `List` существующих записей. Для каждой записи:
      - 1-я колонка: путь (truncated), иконка `folder.badge.gearshape`.
      - 2-я колонка: редактируемое поле `projectId` (TextField).
      - 3-я колонка: `Picker` ветки (список локальных веток репо).
      - 4-я колонка: три галочки (`Toggle`): «git fetch», «вес по diff»,
        «категория по типу».
      - 5-я колонка: кнопка «Удалить» (trash icon).
- [ ] **Авто-projectId из remote:** при добавлении репо `projectId`
      инициализируется парсингом `git -C <path> remote get-url origin`
      (SSH/HTTPS форматы). При отсутствии remote — имя последней папки.
      Юзер может вручную переопределить.
- [ ] **Авто-выбор ветки:** при добавлении ветка = `main` если существует,
      иначе `master`, иначе первая локальная ветка. Юзер может переопределить
      через Picker.
- [ ] **`git log` parse:** `git -C <path> log <branch> --since <last_check_ts_iso>
      --pretty=format:"%H|%ct|%s" --no-merges` (флаг `--no-merges` опционален —
      если у юзера трудоёмкие merge-коммиты с осмысленным subject, можно
      отключить через будущую галочку; в этом скоупе всегда `--no-merges`).
      Парсится `<sha>|<commit ts unix>|<subject>`. Подсчёт коммитов с
      `--since` ограничен 1000 за один scan (защита от первого scan'а с
      `lastCheckTs = .distantPast` на репо с 50k коммитов; см. edge case).
- [ ] **Создание события на коммит:** для каждого нового sha — событие
      `taskCompleted` с `project=<projectId>`, `title=<subject>` (truncate
      255 символов), `ts=<commit ts>`, `source="git:<repoId>:<sha>"`. Где
      `<repoId>` — стабильный хэш `path+remote-url+projectId` (не меняется
      при ребранчинге, изменяется при смене projectId юзером — это
      ожидаемо).
- [ ] **Опция «git fetch» (выкл по дефолту):** если включена — перед scan
      выполнить `git -C <path> fetch <remote> <branch>` с таймаутом 10
      секунд. Ошибка fetch (нет сети / нет permissions) → лог в `ErrorsLog`,
      scan продолжается с тем, что есть локально. Не выкл watcher.
- [ ] **Опция «вес по diff» (выкл по дефолту):** если включена — для
      каждого нового коммита запускается `git -C <path> diff --shortstat
      <prev_sha>..<sha>`, парсится `N insertions(+), M deletions(-)`.
      Вес (число юнитов от одного коммита): `lines = N + M`. Если `lines ≤
      10` → 1 юнит (одно событие). `10 < lines ≤ 100` → 2 события. `100 <
      lines ≤ 500` → 3 события. `> 500` → 5 событий. События имеют один и
      тот же sha-источник, но разные suffix'ы (`source: "git:<repoId>:<sha>#1"`,
      `#2`, ...) для idempotency.
- [ ] **Опция «категория по типу коммита» (выкл по дефолту):** парсится
      префикс subject по conventional-commits: `feat:` → category=residential
      (новый дом), `fix:` → infrastructure (ремонт), `refactor:` →
      production, `docs:` → social, `chore:`/`style:`/`wip:` → игнорируется
      (событие НЕ создаётся). Если ни один префикс не совпал — события идут
      без категорийной подсказки (по умолчанию residential — UnitPlanner сам
      решит). **Этот hint** передаётся в `GameEvent` через новое опциональное
      поле (или через подсказку в title — формат на усмотрение лида).
- [ ] **Интеграция с F-20 (TASK-020):** реализация протокола `EventSource`
      (`scan(since:)`, `lastCheckTs`), регистрация в `CatchUpScheduler` при
      старте и при добавлении репо через Settings.
- [ ] **Persistence:** список репо (path, projectId, branch, 3 опции) и
      `lastCheckTs` сохраняются. Path/projectId/branch в `AppSettings`
      (UserDefaults). `lastCheckTs` — в общем `catchup-state.json` через
      F-20.
- [ ] **Idempotency и replay:** все события идут через общий `eventLog`
      и `apply` (F-03). Replay snapshot+tail восстанавливает все git-события
      на тех же кварталах.
- [ ] **Done-критерий F-19:** см. блок ниже.

### Что НЕ делаем (границы скоупа)

- Не работаем с remote-репозиториями (нет API запросов к GitHub/GitLab). Только
  локальные клоны через `git` CLI.
- Не клонируем репо за пользователя — он сам делает `git clone` куда хочет, мы
  только подцепляем существующий путь.
- Не push'им ничего и не делаем `git pull` — только `git fetch` (опц.) и
  `git log` / `git diff` read-only.
- Не парсим body коммита — только subject (`%s`). Multi-line commit messages
  обрезаются до первой строки.
- Не учитываем коммиты в feature-веток (только основная). Squash merge в main —
  один merge-commit (если `--no-merges` отключить в будущей версии). В этой
  задаче `--no-merges` всегда включён.
- Не реализуем «реверс» коммитов (`git revert`) как удаление юнита. Юнит
  остался — событие историческое, отмена не вычитает.
- Не делаем UI стилизацию репо специально под git (используем те же токены
  parchment / inkDark / sandLight как F-14 Settings).
- **Не поддерживаем sandbox / security-scoped bookmarks.** Допущение:
  приложение non-sandboxed.

### Edge cases

- [ ] **Репо без коммитов** (свежий `git init`) — `git log` вернёт ошибку
      или пустой результат; scan завершается без событий, `lastCheckTs`
      обновляется на `now`. Без warning.
- [ ] **Репо удалено / путь не существует** — лог `ErrorsLog`,
      `lastCheckTs` не обновляется (ретрай в следующий poll), запись в
      Settings остаётся.
- [ ] **Папка существует, но не git-репо** — при добавлении через Settings
      сразу alert «Это не git-репозиторий», запись не создаётся.
- [ ] **Первый scan на старом репо с 50k коммитов** — `lastCheckTs =
      .distantPast`, `git log --since` вернёт все коммиты. Защита: лимит 1000
      коммитов на один scan, остальное — на следующий poll с обновлённым
      `lastCheckTs` (берём ts последнего обработанного). Юзер увидит warning
      «Репо содержит >1000 не-обработанных коммитов, импорт займёт N
      poll-циклов».
- [ ] **Часы системы переведены назад** → `lastCheckTs > now` → `git log
      --since <future>` вернёт пусто. На следующем scan'е `lastCheckTs` будет
      clamped к `now`, всё догонит.
- [ ] **Ветка `main` удалена/переименована после настройки** — `git log
      <branch>` вернёт ошибку. Лог в `ErrorsLog`, в Settings показать ⚠️
      рядом с записью, не создавать события до починки.
- [ ] **`git fetch` зависает >10 сек** — таймаут, прерывание, лог
      `ErrorsLog`. Scan продолжается с локальным состоянием.
- [ ] **Конфликт `projectId` между git-watcher и notes-watcher / журналом**
      (юзер настроил `projectId: "myapp"` в git, и тот же `"myapp"` где-то
      ещё) — оба источника пишут в один проект, юниты накапливаются в одном
      квартале. Это **ожидаемое поведение** (юзер сам выбрал то же имя).
- [ ] **Conventional-commit префикс с opcase** (`FEAT:`, `Fix:`) —
      нормализуем к lowercase перед сравнением.
- [ ] **Subject с двоеточием внутри** (`docs: fix: typo`) — берём только
      первый сегмент до `:` как префикс (`docs`), остальное — title.
- [ ] **Title содержит pipe `|`** (наш разделитель в `--pretty=format`) —
      **зафиксировано**: используем null-separated формат
      `--pretty=tformat:%H%n%ct%n%s%x00` (record separator = `\0`). Tab
      технически тоже встречается в commit message reflows — null безопаснее.
- [ ] **Смена опции «вес по diff» не ретроактивна:** уже обработанные sha не
      пересканируются и не делятся на N юнитов задним числом. После
      включения опции — только новые коммиты получают N-юнит обработку.
      Это известное ограничение, dedup по `source`-ключу гарантирует
      отсутствие дублей.
- [ ] **Non-standard remote URL** (`ssh://git@host:port/owner/repo.git`,
      `git@host-aliased:owner/repo`, `file://`-пути, GitHub Enterprise) —
      если parse не сработал в один из двух паттернов (`<host>:<owner>/<repo>`
      или `<host>/<owner>/<repo>`), **fallback** на имя последней папки.
      Юзер всегда может переопределить projectId вручную через TextField
      в Settings.
- [ ] **Merge-коммит от `git pull` без `--ff-only`** при включённом
      `--no-merges` — юнит НЕ появится (merge-commit отфильтрован). Это
      известное ограничение текущей версии. Workaround для юзера: либо
      `git pull --ff-only`, либо `git pull --rebase`. Будущая опция «учитывать
      merge-коммиты» — в Backlog.
- [ ] **`git` не установлен в `$PATH`** — при первом scan'е получаем
      ENOENT. Alert «Git не найден в системе, установите через Xcode CLI tools
      или brew». Watcher выключается до перезапуска приложения.
- [ ] **Большой commit (>500 строк) в режиме «вес по diff» → 5 событий
      сразу** — все 5 пишутся атомарно в одном тике engine? Это плохо для
      replay (5 событий с близкими ts могут перемешаться при сортировке). Лид
      должен дать каждому событию монотонно растущий ts: `ts + i*1ms` для
      `i in 0..4`. Это документировано здесь и реализуется на этапе разбора.
- [ ] **Repo path содержит спецсимволы / пробелы / non-ASCII** — все вызовы
      `git` через `Process` со списком аргументов (`arguments: [path]`), не
      через shell. Не интерпретировать как shell-команды.
- [ ] **Symbolic link на репо** — следуем (FileManager default), `.git` за
      symlink тоже работает.

### Зависимости

- **TASK-020 (F-20 Catch-up scheduler)** — **pre-condition**. Git watcher
  реализует `EventSource` протокол.
- **F-03** Event sourcing — закрыт. События идут через `eventLog`.
- **F-12** Snapshots — закрыт. Git-события сохраняются в snapshot+tail.
- **F-14** AppSettings — закрыт. Расширяем структурой repo list.
- **F-06** Project-District — закрыт (TASK-017). Новые projectId — новые
  кварталы.
- **Внешняя зависимость:** `git` CLI установлен в `$PATH` (Xcode CLI tools
  или Homebrew). Допущение — стандартная dev-среда macOS.
- Нет секретов / миграций state.

### Дизайн

Из `DesignConcept.md`:
- **Раздел «Git watcher» в Settings** — `Form`/`Section` рядом с «Notes
  watcher» (F-18, TASK-022). Те же дизайн-токены: parchment фон, padding
  `padM`, разделители 1pt `inkDark` 20%.
- **Список репо** — `List` или `Table` (на усмотрение лида), строки
  компактные (`padXS = 4pt` между элементами в строке).
- **Поля строки:** `TextField` для projectId — 13pt Regular `inkDark`,
  ширина 100pt. `Picker` для ветки — 11pt caption, ширина 80pt.
  `Toggle`-галочки — стандартные SwiftUI Toggle с label 11pt caption.
- **«Добавить репозиторий»** — кнопка под списком, primary-button цвет
  `info` (`#3C6A8C`).
- **Alert «Не git-репозиторий»** — стандартный `Alert(title:, message:,
  dismissButton:)` SwiftUI.
- **⚠️ индикатор у проблемной записи** (например, ветка удалена) — иконка
  `exclamationmark.triangle.fill` цвет `warning` (`#D49B2A`), tooltip с
  описанием проблемы.

### Done-критерий

_Из concept.md F-19 (дословно):_

> Юзер добавляет локальный git-репо в Settings. Делает коммит в `main`
> (локально или `git pull` после push из web-UI). В течение 5 мин на карте
> появляется юнит в соответствующем квартале. Дубликаты по sha не создаются
> при повторном сканировании. Опции «вес по diff» и «категория по
> commit-type» можно включить/отключить независимо в Settings.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Статус: ready_

### Архитектурный каркас

`GitWatcher` — отдельный модуль, реализует тот же `EventSource`-протокол, что и
`NotesWatcher` (TASK-022). Вся работа с git — **только через `Foundation.Process`
со списком аргументов** (никаких shell-строк, никакого user-input в командной
строке). Минимально один helper `GitCLI`, выше — `GitWatcher` с per-repo
state'ом.

### Новые файлы

| Файл                                          | Назначение                                                                |
|-----------------------------------------------|---------------------------------------------------------------------------|
| `Data/GitWatcher/GitCLI.swift`                | Process-обёртка: `run(args:cwd:timeout:) -> (stdout, stderr, exit)`        |
| `Data/GitWatcher/GitRepoSpec.swift`           | `struct GitRepoSpec: Codable, Identifiable`                               |
| `Data/GitWatcher/GitWatcher.swift`            | Lifecycle, scan, dedup, ts-bumping, integration with engine               |
| `Data/GitWatcher/ConventionalCommit.swift`    | Парсер префиксов `feat/fix/refactor/docs/chore/...` → category hint        |
| `UI/Settings/GitWatcherSection.swift`         | Settings UI секция «Git watcher»                                          |

### Изменения в существующих файлах

- **`Data/AppSettings.swift`** — добавить `@Published var gitRepos: [GitRepoSpec] = []`
  + опциональное поле `gitRepos: [GitRepoSpec]?` в `Persisted` (backward-compat,
  без bump `version`).
- **`Game/CityEngine.swift`** — использовать тот же `ingestTaskCompletionIfUnique`,
  что вводит TASK-022. Если задачи стартуют параллельно — реализует тот, кто
  первый.
- **`Data/GameEvent.swift`** — **опциональное** поле `category: UnitCategory?`
  (или `categoryHint: String?`) — для проброса hint'а в UnitPlanner.
  **Не обязательно** в этой версии: если решаем без него, hint передаётся
  через title-префикс «[feat] …» и игнорируется UnitPlanner'ом (он сам решит).
  Дефолтная реализация: без поля; hint только для эстетики в title.
- **`UI/SettingsView.swift`** — встроить `GitWatcherSection` после `NotesWatcherSection`.
- **`App/AppDelegate.swift`** — инстанциирование `GitWatcher` после engine,
  регистрация в `CatchUpScheduler`.

### Структуры данных

```swift
struct GitRepoSpec: Codable, Identifiable, Hashable {
    let id: String                   // SHA-256(path + projectId + remoteUrl?)
    var path: URL
    var projectId: String            // editable юзером
    var branch: String               // editable, default main/master
    var gitFetch: Bool = false
    var weightByDiff: Bool = false
    var categoryByType: Bool = false
}

struct GitCommit {
    let sha: String
    let ts: Date
    let subject: String              // первая строка commit message
}
```

### GitCLI (синхронная обёртка)

```swift
enum GitCLIError: Error { case notFound, timeout, exitCode(Int32, String) }

struct GitCLI {
    static let gitPath: String = "/usr/bin/git"   // macOS default; PATH override —
                                                  // отдельный fallback `which git`
                                                  // на первом запуске

    static func run(args: [String], cwd: URL, timeout: TimeInterval = 10)
        throws -> (stdout: Data, stderr: String, exit: Int32)
}
```

- Запуск через `Process` + `Pipe` для stdout/stderr.
- Timeout — через `DispatchQueue.global().asyncAfter` + `process.terminate()`.
- `ENOENT` (нет `/usr/bin/git`) → `GitCLIError.notFound` → alert юзеру при
  первой ошибке, watcher выключается до перезапуска.
- Все аргументы — отдельные элементы массива, **без интерполяции**.

### GitWatcher.scan(repo: since:)

Псевдокод:

```swift
1. Validate path: .exists && isDirectory && (path/.git).exists
   - не выполняется → ErrorsLog + return since (no advance).
2. (Опц.) git fetch:
   if repo.gitFetch:
       GitCLI.run(["-C", path, "fetch", "origin", repo.branch], timeout: 10)
       fail → log, continue with local.
3. git log:
   args = ["-C", path, "log", repo.branch,
           "--since", ISO8601(since),
           "--pretty=tformat:%H%n%ct%n%s%x00",
           "--no-merges",
           "-n", "1000"]   // hard cap
   stdout = GitCLI.run(args).stdout
4. Parse: split by 0x00, for each record split by \n → (sha, ct, subject).
5. Sort by ts asc (`--since` уже даёт reverse chrono, нужно asc для
   стабильного порядка ingest).
6. For each commit:
   - title = String(subject.prefix(255))
   - category = if repo.categoryByType {
        ConventionalCommit.category(from: subject) ?? .residential
     } else { .residential }
   - if categoryByType && ConventionalCommit.isIgnored(subject) { continue }
   - weight = repo.weightByDiff ? computeWeight(repo, prevSha, sha) : 1
     // prevSha = previous in this scan, or nil (skip diff if no prev)
   - For i in 0..<weight:
       source = "git:\(repo.id):\(sha)" + (weight > 1 ? "#\(i)" : "")
       ts_i = Date(timeIntervalSince1970: ct) + Double(i) * 0.001
       engine.ingestTaskCompletionIfUnique(
           project: repo.projectId,
           title: title + (weight > 1 ? " (\(i+1)/\(weight))" : ""),
           taskId: nil,
           source: source,
           ts: ts_i)
7. Return ts последнего обработанного коммита (для `lastCheckTs` через F-20).
```

### computeWeight

```swift
GitCLI.run(["-C", path, "diff", "--shortstat", "\(prevSha)..\(sha)"])
parse stdout: "N insertions(+)" + "M deletions(-)"
lines = N + M
return switch lines {
    case 0...10: 1
    case 11...100: 2
    case 101...500: 3
    default: 5
}
```

При отсутствии `prevSha` (первый коммит в scan'е, либо первый коммит в репо) —
`weight = 1`.

### projectId auto-resolve

```swift
GitCLI.run(["-C", path, "remote", "get-url", "origin"])
remote = stdout.trim
// SSH:   git@host:owner/repo.git           → "repo"
// HTTPS: https://host/owner/repo(.git)?    → "repo"
// fallback на path.lastPathComponent
parse via two regex:
  1. ^.*[:/]([A-Za-z0-9_.-]+?)(\.git)?$
  2. else → path.lastPathComponent
```

`projectId` editable юзером в Settings (TextField) — auto-value только initial.

### branch auto-pick

```swift
GitCLI.run(["-C", path, "branch", "--list", "--format=%(refname:short)"])
branches = stdout split by \n
if "main" in branches → "main"
else if "master" in branches → "master"
else branches.first ?? ""
```

### ConventionalCommit

```swift
enum ConventionalCommit {
    static func category(from subject: String) -> UnitCategory? {
        let prefix = subject.split(separator: ":").first.map { $0.lowercased() }
        switch prefix {
            case "feat":     return .residential
            case "fix":      return .infrastructure
            case "refactor": return .production
            case "docs":     return .social
            default:         return nil
        }
    }
    static func isIgnored(_ subject: String) -> Bool {
        ["chore", "style", "wip"].contains(
            subject.split(separator: ":").first.map { $0.lowercased() } ?? ""
        )
    }
}
```

### Live режим

Git не даёт inotify-аналога на `.git/refs/heads/<branch>`. Best-effort:
- `DispatchSource` на файл `<path>/.git/refs/heads/<branch>` с `.write/.extend`
  event'ом → immediate re-scan.
- Если файл не существует (packed refs) — fallback только на 5-минутный poll
  через F-20.
- Документировано как edge case.

### Catch-up интеграция (TASK-020)

Аналогично notes-watcher: каждый `GitRepoSpec` = отдельный `EventSource`.
Если TASK-020 ещё не закрыта — временный `DispatchSourceTimer` внутри
GitWatcher на 5 мин, удаляется при миграции на F-20.

### Settings UI

`GitWatcherSection` — `Form/Section`. Список репо — `Table` (или `List`),
строки с inline-edit:
- `projectId` — `TextField`, ширина 100pt.
- `branch` — `Picker`, ширина 80pt, источник — `branches(of: repo.path)`
  (lazy, кэш на 10 сек, чтобы не дёргать git каждое открытие меню).
- 3 `Toggle`.
- Кнопка trash.

`NSOpenPanel` — только директории (`canChooseFiles=false,
canChooseDirectories=true`). После выбора — sync-проверка `<path>/.git`
существования; если нет — `Alert(title: "Не git-репозиторий")`.

### Тестовый план (юнит-тесты)

1. `ConventionalCommit.category` — все 4 префикса + 3 игнор + 2 unknown
   (`build:`, `FEAT:` lowercase normalize).
2. `subject` с `:` внутри (`docs: fix: typo`) → prefix=`docs`, title=`fix: typo`.
3. `GitCLI.run` mock на in-memory temp-репо (создать `git init`, 3 коммита,
   запустить scan): 3 события в `engine.events`, повторный scan → 0.
4. `weightByDiff`: коммит на 150 строк → 3 события с suffix'ами `#0/#1/#2`,
   ts смещены на 0/1/2 ms.
5. `gitFetch` timeout (mock через slow process): warning в ErrorsLog,
   scan продолжается.
6. Remote-URL parse: 6 кейсов (SSH, HTTPS, file://, GitHub Enterprise,
   broken, missing).
7. Branch auto-pick: 3 кейса (есть main, нет main но есть master, ни того ни
   другого).

### Точки риска

- **`/usr/bin/git` не существует** на чистом mac (без Xcode CLI tools). Fallback:
  при `ENOENT` пробовать `which git` через `Process`. Если и это пусто —
  выключение watcher'а до перезапуска с alert.
- **`git log --since` точность**: `--since` парсит ISO8601, но игнорирует
  миллисекунды. Достаточно секундной точности — `lastCheckTs` обновляем на
  `ts последнего коммита + 1 секунда` чтобы не получать его повторно на
  следующем scan'е. Dedup по `source` — страховка.
- **Большие репо**: ограничение `-n 1000` хард-капит. Если в очереди >1000 —
  warning + следующий poll. Edge case покрыт.
- **`Process` zombie** при таймауте: после `terminate()` сделать `waitUntilExit()`
  с дополнительным timeout 1s, потом `interrupt()`. Документировано в `GitCLI`.
- **ts-collision при weight-split**: суффикс `#i` гарантирует уникальность
  `source`, +1ms на ts даёт детерминированный порядок при replay'е.
- **Race на `lastCheckTs` при concurrent scan'ах**: единая `serial queue`
  внутри `GitWatcher` гарантирует, что один и тот же repo не сканируется
  параллельно (live-event + 5-мин poll могут совпасть). `liveScanInFlight: Set<repoId>` — guard.

### Что лид НЕ решает в этой задаче

- Поддержку feature-веток / multi-branch на один репо (Backlog).
- Учёт `git revert` как удаления юнита (явно out-of-scope).
- Sandbox / security-scoped bookmarks (явно out-of-scope).
- Параллельный fetch нескольких репо на старте — sequential на serial queue
  достаточно для MVP.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Smoke-тест: создать тестовый временный репо, сделать 3 коммита (один
      `feat:`, один `fix:`, один `chore:`), добавить в Settings → через 5
      сек на карте 2 юнита (chore проигнорирован если опция «категория»
      включена; 3 юнита если выкл). Изменить ветку — события из старой
      ветки не повторяются.

#### Технические
- [ ] Компиляция Swift без новых ошибок/варнингов
- [ ] Существующие тесты F-04 / F-12 / F-14 / F-20 не сломаны
- [ ] Все вызовы `git` через `Process` с массивом аргументов (не через
      shell — защита от injection)

#### Обновление документации
- [ ] `Current.md`: F-19 → ✅
- [ ] `Diff.md`: D-19 удалён
- [ ] Новые идеи → `Backlog.md`, баги → `Bugs.md`

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: —
- Lead-разбор: 2026-05-22
- Готова к работе: 2026-05-22
- Завершена: 2026-05-23
- Коммит: 4620e89
