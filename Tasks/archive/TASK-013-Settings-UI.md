# TASK-013: Settings UI — путь к `tasks.jsonl`, hotkey, путь к данным

## Связь
- **F-14** Настройки (UI)
- **D-14**
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Дать пользователю контроль над тремя ключевыми параметрами, которые сейчас
захардкожены: путь к `tasks.jsonl`, путь к данным игры (`events.jsonl`,
снэпшоты), глобальный hotkey explore-режима. Параметры применяются без
перезапуска приложения. Это закрывает F-14 и снимает барьер «нужно
перекомпилировать ради смены пути».

### Пользовательский сценарий

1. В меню статус-бара появляется пункт «Настройки…» (или ⌘,).
2. Открывается отдельное SwiftUI-окно с формой:
  - Поле «Путь к `tasks.jsonl`» с кнопкой «Выбрать…» (`NSOpenPanel`,
    `canChooseFiles = true`, `allowedContentTypes = [.json]` или wildcard).
  - Поле «Путь к данным игры» (директория) с кнопкой «Выбрать…»
    (`canChooseDirectories = true`).
  - Поле «Hotkey explore» — отображает текущую комбинацию («⌘⌥G»);
    кнопка «Изменить…» → модальный recorder, ловит следующий нажатый shortcut.
  - Кнопка «Сохранить» (применяет немедленно).
3. Сохраняю изменения — watcher переподписывается на новый путь, эмиттер
   событий переключается на новый каталог, hotkey пере-регистрируется. Без
   перезапуска.
4. Закрываю окно, возвращаюсь к городу — он работает с новыми параметрами.

### Acceptance criteria

- [ ] `Data/AppSettings.swift` — `Codable struct` с полями:
  - `tasksJsonlPath: URL`
  - `dataDirectory: URL`
  - `hotkeyKeyCode: UInt32` (по умолчанию `kVK_ANSI_G`)
  - `hotkeyModifiers: UInt32` (по умолчанию `cmdKey | optionKey`)
  - `version: Int = 1`
- [ ] Настройки персистятся в `~/Library/Preferences/com.outbyte.citydeveloper.plist`
      через `UserDefaults` (либо отдельный JSON в стандартном Preferences
      каталоге).
- [ ] При старте `AppDelegate` читает `AppSettings`; при отсутствии — создаёт
      дефолтный (пути из `AppPaths`, hotkey ⌘⌥G).
- [ ] `SwiftUI Settings` окно через `Settings { … }` сцену или отдельный
      `NSWindow` с `SwiftUI Form`:
  - Группы: «Данные», «Hotkey».
  - Каждое поле с label и кнопкой / picker.
  - Внизу — «Сохранить» / «Отмена».
- [ ] **Применение пути к `tasks.jsonl` без перезапуска:** `TasksJsonlWatcher`
      получает `restart(at: URL)`, останавливает текущий `DispatchSource`,
      сбрасывает `IngestionState.offset = 0` (или мигрирует, если такой
      offset валиден для нового файла — упрощение: всегда 0), запускает
      новый source.
- [ ] **Применение пути к данным без перезапуска:** при смене `dataDirectory`
      — `EventLog` flush + reopen на новом пути; снэпшоты (если есть из
      TASK-012) переезжают на новый путь; `errors.log` тоже.
- [ ] **Применение hotkey без перезапуска:** `GlobalHotkey.unregister() +
      register(keyCode:modifiers:)`; если регистрация неудачна (конфликт
      с другим приложением) — вернуть предыдущий hotkey, показать алерт.
- [ ] **Валидация при сохранении:**
  - `tasksJsonlPath` существует И доступен на чтение → ок; иначе — алерт
    «Файл не найден или недоступен», изменения не применяются.
  - `dataDirectory` существует И доступен на запись (test write `tmp.txt` +
    delete) → ок; иначе — алерт.
  - Hotkey-recorder: пустой shortcut запрещён; известные конфликты
    (⌘+space, ⌘+tab, ⌘+Q) — предупреждение.
- [ ] Меню статус-бара получает пункт «Настройки…» (key equiv ⌘, только
      в открытом меню).

### Что НЕ делаем (границы скоупа)

- Не делаем выбор дисплея (мульти-монитор) — F-14 концепта упоминает, но
  это в backlog (B-NN), не в Done MVP.
