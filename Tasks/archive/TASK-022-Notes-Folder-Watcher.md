# TASK-022: Notes/folder watcher — парсер markdown-источников (F-18)

## Связь
- **F-18** Notes/folder watcher
- **D-18** из diff.md
- **F-04** TasksJsonlWatcher (станет частным случаем F-18)
- **F-14** AppSettings (UI для путей и шаблонов)
- **F-20** Catch-up scheduler (TASK-020 — pre-condition)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Дать пользователю возможность подцепить любую папку с .md-заметками (Obsidian
vault, личные notes, project-folder) и автоматически закрывать в городе те
задачи, которые он отметил выполненными в этих заметках. Сейчас watcher только
один — `tasks.jsonl` с фиксированным форматом (F-04). Расширяем до общего
«notes/folder watcher» с 4 встроенными шаблонами парсинга, опциями обработки
обработанных записей (удалить из исходника / sidecar-dedup) и описанием
шаблонов в in-game docs.

F-04 (TasksJsonlWatcher) **остаётся работать** — его поведение не ломаем, лишь
семантически переосмысляем как частный случай F-18 (один файл, один формат
строк jsonl).

### Пользовательский сценарий

1. В Settings → раздел «Notes watcher» — кнопка «Добавить источник». Юзер
   выбирает через `NSOpenPanel`: файл `~/notes/work.md`, папка
   `~/Obsidian-vault/projects/` (нерекурсивно), или папка `~/notes/`
   рекурсивно (с галкой «включая подпапки»).
2. Для каждого источника юзер выбирает режим обработки:
   - **`delete-processed`** — после успешного парсинга строка с `[x]`
     удаляется из исходного .md. Если файл стал пустым (только пустые строки
     или сразу пустой) — файл удаляется.
   - **`sidecar-dedup`** — рядом с источником создаётся
     `<filename>.processed-state.json`, в нём хранятся хэши обработанных
     строк. Исходные .md не модифицируются.
3. Юзер открывает свой .md-редактор и пишет:
   ```
   - [x] [project: myapp] починил баг авторизации
   ```
   Сохраняет файл.
4. В течение ≤ 5 секунд (или сразу при file-change через DispatchSource)
   watcher замечает изменение, парсит, находит совпадение с шаблоном,
   создаёт событие `GameEvent.taskCompleted(project: "myapp",
   title: "починил баг авторизации", ts: <time of file modification>,
   source: "notes:<sourceId>")`.
5. На карте появляется юнит в квартале `myapp`.
6. В зависимости от режима: строка удалена из .md (`delete-processed`) или
   хэш записан в `.processed-state.json` (`sidecar-dedup`).
7. Юзер открывает in-app docs (кнопка «?» в Settings рядом с источником) —
   видит описание всех 4 встроенных шаблонов с примерами.

### Acceptance criteria

- [ ] **4 встроенных шаблона парсинга** реализованы как regex/детерминированные
      парсеры:
      1. `- [x] [project: <id>] <title>` (где `<id>` — `[A-Za-z0-9_-]+`,
         `<title>` — остаток строки).
      2. `- [x] <title> #<project>` (hashtag в конце строки, `<project>` —
         `[A-Za-z0-9_-]+`).
      3. `~~<title>~~ #<project>` (strikethrough + hashtag, project обязателен).
      4. `- [x] <project>: <title>` — `<project>` строго `[A-Za-z0-9_-]+`,
         **запрещённые значения projectId**: `project`, `system`, `null`, `none`
         (case-insensitive). Если совпало с зарезервированным — строка
         **не матчится** этим шаблоном (fallback к следующим / игнор).
- [ ] **Приоритет шаблонов 1→2→3→4:** если строка матчится более чем одному
      шаблону, выигрывает шаблон с меньшим номером. Пример-тест:
      `- [x] [project: foo] task #bar` создаёт событие с `project=foo`
      (шаблон 1), **не** `bar` (шаблон 2). Покрывается unit-тестом.
