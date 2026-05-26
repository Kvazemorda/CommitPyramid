# TASK-062: DistrictPlanner water-skip — ErrorsLog warning + регресс-щит

## Связь
- **F-06** из Concept.md (Project-District и автоматическое размещение)
- **F-15** из Concept.md (Биомы и генерация карты)
- **BUG-009** из Bugs.md
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-26_

### Что хотим

Water-skip в `DistrictPlanner` **уже частично реализован** через TASK-030c
+ TASK-056 (см. `DistrictPlanner.swift:40-118, 180-183` — `// MARK: - BUG-009`).
Порядок water → cross-project → preferred соблюдён, существуют тесты
`DistrictPlannerBiomeAwareTests.test_EmptyPreferredBiomesSkipsWater` и
`test_WaterTileInPreferredBiomesIsSkipped`.

Что не закрыто:
1. Defensive fallback при исчерпании спирали (например, полностью водная
   карта) возвращает `(origin, idx)` без warning — пользователь / разработчик
   не знает, что произошло fallback. Нужен `ErrorsLog.write` warning.
2. Тестов регресс-щита для AC «100% водной карты» нет — если будущая
   правка снимет water-skip, это не отловится.
3. BUG-009 не закрыт в bugs.md, хотя фикс уже работает.

Скоуп — узкий delta: warning + регресс-тест + закрытие BUG-009.

### Пользовательский сценарий

1. Пользователь запускает игру на (теоретической) полностью водной карте
   или на карте с островом меньше радиуса спирали.
2. Создаёт новый проект.
3. `DistrictPlanner.allocateNextOrigin` исчерпывает 10_000 попыток
   спирали (все клетки `.sea` / `.river`).
4. В `errors.log` появляется warning: `"DistrictPlanner.allocateNextOrigin:
   no land cell within spiral radius after N attempts; returning defensive
   fallback at <origin>"`.
5. Юнит размещается по defensive fallback (текущее поведение —
   `return (origin, idx)`), без crash.
6. На сцене — юнит на воде (visual artefact, но не падение). Это
   приемлемо для теоретического edge case; warning в логе указывает
   разработчику на проблему.

### Acceptance criteria

- [ ] **AC1.** При исчерпании спирали в `DistrictPlanner.allocateNextOrigin`
      (10_000 attempts без land-клетки) — `ErrorsLog.write` warning с
      контекстом (origin, attempts, projectKey если доступен).
- [ ] **AC2.** То же для `DistrictPlanner.allocateAlongMagistrale` при
      выходе из maxAttempts-цикла.
- [ ] **AC3.** Property-тест в `DistrictPlannerBiomeAwareTests.swift`:
      mock `BiomeMapReader` возвращает `.sea` для всех клеток в радиусе
      → вызов `allocateNextOrigin` → проверка вызова ErrorsLog
      (через test seam или захват записей).
- [ ] **AC4.** Не регрессируют существующие тесты
      `DistrictPlannerBiomeAwareTests` (2 кейса) и
      `DistrictNoOverlapPropertyTests` (2 кейса).
- [ ] **AC5.** BUG-009 закрыт в `bugs.md` со ссылкой на commit
      этой задачи; в описании Решения указано, что hard-skip уже
      работает с TASK-030c/TASK-056, эта задача добавила warning +
      регресс-щит.

### Что НЕ делаем (границы скоупа)

- Не переписываем water-skip логику — она уже работает.
- Не меняем порядок hard/soft фильтров (water → cross-project → preferred
  уже корректен).
- Не добавляем port / wharf юниты (отдельная задача).
- Не меняем `BiomeMapReader` API.
- Не добавляем UI-уведомление пользователю про fallback (только log
  для разработчика).
- Не реогранизуем `DistrictPlannerBiomeAwareTests` — только дописываем
  1-2 кейса.

### Edge cases

- [ ] Карта без воды — warning не вызывается (water-skip = no-op, привычное
      поведение).
- [ ] Узкий остров (1-2 клетки земли, остальное вода) — origin
      размещается на земле, warning не вызывается; для второго origin
      без `minDistrictRadius` — warning сработает.
- [ ] ErrorsLog недоступен (файловая система readonly) — warning тихо
      проглатывается (текущее поведение ErrorsLog.write), allocateNextOrigin
      продолжает работу.
- [ ] Multiple concurrent allocations — каждый получает свой warning;
      `ErrorsLog.write` thread-safe (см. existing API).

### Зависимости

- `ErrorsLog` (`Sources/CityDeveloper/Data/ErrorsLog.swift`) — существующий
  helper с thread-safe write.