- Не делаем экспорт / импорт настроек.
- Не делаем темы / визуальные настройки (палитра, день/ночь).
- Не делаем настройку поведения decay, частоты тиков, размера квартала и
  т.п. — они в геймплейной модели, не в UI.
- Не делаем sync настроек между устройствами / iCloud.
- Не делаем настройку «авто-старт при логине» (отдельная задача).

### Edge cases

- [ ] **Файл `tasks.jsonl` не существует, но настройка указывает на него:**
      при следующем запуске — алерт «Файл по сохранённому пути не найден»,
      открыть Settings.
- [ ] **`dataDirectory` стал недоступен (например, размонтирован внешний
      диск):** алерт при попытке записи в `events.jsonl`; приложение
      продолжает работать, события буферизуются в памяти и пишутся при
      возврате доступа.
- [ ] **Hotkey уже занят:** регистрация падает → алерт, возврат к предыдущему.
- [ ] **Сохранение настроек дублируется** (быстрые нажатия «Сохранить»): только
      первая применяется, последующие игнорируются если значения те же.
- [ ] **Невалидный JSON `AppSettings`** (после ручного редактирования):
      fallback на дефолты, лог в `errors.log`.
- [ ] **Очень длинный путь** (>1024 символов) — стандартный `URL` ограничен
      OS; алерт «Слишком длинный путь».
- [ ] **Открытие Settings когда окно уже открыто:** focus на существующее
      окно, не создавать новое.

### Зависимости

- **F-01** (GlobalHotkey) — переиспользуется `register/unregister`.
- **F-03** (EventLog) — добавить `EventLog.relocate(to: URL)`.
- **F-04** (TasksJsonlWatcher) — добавить `restart(at: URL)`.
- **F-12** (Snapshots, опционально) — если есть — переезжают вместе с
  `dataDirectory`.
- **AppPaths** — становится «дефолты», не источник истины; источник —
  `AppSettings`.

### Дизайн

Из `DesignConcept.md`:
- Settings окно — стандартный macOS look (`Form` / `GroupBox` SwiftUI).
- Шрифт — системный (`SF Pro`).
- Размер окна — фиксированный, минимум 480×360 pt.
- Используются стандартные системные цвета (не палитра города — это окно
  utility, а не игровое).
- Кнопки — стандартные `Button` (primary «Сохранить», secondary «Отмена»).

### Done-критерий

_Из `Concept.md` F-14 (дословно):_ В настройках можно сменить путь к
`tasks.jsonl` — изменение подхватывается watcher-ом без перезапуска.
Переназначенный hotkey начинает работать немедленно. Путь к данным валидируется
при сохранении (есть ли доступ на запись).

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния
- `App/GlobalHotkey.swift` — `register(keyCode:modifiers:)` + `unregister()`. Поддерживает re-register.
- `Data/TasksJsonlWatcher.swift` — конструктор `init(engine: CityEngine)`, путь через `AppPaths.tasksJsonl` (захардкожен). Нужен `restart(at: URL)`.
- `Data/EventLog.swift` — `init()` с дефолтным путём `AppPaths.eventsJsonl`. Нужен `relocate(to: URL)`.
- `Data/AppPaths.swift` — статические let'ы, hardcoded в `~/Library/Application Support/CityDeveloper/`.
- `App/AppDelegate.swift` — точка входа, создаёт engine, watcher, hotkey, scene.
- `Status/StatusBarController.swift` — меню «Открыть город» / «Выйти»; пункт «Настройки» отсутствует.

### Архитектурное решение
- Новая `AppSettings` (`ObservableObject` + Codable persistent state в `UserDefaults`). Дефолты — текущие значения из `AppPaths`.
- При запуске `AppDelegate` создаёт `appSettings = AppSettings.load()`; все компоненты получают параметры из неё, а не из `AppPaths` напрямую.
- `AppSettings` публикует `@Published` поля → подписчики реагируют. Альтернатива: callback'и через `WindowModeManager`-стиль. Выбираем `ObservableObject` — стандартный SwiftUI-паттерн, легче подписать SwiftUI Form.
- Settings-окно — через `Settings { ... }` сцена SwiftUI (`@main App` уровень). НО проект использует `AppDelegate` + `NSApplication.shared.run()` без `App` protocol. Поэтому: отдельное `NSWindow` с `NSHostingView` содержащим `SettingsView`. `NSWindowController` обеспечивает focus-on-existing.
- `AppPaths` остаётся как «дефолты». Все рантайм-чтения проксируются через `appSettings`.