- [ ] **Settings UI секция «Notes watcher»:**
      - Кнопка «Добавить источник» открывает `NSOpenPanel` с фильтром по
        `.md` / папкам.
      - Список добавленных источников: путь, тип (`file` / `folder` /
        `folder-recursive`), режим (`delete-processed` / `sidecar-dedup`).
      - Для каждого источника — кнопка «Удалить» и переключатель режима.
      - Кнопка «?» рядом с источником открывает popover с описанием 4
        шаблонов и примерами (детали оформления — в разделе «Дизайн»).
- [ ] **Парсинг файла:** при сканировании источника watcher читает все
      `.md`-файлы (с фильтром по расширению; для `folder-recursive` — рекурсивно
      через `FileManager.enumerator`), парсит каждую строку через 4
      шаблона. Совпадения — события.
- [ ] **Формат `source` для idempotency:** все notes-события пишутся в
      `events.jsonl` с `source: "notes:<sourceId>:<lineHash>"`, где
      `<lineHash>` — SHA-256 от полного содержимого matched line (включая
      пробелы и шаблон-markers, как было в исходнике). Это первичный ключ
      dedup на уровне events.jsonl. Sidecar/scheduler — дополнительная защита,
      но даже если sidecar потерян и строка перепарсилась — events-уровень
      обнаружит дубликат по `source`-ключу и пропустит вторую запись.
      **Правка строки после обработки** → новый хэш → новое событие (новая
      задача в городе). Юзер может откатить, удалив запись из sidecar
      вручную, либо удалить дубликат из `events.jsonl` (через ручную правку).
- [ ] **Dedup в режиме `sidecar-dedup`:** sidecar **хранится в data-dir
      приложения**, не рядом с источником:
      `~/Library/Application Support/CityDeveloper/notes-state/<sourceHash>.json`,
      где `<sourceHash>` — стабильный хэш пути источника. Это снимает
      проблему read-only папок и не засоряет vault юзера. JSON-структура:
      `{ "<lineHash>": "<lastSeenTs ISO8601>" }`. Повторное сканирование
      той же строки → проверка по `lineHash` в этом файле → пропуск.
- [ ] **Удаление в режиме `delete-processed` (только UTF-8):** доступен
      ТОЛЬКО для файлов, успешно прочитанных как UTF-8. Если файл прочитан
      через fallback (Latin-1 или ошибка) — режим `delete-processed`
      автоматически даунгрейдится на `sidecar-dedup` для этого файла (одно
      предупреждение в `ErrorsLog`). После успешной записи события watcher
      удаляет соответствующую строку из исходного .md через atomic re-write
      всего файла (`data.write(to:, options:.atomic)`). Если файл после
      удаления состоит только из пустых строк / whitespace — файл удаляется
      (`FileManager.removeItem`). Папка не удаляется автоматически.
- [ ] **Интеграция с F-20 (TASK-020):** watcher реализует протокол
      `EventSource` (`scan(since:)`, `lastCheckTs` per-source), регистрируется
      в `CatchUpScheduler` при старте приложения и при добавлении нового
      источника через Settings (горячая регистрация).
- [ ] **Live режим через DispatchSource (опц.):** для каждого добавленного
      файла/папки запускается `DispatchSource.makeFileSystemObjectSource` на
      `.write` / `.extend` event. Изменение файла → немедленный re-scan этого
      источника, не дожидаясь 5-минутного poll. Это поверх F-20 — дополнительная
      низколатентная реакция.
- [ ] **In-game docs:** popover из кнопки «?» показывает таблицу из 4
      шаблонов с примерами и пояснением, какой шаблон что извлекает.
- [ ] **Idempotency через F-03:** события идут в `events.jsonl` через общий
      eventLog. Replay из snapshot+tail восстанавливает все notes-события
      на тех же кварталах.
- [ ] **Persistence источников:** список путей и режимов сохраняется в
      `AppSettings` (UserDefaults через существующий механизм F-14). При
      рестарте приложения источники восстанавливаются.
