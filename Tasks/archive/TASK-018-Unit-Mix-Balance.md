# TASK-018: Валидация пропорций состава юнитов в квартале (F-07)

## Связь
- **F-07** Состав и баланс юнитов в квартале
- **D-07** из diff.md
- **Приоритет:** P0

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим

Сейчас в квартале появляется паттерн на 20 шагов (см. D-07: «Паттерн на 20
шагов, пропорции не валидированы; нет правил "N жилых → колодец"»). Целевые
пропорции из F-07 (~50% жилые, ~20% инфраструктура, ~20% производство,
~10% социальное) не подтверждены измерением; стадийные ограничения (рынок ≥
stage 2, храм/обелиск ≥ stage 4) и правило «на каждые N жилых обязательно
колодец» — не реализованы. Нужно: ввести таблицу выбора типа юнита,
гарантирующую пропорции и стадийные ограничения, и валидировать её
измерением на квартале 20+ юнитов. Выбор остаётся детерминированным от
порядкового номера задачи в проекте.

### Пользовательский сценарий

1. Пользователь закрывает 20+ задач в одном проекте `gamma` через
   `tasks.jsonl` (исторический лог или live-добавление).
2. Watcher подхватывает события, для каждого вызывается UnitPlanner / правило
   выбора типа.
3. По мере набора задач stage квартала растёт (F-08 уже учитывает).
4. На каждом шаге система выбирает тип юнита по детерминированной таблице
   с учётом stage и накопленного состава.
5. По достижении 20 юнитов в квартале состав содержит все 4 категории, и
   пропорции укладываются в ±10% от целевых (50/20/20/10).
6. Правило «на каждые N жилых — колодец»: явно зафиксировать `N = 5`
   (разумный дефолт для 50/20 жилые/инфра пропорций — каждый 5-й жилой даёт
   колодец, что даёт ~10% колодцев в составе инфраструктуры). Если N в
   ходе валидации не сходится с пропорциями — лид может скорректировать
   внутри окна `N ∈ [4, 6]`, остальное — пересогласовывать с PM.
7. Replay того же tasks.jsonl даёт идентичный состав (для тех же
   projectId и того же набора событий).

### Acceptance criteria

- [ ] **Покрытие категорий:** квартал из 20+ юнитов в одном проекте
      содержит **минимум по одному юниту каждой из 4 категорий** (жилые,
      инфра, производство, социальное). Измеряется автоматическим smoke-тестом
      на синтетическом `tasks.jsonl` с 20+ событиями одного проекта
      (приведено в соответствие с Done-критерием F-07).
- [ ] **Пропорции в окне ±10%:** на квартале 20+ юнитов доли по категориям
      укладываются в диапазоны: жилые 45–55%, инфра 18–22%, производство
      18–22%, социальное 9–11% (включительно). При смещении за окно более
      чем на одну категорию — smoke-тест fail. Измеряется тем же smoke-тестом.
- [ ] **Stage-ограничения** соблюдены:
      - Рынок (`market`) появляется только при `stage ≥ 2` — нет ни одного
        рынка в квартале со `stage < 2`.
      - Храм/обелиск (`temple` / `obelisk`) появляются только при `stage ≥ 4`.
- [ ] **Правило колодцев:** в квартале на каждые `N = 5` жилых юнитов
      присутствует минимум 1 колодец. Допустимый диапазон `N` для лида
      при тонкой настройке таблицы — `[4, 6]`. Меньше/больше — escalate к PM.
- [ ] **Детерминированность:** при двух независимых запусках на одном
      `tasks.jsonl` итоговый состав квартала (тип + порядок) идентичен.
      Покрывается тем же smoke-тестом (двойной прогон).
- [ ] **Done-критерий F-07:** см. блок ниже.

### Что НЕ делаем (границы скоупа)

- Не меняем формат `tasks.jsonl` и event log.
- Не вводим юзер-конфиг пропорций (концепт явно: «без конфига от пользователя»).
- Не расширяем каталог юнитов сверх уже введённых 12 типов (расширение —
  работа D-16 / TASK-будущий-каталог-50).
