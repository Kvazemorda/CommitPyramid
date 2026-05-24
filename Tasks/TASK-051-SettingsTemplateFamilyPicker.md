# TASK-051: Settings UI — выбор «Стиль города» (templateFamily Picker)

## Связь
- **F-25** из Concept.md (шаблоны кварталов)
- **F-14** из Concept.md (Settings UI)
- **D-25** из Diff.md (часть 5/5 — настройка стиля)
- **Приоритет:** P2

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-24_

### Что хотим

Пользователь должен иметь возможность **выбирать стиль города** в
Settings — egyptian / roman / greek / mixed / auto. Без программирования
и без редактирования файлов. Эта настройка применяется к **новым
проектам** (существующие кварталы не перерисовываются, иначе сломаем
replay).

Это последняя часть F-25 — пользовательский control над шаблонами.

### Пользовательский сценарий

1. Пользователь открывает Settings (⌘,) → новая секция «Стиль города».
2. Видит Picker с 5 опциями:
   - `Auto` (по биому) — default.
   - `Egyptian` (Pharaoh-style).
   - `Roman` (castrum/insula). [только когда добавлена Roman family — TASK
     по backlog]
   - `Greek` (Hippodamian/polis). [только когда добавлена Greek family]
   - `Mixed` (рандом на каждый проект).
3. Tooltip объясняет: «Влияет только на новые проекты. Существующие
   кварталы сохраняют свой стиль».
4. Пользователь выбирает «Mixed» → следующий новый проект получает
   случайно выбранную family (детерминированно по projectId hash).
5. Чекбокс ниже: «Показывать silhouette шаблона при создании квартала
   (debug)» — по умолчанию off.

### Acceptance criteria

- [ ] `AppSettings.templateFamily: String` (default `"auto"`) — добавляется
      в AppSettings, persistence v4 (UserDefaults). Backwards-compat:
      старые версии без поля → "auto".
- [ ] `AppSettings.previewTemplateSilhouette: Bool` (default false) — debug
      toggle.
- [ ] Новая Section в `SettingsView`: `TemplateFamilySection`. Содержит:
      - `Picker("Стиль города", selection: $settings.templateFamily)` с
        опциями только из families, реально присутствующих в
        `DistrictTemplateCatalog.availableFamilies()` (`auto` и `mixed`
        всегда есть).
      - `Toggle("Превью шаблона при создании квартала",
        isOn: $settings.previewTemplateSilhouette)`.
      - Text с tooltip explanation.
- [ ] `DistrictTemplatePicker` обновлён: family `"mixed"` → выбирает
      случайную family через `SplitMix64(seed: fnv1a([projectId,
      "mixed-family"]))`, family `"auto"` → biome-based mapping
      (meadow/desert → egyptian; mountain/stone → roman; sea/river →
      greek; fallback → egyptian).
- [ ] Изменение `templateFamily` в Settings **НЕ** triggers перерисовку
      существующих кварталов. Только новые проекты после смены получают
      новую family.
- [ ] Если выбранная family отсутствует в catalog (например, выбран
      Roman до того, как Roman добавлена) → fallback на "auto" с
      warning'ом в errors.log при создании нового проекта.
- [ ] Если включён `previewTemplateSilhouette` → при создании нового
      квартала GameScene на 3 секунды рисует полупрозрачный (alpha 0.3)
      контур всех слотов шаблона; через 3 сек fade-out.
- [ ] Тест `AppSettingsTemplateFamilyTests.swift`:
      `testDefaultIsAuto`,
      `testPersistenceRoundtrip`,
      `testInvalidFamilyFallsBackToAuto`.
- [ ] Тест `SettingsViewSnapshotTests.swift` (если есть инфраструктура для
      SwiftUI snapshot — иначе manual visual check) — секция отрисовывается
      без overflow в текущей ширине окна (BUG-003 регресс).

### Что НЕ делаем (границы скоупа)

- НЕ добавляем «перерисовать все существующие кварталы» — это нарушит
  replay-детерминизм.
- НЕ добавляем семьи Roman/Greek сами — их добавление = отдельная TASK
  в backlog (template-content task, не logic).
- НЕ позволяем пользователю редактировать сами шаблоны через UI — это
  работа разработчика/контрибьютора через JSON-файлы.

### Edge cases

- [ ] Catalog содержит только egyptian → Picker показывает 3 опции:
      Auto / Egyptian / Mixed. Roman/Greek не видны.
- [ ] Mixed + только 1 доступная family → mixed эквивалентен этой
      family (нечего рандомизировать).
- [ ] Settings persistence v3 → v4 миграция: при первом запуске после
      релиза добавляется templateFamily="auto" в существующий
      UserDefaults без потери других настроек.
- [ ] Auto + nil biome (новая карта до biome init) → fallback "egyptian".
- [ ] Окно Settings слишком узкое (BUG-003 регресс) → новая секция
      обёрнута в ScrollView вместе с остальными (BUG-007 регресс).

### Зависимости

- **Blocked-by:** TASK-047 (catalog), TASK-048 (Picker uses
  templateFamily).
- **Soft-blocks:** —

### Дизайн

`SettingsView` уже существует (см. `Sources/CityDeveloper/UI/SettingsView.swift`).
Новая секция вставляется по аналогии с `GitWatcherSection` /
`NotesWatcherSection`. Picker SwiftUI стандартный (segmented или menu —
на усмотрение исполнителя, главное чтобы текст не обрезался при
default width).

### Done-критерий

_Часть F-25 Done-критерия:_ «Переключение templateFamily в Settings
влияет только на следующие новые проекты». Эта TASK закрывает это
полностью.

**Закрывает D-25 целиком** (последняя из 5 задач F-25).

---

## 🛠 Технический разбор от тимлида

_Статус: [ ] нужен разбор_

> Заполняется командой `/lead 051`.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)
_Объём: S_

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Smoke: открыть Settings (⌘,) → видна секция «Стиль города». Выбрать
      Mixed → закрыть Settings → создать новый проект через add-task.sh →
      проверить project.templateFamily ≠ дефолтному.

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны
- [ ] AppSettings persistence v3 → v4 backwards-compat
- [ ] Окно Settings помещается в default size (regression BUG-003/BUG-007)

#### Обновление документации
- [ ] `Current.md`: F-25 → ✅ (после этой задачи все 5 частей готовы)
- [ ] `Diff.md`: D-25 → удалить (закрыто)
- [ ] `concept/Concept.md`: проверить, что F-25 Done-критерий полностью
      покрыт (если part про Roman/Greek family остаётся открытым —
      пометить F-25 как ⚠️ с уточнением «egyptian-only first iteration»).

---

## Статус

`[x] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[ ] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-24
- Spec-review: approved
- Blocked-by: TASK-047, TASK-048
- Готова к работе: —
- Завершена: —
- Коммит: —
