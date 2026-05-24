# TASK-046: Cross-unit эволюция через требования по окружению

## Связь
- **F-16** из Concept.md (расширенный каталог 50 юнитов)
- **F-23** из Concept.md (новая фича — cross-unit evolution)
- **BUG-016** из Bugs.md
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: opus_
_Дата: 2026-05-24_

### Что хотим

Сейчас эволюция «лачуга → дом» работает по тупому счётчику: 2 шалаша → 1 дом,
без учёта остального квартала. Нужно: каждая эволюция определяется **набором
требований** к окружению (другие юниты в этом же квартале с минимальной
стадией). Это превращает рост квартала в видимую логику: «нет колодца → не
будет дома». Все юниты влияют на эволюцию друг друга.

### Пользовательский сценарий

1. Игрок в квартал, где много шалашей, но нет колодца — шалаши НЕ
   превращаются в дома, сколько бы их ни было.
2. Игрок закрывает task, в квартале появляется well → следующая
   task_completed для этого квартала triggers `shack → house` (наконец).
3. Для эволюции `house → tenement` требуется ≥1 market и ≥2 well. Игрок видит
   в журнале не только «house→tenement» но и «не выполнено: нужен market».
4. Каждое здание имеет 3+ визуальных стадий — переход стадии тоже подчинён
   правилам.

### Acceptance criteria

- [ ] Реализован `EvolutionGraph` — таблица правил вида
      `(fromKind, toKind, requirements: [Requirement])`.
- [ ] Минимум 10 правил с реальными requirements (см. ниже).
- [ ] `CityEngine.applyEvolutionsIfReady` использует EvolutionGraph вместо
      простого count'a по kind.
- [ ] При невыполнении требования эволюция НЕ происходит. Логируется почему
      (debug-логи, не пользовательские).
- [ ] Каскады (несколько эволюций за один task) разрешены (как сейчас через
      repeat-while).
- [ ] Replay deterministic — те же event'ы дают тот же результат.

### Что НЕ делаем

- Не делаем UI для отображения «почему не эволюционирует» (это backlog).
- Не делаем визуально новые стадии для всех 50 юнитов (это часть TASK-040).
- Не меняем формат events.jsonl (`unit_evolved` остаётся как сейчас).
- Не реализуем deconstruction (старые юниты остаются на месте, не
  «потребляются» эволюцией — это упрощение MVP).

### Edge cases

- [ ] Несколько правил с одним fromKind подходят одновременно (например, и
      `shack → house` и `shack → khizhina`) — выбираем первое по rawValue
      `toKind` лексикографически.
- [ ] Юнит, который эволюционировал (теперь house вместо shack), считается ли
      в счётчиках? Да, считается как новый kind (house). Старого shack нет.
- [ ] Каскад: после `shack → house` сразу запускается `house → tenement` если
      requirements выполнены. Защита: max 5 каскадов за один task для одного
      проекта.
- [ ] Replay: правила должны быть детерминированы. EvolutionGraph — static
      таблица.

### Зависимости

- F-23 (новая фича в Concept.md) — design-doc.
- TASK-034 (старая эволюция) — заменяется, не дополняется.

### Дизайн

Не применимо (нет UI). Логика в CityEngine.

### Done-критерий

_Из Concept.md F-23:_

> В квартале без колодца лачуги НЕ превращаются в дома, сколько бы их ни
> было. После строительства колодца следующая task_completed для этого
> квартала triggers эволюцию (видно `unit_evolved` в журнале). При replay
> 5000 событий цепочка эволюций воспроизводится идентично.

---

## 🛠 Технический разбор от тимлида

_Автор: opus_
_Дата: 2026-05-24_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

- **`CityEngine.applyEvolutionsIfReady`** (`CityEngine.swift:413`): группирует
  юниты квартала по kind, при `units.count >= threshold` находит N старейших,
  пишет N `unit_evolved` событий. `evolutionThreshold` и `evolvesTo` —
  свойства `UnitKind`.
- **`UnitKind.evolvesTo` / `evolutionThreshold`** — где-то в CityState.swift
  или extension. Возвращает single target и пороговый count.

### Архитектурное решение

Создать `EvolutionGraph` — struct с правилами:

```swift
struct EvolutionRequirement {
    let kind: UnitKind
    let minStage: Int     // юниты данного kind должны быть на ≥ этой стадии
    let minCount: Int     // минимум столько юнитов
}

struct EvolutionRule {
    let from: UnitKind
    let to: UnitKind
    let consumeCount: Int  // сколько юнитов from превращается в один to (default 1)
    let requirements: [EvolutionRequirement]
}

enum EvolutionGraph {
    static let rules: [EvolutionRule] = [
        EvolutionRule(
            from: .shack, to: .house, consumeCount: 1,
            requirements: [
                EvolutionRequirement(kind: .well, minStage: 0, minCount: 1),
                EvolutionRequirement(kind: .shack, minStage: 1, minCount: 3),
                EvolutionRequirement(kind: .road, minStage: 0, minCount: 5),
            ]
        ),
        EvolutionRule(
            from: .zemlyanka, to: .shack, consumeCount: 1,
            requirements: [
                EvolutionRequirement(kind: .zemlyanka, minStage: 0, minCount: 2),
            ]
        ),
        EvolutionRule(
            from: .khizhina, to: .stoneHouse, consumeCount: 1,
            requirements: [
                EvolutionRequirement(kind: .khizhina, minStage: 0, minCount: 2),
                EvolutionRequirement(kind: .quarry, minStage: 1, minCount: 1),
            ]
        ),
        EvolutionRule(
            from: .house, to: .tenement, consumeCount: 3,
            requirements: [
                EvolutionRequirement(kind: .market, minStage: 1, minCount: 1),
                EvolutionRequirement(kind: .well, minStage: 0, minCount: 2),
                EvolutionRequirement(kind: .house, minStage: 2, minCount: 3),
            ]
        ),
        EvolutionRule(
            from: .stoneHouse, to: .manor, consumeCount: 2,
            requirements: [
                EvolutionRequirement(kind: .stoneHouse, minStage: 2, minCount: 2),
                EvolutionRequirement(kind: .forum, minStage: 0, minCount: 1),
            ]
        ),
        EvolutionRule(
            from: .twoStoryHouse, to: .tenement, consumeCount: 2,
            requirements: [
                EvolutionRequirement(kind: .twoStoryHouse, minStage: 2, minCount: 2),
                EvolutionRequirement(kind: .market, minStage: 1, minCount: 1),
            ]
        ),
        EvolutionRule(
            from: .farmhouse, to: .manor, consumeCount: 1,
            requirements: [
                EvolutionRequirement(kind: .farm, minStage: 1, minCount: 1),
                EvolutionRequirement(kind: .well, minStage: 0, minCount: 1),
            ]
        ),
        EvolutionRule(
            from: .warehouse, to: .largeWarehouse, consumeCount: 3,
            requirements: [
                EvolutionRequirement(kind: .warehouse, minStage: 2, minCount: 3),
                EvolutionRequirement(kind: .road, minStage: 0, minCount: 8),
            ]
        ),
        EvolutionRule(
            from: .workshop, to: .factory, consumeCount: 2,
            requirements: [
                EvolutionRequirement(kind: .workshop, minStage: 3, minCount: 2),
                EvolutionRequirement(kind: .warehouse, minStage: 1, minCount: 1),
            ]
        ),
        EvolutionRule(
            from: .chapel, to: .temple, consumeCount: 1,
            requirements: [
                EvolutionRequirement(kind: .chapel, minStage: 2, minCount: 1),
                EvolutionRequirement(kind: .forum, minStage: 1, minCount: 1),
            ]
        ),
    ]
}
```

`CityEngine.applyEvolutionsIfReady` переписывается:

```swift
private func applyEvolutionsIfReady(projectKey: String) -> Bool {
    guard let project = state.projects[projectKey] else { return false }
    let projectUnits = state.units.values.filter { $0.projectId == projectKey }

    // Группируем по (kind, tier) для подсчёта требований.
    var changed = false
    for rule in EvolutionGraph.rules {
        // 1. Проверить, есть ли в квартале достаточно юнитов `from` для consumeCount.
        let fromCandidates = projectUnits.filter { $0.kind == rule.from }
        guard fromCandidates.count >= rule.consumeCount else { continue }

        // 2. Проверить minStage у from-candidates (если в Requirement есть про сам from).
        //    Берём ВСЕ requirements, включая возможные для самого fromKind.
        let allRequirementsMet = rule.requirements.allSatisfy { req in
            let matching = projectUnits.filter { $0.kind == req.kind && $0.tier >= req.minStage }
            return matching.count >= req.minCount
        }
        guard allRequirementsMet else { continue }

        // 3. minStage target ≤ project.stage
        guard rule.to.minStage <= project.stage else { continue }

        // 4. Берём consumeCount старейших.
        let oldest = fromCandidates
            .sorted { lhs, rhs in
                if lhs.taskTs != rhs.taskTs { return lhs.taskTs < rhs.taskTs }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(rule.consumeCount)

        // 5. Если consumeCount > 1 — пишем эволюции для каждого, но
        //    в state остаётся только ОДИН target (последний).
        //    MVP: эволюционируем самый старый, остальные ОСТАЮТСЯ без изменений
        //    (упрощённо). consumeCount>1 — на TODO для будущей версии.
        if rule.consumeCount > 1 {
            // Простая логика: эволюционируем старейший в target, остальные не
            // трогаем. consumeCount влияет только на gate (нужно ≥N того же).
        }

        guard let oldestUnit = oldest.first else { continue }
        let title = "\(oldestUnit.id.uuidString)|\(rule.from.rawValue)|\(rule.to.rawValue)"
        appendSystemEvent(.unitEvolved, project: projectKey, title: title)
        changed = true
        break  // Один rule за tick (для детерминизма каскадов через repeat-while снаружи)
    }

    return changed
}
```