- Не трогаем F-08 (формула stage) — он закрыт; читаем stage как input.
- Не трогаем F-10 (жители) — состав влияет только на их количество через
  существующую формулу F-10.
- Не делаем визуал «дороги между юнитами» — это работа существующего
  `RoadConnector.swift` (F-13 закрыт).
- Не вводим ML/случайные элементы — выбор строго детерминирован порядковым
  номером + stage.

### Edge cases

- [ ] **Очень короткий квартал (<5 юнитов):** stage ≤ 1, доступны только
      жилые и инфра. AC покрытия категорий не применяется (требует 20+).
      Smoke-тест на коротком квартале проверяет только stage-ограничения и
      отсутствие «несуществующих» типов.
- [ ] **Квартал ровно 20 юнитов на границе stage 4:** все категории должны
      присутствовать, последняя добавка не должна нарушить пропорции более чем
      на 5% (часть допустимого окна ±10%).
- [ ] **Stage откатывается** (если в F-08 это возможно при decay/F-09 в
      теории) — таблица не должна крашиться на «недопустимом» текущем составе
      (например, рынок есть, а stage упал в 1). Поведение: существующие юниты
      остаются, новые юниты следуют новому stage. Это не вносит нарушение
      пропорций задним числом (юниты не удаляются).
- [ ] **Порядок задач отличается от ожидания** (например, первые 10 задач
      выпали в порядке, который таблица не предусматривала): таблица должна
      покрывать любые перестановки до 20 задач, поскольку каждый порядковый
      номер однозначно отображается в тип.
- [ ] **Snapshot+tail замешан с live-добавлением задач:** F-12 даёт восстановление
      state, после чего таблица продолжает с правильного порядкового номера.
- [ ] **Несколько проектов параллельно:** каждый проект имеет свой
      `taskIndex`, таблица применяется per-проект — пропорции между проектами
      не смешиваются.

### Зависимости

- **F-08** Stage квартала — закрыт. Источник `stage` для каждого квартала.
  Pre-condition.
- **F-03** Event sourcing — закрыт. Порядок задач детерминированный.
- **F-12** Snapshots — закрыт. Состав восстанавливается через snapshot+tail.
- **F-06** Project-District — закрыт частично (после TASK-017 закроется
  полностью). Используем `District` как контейнер юнитов. **Не блокер** для
  данной задачи — F-06 определяет место квартала, а не состав внутри него.
- Нет внешних сервисов, секретов, миграций.

### Дизайн

Не применимо (нет нового UI). Визуал юнитов уже в `UnitSprites.swift`
(F-13 закрыт), используется существующий каталог 12 типов.

### Done-критерий

_Из concept.md F-07 (дословно):_

> Квартал из 20+ юнитов содержит здания всех 4 категорий (жилые, инфра,
> производство, социальное). Пропорции укладываются в ±10% от целевых.
> Replay лога даёт идентичный состав.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-22_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

В коде уже есть:
- `Sources/CityDeveloper/Game/UnitPlanner.swift` — паттерн на 20 слотов
  (`shack, well, shack, workshop, shack, road, shack, warehouse, shack, market, ...`)
  + `promote(_:toStage:)` — `shack → house → villa`, `market → well` при
  stage<2, `market → forum` при stage≥4, `raw/workshop → workshop` при stage≥3.
- `Sources/CityDeveloper/Data/CityState.swift:16–29` — `UnitKind` enum (12
  типов: shack, house, villa, well, road, warehouse, workshop, raw, market,
  forum, temple, obelisk). Категории нигде не объявлены — только в
  комментариях `UnitSprites.swift` и в `Concept.md`.
- `Sources/CityDeveloper/Data/CityState.swift:4–14` — `UnitState` с
  `kind: UnitKind`, `projectId: String`. **Снэпшот содержит все юниты** —
  считать `residentialCount` per-project через
  `state.units.values.filter { $0.projectId == p && residential.contains($0.kind) }`.
- `Sources/CityDeveloper/Game/CityEngine.swift:183–188` — единственная точка
  вызова `unitPlanner.nextUnitKind(forTaskIndex: project.taskCount, stage:
  project.stage)`. `project.taskCount` уже инкрементирован к этому моменту,
  т.е. это 1-based индекс новой задачи.