- `DistrictPlannerBiomeAwareTests.swift` — расширяем существующий файл.
- TASK-030c / TASK-056 — реализовали water-skip и cross-project skip
  паттерны (фоновый контекст, не правим).

### Дизайн

Не применимо (engine-fix + log + test).

### Done-критерий

_На основе bugs.md BUG-009:_ DistrictPlanner пропускает water-биомы
(работает с TASK-030c/TASK-056); при невозможности найти land —
ErrorsLog warning + defensive fallback без crash. Регресс-щит покрывает
сценарий 100% водной карты.

---

## 🛠 Технический разбор от тимлида

_Статус: [x] ready_
_Lead-model: opus_
_Plan-review: approved_

### Анализ текущего состояния

Water-skip + cross-project-skip + preferred-biome soft-scan уже работают
(`DistrictPlanner.swift:40-118`, `:180-192`). Защитный fallback при
исчерпании спирали — `return (origin, idx)` на `DistrictPlanner.swift:117`
(spiral) и `return (mag[centerIdx], idx)` на `:195` (магистраль) — молчит.
По этой задаче добавляем только **ErrorsLog.write warning** в эти два места
и **регресс-тест** для AC «100% water map». Логика skip не меняется.

### Архитектурное решение

Минимальный delta: после исчерпания цикла спирали/магистрали (idx ≥
maxAttempts) — `ErrorsLog.write(...)` с контекстом перед defensive return.
Для тестируемости вводим в `ErrorsLog` test seam — `static var writer:
(String) -> Void` (default = текущий file-write через `queue.async`),
которую тесты могут подменить и захватить записи. Это согласуется со
стилем `UnitPlanner.legacyRingPosition:501` (defensive ErrorsLog +
no-crash return) и не требует менять остальные ~50 call-sites.

### Пошаговая декомпозиция

**Шаг 1.** [AC1 / AC2 база] — Test seam в `ErrorsLog`.
Файл: `Sources/CityDeveloper/Data/ErrorsLog.swift`.
Извлечь текущий file-write код в `private static let defaultWriter:
(String) -> Void = { message in queue.async { ... } }`. Объявить
`static var writer: (String) -> Void = defaultWriter`. Метод `write(_:)`
делегирует в `Self.writer(message)`. Поведение в проде идентичное.

**Шаг 2.** [AC1] — Warning в `allocateNextOrigin`.
Файл: `Sources/CityDeveloper/Game/DistrictPlanner.swift:115-117`.
Перед `return (origin, idx)` (line 117) добавить проверку
`if idx >= maxAttempts { ErrorsLog.write("DistrictPlanner.allocateNextOrigin:
no land cell within spiral radius after \(idx - currentIndex) attempts;
returning defensive fallback at \(origin)") }`. `projectKey` сюда не
прокидывается (нет в сигнатуре, не трогаем API — см. «Что НЕ делаем»),
указываем origin + attempts.

**Шаг 3.** [AC2] — Warning в `allocateAlongMagistrale`.
Файл: `Sources/CityDeveloper/Game/DistrictPlanner.swift:194-195`.
Перед `return (mag[centerIdx], idx)` добавить
`ErrorsLog.write("DistrictPlanner.allocateAlongMagistrale: maxAttempts
\(maxAttempts - currentIndex) exhausted; returning defensive fallback at
mag[\(centerIdx)]=\(mag[centerIdx])")`. Тут exit — только по
`idx >= maxAttempts` (единственный путь выхода из while-loop), отдельный
guard не нужен.

**Шаг 4.** [AC3 / AC4] — Регресс-тесты.
Файл: `Tests/CityDeveloperTests/DistrictPlannerBiomeAwareTests.swift`.
Добавить `setUp/tearDown` (override ErrorsLog.writer, восстановить
default), helper `captureErrorsLog(_ block:) -> [String]`. Добавить:
(a) `test_AllWaterMapTriggersErrorsLogWarning` — `MockBiomeReader(biomes:
[:], defaultBiome: .sea)`, currentIndex=0 → проверка `captured.contains
{ $0.contains("allocateNextOrigin") && $0.contains("defensive fallback") }`,
`origin == spiralPoint(idx)` где idx == 10_000.
(b) `test_AllWaterMagistraleTriggersErrorsLogWarning` — тот же sea-reader,
`mainRoadCells = [GridPoint(x:0,y:128), ...]` (≥1 cell), currentIndex=0
→ проверка warning + `origin == mag[centerIdx]`.
Также короткий negative-test `test_MeadowMapDoesNotTriggerWarning`
(meadow-only → captured.isEmpty) для подтверждения, что seam не ловит
посторонние записи и для AC4 (существующие 2 кейса) запускаются без
регрессий.

