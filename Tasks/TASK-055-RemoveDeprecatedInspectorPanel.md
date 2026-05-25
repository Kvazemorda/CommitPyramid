# TASK-055: Удалить deprecated SpriteKit InspectorPanel + закрыть BUG-001

## Связь
- **F-11** из Concept.md (Инспектор / журнал событий)
- **BUG-001** из Bugs.md (P1)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-25_

### Что хотим

Убрать дублирование плашки при клике на здание. Сейчас в коде это уже фактически
сделано — вызовы `InspectorPanel.build(...)` в `GameScene.showInspector` и
`hideInspector` закомментированы (см. пометки `// BUG-001:`), и пользователь видит
только одну SwiftUI overlay-плашку (`InspectorOverlayCard`). Сам класс
`InspectorPanel` помечен `@available(*, deprecated)`. То есть user-facing
поведение уже соответствует ожидаемому из Bugs.md.

Осталось финальный cleanup: удалить deprecated файл `InspectorPanel.swift`, выпилить
мёртвое поле `inspector` и закомментированные строки в `GameScene.swift`, перенести
BUG-001 в «Закрытые» в `Bugs.md`. Это техдолг от частичного фикса — оставленные
заглушки путают читателя кода и мешают будущему рефактору click-handler'а.

### Пользовательский сценарий

1. Пользователь кликает на любой юнит в режиме explore.
2. Появляется ровно одна плашка — SwiftUI `InspectorOverlayCard` (trailing-center
   overlay, текст задачи + дата + проект). SpriteKit-попап не появляется.
3. Повторный клик на другой юнит — старая плашка скрывается, появляется новая для
   нового юнита.
4. Клик мимо юнита (по пустой клетке / по фону) — плашка скрывается.

Это поведение **уже работает в текущем коде** (через `bridge?.selectedUnitInfo`).
Задача — финальный cleanup, не поведенческий фикс.

### Acceptance criteria

- [ ] Файл `Sources/CityDeveloper/Game/InspectorPanel.swift` удалён из репо
      (через `git rm`, чтобы история сохранилась).
- [ ] В `Sources/CityDeveloper/Game/GameScene.swift` нет упоминаний
      `InspectorPanel` (ни в коде, ни в комментариях).
- [ ] В `GameScene.swift` удалено приватное поле `private var inspector: SKNode?`
      (строка 34) и все его присваивания (`inspector = nil` в строке 190; защита
      `if n === inspector { return }` в строке 978 — удалить эту проверку
      полностью, она была единственной защитой от клика по самому SpriteKit-попапу
      и теперь не нужна).
- [ ] Тела `showInspector(near:unit:project:)` и `hideInspector()` очищены от
      закомментированного legacy-кода — оставлены только активные строки
      (`bridge?.selectedUnitInfo = ...`).
- [ ] `swift build -c debug` проходит без ошибок и warning'ов про `deprecated`
      (так как класс удалён).
- [ ] `swift test` проходит — не меньше текущего baseline (165 pass + 1 skip на
      момент создания задачи; после TASK-054 baseline может измениться). Ни один
      тест не сломан удалением InspectorPanel.
- [ ] В `concept/Bugs.md` строка `BUG-001 | P1 | 🔴 Открыт | ...` удалена из
      раздела «Активные» и добавлена в раздел «Закрытые» с записью
      `| BUG-001 | 2026-05-25 (<commit-hash>) | ... | TASK-055: cleanup deprecated
      InspectorPanel.swift + удалены мёртвые ссылки в GameScene; SwiftUI
      InspectorOverlayCard остался единственной плашкой клика. |`.
- [ ] В `concept/Current.md` строка F-11 не меняется (статус остаётся ✅, баг был
      косметическим дубль-рендером — основная функциональность F-11 не страдала).
- [ ] Doc-comment в `Sources/CityDeveloper/UI/InspectorOverlayCard.swift:4`
      («Не путать с SpriteKit-попапом `InspectorPanel`») обновлён или удалён —
      ссылка на удалённый класс не должна остаться. Также `grep -r InspectorPanel
      Sources/` после правок не должен возвращать ни одной строки.

### Что НЕ делаем (границы скоупа)

- НЕ меняем поведение SwiftUI `InspectorOverlayCard` — его layout, тексты,
  таймеры. Только cleanup SpriteKit-части.