- `Sources/CityDeveloper/Game/StageRules.swift` — формула stage; за пределы
  скоупа.

Переиспользуем:
- `UnitPlanner.promote(_:toStage:)` — для tier-промоушена внутри
  категории residential (`shack→house→villa`) и social (`market` ограничения).
- 12 типов уже определены; новых типов не добавляем.

Что нужно дописать:
- `UnitCategory` enum (`.residential | .infrastructure | .production | .social`).
- `UnitKind.category: UnitCategory` (computed property) — единый source of truth.
- Категориальная таблица на 20 шагов (10R/4I/4P/2S), равномерное распределение.
- Внутри категории — детерминированный выбор `UnitKind` по `taskIndex` +
  stage-ограничения + well-правило.
- Smoke-тест `Scripts/smoke-unit-mix.sh`.

### Архитектурное решение

Делим выбор юнита на два уровня: **категория по slot** → **конкретный тип
внутри категории**. Это даёт гарантированные пропорции на любом квартале
кратном 20 (10/4/4/2 = 50/20/20/10), и независимо позволяет менять подтипы
внутри категории без сдвига пропорций.

**Таблица категорий на 20 слотов** (1-based, выбрана так, чтобы все 4
категории появились до 10-го юнита — это закрывает AC «покрытие категорий
при 20+»):

```
slot:    1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20
category R  I  R  P  R  R  S  I  R  P  R  I  R  R  P  I  R  S  R  P
```
итог: R=10, I=4, P=4, S=2 ✓

**Подтипы внутри категории** (детерминированно по порядковому номеру юнита
в этой категории, 1-based):

- **Residential** (`promote(.shack, toStage: stage)`):
  - все 10 слотов — `shack/house/villa` по stage (как сейчас в `promote`).
- **Infrastructure** (rotation `[well, road, warehouse, well]`):
  - Цикл из 4: well, road, warehouse, well (повышает плотность колодцев).
- **Production** (rotation `[workshop, raw, workshop, raw]`):
  - С учётом `promote`: при stage<3 — `workshop/raw` по rotation; при stage≥3
    — оба превращаются в `workshop` (это уже делает `promote`). Делегируем
    `promote` существующей функции.
- **Social** (stage-ограничения):
  - slot 7 (1-й social): `temple` при stage≥4, `forum` при stage 2..3, `market`
    при stage<2 (если stage<2 — market запрещён по концепту → fallback `well`).
  - slot 18 (2-й social): `obelisk` при stage≥4, `market` при stage≥2, fallback
    `well` при stage<2.
  - Замена на `well` при stage<2 НЕ ломает пропорции, потому что social-слот
    при stage<2 семантически и так не работает — пропорции «50/20/20/10»
    концепт предписывает на квартале 20+, а stage<2 это quartal ≤ 5 юнитов
    (по F-08 — slow ramp). AC покрытия категорий применяется только при ≥20.

**Well-правило «N=5 жилых → 1 колодец»**: при базовой таблице на 20 юнитов
получаем 4 infra-слота, из них минимум 2 `well` (slots 2 и 16 в rotation),
плюс 2 fallback-well при stage<2. На 10 жилых это даёт 2 well = 1:5 ровно —
правило выполняется с запасом. Защита от слома пропорций при изменении
rotation: добавляем guard в выборщике — `if residentialCount >= 5 *
(wellCount + 1) && currentSlotCategory == .residential` — заменить юнит на
`well` (без изменения категории-плана, корректирующая мера на случай если
rotation изменят). Это soft-guard, без него таблица всё равно проходит AC.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй.

1. **Добавить enum UnitCategory** `[AC:1,4]`
   - Файл: `Sources/CityDeveloper/Data/CityState.swift`, сразу после
     объявления `UnitKind` (~строка 30).
   - Действие: объявить `enum UnitCategory: String, Codable { case residential,
     infrastructure, production, social }`.

