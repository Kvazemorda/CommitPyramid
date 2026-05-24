# TASK-043: Множитель веса коммита/задачи в Settings (×0.1 по умолчанию)

## Связь
- **F-19** из Concept.md (Git watcher)
- **F-24** из Concept.md (новая фича — настройка веса)
- **BUG-013** из Bugs.md
- **Приоритет:** P0

---

## 📋 Постановка от менеджера

_Автор: opus_
_Дата: 2026-05-24_

### Что хотим

Текущий `weightByDiff` для коммитов даёт 1–5 юнитов за коммит — для репо в 200
коммитов получается 600 юнитов, для 7 репо это 3000+ юнитов на старте. Город
переполнен. Пользователь хочет:

1. Уменьшить вес ×20 по умолчанию — каждый коммит = ~1 юнит.
2. Иметь слайдер в Settings для настройки множителя (от очень редкого до
   плотного).
3. То же для tasks.jsonl и notes-источников — отдельный слайдер.
4. Множитель применяется только при Reset & Rebuild, не на live.

### Пользовательский сценарий

1. Пользователь открывает Settings → Git watcher → видит слайдер «Вес коммита»
   (default 0.1).
2. Подвигав слайдер до 0.05 — ставит дату, нажимает Reset → город маленький,
   ~1 юнит на коммит.
3. Двигает до 1.0 → Reset → город как был раньше (1-5 юнитов на коммит).
4. В Settings → Notes watcher / Tasks file — отдельный слайдер «Вес задачи»
   (default 1.0).

### Acceptance criteria

- [ ] В Settings → Git watcher над списком репо есть слайдер «Вес коммита»
      0.05…2.0 step 0.05, default 0.1.
- [ ] При весе 0.1 коммит в 50 строк = 1 юнит, в 5000 строк = 1 юнит, в
      50000 строк = 1 юнит (все clamped to ≥1).
- [ ] При весе 1.0 поведение возвращается к до-фикса (1/2/3/5 по новым
      порогам).
- [ ] В Settings → Notes watcher есть слайдер «Вес задачи» 0.5…5.0 step 0.5,
      default 1.0. Применяется и к notes, и к tasks.jsonl.
- [ ] Множитель применяется только в performScan ПОСЛЕ reset, не пересчитывает
      существующие events.
- [ ] Tooltip к каждому слайдеру объясняет как это работает.

### Что НЕ делаем

- Не меняем GitWatcher на live-обновление multiplier'а (изменение применяется
  только при следующем Reset).
- Не делаем per-repo multiplier (один глобальный для git, один для notes/tasks).

### Edge cases

- [ ] Множитель 0 — clamp до 0.05 (минимум 1 юнит на коммит).
- [ ] При обновлении multiplier во время идущего scan — текущий scan
      использует старое значение, следующий scan новое.
- [ ] Совместимость с persisted AppSettings: новые поля optional, default из
      кода.

### Зависимости

- AppSettings.save() — добавить новые поля.
- GitWatcherSection / NotesWatcherSection — добавить UI.

### Дизайн

Slider под кнопками «Добавить репозиторий»/«Сканировать папку», с label и
числовым отображением значения. Tooltip через `.help()`.

### Done-критерий

_Из Concept.md F-24:_

> В Settings → Git watcher есть слайдер «Вес коммита» (default 0.1). После
> reset с этим значением каждый git commit (даже большой) даёт ровно 1 юнит.
> При увеличении до 1.0 поведение возвращается к до-фикса (1-5 юнитов по diff).
> Слайдер для tasks/notes отдельный.

---

## 🛠 Технический разбор от тимлида

_Автор: opus_
_Дата: 2026-05-24_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

- **`GitWatcher.computeWeight`** (`GitWatcher.swift:251-273`) возвращает 1/2/3/5.
- **`GitWatcher.performScan`** (line 213): `let weight: Int = repo.weightByDiff
  ? computeWeight(...) : 1`. Дальше `for i in 0..<weight { ... ingest ... }`.
- **`AppSettings`** (`AppSettings.swift`): Codable Persisted с version=2.
  Добавить поля как Optional<Double> с дефолтами в init.
- **`AppSettings.save`** уже умеет добавлять поля back-compat (через Optional).