- НЕ переименовываем `showInspector` / `hideInspector` методы в `GameScene`
  (несмотря на то что SpriteKit-popup больше нет, API нужен для `SceneBridge` и
  публичного `showInspector(forUnitId:)`).
- НЕ трогаем `bridge?.selectedUnitInfo` логику — она и есть единственный путь
  отображения плашки.
- НЕ объединяем `showInspector(near:)` и `showInspector(forUnitId:)` в один
  метод — это техдолг другого скоупа.
- НЕ добавляем тесты на «появилась одна плашка» — это manual UI smoke; верификация
  через компиляцию и существующие тесты.

### Edge cases

- [ ] `showInspector(forUnitId:)` (строка 1061) — публичный API, вызывается
      извне. После cleanup продолжает работать через `bridge?.selectedUnitInfo`,
      ничего не сломать. Проверить, что вызовы из `SceneBridge` / `ContentView` не
      ожидают наличия SKNode-попапа в сцене.
- [ ] Reset/cleanup сцены (`resetScene`, строка 190 — `inspector = nil`): после
      удаления поля `inspector` строку 190 надо тоже удалить (или адаптировать,
      если там было что-то ещё). Никакой утечки SKNode'ов — их и так не создаётся.
- [ ] Защита `if n === inspector { return }` (строка 978) была единственным
      фильтром «не считать клик по самому SpriteKit-попапу за клик по юниту».
      После удаления её — нужно проверить, что клик по области, где раньше был
      SpriteKit-попап, корректно обрабатывается (теперь там ничего нет — клик
      идёт на юнит/фон под этой областью). Это семантически правильно после
      удаления popup'а. Manual smoke: кликнуть → видеть SwiftUI плашку → кликнуть
      рядом → видеть, что переключилось/скрылось корректно.
- [ ] Если в других местах кода (CitizenManager, SceneBridge, ContentView) есть
      `import` или ссылки на `InspectorPanel` — удалить и их (grep по проекту
      перед удалением файла).

### Зависимости

- **Blocked-by:** —
- **Soft-blocks:** —
- Внешние сервисы: —
- Миграции: —

### Дизайн

Не применимо (cleanup deprecated кода; UI-layer не меняется — `InspectorOverlayCard`
остаётся как есть).

### Done-критерий

_Из Bugs.md BUG-001:_ «Одна плашка — современная SwiftUI overlay. SpriteKit-попап
убрать (legacy от MVP).» — выполнено по факту коммита частичного фикса; задача
закрывает финальный cleanup deprecated кода и формальный перенос BUG в «Закрытые».

_Из Concept.md F-11:_ «Клик на любой юнит открывает попап с текстом задачи, датой
и проектом» — остаётся ✅ через SwiftUI overlay; статус F-11 не меняется.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-25_
_Модель: sonnet (downgrade от P1-триггера; spec-review Opus подтвердил фактическую P2 tech-debt природу)_
_Статус: [x] готов_

### Анализ текущего состояния

- `Sources/CityDeveloper/Game/InspectorPanel.swift` — `enum InspectorPanel` с
  одним статическим методом `build(unit:project:) -> SKNode`. Помечен
  `@available(*, deprecated)`. Файл целиком к удалению.
- `Sources/CityDeveloper/Game/GameScene.swift`:
  - `:34` — `private var inspector: SKNode?` (мёртвое поле, всегда nil после
    закомментированного `inspector = panel`).
  - `:190` — `inspector = nil` в `resetScene` (тоже мёртвое, поле удаляется).
  - `:978` — `if n === inspector { return }` в touch-handler'е (защита от клика
    по самому SpriteKit-попапу, теперь не нужна — popup'а нет).
  - `:982` → `:988` — вызовы `showInspector(near:unit:project:)` и
    `hideInspector()` (остаются — они теперь только обновляют `bridge?.selectedUnitInfo`).
  - `:1028-1039` — тело `showInspector(near:unit:project:)`. Активные строки:
    `hideInspector()` (первая) и `bridge?.selectedUnitInfo = (unit, project)`
    (последняя). Между ними 7 закомментированных строк с `InspectorPanel.build`,
    `panel.position`, `world.addChild(panel)` и т.д. — всё к удалению.
  - `:1041-1046` — тело `hideInspector()`. Активная строка:
    `bridge?.selectedUnitInfo = nil`. Закомментированы 2 строки про
    `inspector?.removeFromParent()` и `inspector = nil`.
  - `:1061-1066` — `showInspector(forUnitId id: UUID)` — публичный API,
    вызывает `showInspector(near:unit:project:)` после lookup'а unit. Не трогаем.