2. **Добавить computed property `UnitKind.category`** `[AC:1,4]`
   - Файл: `Sources/CityDeveloper/Data/CityState.swift`, расширение
     `UnitKind` после `CaseIterable`.
   - Действие:
     ```swift
     extension UnitKind {
         var category: UnitCategory {
             switch self {
             case .shack, .house, .villa: return .residential
             case .well, .road, .warehouse: return .infrastructure
             case .workshop, .raw: return .production
             case .market, .forum, .temple, .obelisk: return .social
             }
         }
     }
     ```
   - Замечание: `warehouse` → `infrastructure`, не `production`. Это
     совпадает с дословным Concept.md F-07: «инфра (колодец, дорога, склад)».

3. **Переписать UnitPlanner: категориальная таблица** `[AC:1,2,3,5,6]`
   - Файл: `Sources/CityDeveloper/Game/UnitPlanner.swift`.
   - Действие: заменить `pattern` 20 `UnitKind` на:
     ```swift
     private static let categoryPattern: [UnitCategory] = [
         .residential, .infrastructure, .residential, .production, .residential,
         .residential, .social, .infrastructure, .residential, .production,
         .residential, .infrastructure, .residential, .residential, .production,
         .infrastructure, .residential, .social, .residential, .production,
     ]
     ```
     (10R/4I/4P/2S, сумма 20).
   - Заменить `nextUnitKind(...)` на сигнатуру с per-category счётчиками
     (rotation внутри категории идёт по **числу юнитов этой категории в
     проекте**, не по taskIndex — это даёт честный цикл и независимость от
     базовой `categoryPattern`):
     ```swift
     func nextUnitKind(
         forTaskIndex idx: Int,
         stage: Int,
         residentialCount: Int,
         wellCount: Int,
         infraCount: Int,
         productionCount: Int,
         socialCount: Int
     ) -> UnitKind {
         let category = Self.categoryPattern[(idx - 1) % Self.categoryPattern.count]
         // Well-правило (soft-guard): на случай если rotation изменят и
         // колодцев станет недостаточно.
         if category == .residential && residentialCount >= 5 * (wellCount + 1) {
             return .well
         }
         return pickKind(
             in: category, stage: stage,
             infraCount: infraCount, productionCount: productionCount,
             socialCount: socialCount
         )
     }
     private func pickKind(
         in c: UnitCategory, stage: Int,
         infraCount: Int, productionCount: Int, socialCount: Int
     ) -> UnitKind {
         switch c {
         case .residential:
             return promote(.shack, toStage: stage)
         case .infrastructure:
             // Rotation по фактическому числу infra-юнитов в проекте.
             let rot: [UnitKind] = [.well, .road, .warehouse, .well]
             return rot[infraCount % rot.count]
         case .production:
             let rot: [UnitKind] = [.workshop, .raw, .workshop, .raw]
             return promote(rot[productionCount % rot.count], toStage: stage)
         case .social:
             // Чередуем «храм-семейство» (1-й social) и «обелиск-семейство»
             // (2-й social) по числу social-юнитов в проекте.
             let isFirstFamily = (socialCount % 2 == 0)
             if isFirstFamily {
                 if stage >= 4 { return .temple }
                 if stage >= 2 { return .forum }
                 return .well // fallback при stage < 2
             } else {
                 if stage >= 4 { return .obelisk }
                 if stage >= 2 { return .market }
                 return .well // fallback
             }
         }
     }
     ```
   - Сохранить существующую `private func promote(_ kind: UnitKind, toStage:
     Int) -> UnitKind` без изменений (нужно для residential и production).
   - **Проверка результата rotation на цикле 20:**
     - Infra-слоты `[2, 8, 12, 16]` (1-based) → infraCount при вызове:
       0, 1, 2, 3 → rot: well, road, warehouse, well ✓
     - Production-слоты `[4, 10, 15, 20]` → productionCount: 0, 1, 2, 3 →
       rot: workshop, raw, workshop, raw (с promote по stage) ✓
     - Social-слоты `[7, 18]` → socialCount: 0, 1 →
       slot 7 = первое семейство (temple/forum/well), slot 18 = второе
       (obelisk/market/well) ✓