### Edge cases

- **Карта без воды** (`DistrictPlanner.swift:67` — `isWater == false`
  сразу → break) — warning не вызывается. Покрыто `test_MeadowMapDoes
  NotTriggerWarning` (Шаг 4c).
- **Узкий остров / cross-project fill** (`DistrictPlanner.swift:76-88`) —
  если spiral исчерпан на cross-skip ветке, idx тоже достигает
  maxAttempts → warning сработает (это правильно: всё равно defensive
  fallback на water-cell может произойти).
- **ErrorsLog недоступен** (FS readonly) — `try?` в текущем `write` глотает
  ошибку (`ErrorsLog.swift:15-18`); поведение сохраняем. После Шага 1
  default-writer асинхронен, warning не блокирует allocate-вызов.
- **Concurrent allocations** — каждый поток получает свой
  `ErrorsLog.write`, default-writer пишет через `queue.async` (serial
  queue, thread-safe). В тестах подменяем на синхронный capture-writer —
  убедиться, что capture-array под XCTAssertions читается на test-thread
  (allocateNextOrigin синхронный, writer вызывается синхронно перед
  return → safe без extra sync).
- **TASK-056/TASK-030c регрессия** (`DistrictPlannerBiomeAwareTests.swift
  :121-166`) — water-skip вызовы при наличии земли возвращают раньше
  break-условия → warning silent. Покрыто AC4.

### Файлы для изменения

- `Sources/CityDeveloper/Data/ErrorsLog.swift` — test seam (Шаг 1).
- `Sources/CityDeveloper/Game/DistrictPlanner.swift` — 2 warning'а
  (Шаги 2-3).
- `Tests/CityDeveloperTests/DistrictPlannerBiomeAwareTests.swift` —
  setUp/tearDown + 3 теста (Шаг 4).
- `concept/Bugs.md` — закрыть BUG-009 с примечанием о TASK-030c/056 как
  root fix и TASK-062 как warning+щит (AC5).
- `concept/Current.md` — короткая запись F-06/F-15 о defensive warning.

### Файлы НЕ трогать (обоснование)

- `BiomeMapReader`, `BiomeKind` — API не меняется, MockReader уже умеет
  всё нужное.
- `CityEngine`, `UnitPlanner` — не зависят от сигнатуры
  allocateNextOrigin; warning внутренний.
- `concept/Backlog.md` / `concept/Diff.md` — текущий delta не плодит
  новых идей; новые баги/идеи добавлять только при возникновении.
- Остальные ~50 call-sites `ErrorsLog.write` — test seam обратно
  совместим, никаких изменений.

### Команды проверки

```bash
cd /Users/ilahohlov/CityDeveloper
swift test --filter DistrictPlannerBiomeAwareTests
swift test --filter DistrictNoOverlapPropertyTests
swift build 2>&1 | tail -20
```

Ожидание: 5+5 кейсов BiomeAware (2 старых + 3 новых) и 2 кейса
NoOverlapProperty — все green; build без warning'ов.

### Сложность / Объём

- **Сложность:** middle (test seam в shared utility + 2 строчных warning'а
  + 3 теста; требует понимания thread-safety closure writer и порядка
  setUp/tearDown).
- **Объём:** S (≤2ч; ~30 строк кода + ~80 строк тестов + 2 doc-edit).

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен (mock полностью водной карты → warning в log)

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны
- [ ] +1-2 property-теста (AC3, AC4)

#### Обновление документации
- [x] `Current.md`: F-06 / F-15 запись упоминает defensive warning
- [x] `Bugs.md`: BUG-009 закрыт со ссылкой на коммит + примечание про TASK-030c/TASK-056
- [x] Новые идеи → `Backlog.md`, новые баги → `Bugs.md` (followups нет)

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-26
- Spec-review: revised (Opus, 1 круг — обнаружено: BUG-009 уже частично закрыт TASK-030c/TASK-056; спека переписана на узкий delta = warning + регресс-щит. Размер S вместо M)
- Lead-trigger: opus (P1)
- Lead-model: opus
- Plan-review: approved (Sonnet, 1 круг — Opus subagent inline без отдельного Agent tool)
- Готова к работе: 2026-05-26
- Исполнитель: sonnet (middle)
- Verify: pass (179/179, AC1-4 auto, AC5 docs main session)
- Code-review: approved (Opus — Lead-model: opus + P1)
- Завершена: 2026-05-26
- Коммит: —