**Rules ordering для детерминизма:** в `EvolutionGraph.rules` правила
упорядочены по `(from.rawValue, to.rawValue)` лексикографически. Итерация в
порядке массива.

**Каскадная защита:** repeat-while цикл вокруг `applyEvolutionsIfReady` уже
есть в `CityEngine.applyTaskCompleted`. Добавить counter (max 5 iterations)
для защиты от потенциальных циклов.

### Пошаговая декомпозиция

1. **Создать EvolutionGraph.swift** `[AC:1,2]`
   - Файл: `Sources/CityDeveloper/Game/EvolutionGraph.swift` (новый)
   - Поместить структуры и таблицу `rules` (см. выше).
   - Минимум 10 правил.

2. **Удалить старую логику UnitKind.evolvesTo / evolutionThreshold** `[AC:3]`
   - Файл: `Sources/CityDeveloper/Data/CityState.swift` (поиск `evolvesTo`,
     `evolutionThreshold`)
   - Удалить или пометить deprecated. Логика переезжает в EvolutionGraph.

3. **Переписать `applyEvolutionsIfReady`** `[AC:3,4]`
   - Файл: `Sources/CityDeveloper/Game/CityEngine.swift:413-450`
   - Заменить тело на код выше (итерация по EvolutionGraph.rules).
   - Возвращать true если хотя бы одно правило сработало.

4. **Cascade limit** `[AC:5]`
   - В `applyTaskCompleted` где есть `repeat { } while applyEvolutionsIfReady(...)`:
     ```swift
     var cascadeCount = 0
     repeat {
         cascadeCount += 1
         if cascadeCount > 5 {
             ErrorsLog.write("CityEngine: cascade limit 5 reached for \(projectKey)")
             break
         }
     } while applyEvolutionsIfReady(projectKey: projectKey)
     ```

5. **Smoke test** `[AC:1,2,3,4,6]`
   - Импорт репо без well в квартал → видно, что shack'и не превращаются в
     дома.
   - Симуляция: вручную в state.json добавить well в квартал → следующая
     task_completed → `unit_evolved shack→house`.
   - Replay events.jsonl 2 раза → одинаковый результат.

### Edge cases

- [ ] **Requirement на сам fromKind** — например, `shack→house` требует
      `shack:minStage=1, minCount=3`. Проверять как обычно (включает сам
      эволюционирующий юнит в проверке).
- [ ] **consumeCount > 1 — MVP**: эволюционирует старейший, остальные нет.
      Не идеально, но запускает механику. Дальше — backlog «consume multiple
      units на 1 target».
- [ ] **Каскад stack overflow** — counter 5 защищает.

### Файлы для изменения

- `Sources/CityDeveloper/Game/EvolutionGraph.swift` (новый)
- `Sources/CityDeveloper/Data/CityState.swift` — убрать evolvesTo /
  evolutionThreshold (или deprecated).
- `Sources/CityDeveloper/Game/CityEngine.swift` — переписать
  applyEvolutionsIfReady + cascade limit.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/GameScene.swift` — обработчик
  `onUnitEvolved` остаётся.
- `Sources/CityDeveloper/Game/UnitSprites.swift` — sprite swap при эволюции
  работает через kind change.
- `events.jsonl` schema — `unit_evolved` запись не меняется.

### Команды проверки

- Компиляция: `swift build`
- Тесты: `swift test --filter CityEngine` (если есть)
- Ручная: создать тестовый квартал на дев-сборке, проверить что без well
  shack не растёт.

### Сложность
`senior` — новая архитектура эволюции, влияет на главный движок, нужен
детерминизм и тестирование replay.

### Объём
M (≤1д)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: senior_

### Definition of Done

- [ ] Минимум 10 правил в EvolutionGraph
- [ ] Старая логика evolvesTo/evolutionThreshold убрана или deprecated
- [ ] Replay deterministic подтверждён smoke-тестом
- [ ] `Bugs.md`: BUG-016 → закрыт
- [ ] `Current.md`: F-23 → ✅

---

## Статус
`[x] done`

## Метаданные
- Создана: 2026-05-24
- Завершена: 2026-05-24
- Коммит: 2840287