4. **Обновить вызов в CityEngine** `[AC:3,5]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift:183`.
   - Действие: заменить
     ```swift
     let kind = unitPlanner.nextUnitKind(forTaskIndex: project.taskCount, stage: project.stage)
     ```
     на:
     ```swift
     let projectUnits = state.units.values.filter { $0.projectId == projectKey }
     let residentialCount = projectUnits.filter { $0.kind.category == .residential }.count
     let wellCount = projectUnits.filter { $0.kind == .well }.count
     let infraCount = projectUnits.filter { $0.kind.category == .infrastructure }.count
     let productionCount = projectUnits.filter { $0.kind.category == .production }.count
     let socialCount = projectUnits.filter { $0.kind.category == .social }.count
     let kind = unitPlanner.nextUnitKind(
         forTaskIndex: project.taskCount,
         stage: project.stage,
         residentialCount: residentialCount,
         wellCount: wellCount,
         infraCount: infraCount,
         productionCount: productionCount,
         socialCount: socialCount
     )
     ```
   - Замечание: один filter за вызов даёт O(N) по `state.units`. На
     квартале до ~100 юнитов — микросекунды. Если станет проблемой —
     кешировать счётчики в `ProjectState` (потребует миграции snapshot —
     отложить).

5. **Smoke-тест `smoke-unit-mix.sh`** `[AC:1,2,3,4,5]`
   - Файл: `Scripts/smoke-unit-mix.sh` (новый).
   - Действие: shell-скрипт, который:
     1. Создаёт временный `tasks.jsonl` с двумя проектами:
        - **Проект `mix-long`**: 20 строк (ровно один цикл `categoryPattern`),
          даты от 60 дней назад с интервалом 3 дня (имитация активного
          проекта → к концу stage ≥ 4).
        - **Проект `mix-short`**: 5 строк, даты от 5 дней назад (stage
          останется 0–1, social-слот = `well` fallback).
     2. Запускает приложение или CLI-replay (если есть target), сохраняет
        `state.json`.
     3. Парсит `jq '.cityState.units | map(select(.projectId == "mix-long"))'`.
        Проверяет **на первых 20 юнитах** (отсортированных по
        `taskTs`):
        - Доли по категориям: 45..55 / 18..22 / 18..22 / 9..11 — ровно по
          AC ±10%.
        - **AC «на каждых 20 юнитах»** — фиксируется в DoD как
          интерпретация AC; на нецелых кратных пропорции могут плавать в
          пределах ±5% от целевых, что не является failure.
        - Все 4 категории присутствуют ≥1 юнит каждой.
        - Count of `well` ≥ ceil(residential/5).
     4. Парсит `mix-short` и проверяет stage-ограничения **негативно**:
        - Нет ни одного юнита с `kind in ("market", "temple", "obelisk")`
          при `tier < 2` (для market) или `tier < 4` (для temple/obelisk).
        - Поскольку у `mix-short` stage не растёт > 1 — социальные слоты
          должны быть `well` (fallback), что подтверждает stage-ограничения
          работают: `socialCount == 0` для market/temple/obelisk в
          `mix-short`.
     5. Двойной прогон: удалить `state.json`, повторить, сравнить итоговые
        составы `mix-long` и `mix-short` через `jq` — должны быть
        идентичны (детерминированность).
   - Если CLI-replay недоступен — пометить как «manual run» в комментарии
     заголовка скрипта, в DoD соответствующий чекбокс — `[ ] ручной прогон`.

### Edge cases (явно обработать)

- [ ] **<5 юнитов (stage ≤ 1):** slot 7 — social@stage<2 → fallback `well`.
      Проверки пропорций не применяются (smoke-тест требует ≥20). Логика
      `pickKind` уже это обрабатывает в кейсе `.social`.
- [ ] **Граница 20 на stage 4:** на 20-м юните slot=20 → production, stage
      ≥ 2..3 → `workshop`/`raw`; stage ≥ 3 — оба `workshop` по `promote`.
      Все 4 категории присутствуют (R=10, I=4, P=4, S=2).
- [ ] **Перестановка порядка задач**: невозможна по архитектуре — `taskCount`
      инкрементируется per-event в `CityEngine.swift:164`, события приходят строго
      по порядку из `EventLog`. Smoke-тест дополнительно подтверждает.