- [ ] **Done-критерий F-18:** см. блок ниже.

### Что НЕ делаем (границы скоупа)

- Не пишем интеграцию с Obsidian/Bear/Notes-app через их API — только файловая
  система (`.md` файлы).
- Не позволяем юзеру добавлять собственные regex-шаблоны через UI — только 4
  встроенных. Расширение шаблонов — отдельная фича в Backlog.
- Не парсим вложенные структуры markdown (heading, list-nesting) — только
  построчно.
- Не реализуем редактор .md внутри приложения — юзер редактирует своим
  редактором.
- Не трогаем F-04 (TasksJsonlWatcher) — он продолжает работать параллельно.
  Миграция F-04 на новый протокол `EventSource` — отдельная refactor-задача.
- Не делаем undo «вернуть удалённую строку обратно в .md» — операция
  необратима, юзер выбирал режим осознанно.
- Не делаем парсинг `tasks.jsonl` через F-18 — для этого есть F-04.
- Не делаем Settings UI красивее (drag-drop списка, sort, etc.) — простой
  список + кнопки.
- **Не поддерживаем sandbox / security-scoped bookmarks** в этой задаче.
  Допущение: приложение non-sandboxed, имеет доступ к произвольным путям
  через `NSOpenPanel`-grant. Если в будущем потребуется sandbox — отдельная
  задача на security-scoped bookmarks (хранение в `AppSettings` вместо
  raw path).

### Edge cases

- [ ] **Папка не существует** (юзер переместил/удалил) — при scan'е
      сообщение в `ErrorsLog`, источник остаётся в списке (юзер сам решит
      убрать), `lastCheckTs` не обновляется.
- [ ] **Файл .md содержит строку, подходящую под ДВА шаблона** (например
      `- [x] [project: foo] task #bar`) — применять шаблоны в порядке
      приоритета: 1 → 2 → 3 → 4. Первый match выигрывает. В этом примере
      шаблон 1 (project=foo) перекроет шаблон 2 (project=bar).
- [ ] **Незакрытый strikethrough** (`~~text` без закрывающего `~~`) —
      шаблон 3 не матчит, строка игнорируется.
- [ ] **Encoding не UTF-8** — пробуем UTF-8, при ошибке — пробуем
      Latin-1, если и это не сработало — лог ошибки, пропуск файла.
      **Latin-1 файлы НЕ поддерживают `delete-processed`** (см. AC) — auto-
      даунгрейд на sidecar-dedup с warning. Иначе при re-write мы бы испортили
      кодировку юзерского файла.
- [ ] **Файл-источник удалён** (только для type=file): DispatchSource на
      этот inode снимается, `lastCheckTs` замораживается. При повторном
      появлении файла по тому же пути — на следующем 5-минутном poll (F-20)
      watcher переподписывает DispatchSource. Для folder-источника удаление
      одного из вложенных файлов не критично (folder source продолжает
      работать).