### Пошаговая декомпозиция

1. **AppSettings модель + persistence** `[AC:1,2]`
   - Файл: `Sources/CityDeveloper/Data/AppSettings.swift` (новый)
   - Скелет:
     ```swift
     final class AppSettings: ObservableObject {
         @Published var tasksJsonlPath: URL
         @Published var dataDirectory: URL
         @Published var hotkeyKeyCode: UInt32
         @Published var hotkeyModifiers: UInt32
         let version: Int = 1
         private static let key = "com.outbyte.citydeveloper.settings"
         init(tasksJsonlPath: URL, dataDirectory: URL, hotkeyKeyCode: UInt32, hotkeyModifiers: UInt32) {
             self.tasksJsonlPath = tasksJsonlPath; self.dataDirectory = dataDirectory
             self.hotkeyKeyCode = hotkeyKeyCode; self.hotkeyModifiers = hotkeyModifiers
         }
         static func load() -> AppSettings {
             if let data = UserDefaults.standard.data(forKey: key),
                let decoded = try? JSONDecoder().decode(Persisted.self, from: data),
                decoded.version == 1 {
                 return AppSettings(tasksJsonlPath: decoded.tasksJsonlPath, dataDirectory: decoded.dataDirectory,
                     hotkeyKeyCode: decoded.hotkeyKeyCode, hotkeyModifiers: decoded.hotkeyModifiers)
             }
             return AppSettings(tasksJsonlPath: AppPaths.tasksJsonl, dataDirectory: AppPaths.appSupport,
                 hotkeyKeyCode: UInt32(kVK_ANSI_G), hotkeyModifiers: UInt32(cmdKey | optionKey))
         }
         func save() {
             let p = Persisted(version: version, tasksJsonlPath: tasksJsonlPath, dataDirectory: dataDirectory,
                 hotkeyKeyCode: hotkeyKeyCode, hotkeyModifiers: hotkeyModifiers)
             if let data = try? JSONEncoder().encode(p) { UserDefaults.standard.set(data, forKey: AppSettings.key) }
         }
         private struct Persisted: Codable {
             let version: Int; let tasksJsonlPath: URL; let dataDirectory: URL
             let hotkeyKeyCode: UInt32; let hotkeyModifiers: UInt32
         }
     }
     ```