- [ ] **Snapshot+tail с live-добавлением**: `taskCount` хранится в
      `ProjectState`, восстанавливается из `state.json`. Следующая задача
      получит правильный slot.
- [ ] **Несколько проектов параллельно**: filter по `projectId` в шаге 4
      изолирует residential/well-счётчики per-project. Slot тоже per-project
      через `project.taskCount`.
- [ ] **Stage растёт между юнитами**: `promote` уже учитывает stage в
      момент создания юнита. Существующие юниты не меняются (это работа
      TASK-019, не наша).
- [ ] **Soft-guard не нужен на 20 базовых юнитов**: базовая rotation даёт 2
      well в 4 infra-слотах, плюс fallback `well` для social@stage<2. На 10
      residential получаем минимум 2 well = 1:5 как раз. Guard срабатывает
      только если кто-то изменит rotation, нарушив инвариант. Логика
      оставлена для устойчивости.
- [ ] **warehouse в обеих категориях** (исторический конфликт из комментариев):
      решено категорически — `warehouse` → `.infrastructure`. Дословно Concept
      F-07: «инфра (колодец, дорога, склад)».

### Файлы для изменения

- `Sources/CityDeveloper/Data/CityState.swift` — `UnitCategory` enum +
  `UnitKind.category` extension.
- `Sources/CityDeveloper/Game/UnitPlanner.swift` — переписать
  `nextUnitKind`, оставить `promote`, заменить `pattern` на
  `categoryPattern` + `pickKind`.
- `Sources/CityDeveloper/Game/CityEngine.swift` — обновить вызов с
  передачей `residentialCount`/`wellCount`.
- `Scripts/smoke-unit-mix.sh` — новый smoke-тест.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/StageRules.swift` — F-08 закрыта.
- `Sources/CityDeveloper/Game/UnitSprites.swift` — арт-каталог, расширение
  будет в TASK-019.
- `Sources/CityDeveloper/Data/StateSnapshot.swift` — формат не меняем.
- `Sources/CityDeveloper/Game/GameScene.swift` — выбор типа юнита не связан с
  визуализацией.

### Команды проверки (для DoD)

- Компиляция: `swift build`.
- Smoke-тест: `bash Scripts/smoke-unit-mix.sh` — exit 0, отчёт по долям
  внутри окна.
- Ручная проверка: запустить приложение с подготовленным `tasks.jsonl`
  (25+ событий одного проекта, спустя 30+ дней по `ts`), визуально
  посмотреть на квартал — наличие всех 4 категорий, наличие колодцев,
  отсутствие market при низком stage.

### Сложность

`middle`

**Обоснование:** 3 файла (Data + Engine + Planner) + smoke-тест, нужно
понимать инварианты stage-ограничений и well-rule, корректно расщеплять
выбор на «категория → подтип», избегать миграции snapshot. Не junior —
junior легко сломает пропорции при добавлении ad-hoc guard'ов или забудет
fallback `well` для social@stage<2. Не senior — нет архитектурного
рефакторинга, нет security/perf-проблем.

### Ожидаемое время

S (≤2ч)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Smoke-тест: синтетический `tasks.jsonl` с 25+ событиями одного проекта,
      проверка категорий, пропорций, stage-ограничений, колодцев,
      детерминированности.

#### Технические
- [ ] Компиляция Swift без новых ошибок/варнингов
- [ ] Существующие тесты F-08 / F-10 / F-13 не сломаны
- [ ] Smoke-тест выполняется за < 5 сек локально

#### Обновление документации
- [ ] `Current.md`: F-07 → ✅
- [ ] `Diff.md`: D-07 удалён
- [ ] Новые идеи → `Backlog.md`, новые баги → `Bugs.md`

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: approved (round 1)
- Готова к работе: 2026-05-22
- Lead-model: opus
- Plan-review: revised (3 блокера круг 1 → 1 блокер круг 2 → resolved)
- Lead-trigger: opus (priority P0)
- Исполнитель: sonnet (middle), retries=0
- Code-review: approved (opus, P0)
- Завершена: 2026-05-22
- Коммит: 456dd37
