# TASK-037: Миграция старого state с 12 юнитов на 50

## Связь
- **F-16** из Concept.md (расширенный каталог)
- **F-03** из Concept.md (event sourcing, replay)
- **F-12** из Concept.md (снэпшоты state.json)
- **D-16** из Diff.md (часть 7/10 — миграция)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-22_

### Что хотим
У пользователя в `~/Library/Application Support/CityDeveloper/` уже лежит
`state.json` со снэпшотом и `events.jsonl` с историей событий, где `UnitKind`
закодирован старым 12-юнитным набором (`shack`, `house`, `villa`, `well`,
`road`, `warehouse`, `workshop`, `raw`, `market`, `forum`, `temple`,
`obelisk`). После TASK-031 каталог становится 50-юнитным, и при первом
запуске новой версии нужно:
1. Корректно прочитать старый state.json (decode не должен падать на
   старых rawValue).
2. Корректно проиграть старый events.jsonl (replay не должен падать).
3. По возможности «обогатить» данные — например, старые `shack` на стадии
   квартала 0 можно оставить `shack`, но добавить им поле «эволюционирует в
   Лачугу» через TASK-031/TASK-034 без re-write старого state.

Цель — **никакой потери истории** и никакого «вы потеряли свой город».

### Пользовательский сценарий
1. Игрок обновляет приложение с версии «до D-16» на версию «после D-16».
2. Запускает игру → состояние города восстанавливается полностью: все
   проекты на месте, все юниты на месте, населённость считается корректно,
   декай-уровни сохранены.
3. Новые юниты появляются только из новых задач (старые не
   перекодируются «задним числом» в новые типы — это разрушило бы
   историю «почему этот дом тут»).
4. Если игрок удалит `state.json` и запустит замену по полному replay из
   `events.jsonl` (фолбэк F-12) — результат идентичен.

### Acceptance criteria
- [ ] Старый `state.json`, сохранённый до TASK-031, успешно декодируется в
      новый формат `CityState` без падений и без потери юнитов / проектов
      (smoke-тест: подложить test-state.json из старой версии, запустить —
      город виден целиком).
- [ ] Старый `events.jsonl` со старыми rawValue для `UnitKind` успешно
      реплеится (smoke-тест: удалить `state.json`, оставить старый
      `events.jsonl`, запустить — состояние идентично state.json до удаления).
- [ ] Старые юниты сохраняют свой `UnitKind` (никакой автоматической
      замены `shack → землянка` или `warehouse → склад_F16` — это разрушит
      идентичность с прошлым). Старые 12 типов из TASK-031 остаются
      валидными и узнаваемыми.
- [ ] Если в логе встречается событие нового типа (`unit_evolved` из
      TASK-034 или новый rawValue юнита из TASK-031), а версия приложения
      слишком старая для его понимания — событие пропускается с записью в
      `errors.log` (forward-compat: не падать на «событиях из будущего»).
- [ ] Снэпшот, созданный новой версией приложения после миграции, при
      повторной загрузке этой же версией идентичен.

### Что НЕ делаем (границы скоупа)
- Не переписываем старые события в `events.jsonl` (append-only по F-03).
- Не «обновляем» старые юниты до новых типов (Лачуга остаётся `shack`,
  а не превращается в Землянку задним числом).
- Не вводим UI-флоу «мигрировать вручную» — миграция автоматическая и
  прозрачная для пользователя.
- Не пишем тулзу для конвертации (вне сценария: игрок просто запускает
  приложение).
- Не реализуем сами эволюционные цепочки (TASK-034) — здесь только
  гарантия, что миграция их не ломает.

### Edge cases
- [ ] `state.json` отсутствует, `events.jsonl` отсутствует → создаётся
      пустой `CityState`, никаких ошибок.
- [ ] `state.json` повреждён (битый JSON) → fallback на полный replay из
      `events.jsonl` (как сейчас по F-12), пишется одна запись в
      `errors.log`.
- [ ] `events.jsonl` содержит событие с неизвестным `UnitKind` rawValue
      (например, пользователь правил вручную) → событие пропущено,
      `errors.log`.
- [ ] В старом state есть юниты с `UnitKind`, который во новом каталоге
      переименован (если из TASK-031 у кого-то изменился rawValue) →
      должна быть таблица алиасов (например, `temple → temple`,
      `obelisk → obelisk` — старые остаются как есть; новые «Храм» уже
      под `temple_v2` если бы переименовали). Жёсткое требование TASK-031:
      старые rawValue не меняются, так что алиасы не нужны; в этой задаче
      явно проверить, что переименований не случилось.