### Архитектурное решение

1. AppSettings обзаводится `commitWeightMultiplier` (Double, default 0.1) и
   `taskWeightMultiplier` (Double, default 1.0). Codable optional, версия
   персиста повышается до 3.
2. GitWatcher.computeWeight остаётся, но порог пересматривается + множитель
   применяется в конце:
   ```swift
   let baseWeight = computeBaseWeight(...)  // 1/2/3/5 по новым порогам
   let scaled = max(1, Int(round(Double(baseWeight) * multiplier)))
   return scaled
   ```
3. GitWatcher принимает `multiplier` через GitRepoSpec или через прямую
   ссылку на AppSettings. Проще — `weak var appSettings: AppSettings?` в
   GitWatcher, читать multiplier при scan.
4. То же для NotesWatcher и TasksJsonlWatcher (если они умеют веса). По
   контексту: notes/tasks НЕ имеют веса (каждая задача = 1 юнит). Множитель
   `taskWeightMultiplier > 1` нужно интерпретировать как «N юнитов на одну
   задачу» — дублировать ingest N раз. Множитель `<1` clamp до 1.

### Пошаговая декомпозиция

1. **Добавить поля в AppSettings** `[AC:1,4]`
   - Файл: `Sources/CityDeveloper/Data/AppSettings.swift`
   - В `@Published` блок добавить:
     ```swift
     @Published var commitWeightMultiplier: Double = 0.1 {
         didSet { commitWeightMultiplier = min(max(commitWeightMultiplier, 0.05), 2.0) }
     }
     @Published var taskWeightMultiplier: Double = 1.0 {
         didSet { taskWeightMultiplier = min(max(taskWeightMultiplier, 0.5), 5.0) }
     }
     ```
   - В `Persisted` struct добавить:
     ```swift
     let commitWeightMultiplier: Double?
     let taskWeightMultiplier: Double?
     ```
   - В `load()`:
     ```swift
     commitWeightMultiplier: decoded.commitWeightMultiplier ?? 0.1,
     taskWeightMultiplier: decoded.taskWeightMultiplier ?? 1.0
     ```
   - В `save()` (version 3): передавать новые поля.
   - В `init`: принимать optional с дефолтами.

2. **Поднять пороги computeWeight (BUG-013)** `[AC:2]`
   - Файл: `Sources/CityDeveloper/Data/GitWatcher/GitWatcher.swift`
   - Метод: `computeWeight(repo:prevSha:sha:)` → `computeBaseWeight`.
   - Новые пороги:
     ```swift
     switch lines {
     case 0...200:    return 1
     case 201...2000: return 2
     case 2001...10000: return 3
     default:         return 5
     }
     ```

3. **Применить multiplier в performScan** `[AC:2,3,5]`
   - Файл: `Sources/CityDeveloper/Data/GitWatcher/GitWatcher.swift`
   - В `performScan`, перед циклом ingest:
     ```swift
     let multiplier = appSettings?.commitWeightMultiplier ?? 0.1
     ```
   - Заменить вычисление weight:
     ```swift
     let baseWeight: Int
     if repo.weightByDiff, let prev = prevSha {
         baseWeight = computeBaseWeight(repo: repo, prevSha: prev, sha: commit.sha)
     } else {
         baseWeight = 1
     }
     let weight = max(1, Int(round(Double(baseWeight) * multiplier)))
     ```
   - Добавить `weak var appSettings: AppSettings?` в GitWatcher.

4. **Прокинуть appSettings в GitWatcher** `[AC:1]`
   - Файл: `Sources/CityDeveloper/App/AppDelegate.swift`
   - В `applicationDidFinishLaunching` после `gitWatcher = GitWatcher()`:
     ```swift
     gitWatcher.appSettings = appSettings
     ```
   - Та же строка в resetCity.