2. **TasksJsonlWatcher.restart(at:)** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Data/TasksJsonlWatcher.swift`
   - Добавить:
     ```swift
     func restart(at newPath: URL) {
         stop()
         self.path = newPath  // нужно изменить let → var path: URL
         // Сбросить IngestionState.offset = 0 (упрощение)
         ingestionState.offset = 0
         ingestionState.save()
         start()
     }
     ```

3. **EventLog.relocate(to:)** `[AC:4]`
   - Файл: `Sources/CityDeveloper/Data/EventLog.swift`
   - Добавить:
     ```swift
     func relocate(to newDirectory: URL) {
         flush()  // если есть buffer'ы — выгрузить
         closeHandle()
         self.fileURL = newDirectory.appendingPathComponent("events.jsonl")
         openHandle()
     }
     ```
   - Свойство `fileURL` сделать `var`.

4. **GlobalHotkey: возврат при неудаче** `[AC:5]`
   - Файл: `Sources/CityDeveloper/App/GlobalHotkey.swift`
   - Текущая `register` уже возвращает `Bool`. Использовать: при неудаче — caller должен восстановить предыдущую комбинацию.

5. **SettingsView SwiftUI** `[AC:UI]`
   - Файл: `Sources/CityDeveloper/UI/SettingsView.swift` (новый)
   - Скелет:
     ```swift
     struct SettingsView: View {
         @ObservedObject var settings: AppSettings
         @State private var draftTasksPath: URL
         @State private var draftDataDir: URL
         @State private var draftKeyCode: UInt32
         @State private var draftModifiers: UInt32
         @State private var alertText: String? = nil
         var onSave: (AppSettings) -> Void
         var onCancel: () -> Void
         init(settings: AppSettings, onSave: @escaping (AppSettings) -> Void, onCancel: @escaping () -> Void) {
             self.settings = settings; self.onSave = onSave; self.onCancel = onCancel
             _draftTasksPath = State(initialValue: settings.tasksJsonlPath)
             _draftDataDir = State(initialValue: settings.dataDirectory)
             _draftKeyCode = State(initialValue: settings.hotkeyKeyCode)
             _draftModifiers = State(initialValue: settings.hotkeyModifiers)
         }
         var body: some View {
             Form {
                 Section("Данные") {
                     HStack { Text("tasks.jsonl:"); Text(draftTasksPath.path).truncationMode(.middle)
                         Button("Выбрать…", action: pickTasks) }
                     HStack { Text("Папка данных:"); Text(draftDataDir.path).truncationMode(.middle)
                         Button("Выбрать…", action: pickDataDir) }
                 }
                 Section("Hotkey") {
                     HStack { Text(hotkeyDisplay(draftKeyCode, draftModifiers))
                         Button("Изменить…", action: recordHotkey) }
                 }
                 HStack { Spacer(); Button("Отмена", action: onCancel); Button("Сохранить", action: save).keyboardShortcut(.return) }
             }.padding(20).frame(minWidth: 480, minHeight: 360)
                 .alert("Ошибка", isPresented: .constant(alertText != nil), actions: { Button("OK") { alertText = nil } }, message: { Text(alertText ?? "") })
         }
         private func pickTasks() { let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; if panel.runModal() == .OK, let url = panel.url { draftTasksPath = url } }
         private func pickDataDir() { let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; if panel.runModal() == .OK, let url = panel.url { draftDataDir = url } }
         private func recordHotkey() { /* модальный recorder; см. шаг 6 */ }
         private func save() {
             // Валидация
             guard FileManager.default.isReadableFile(atPath: draftTasksPath.path) else { alertText = "Файл tasks.jsonl не найден или недоступен"; return }
             let testFile = draftDataDir.appendingPathComponent(".citydev_write_test")
             guard (try? "test".write(to: testFile, atomically: true, encoding: .utf8)) != nil else { alertText = "Папка данных недоступна для записи"; return }
             try? FileManager.default.removeItem(at: testFile)
             // Применить
             settings.tasksJsonlPath = draftTasksPath
             settings.dataDirectory = draftDataDir
             settings.hotkeyKeyCode = draftKeyCode
             settings.hotkeyModifiers = draftModifiers
             settings.save()
             onSave(settings)
         }
     }
     ```

6. **Hotkey recorder** `[AC:5]`
   - В `SettingsView.recordHotkey()` — открыть модальный sheet с `Text("Нажмите комбинацию…")` и `NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in ... }`. Захватить `event.keyCode` + `event.modifierFlags` (преобразовать в `cmdKey/optionKey/...`), валидировать ≥ 1 модификатор + клавиша, проверить black-list (минимально: пустая комбинация). Сохранить в `draftKeyCode`/`draftModifiers`.

7. **SettingsWindowController** `[AC:UI focus-on-existing]`
   - Файл: `Sources/CityDeveloper/App/SettingsWindowController.swift` (новый)
   - Скелет:
     ```swift
     final class SettingsWindowController {
         private var window: NSWindow?
         func show(settings: AppSettings, onSave: @escaping (AppSettings) -> Void) {
             if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
             let view = SettingsView(settings: settings,
                 onSave: { s in onSave(s); self.window?.close() },
                 onCancel: { self.window?.close() })
             let host = NSHostingController(rootView: view)
             let w = NSWindow(contentViewController: host)
             w.title = "Настройки CityDeveloper"
             w.styleMask = [.titled, .closable]
             w.setContentSize(NSSize(width: 480, height: 360))
             w.center()
             window = w
             w.makeKeyAndOrderFront(nil)
             NSApp.activate(ignoringOtherApps: true)
         }
     }
     ```

8. **StatusBarController: пункт «Настройки…»** `[AC:menu]`
   - Файл: `Sources/CityDeveloper/Status/StatusBarController.swift`
   - Добавить `NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")` (modifiers = `.command`). Action — selector в StatusBarController, который дёргает `onSettingsRequested?()` (closure, прокидывается из AppDelegate).