### Зависимости
- **Blocked-by:** TASK-031 (новый каталог должен быть в коде).
- **Soft-blocked-by:** TASK-034 (нужно для проверки совместимости с
  `unit_evolved` событиями; можно делать параллельно, но финальная
  проверка после TASK-034).

### Дизайн
Не применимо (нет UI; миграция автоматическая и невидимая).

### Done-критерий
_Из Concept.md F-16:_ Все 50 юнитов имеют реализованный спрайт и корректно выбираются
алгоритмом размещения с учётом `terrain`, `minStage` и `large`. Эволюционные цепочки
визуально срабатывают при достижении порога. Квартал из 30+ юнитов содержит ≥ 3
разных категории. Воспроизводимость через replay.

---

## 🛠 Технический разбор от тимлида

_Статус: [x] разобрана (Opus, 2026-05-22)_

### Ключевое наблюдение про текущую модель данных

Перед планированием миграции — важный факт, который радикально упрощает задачу:

1. **`GameEvent` НЕ содержит `UnitKind`.** Структура `GameEvent`
   (`Data/GameEvent.swift`) хранит только `id, ts, kind (GameEvent.Kind),
   project, title, taskId, source`. `GameEvent.Kind` — узкий enum событий
   (`task_completed, unit_built, stage_up, decay_tick, fire, restore,
   ruins_cleared`), без `unit_evolved`. Поле `title` для `unit_built`
   содержит лишь **русский label** (`unit.kind.label`, см.
   `CityEngine.swift:281`), а не rawValue юнита.
2. **`UnitKind` материализуется только при replay-исполнении
   `applyTaskCompleted`** через `UnitPlanner.nextUnitKind(...)` — то есть
   при replay UnitKind **выбирается заново** по текущей логике планировщика
   (`CityEngine.swift:232-240`). Поэтому в `events.jsonl` ни старого, ни
   нового rawValue юнита нет, и проблема «старого rawValue в логе» не
   существует **сегодня** (до TASK-034 / TASK-024 расширений).
3. **`UnitKind` десериализуется только из `state.json`** (через
   `CityState.units: [UUID: UnitState]`, `UnitState.kind: UnitKind`,
   `Data/CityState.swift:7,16`). Это единственное место, где старый
   12-юнитный rawValue может прийти из устаревшего файла.
4. **`SnapshotStore.load()` уже имеет fallback:** при
   `try? decoder.decode(...)` (`Data/SnapshotStore.swift:12-17`) любой
   сбой декодирования (включая неизвестный rawValue) → `nil` → `ErrorsLog`
   + `replayFromLog()` идёт по full-replay-ветке
   (`CityEngine.swift:104-108`).
5. **`EventLog.readAll()` тоже толерантен:** строки, не декодируемые
   в `GameEvent`, пропускаются с записью в `ErrorsLog`
   (`EventLog.swift:42-45`). Это уже даёт forward-compat
   для «событий из будущего» (новый `unit_evolved` старым бинарём — старый
   бинарь его не увидит и не упадёт; это **уже описано в LogFormat.md**,
   строки 184-191).

Вывод: задача почти полностью **разрешается грамотным расширением UnitKind
в TASK-031 без изменения rawValue существующих 12 case'ов** + один-два
осознанных штриха в `SnapshotStore`/`CityState`. Это **junior–middle / S**
по объёму, а не L.

### Что физически нужно сделать в этой задаче

#### 1. Гарантировать неизменность rawValue в TASK-031 (контракт)

Это AC#85-89 спеки. Технически — это правило для исполнителя TASK-031,
но в TASK-037 явно проверяем:

- Все 12 существующих case'ов в новом `UnitKind` обязаны сохранить точное
  raw-value (`shack`, `house`, `villa`, `well`, `road`, `warehouse`,
  `workshop`, `raw`, `market`, `forum`, `temple`, `obelisk`).
- В новой `UnitCategory` оба новых case'а (`.religious`, `.military`) —
  добавляются, существующие 4 не переименовываются.