5. **UI слайдер commitWeight в GitWatcherSection** `[AC:1,6]`
   - Файл: `Sources/CityDeveloper/UI/Settings/GitWatcherSection.swift`
   - В body, ПЕРЕД списком репо:
     ```swift
     VStack(alignment: .leading, spacing: 4) {
         HStack {
             Text("Вес коммита:")
             Slider(value: $settings.commitWeightMultiplier, in: 0.05...2.0, step: 0.05)
             Text(String(format: "×%.2f", settings.commitWeightMultiplier))
                 .monospacedDigit().frame(width: 50)
         }
         .help("Множитель количества юнитов на один коммит. 0.1 = почти всегда 1 юнит. 1.0 = 1-5 юнитов по размеру diff. Применяется при следующем Reset.")
     }
     .padding(.bottom, 4)
     ```
   - На onChange: `settings.save()`.

6. **UI слайдер taskWeight** `[AC:4]`
   - Файл: `Sources/CityDeveloper/UI/Settings/NotesWatcherSection.swift`
   - Аналогично — слайдер в начале, range 0.5...5.0, step 0.5, default 1.0.
   - Tooltip: «Множитель числа юнитов на одну закрытую задачу из заметок/tasks.jsonl. Применяется при следующем Reset.»

7. **NotesWatcher / TasksJsonlWatcher применение multiplier**
   - Файл: `Sources/CityDeveloper/Data/NotesWatcher/NotesWatcher.swift`
   - В `performScan` где `ingestTaskCompletionIfUnique`:
     ```swift
     let multiplier = appSettings?.taskWeightMultiplier ?? 1.0
     let repeatCount = max(1, Int(round(multiplier)))
     for j in 0..<repeatCount {
         let suffix = repeatCount > 1 ? "#\(j)" : ""
         let key = "\(sourceKey)\(suffix)"
         engine.ingestTaskCompletionIfUnique(project: ..., source: key, ts: ts.addingTimeInterval(Double(j) * 0.001))
     }
     ```
   - Добавить `weak var appSettings: AppSettings?` в NotesWatcher.
   - В AppDelegate (init + reset) проставить ссылку.
   - Тот же паттерн для TasksJsonlWatcher (если нужно — у него ингест в
     processLine, добавить repeat).

### Edge cases

- [ ] **Существующие events не пересчитываются** — multiplier применяется ТОЛЬКО в
      performScan. Существующие events.jsonl как был, так и останется.
- [ ] **multiplier=0.05, baseWeight=1** → 0.05 → round → 0 → clamp до 1. OK.
- [ ] **multiplier=2.0, baseWeight=5** → 10 юнитов на коммит. OK (юзер сам
      просил).
- [ ] **NotesWatcher multiplier=0.5** → round(0.5) = 0, clamp до 1. То есть для
      notes ≤1 — всегда 1 юнит.

### Файлы для изменения

- `Sources/CityDeveloper/Data/AppSettings.swift` — новые поля + persistence.
- `Sources/CityDeveloper/Data/GitWatcher/GitWatcher.swift` — пороги +
  multiplier + appSettings ref.
- `Sources/CityDeveloper/Data/NotesWatcher/NotesWatcher.swift` — multiplier +
  appSettings ref.
- `Sources/CityDeveloper/Data/TasksJsonlWatcher.swift` — multiplier + ref.
- `Sources/CityDeveloper/UI/Settings/GitWatcherSection.swift` — слайдер.
- `Sources/CityDeveloper/UI/Settings/NotesWatcherSection.swift` — слайдер.
- `Sources/CityDeveloper/App/AppDelegate.swift` — пропатчить ссылку.

### Файлы НЕ трогать

- Существующие events.jsonl и replay — multiplier не должен пересчитывать
  историю.

### Команды проверки

- Компиляция: `swift build`
- Ручная проверка:
  1. Открыть Settings → видеть слайдеры.
  2. Поставить 0.05, Reset с датой 2020 → ~1 юнит на коммит.
  3. Поставить 1.0, Reset → стандартное поведение.
  4. Слайдер persist'ится между запусками.

### Сложность
`middle` — несколько файлов, persistence + UI + watcher integration.

### Объём
M (≤1д)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: middle_

### Definition of Done

- [ ] AC выполнены
- [ ] Сборка чистая
- [ ] `Bugs.md`: BUG-013 → закрыт
- [ ] `Current.md`: F-24 → ✅

---

## Статус
`[x] done`

## Метаданные
- Создана: 2026-05-24
- Завершена: 2026-05-24
- Коммит: 2840287