- [ ] **Огромная папка с тысячами .md** (например, рекурсивный node_modules
      внутри vault'а): soft-предупреждение в ErrorsLog при первом scan'е, если
      найдено >500 файлов. Лимита на количество нет, но в Backlog идея
      «настраиваемый ignore-glob».
- [ ] **Файл изменён во время чтения** (live edit + `DispatchSource` fire):
      повторный scan на следующем тике подхватит изменения. Один scan
      атомарен через `try String(contentsOf:)`.
- [ ] **`delete-processed` + write-race с редактором юзера** (юзер
      сохраняет файл, watcher параллельно пишет atomic re-write): atomic
      re-write через `data.write(to:, options:.atomic)` гарантирует, что
      файл либо старый, либо новый. Юзерская запись поверх перезапишет —
      на следующем тике watcher просто заново перепарсит. Не критично.
- [ ] **`sidecar-dedup` файл повреждён** (битый JSON) — лог ошибки, новый
      пустой словарь, sidecar пересоздаётся. Все «обработанные ранее»
      строки могут попасть в события повторно — но dedup по
      `source: "notes:<sourceId>:<lineHash>"` в events.jsonl снимет дубликат.
- [ ] **Огромный .md (10MB+)** — читаем целиком (приемлемо для notes).
      Если хочется streaming — отдельный optimization в Backlog.
- [ ] **Удалённый файл во время режима `delete-processed`** (юзер удалил
      .md между scan'ами) — папка перестаёт содержать файл, watcher не
      делает ничего особенного. `lastCheckTs` обновляется как обычно.
- [ ] **Файл символическая ссылка** — следуем (`FileManager` default),
      но если ссылка broken — лог ошибки и пропуск.
- [ ] **Folder-recursive + слишком глубокая иерархия** (10+ уровней) — без
      ограничения уровней, но `FileManager.enumerator` пропускает hidden
      файлы по умолчанию (мы не меняем) — `.git`, `.obsidian` и пр. не
      сканируются.
- [ ] **Конфликт projectId с зарезервированными словами** (`system`, `null`,
      пустая строка) — фильтр на минимум 1 символ алфавит/цифры, иначе строка
      игнорируется.

### Зависимости

- **TASK-020 (F-20 Catch-up scheduler)** — **pre-condition**. Watcher
  реализует `EventSource` протокол, регистрируется в `CatchUpScheduler`.
  Без TASK-020 нет универсального poll-механизма.
- **F-03** Event sourcing — закрыт. Все события идут через `eventLog`.
- **F-12** Snapshots — закрыт. Notes-события сохраняются в snapshot+tail.
- **F-14** AppSettings — закрыт. Расширяем `AppSettings` новыми полями для
  списка источников (массив структур: path, mode, type).
- **F-06** Project-District — закрыт (TASK-017). Новые projectId-кварталы
  создаются по правилам.
- **F-04** TasksJsonlWatcher — закрыт, остаётся параллельно. Семантически
  становится частным случаем F-18, но физически не мигрируется в этой задаче.
- Нет внешних сервисов / секретов / миграций state.

### Дизайн

Из `DesignConcept.md` и F-14 (Settings UI):

- **Раздел «Notes watcher» в Settings** — стандартный `Form`/`Section` SwiftUI
  под существующими настройками (tasks.jsonl path / hotkey / data dir).
- **Список источников** — `List` или `Table`, каждая строка:
  - 1-я колонка: иконка (file / folder / folder-recursive), путь
    обрезанный с tooltip полного пути.
  - 2-я колонка: `Picker` режима (delete / sidecar).
  - 3-я колонка: кнопки «?» (docs popover) и «Удалить» (trash icon).
- **Popover docs «?»:**
  - Заголовок «Шаблоны парсинга задач» 15pt Semibold.
  - Таблица из 4 шаблонов: pattern + example + extracted fields.
  - Caption внизу: «Совпадения проверяются в порядке сверху вниз.»
  - Фон: parchment, padding `padM`, radiusS = 6pt.
- **«Добавить источник»** — кнопка под списком, открывает `NSOpenPanel`
  (`canChooseFiles=true`, `canChooseDirectories=true`,
  `allowedContentTypes=[.markdown]`, `allowsMultipleSelection=false`).
- **Подтверждение `delete-processed`** при первой настройке — alert:
  «Режим `delete-processed` навсегда удалит обработанные строки из ваших
  заметок. Продолжить? `Cancel` / `Понимаю, продолжить`.» Показывается один
  раз per-source (при добавлении или смене режима).

### Done-критерий

_Из concept.md F-18 (дословно):_

> Юзер добавляет файл/папку в Settings. Записывает `- [x] [project: test]
> hello` в .md-файл, сохраняет — в течение 5 сек на карте появляется юнит в
> квартале `test`. При `delete-processed` режиме строка удаляется из .md. При
> `sidecar-dedup` — хэш строки записан в `.processed-state.json`, повторный
> парсинг не создаёт дубликат. Все 4 встроенных шаблона работают. In-game
> docs описывают шаблоны через `?`-кнопку в Settings.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Статус: ready_

### Архитектурный каркас

Источник F-04 (`TasksJsonlWatcher`) намеренно не мигрируем. Делаем **отдельный**
модуль `NotesWatcher` рядом, со своими структурами, парсером, sidecar'ом и
DispatchSource'ами. EventSource-протокол (вводится в TASK-020) — общий
интерфейс между notes-watcher'ом и `CatchUpScheduler`.

### Новые файлы

| Файл                                          | Назначение                                                           |
|-----------------------------------------------|----------------------------------------------------------------------|
| `Data/NotesWatcher/NotesSourceSpec.swift`     | `struct NotesSourceSpec: Codable, Identifiable` (path, kind, mode, id) |
| `Data/NotesWatcher/NotesPatternParser.swift`  | 4 шаблона (regex/детерм.), `parse(_ line: String) -> ParsedTask?`     |
| `Data/NotesWatcher/NotesStateStore.swift`     | sidecar `<sourceHash>.json` в `notes-state/`, R/W lineHash → ts        |
| `Data/NotesWatcher/NotesFileReader.swift`     | UTF-8 → Latin-1 fallback, encoding-флаг для `delete-processed` gate   |
| `Data/NotesWatcher/NotesWatcher.swift`        | Главный класс: lifecycle, DispatchSource per-source, `scan(since:)`   |
| `UI/Settings/NotesWatcherSection.swift`       | Settings UI секция «Notes watcher»                                    |
| `UI/Settings/NotesPatternsPopover.swift`      | Popover из «?» с описанием 4 шаблонов                                 |

### Изменения в существующих файлах

- **`Data/AppSettings.swift`** — добавить `@Published var notesSources: [NotesSourceSpec] = []`;
  в `Persisted` — поле `notesSources: [NotesSourceSpec]?` (опционально для
  backward-compat со старым JSON). `Persisted.version` **не повышаем** —
  отсутствие поля = `[]`.
- **`Game/CityEngine.swift`** — добавить публичный метод
  `func ingestTaskCompletionIfUnique(project:, title:, taskId:, source:, ts:)`:
  перед `eventLog.append` проверяет, нет ли в `engine.events` события с тем
  же непустым `source`. Если есть — silent no-op (idempotency через
  events.jsonl-уровень). Используется и `NotesWatcher`, и (в будущем)
  `GitWatcher`. `TasksJsonlWatcher` продолжает звать `ingestTaskCompletion`
  без проверки (его `source` либо nil, либо произвольная строка от агента —
  не наш канал dedup'а).
- **`UI/SettingsView.swift`** — встроить `NotesWatcherSection` после
  существующих полей.
- **`App/AppDelegate.swift`** — инстанциирование `NotesWatcher` после
  `engine`, регистрация в `CatchUpScheduler` (если он уже доступен — иначе
  ждём TASK-020).

### Протокол EventSource (контракт с TASK-020)

```swift
protocol EventSource: AnyObject {
    var sourceId: String { get }
    func scan(since: Date) -> Date  // returns new lastCheckTs
    func startLive()                // attach DispatchSource (if applicable)
    func stopLive()
}
```

`NotesWatcher` держит одну запись `EventSource` на каждый `NotesSourceSpec`
(file/folder/folder-recursive — единое поведение, переключается через
enumerator). `sourceId` = стабильный хэш `path + kind`.

### Структуры данных

```swift
struct NotesSourceSpec: Codable, Identifiable, Hashable {
    let id: String                   // SHA-256(path + kind), стабильный
    var path: URL                    // bookmark-free, прямой путь
    var kind: SourceKind             // .file / .folder / .folderRecursive
    var mode: ProcessingMode         // .deleteProcessed / .sidecarDedup
    enum SourceKind: String, Codable { case file, folder, folderRecursive }
    enum ProcessingMode: String, Codable { case deleteProcessed, sidecarDedup }
}

struct ParsedTask {
    let projectId: String            // [A-Za-z0-9_-]+, не зарезервированное
    let title: String                // trimmed, 1..500 chars
    let lineHash: String             // SHA-256 от исходной строки (raw)
    let templateNumber: Int          // 1..4 (для отладки/тестов)
}
```

### Парсер шаблонов (`NotesPatternParser`)

- Регекспы как `static let` (компиляция один раз).
- Шаблон 1: `^- \[x\] \[project: ([A-Za-z0-9_-]+)\] (.+)$`
- Шаблон 2: `^- \[x\] (.+) #([A-Za-z0-9_-]+)\s*$` (title до hashtag'а, обрезать
  trailing whitespace)
- Шаблон 3: `^~~(.+)~~ #([A-Za-z0-9_-]+)\s*$`
- Шаблон 4: `^- \[x\] ([A-Za-z0-9_-]+): (.+)$` с пост-фильтром zoom'a
  projectId по `RESERVED = { "project", "system", "null", "none" }` (lowercase
  compare).
- Приоритет: пробуем 1 → 2 → 3 → 4, возвращаем первый match.
- `lineHash` берётся **до** trimming'а, по сырой строке файла (без LF).

### Sidecar (`NotesStateStore`)

- Каталог: `AppPaths.appSupport.appendingPathComponent("notes-state")`,
  создаётся при старте.
- Файл: `<sourceId>.json`, формат `{ "<lineHash>": "<ISO8601>" }`.
- Atomic write через `Data.write(to:, options:.atomic)`.
- R/W из IO-очереди watcher'а (последовательная), main thread не блокируется.

### NotesWatcher (главный класс)

```swift
final class NotesWatcher {
    weak var engine: CityEngine?
    private var specs: [NotesSourceSpec.ID: NotesSourceSpec] = [:]
    private var liveSources: [NotesSourceSpec.ID: DispatchSourceFileSystemObject] = [:]
    private var state: [NotesSourceSpec.ID: NotesStateStore] = [:]
    private let queue = DispatchQueue(label: "city.notes.io")

    func register(_ spec: NotesSourceSpec)            // от Settings UI
    func unregister(_ id: NotesSourceSpec.ID)
    func scan(_ id: NotesSourceSpec.ID, since: Date)  // ручной/scheduler-driven
}
```

- `register` — открывает sidecar, attach DispatchSource (на file или папку),
  immediate scan с `since = sidecar.lastSeen ?? .distantPast`.
- `unregister` — closes fd, сохраняет sidecar.
- На каждый файл при scan'е: `NotesFileReader.read(url) -> (text, encoding)`,
  построчно через парсер, для каждой match'нувшей строки:
  1. `lineHash` → если `state.contains(lineHash)` (sidecar-режим) → skip.
  2. `event = (project, title, ts = file mtime, source = "notes:<sourceId>:<lineHash>")`.
  3. `engine.ingestTaskCompletionIfUnique(...)` на main queue.
  4. После успешного ingest (синхронно через main.sync? — нет, считаем
     pessimistic: если ingest упал, на следующем тике перепарсится):
     - `sidecar-dedup`: `state[lineHash] = Date()` + save.
     - `delete-processed` (только UTF-8): построить новый текст без этой
       строки, atomic write; если файл стал empty/whitespace → `removeItem`.

### DispatchSource live-режим

Для `.file` — стандартный `O_EVTONLY` (как в TasksJsonlWatcher).
Для `.folder` / `.folderRecursive` — DispatchSource на сам каталог; на write/extend
запускаем полный re-scan папки (cheap, файлов десятки–сотни). Это проще, чем
поддерживать индекс открытых fd'ев на каждый .md.

### Catch-up интеграция

Каждый `NotesSourceSpec` регистрируется как `EventSource` в
`CatchUpScheduler`. Если TASK-020 ещё не закрыта на момент работы — оставляем
TODO-комментарий + `DispatchSourceTimer` 5 мин внутри `NotesWatcher` как
временное решение. **Чистая реализация — только после закрытия TASK-020.**

### Settings UI

`NotesWatcherSection` — `Section` внутри существующей `Form` в `SettingsView`.
Биндинг — массив `@Published var notesSources` в `AppSettings`. Изменение
массива → `appSettings.save()` + `notesWatcher.register/unregister`.

`NSOpenPanel` запускается из метода View (через `NSApp.runModal`), результат —
один `URL`. По типу URL (`isDirectory` атрибут + checkbox «рекурсивно»)
строится `NotesSourceSpec`.

Alert «delete-processed подтверждение» — стандартный SwiftUI `.alert`,
триггер — `@State var pendingMode: ProcessingMode?`.

### Тестовый план (юнит-тесты)

1. `NotesPatternParser` — 4 позитива (по одному на шаблон), 4 негатива
   (зарезервированный projectId; незакрытый strikethrough; пустой title;
   неподходящий формат).
2. Приоритет: `- [x] [project: foo] task #bar` → шаблон 1, `project=foo`.
3. `NotesStateStore` — write/read round-trip, atomic при concurrent reader.
4. `NotesFileReader` — UTF-8 ok, Latin-1 fallback ok, mode auto-downgrade
   в Latin-1 + warning.
5. `NotesWatcher.scan` на тестовой папке (in-memory через `FileManager` в
   `tmp`): 4 шаблона → 4 события в `engine.events`, повторный scan → 0 новых
   событий.

### Точки риска

- **NSOpenPanel + SwiftUI**: в macOS modal не блокирует SwiftUI render-цикл
  правильно при некоторых combinations. Сделать через AppKit-обёртку с
  `runModal()`, return `URL?` синхронно.
- **DispatchSource на папку при rename**: macOS не всегда даёт write-event при
  моде Obsidian (создаёт temp + rename). Покрыть через периодический scan
  (5-мин F-20) — это и есть страховка.
- **delete-processed race с редактором**: документировано в edge cases,
  atomic write минимизирует риск, но не исключает потерю «второй редакции
  юзера за тот же scan». Решение «накат поверх»: на следующем тике
  пере-чтение из файла даст новое состояние; не блокер для приёмки.
- **Sidecar drift** (state corrupt): `NotesStateStore.load()` при decode-fail →
  лог + пустой словарь + регенерация на следующем save. Events.jsonl dedup
  через `ingestTaskCompletionIfUnique` спасает от повторного ingest.

### Что лид НЕ решает в этой задаче

- Расширение шаблонов через UI (Backlog).
- Расширение `version` в `Persisted` AppSettings (опциональное поле решает
  forward-compat).
- Миграция F-04 на `EventSource` (отдельная refactor-задача в Backlog).

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Smoke-тест: добавить тестовую папку, записать 4 примера (по одному на
      каждый шаблон), сохранить, через 5 сек все 4 события в `events.jsonl`,
      юниты на карте. Проверить оба режима (delete / sidecar).

#### Технические
- [ ] Компиляция Swift без новых ошибок/варнингов
- [ ] Существующие тесты F-04 / F-12 / F-14 / F-20 не сломаны
- [ ] Atomic write для `delete-processed` (re-write через `.atomic`)

#### Обновление документации
- [ ] `Current.md`: F-18 → ✅, F-04 пометка «legacy / частный случай F-18»
- [ ] `Diff.md`: D-18 удалён
- [ ] Новые идеи → `Backlog.md`, баги → `Bugs.md`

---

## Статус

`[x] done`
до закрытия TASK-020 — допустим временный 5-мин `DispatchSourceTimer` внутри
watcher'а)

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: —
- Lead-разбор: 2026-05-22
- Готова к работе: 2026-05-22 (с оговоркой по TASK-020)
- Завершена: 2026-05-22
- Коммит: a19104d