9. **AppDelegate: связать всё** `[AC:hot-reload]`
   - Файл: `Sources/CityDeveloper/App/AppDelegate.swift`
   - Создать `appSettings = AppSettings.load()` ДО engine/watcher/hotkey.
   - Использовать `appSettings.dataDirectory` для `EventLog`/`AppPaths` (но `AppPaths` статика — нужно либо параметризовать `EventLog(directory: URL)`, либо передавать URL напрямую в `init`).
   - `engine = CityEngine(eventLog: EventLog(directory: appSettings.dataDirectory))`.
   - `watcher = TasksJsonlWatcher(engine: engine, path: appSettings.tasksJsonlPath)`.
   - `hotkey.register(keyCode: appSettings.hotkeyKeyCode, modifiers: appSettings.hotkeyModifiers)`.
   - `settingsWindow = SettingsWindowController()`.
   - `statusBarController.onSettingsRequested = { [weak self] in self?.settingsWindow.show(settings: self!.appSettings, onSave: self!.applySettings) }`.
   - Метод `applySettings(_ s: AppSettings)`:
     ```swift
     private func applySettings(_ s: AppSettings) {
         // Watcher restart
         watcher.restart(at: s.tasksJsonlPath)
         // EventLog relocate (если папка изменилась)
         engine.eventLog.relocate(to: s.dataDirectory)
         // Hotkey re-register
         hotkey.unregister()
         let ok = hotkey.register(keyCode: s.hotkeyKeyCode, modifiers: s.hotkeyModifiers)
         if !ok {
             NSLog("Hotkey \(s.hotkeyKeyCode) conflict; reverting")
             hotkey.register(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | optionKey))
             s.hotkeyKeyCode = UInt32(kVK_ANSI_G); s.hotkeyModifiers = UInt32(cmdKey | optionKey); s.save()
             // alert через NSAlert
         }
     }
     ```

### Edge cases (явно обработать)
- [ ] **Файл tasks.jsonl не существует при старте** (после сохранения настройки на удалённый файл): `TasksJsonlWatcher.start()` уже логирует и не падает. При запуске Settings — пользователь видит текущий путь, может перебрать.
- [ ] **dataDirectory недоступен (внешний диск размонтирован):** `EventLog.append` бросает → ловим в `appendSystemEvent` / `ingestTaskCompletion`, пишем в `ErrorsLog` (если ErrorsLog тоже в недоступном dir — увы, лог теряется; принять как ограничение MVP, в backlog «буферизация в памяти»).
- [ ] **Hotkey занят:** `register` возвращает `false` → возврат к дефолту, сохранить новый settings, показать `NSAlert`. См. шаг 9.
- [ ] **Двойные нажатия «Сохранить»:** SwiftUI `Button` обычно не реентерабелен в течение action; принять как достаточное.
- [ ] **Невалидный AppSettings в UserDefaults:** `JSONDecoder.decode` бросает → `load()` возвращает дефолт.
- [ ] **Очень длинный путь:** `URL` ограничен системно; `NSOpenPanel` отдаст валидный URL — без падений.
- [ ] **Открытие Settings когда окно уже открыто:** `SettingsWindowController.show` проверяет `window != nil` → `makeKeyAndOrderFront` (см. шаг 7).

### Файлы для изменения
- `Sources/CityDeveloper/Data/TasksJsonlWatcher.swift` — `restart(at:)`, `path: var`
- `Sources/CityDeveloper/Data/EventLog.swift` — `relocate(to:)`, `fileURL: var`, опциональный `init(directory:)`
- `Sources/CityDeveloper/Status/StatusBarController.swift` — пункт «Настройки», closure
- `Sources/CityDeveloper/App/AppDelegate.swift` — связь всех компонентов

### Файлы НЕ трогать
- `Game/CityEngine.swift` — не зависит от Settings напрямую (получает eventLog в init)
- `Game/GameScene.swift`, `WindowModeManager.swift` — не зависят от settings
- `GlobalHotkey.swift` — API готов

### Новые файлы
- `Sources/CityDeveloper/Data/AppSettings.swift`
- `Sources/CityDeveloper/UI/SettingsView.swift`
- `Sources/CityDeveloper/App/SettingsWindowController.swift`