- `Sources/CityDeveloper/UI/InspectorOverlayCard.swift:4` — doc-comment в начале
  файла со ссылкой «Не путать с SpriteKit-попапом `InspectorPanel`». Ссылка на
  удалённый класс — обновить или удалить упоминание.
- Тестов на InspectorPanel в `Tests/CityDeveloperTests/` нет (`grep -r
  InspectorPanel Tests/` → пусто).
- `bridge?.selectedUnitInfo` — единственный канал передачи в SwiftUI. Не трогаем.

### Архитектурное решение

Чисто механический cleanup deprecated кода. Без архитектурных изменений: API
методов `showInspector(near:unit:project:)`, `hideInspector()`,
`showInspector(forUnitId:)` сохраняем (используется в touch-handler и через
`SceneBridge`). Удаляется только всё, что связано с SKNode-инспектором:
сам класс, поле-хранилище, защита от self-click, закомментированные строки.

Последовательность шагов выбрана так, чтобы каждый промежуточный коммит
оставался компилируемым: сначала чистим ссылки в `GameScene.swift` (поле +
комментарии + защита), затем удаляем сам файл `InspectorPanel.swift`, потом
обновляем doc-comment в `InspectorOverlayCard.swift`. Если делать обратном
порядке (сначала `git rm`), промежуточная компиляция упадёт на закомментированной
строке `// let panel = InspectorPanel.build(...)` — точнее не упадёт (она
закомментирована), но порядок «удалить ссылки → удалить файл» концептуально
чище и безопаснее от swift-build кеша.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй,
> возвращай задачу через сообщение.