- Старые `temple` и `obelisk` остаются в категории `.social`, **а не
  перекидываются в новый `.religious`**: это сломало бы тождественность
  старых юнитов с их прошлой ролью в quartal-балансе (старые `temple`,
  `obelisk` уже считались `.social` в `applyTaskCompleted`-агрегатах
  при формировании квартала, см. `CityEngine.swift:227-231`). Новый
  «Храм» из F-16 (item #44 в каталоге Concept.md:415) — это
  **отдельный новый case** (например, `chapel`, `cathedral`,
  `pyramid` для item #43, #46, #47; для #44 предложить `templeReligious`
  или сохранить старый rawValue `temple` для item #44 и завести новый
  rawValue для старого `temple`-социального — **но это AC спеки
  явно запрещает**, поэтому единственный путь: старые rawValue +
  категория сохраняются, а Храм#44 получает другой rawValue
  (например, `temple_v2` / `religiousTemple`)).

  **Это решение зафиксировать в TASK-031** при выборе rawValue новых
  юнитов. В TASK-037 — отдельным шагом написать unit-тест:
  `XCTAssertEqual(UnitKind.shack.rawValue, "shack")` × 12 case'ов
  (см. п. 6).

#### 2. `SnapshotStore.load()` — отделить «нет файла» от «ошибка декода»

Сейчас оба случая возвращают `nil`, но «битый snapshot» пишет в
`ErrorsLog` всегда (даже если файла просто нет, `try?` глотает обе
ошибки). Это работает, но при анализе errors.log путает:

```swift
// Новое поведение:
func load() -> StateSnapshot? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    guard let data = try? Data(contentsOf: url) else {
        ErrorsLog.write("Snapshot read failed (file exists but unreadable)")
        return nil
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
        let snap = try decoder.decode(StateSnapshot.self, from: data)
        guard snap.version == StateSnapshot.currentVersion else {
            ErrorsLog.write("Snapshot version \(snap.version) ≠ current \(StateSnapshot.currentVersion); full replay")
            return nil
        }
        return snap
    } catch {
        ErrorsLog.write("Snapshot decode failed (likely unknown UnitKind from older/newer version): \(error). Falling back to full replay.")
        return nil
    }
}
```

Польза: при появлении старого state.json с rawValue, который случайно
исчезнет в будущем (или пользователь напрямую отредактировал файл) —
понятная диагностика в errors.log. Edge case спеки «state.json
повреждён → fallback на full replay» — закрыт.

#### 3. `CityState` decoder — пер-юнитная толерантность (опционально, по решению исполнителя)

**Решение по умолчанию: НЕ ВКЛЮЧАТЬ в скоуп TASK-037.**

Аргументы за упрощение:

- При неизменных rawValue 12 case'ов (контракт п. 1) старый snapshot
  читается синтезированным `Codable` без проблем.
- Случай «битый kind в snapshot» (если, скажем, пользователь руками
  правил state.json) уже корректно обрабатывается: `decoder.decode`
  падает → `SnapshotStore.load()` возвращает nil → `CityEngine.replayFromLog`
  идёт по fallback на full replay (`CityEngine.swift:103-108`). Это
  ровно поведение, описанное в AC «edge case: state.json повреждён».
- Кастомный `init(from:)` потребует точно знать, как `JSONEncoder`
  сериализует `[UUID: UnitState]` (array-layout `[k,v,k,v]` vs
  object с string-keys), и держать это в синхроне с дефолтным
  кодером. Это дополнительный риск багов.

Если исполнитель **всё же хочет** пер-юнитную толерантность («не
терять весь город из-за одного битого юнита, не уходя в full replay»):

- Сначала запустить snapshot save с парой проектов/юнитов и
  посмотреть в `state.json` фактический формат словаря UUID→UnitState
  в текущем коде.
- Подстроить кастомный `init(from:)` для `CityState` под него,
  сохраняя обратную совместимость со старым форматом.
- Закрыть тестом round-trip + тестом «один битый юнит → остальные
  читаются».

В рамках текущего скоупа TASK-037 — **этот пункт не делать**,
завести как тикет в `Backlog.md` («partial-snapshot robustness»).

#### 4. Опционально: bump `StateSnapshot.currentVersion` или нет

**Решение: НЕ повышать.** Причина:
- Версия 1 + неизменные rawValue 12 case'ов = старый snapshot читается
  новым кодом без преобразований.
- Если bump'нуть до 2 — старые snapshot'ы будут invalidated через guard
  `snap.version == StateSnapshot.currentVersion` и пойдут на full replay
  (что само по себе валидно, но дороже и теряет смысл «нет потери
  истории»).
- Bump до 2 имеет смысл только когда мы реально меняем структуру
  `CityState` несовместимо. Этого в TASK-037 не происходит.

Зафиксировать это решение в LogFormat.md (см. п. 7).

#### 5. Forward-compat для `unit_evolved` (TASK-034)

AC спеки про «событие нового типа пропускается с записью в errors.log»
**уже работает автоматически**, см. п. 5 ключевого наблюдения. Нужно
только:

- Подтвердить тестом: добавить в `events.jsonl` строку
  `{"id":"...","ts":"...","kind":"unit_evolved","project":"p1"}` —
  убедиться, что `EventLog.readAll()` пропускает её, пишет в
  `ErrorsLog` и остальные строки реплеятся нормально.
- Дописать в `LogFormat.md` раздел про forward-compat (см. п. 7).
- НЕ менять `GameEvent.Kind` enum в этой задаче (это TASK-034).

#### 6. Тесты в `Tests/CityDeveloperTests/`

Создать `LegacyStateMigrationTests.swift`:

1. `testRawValuesStable12()` — для всех 12 старых case'ов проверить
   `UnitKind(rawValue: "shack")?.rawValue == "shack"` × 12. Защита
   от случайного переименования в TASK-031.
2. `testOldStateJsonLoadsCleanly()` — фикстура: захардкоженный
   minimal `state.json` в формате до TASK-031 (с rawValue `shack`,
   `temple`, `obelisk` среди юнитов), `SnapshotStore.load()` →
   non-nil, `CityState.units.count` совпадает с фикстурой.
3. `testOldEventsJsonlReplays()` — фикстура: захардкоженный
   `events.jsonl` со старыми `task_completed`/`unit_built`/
   `decay_tick` событиями (только `kind` enum, не UnitKind). Удаляем
   state.json → `CityEngine` поднимается, `state.projects.count`
   совпадает с количеством разных `project` в логе.
4. `testUnknownEventKindSkipped()` — фикстура: `events.jsonl` со
   строкой `{"kind":"unit_evolved",...}`. `EventLog.readAll()`
   возвращает только декодируемые события, не падает.
5. `testCorruptedSnapshotFallbackToReplay()` — фикстура: подменить
   `state.json` на `{"version":1,"snapshotTs":"...","lastEventIndex":0,"cityState":{"units":{"...":{"kind":"INVALID_KIND",...}}}}`.
   Engine стартует, не падает, идёт по full-replay ветке.
6. `testRoundTripIdentity()` — записать snapshot новым кодом,
   загрузить новым кодом, сравнить структурно (как
   `testReplayEquivalence` в `CityEngineTests.swift:59-91`).

Фикстуры — inline в Swift-строках (как в существующих тестах), без
бинарных файлов.

#### 7. Документация

`concept/LogFormat.md` — добавить раздел «### Совместимость 12 → 50
юнитов (TASK-037)»:

- Старые 12 rawValue (`shack..obelisk`) **гарантированно** валидны во
  всех будущих версиях. Не переименовывать.
- Старые snapshot'ы (`StateSnapshot.version == 1`) читаются новым
  кодом as-is; bump версии не происходит при расширении каталога.
- При добавлении новых полей в `CityState`/`ProjectState`/`UnitState`
  — поля должны быть `Optional` или иметь дефолт в кастомном
  `init(from:)`. Bump `currentVersion` обязателен только при
  несовместимом изменении структуры.
- Неизвестный `UnitKind` rawValue в snapshot → юнит пропускается с
  записью в `errors.log`, остальной snapshot грузится; полный фейл
  декодирования → fallback на full replay.
- Неизвестный `GameEvent.Kind` в логе → строка пропускается с записью
  в `errors.log` (уже работает с TASK-024).

`concept/Current.md` — F-16 → ⚠️ (помечено в спеке).
`concept/Diff.md` — D-16 не закрывать, остаётся открытым до TASK-040.

### План работ (последовательность)

1. **(Pre-req)** Убедиться, что TASK-031 готов и rawValue 12 case'ов
   сохранены — иначе блокировка TASK-037 ещё в силе.
2. Реализовать защитный `SnapshotStore.load()` (п. 2) — отделить «нет
   файла» от «битый файл», улучшить диагностику в errors.log.
3. (Опционально / в backlog) Пер-юнитный fallback в `CityState.init(from:)`
   (п. 3). По умолчанию — пропускаем.
4. Написать 6 тестов из п. 6. Тест #2 (round-trip identity) и тест #5
   (corrupted snapshot fallback) — обязательны для AC.
5. Обновить `LogFormat.md`, `Current.md` (п. 7).
6. Smoke-тест руками: положить старую фикстуру `state.json` +
   `events.jsonl` в Application Support, запустить — город виден,
   `errors.log` пуст / содержит только ожидаемые warning'и.

### Риски и mitigation

| Риск | Mitigation |
|------|-----------|
| TASK-031 случайно изменит rawValue одного из 12 case'ов | Тест `testRawValuesStable12()` ломается → catch на CI до релиза |
| `[UUID: UnitState]` сериализуется array-layout, кастомный `init(from:)` ломает loading нормальных snapshot'ов | Перед коммитом — посмотреть фактический JSON и подстроить. Тест `testRoundTripIdentity()` это поймает. |
| `temple`/`obelisk` в новом каталоге случайно перенесут в `.religious` категорию | AC спеки + категория `.social` для старых случаев фиксируется в коде TASK-031; в TASK-037 — тест на `UnitKind.temple.category == .social` |
| Эволюционные юниты TASK-034 запишут `unit_evolved` в лог, а потом откатим версию приложения | Уже покрыто `EventLog.readAll()` (skip + errors.log) и тестом `testUnknownEventKindSkipped()` |
| Старый `state.json` содержит юниты в позициях, которые конфликтуют с новой `DistrictPlanner`-логикой | Не в скоупе TASK-037: позиции не меняются, `nextDistrictIndex` сохраняется в snapshot. Если планировщик изменится — это уже TASK-035. |
| Пользователь удалил `state.json` и оставил `events.jsonl` со 100% старых событий → новый `applyTaskCompleted` сгенерирует НОВЫЕ UnitKind через `UnitPlanner` (теперь с 50 case'ами) | По AC#3 это допустимо (старые юниты сохраняют свой Kind ТОЛЬКО при наличии snapshot; при full replay UnitKind пересчитывается заново — это **уже текущее поведение, не миграционная проблема**). Зафиксировать в LogFormat.md явно: «full replay → UnitKind пересчитывается планировщиком текущей версии». |

### Спорные места / возможные эскалации

- **AC#4 спеки «Если игрок удалит state.json … результат идентичен»** —
  буквально это **невыполнимо** после TASK-031, потому что `UnitPlanner`
  при full replay сгенерирует UnitKind через новую логику (а если ещё и
  TASK-035 поменяет планировщик — тем более). Это **не миграционная
  проблема, а архитектурное свойство event sourcing'а в этом проекте**:
  UnitKind не event-sourced, он функция от (task index, stage, counters,
  planner version).

  Что предлагаю PM-у: **переформулировать AC#4** как «результат
  идентичен предыдущему snapshot'у new-version'а, если событий после
  него не было». Либо явно принять, что full replay = «город будет
  переразмещён по текущим правилам планировщика». В техническом
  разборе фиксирую как **PM-вопрос, но не блокер задачи**: миграция
  работает корректно при наличии snapshot, и это основной сценарий.

- TASK-037 **не требует параллельной правки нескольких модулей с
  миграционной семантикой** — изменения локальны в `SnapshotStore`,
  `CityState` (опционально) и тестах. Это не L.

---

## ✅ Исполнение

_Исполнитель: agent (sonnet-4.6, 2026-05-23)_
_Сложность: middle_ (после spec-readiness: основная сложность — корректно интерпретировать AC#4 и не сломать round-trip; код — простой)
_Объём: S_ (после разбора: реальные правки укладываются в ~2 часа кода + тесты; L-оценка спеки была завышена, потому что UnitKind не в events.jsonl)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен в реальном использовании (на test-фикстуре
      «старый state.json + старый events.jsonl» → новая версия видит весь
      город)

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны
- [ ] Нет хардкод-строк (rawValue в маппинге миграции — в общей таблице,
      не разбросаны)

#### Обновление документации
- [ ] `Current.md`: F-16 → ⚠️ (миграция готова, общий F-16 — после TASK-040)
- [ ] `Diff.md`: D-16 не закрывать — закрывается только после TASK-040
- [ ] `LogFormat.md`: добавить раздел «совместимость старого 12-юнитного
      формата с новым 50-юнитным» (что гарантировано, что нет)
- [ ] Новые идеи → `Backlog.md`, новые баги → `Bugs.md`

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-22
- Spec-review: approved
- Lead-review: approved (Opus, 2026-05-22), plan-review: approved (self-Sonnet pass)
- Blocked-by: TASK-031
- Готова к работе: 2026-05-22 (но физически — после готовности TASK-031)
- Завершена: 2026-05-23
- Коммит: 32d2a07