### Команды проверки (для DoD)
- Компиляция: `swift build`
- Запуск: `swift run CityDeveloper`
- Ручная проверка:
  1. Меню статус-бара → «Настройки…» — открывается окно.
  2. Сменить tasks.jsonl на тестовый файл → добавить строку → юнит появляется.
  3. Сменить hotkey на ⌘⌥H → проверить.
  4. Конфликт hotkey: попробовать ⌘⌥G когда уже занят — алерт.
  5. Перезапуск приложения → настройки сохранились.

### Сложность
`middle`

**Обоснование:** 3 новых файла + 4 правки. UI с NSOpenPanel и hotkey recorder — стандартные, но требуют аккуратной интеграции с существующим AppDelegate. Без архитектурного риска, но objём средний.

### Ожидаемое время
M (≤ 1 день)

### Plan-review правки (round 1 → applied)

1. **CRITICAL — `EventLog` сигнатура:** реальный конструктор `EventLog.init(fileURL: URL = AppPaths.eventsJsonl)`. Используем явный путь:
   ```swift
   engine = CityEngine(eventLog: EventLog(fileURL: appSettings.dataDirectory.appendingPathComponent("events.jsonl")))
   ```
   `EventLog(directory:)` НЕ создаём (избыточная сигнатура).

2. **CRITICAL — `TasksJsonlWatcher`: правильное имя поля — `fileURL`, не `path`.**
   - В `restart(at:)`: `self.fileURL = newPath`. Поле сменить с `private let fileURL` на `private var fileURL`.
   - В `init`: параметр `fileURL: URL` (уже так в коде).
   - Шаг 9: `TasksJsonlWatcher(fileURL: appSettings.tasksJsonlPath, engine: engine)`.

3. **CRITICAL — `EventLog.relocate(to:)`: реальные методы вместо `flush()/closeHandle()`:**
   ```swift
   func relocate(to newDirectory: URL) {
       try? writeHandle?.close()
       writeHandle = nil
       self.fileURL = newDirectory.appendingPathComponent("events.jsonl")
       ensureFileExists()      // приватный, уже есть
       openForAppend()         // приватный, уже есть
   }
   ```
   Поле `private let fileURL` → `private var fileURL`. `writeHandle` уже `var`.

4. **CRITICAL — доступ к `engine.eventLog` для relocate:** убираем `CityEngine.swift` из «НЕ трогать», добавляем публичный метод:
   ```swift
   // В CityEngine:
   func relocateEventLog(to newDirectory: URL) {
       eventLog.relocate(to: newDirectory)
   }
   ```
   Шаг 9 → `engine.relocateEventLog(to: s.dataDirectory)`. Никакого прямого доступа к приватному полю.

5. **IngestionState — accepted limitation:** `IngestionState.save()` пишет в `AppPaths.ingestionState` (захардкоженный путь). При смене `dataDirectory` `ingestion-state.json` остаётся в старом Application Support. Принимаем как ограничение MVP, фиксируем в `Bugs.md` после релиза TASK-013.

6. **Hotkey rollback алерт ДО закрытия Settings:** в `applySettings(_ s: AppSettings)` при неудаче register показать `NSAlert` модально и НЕ закрывать Settings-окно (или открыть его заново). Сейчас расхождение между UX («пользователь не понял, почему hotkey не изменился») и code-flow.

7. **`NSEvent.addLocalMonitorForEvents`** — обязательно `NSEvent.removeMonitor(_:)` в `dismiss()` recorder'а, иначе утечка обработчиков. Добавить в скелет шага 6.

8. **Файлы для изменения — обновлены:**
   - + `Sources/CityDeveloper/Game/CityEngine.swift` (добавить `relocateEventLog(to:)`)
   - Удалить `CityEngine.swift` из «Файлы НЕ трогать».

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен: сменить tasks.jsonl на тестовый файл, добавить
      строку — юнит появляется. Перебиндить hotkey на ⌘⌥H — работает.

#### Технические
- [ ] `swift build` без новых ошибок
- [ ] Settings персистятся и переживают перезапуск
- [ ] Невалидный JSON настроек → fallback на дефолты

#### Обновление документации
- [ ] `current.md`: F-14 ❌ → ✅
- [ ] `diff.md`: D-14 удалён

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: approved (round 1)
- Lead-model: opus
- Plan-review: needs-revision → applied (round 1)
- Сложность: middle
- Готова к работе: 2026-05-22
- Завершена: 2026-05-22
- Исполнитель: sonnet
- Code-review: revised (opus, round 2 approved)
- Коммит: —