1. **Удалить поле `inspector: SKNode?` из GameScene** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Строка 34: удалить `private var inspector: SKNode?` целиком (вместе со
     строкой). Соседние поля (например `private var bridge: SceneBridge?`)
     не трогать.
   - Строка 190 (`resetScene` или похожий блок): удалить строку `inspector = nil`
     целиком. Проверь, что окружающий контекст не сломан (это просто
     одиночная строка cleanup'а среди других `... = nil`).

2. **Удалить self-click защиту `if n === inspector`** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Строка 978 (внутри touch-handler'а, в цикле по nodes под точкой клика):
     удалить строку `if n === inspector { return }` целиком.
   - Соседние проверки (если есть другие `if n === ...`) не трогать.

3. **Очистить тело `showInspector(near:unit:project:)` от legacy-кода** `[AC:4]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift:1028-1039`
   - Заменить весь блок:
     ```swift
     func showInspector(near anchor: CGPoint, unit: UnitState, project: ProjectState) {
         hideInspector()
         // BUG-001: SpriteKit InspectorPanel отключён — используем SwiftUI InspectorOverlayCard.
         // let panel = InspectorPanel.build(unit: unit, project: project)
         // let unitNode = unitNodes[unit.id]
         // let anchorWorld = unitNode?.position ?? anchor
         // panel.position = CGPoint(x: anchorWorld.x + 80, y: anchorWorld.y + 40)
         // panel.zPosition = 100000
         // world.addChild(panel)
         // inspector = panel
         bridge?.selectedUnitInfo = (unit, project)
     }
     ```
     на:
     ```swift
     func showInspector(near anchor: CGPoint, unit: UnitState, project: ProjectState) {
         hideInspector()
         bridge?.selectedUnitInfo = (unit, project)
     }
     ```
   - Параметр `anchor: CGPoint` не удалять — он остаётся в сигнатуре для
     совместимости с touch-handler'ом (вызов `showInspector(near: location, ...)`),
     даже если внутри больше не используется. Swift warning'а на unused parameter
     не будет (это позиционный параметр функции, не локальная переменная).

4. **Очистить тело `hideInspector()` от legacy-кода** `[AC:4]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift:1041-1046`
   - Заменить весь блок:
     ```swift
     private func hideInspector() {
         // BUG-001: SpriteKit InspectorPanel отключён; inspector всегда nil.
         // inspector?.removeFromParent()
         // inspector = nil
         bridge?.selectedUnitInfo = nil
     }
     ```
     на:
     ```swift
     private func hideInspector() {
         bridge?.selectedUnitInfo = nil
     }
     ```

5. **Удалить файл InspectorPanel.swift** `[AC:1,2]`
   - Команда: `cd /Users/ilahohlov/CityDeveloper && git rm Sources/CityDeveloper/Game/InspectorPanel.swift`
   - После этого `grep -r InspectorPanel Sources/` должен возвращать только
     ссылку из doc-comment'а в `InspectorOverlayCard.swift:4` (которую правим
     в следующем шаге).

6. **Обновить doc-comment в InspectorOverlayCard.swift** `[AC:8]`
   - Файл: `Sources/CityDeveloper/UI/InspectorOverlayCard.swift`
   - Прочитать строки 1-10 (получить точный текст doc-comment'а).
   - Найти строку с упоминанием «Не путать с SpriteKit-попапом `InspectorPanel`»
     (примерно строка 4) и:
     - либо удалить всю строку про «не путать» (если doc-comment остаётся
       осмысленным без неё);
     - либо заменить на более актуальный комментарий типа «SwiftUI overlay-карточка,
       единственный popup-инспектор после удаления legacy SpriteKit InspectorPanel
       (BUG-001 / TASK-055)».
   - После правки: `grep -r InspectorPanel Sources/` должен вернуть **0 строк**.

7. **Проверка компиляции и тестов** `[AC:5,6]`
   - `cd /Users/ilahohlov/CityDeveloper && swift build -c debug 2>&1 | tail -10`
     — ожидание: `Build complete!`, никаких warning'ов `deprecated`.
   - `cd /Users/ilahohlov/CityDeveloper && swift test 2>&1 | tail -10` —
     ожидание: тесты пройдены, число не меньше текущего baseline (после
     TASK-054 это 166 pass + 1 skip; ни один тест не сломан удалением
     InspectorPanel).
   - `cd /Users/ilahohlov/CityDeveloper && grep -r InspectorPanel Sources/` —
     ожидание: **пустой вывод** (0 совпадений).

8. **Перенести BUG-001 в «Закрытые» в Bugs.md** `[AC:7]`
   - Файл: `concept/Bugs.md`
   - Удалить строку `| BUG-001 | P1 | 🔴 Открыт | F-11 | Две информационные плашки...`
     из раздела «## Активные» (она первая в таблице активных).
   - Добавить в раздел «## Закрытые» **первой строкой** (перед BUG-021,
     BUG-020, BUG-019):
     ```
     | BUG-001 | 2026-05-25 (<commit-hash>) | Две информационные плашки при клике на дом: SpriteKit `InspectorPanel` (world-coords) + SwiftUI `InspectorOverlayCard` (screen-coords) одновременно | TASK-055: финальный cleanup. SpriteKit-popup вызов был закомментирован в GameScene ещё в частичном фиксе; TASK-055 удалил deprecated `InspectorPanel.swift` целиком + поле `inspector: SKNode?` + self-click защиту + закомментированные строки в `showInspector`/`hideInspector` + ссылку в doc-comment `InspectorOverlayCard.swift`. SwiftUI overlay остался единственным каналом. |
     ```
   - `<commit-hash>` заполнится в backfill-коммите после основного.
   - `concept/Current.md` НЕ трогать — F-11 остаётся ✅.

### Edge cases (явно обработать)

- [ ] **Параметр `anchor: CGPoint` в `showInspector` после cleanup не используется
      внутри.** Не удалять (вызов из touch-handler `:982` передаёт `location`).
      Swift не выдаёт warning на unused-параметры функций. Если в будущем будет
      рефактор сигнатуры — отдельная задача.
- [ ] **`showInspector(forUnitId:)` (`:1061`)** — публичный API, вызывается
      из `SceneBridge`. После cleanup продолжает работать через
      `bridge?.selectedUnitInfo` без изменений. Не трогаем.
- [ ] **Импорты `import SpriteKit` в GameScene** — оставить, активно используется
      для других сцен/нод. Только в `InspectorPanel.swift` импорт уходит вместе
      с файлом.
- [ ] **Manual smoke после фикса:** кликнуть по любому юниту в режиме explore →
      одна SwiftUI плашка (`InspectorOverlayCard`). Кликнуть на другой юнит →
      переключение. Клик в пустое поле → плашка скрывается. Не делается через
      automated тесты (нет SwiftUI XCUI инфраструктуры в проекте).
- [ ] **Reset/cleanup сцены** (`resetScene` или похожий блок около `:190`) —
      после удаления `inspector = nil` проверить, что окружающий блок остаётся
      синтаксически корректным (если рядом были другие cleanup-присваивания,
      они не задеты).

### Файлы для изменения

- `Sources/CityDeveloper/Game/GameScene.swift` — удалить поле + self-click
  защиту + cleanup двух методов (~15 строк к удалению).
- `Sources/CityDeveloper/Game/InspectorPanel.swift` — удалить файл целиком
  через `git rm`.
- `Sources/CityDeveloper/UI/InspectorOverlayCard.swift` — обновить/удалить
  doc-comment про «не путать с SpriteKit-попапом».
- `concept/Bugs.md` — перенести BUG-001 из «Активные» в «Закрытые».

### Файлы НЕ трогать

- `Sources/CityDeveloper/UI/InspectorOverlayCard.swift` (тело компонента) —
  только doc-comment в начале файла. Логика overlay-карточки, тексты, layout —
  не задеты.
- `Sources/CityDeveloper/UI/SceneBridge.swift` — `selectedUnitInfo` остаётся
  как есть, не трогаем.
- `Sources/CityDeveloper/UI/ContentView.swift` — overlay-наблюдение работает,
  не трогаем.
- `concept/Current.md` — F-11 остаётся ✅, не меняем.
- `concept/Concept.md` — never auto-edit.

### Команды проверки (для DoD)

- Компиляция: `cd /Users/ilahohlov/CityDeveloper && swift build -c debug 2>&1 | tail -10`
- Тесты: `cd /Users/ilahohlov/CityDeveloper && swift test 2>&1 | tail -10`
- Cleanup-чек: `cd /Users/ilahohlov/CityDeveloper && grep -r InspectorPanel Sources/` (ожидание: пусто)
- Manual smoke: запустить `swift run CommitPyramid`, кликнуть на юнит → одна SwiftUI плашка.

### Сложность

`junior`

**Обоснование:** механическое удаление deprecated кода, 3 файла, шаги атомарные
(удалить строку / заменить блок / `git rm` / правка doc-comment); никаких
архитектурных решений, никаких новых интерфейсов, исполнитель не додумывает.

### Ожидаемое время

S (≤2ч, фактически ~15-30 мин включая smoke).

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] `swift build` и `swift test` проходят
- [ ] Manual smoke: клик по юниту даёт одну плашку (SwiftUI InspectorOverlayCard)

#### Технические
- [ ] Файл `InspectorPanel.swift` удалён через `git rm` (сохранение истории)
- [ ] В `GameScene.swift` нет упоминаний InspectorPanel
- [ ] Поле `private var inspector: SKNode?` удалено
- [ ] Нет warning'ов про deprecated классы

#### Обновление документации
- [ ] `Bugs.md`: BUG-001 → «Закрытые» с TASK-055 в решении
- [ ] `Current.md`: F-11 не меняется (✅ остаётся)
- [ ] `Diff.md`: не затрагивается (D-11 давно закрыт)

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-25
- Spec-review: approved (с 2 minor revisions: явное AC на doc-comment в InspectorOverlayCard + baseline тестов переформулирован; приоритет P1 наследуется от BUG-001, фактически tech-debt P2)
- Готова к работе: 2026-05-25
- Lead-model: sonnet (downgrade от P1-триггера; Opus-trigger overridden — фактически P2 tech-debt cleanup, spec-review Opus подтвердил)
- Lead-trigger: opus (P1, naследовано от BUG-001) → overridden continue-current (junior cleanup, 3 файла)
- Plan-review: approved (Opus, контр-модель к Sonnet-лиду; 0 blocking issues; все 8 AC покрыты 8 шагами с [AC:N] тегами; реальные line numbers verified)
- Исполнитель: haiku
- Code-review: approved (Opus, P1 trigger; 0 issues — удаление чистое, dead code исчез, semantics не задеты)
- Завершена: 2026-05-25
- Коммит: (заполнится после git commit)
