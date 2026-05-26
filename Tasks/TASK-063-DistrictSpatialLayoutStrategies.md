# TASK-063: Spatial layout кварталов — спираль/решётка/шаблоны + ответвления дорог

## Связь
- **F-06** из Concept.md (Project-District и автоматическое размещение)
- **BUG-026** из Bugs.md
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-26_

### Что хотим

Город сейчас разрастается тонкой линией вдоль одной магистрали — кварталы
выстраиваются цепочкой в одну сторону, нет спирали / решётки / органичного
паттерна. Нужны spatial-layout стратегии: новый origin отходит **от**
магистрали под прямым углом или по спирали, образуя «гребёнку» / сетку /
ветвление. Плюс ответвления дорог от магистрали к каждому off-road origin'у,
чтобы город «дышал», а не был колбасой.

**Скоуп этой задачи:** минимально жизнеспособная стратегия `branching` —
после первых N кварталов вдоль магистрали следующий origin отходит в
сторону под прямым углом, к нему достраивается короткое road-ответвление.
Этого достаточно, чтобы город визуально перестал быть линией.

**Следующие итерации (вне скоупа):** Settings UI переключатель стратегий
(spiral / grid / template / auto-by-seed), district-placement templates
по family (egyptian-spiral / roman-grid / greek-hippodamian) — оформить
backlog-идеями.

### Пользовательский сценарий

1. Пользователь запускает игру на пустой карте.
2. Создаёт 4+ разных проекта подряд (через tasks.jsonl / journal / commits).
3. Первые 2-3 проекта размещаются вдоль магистрали (текущее поведение).
4. Начиная с 3-го или 4-го проекта (порог — определит лид) — новый
   origin отходит **в сторону** от магистрали, под прямым углом, с
   соблюдением `minDistrictRadius=8`.
5. К новому off-road origin'у автоматически проводится road-ответвление
   от ближайшей точки магистрали (короткий L-образный или прямой сегмент).
6. Визуально город разрастается не цепочкой, а «гребёнкой» / Y-образно:
   главная магистраль с ответвлениями к боковым кварталам.

### Acceptance criteria

- [ ] **AC1.** В `DistrictPlanner.allocateNextOrigin` (или новом методе)
      реализована стратегия `branching`: первые N origin'ов (N ≥ 2,
      порог настраивается константой) идут вдоль магистрали; следующие
      — отклоняются перпендикулярно от магистрали с шагом
      `minDistrictRadius=8` в обе стороны (поочерёдно вверх/вниз для
      east-west магистрали или влево/вправо для north-south).
- [ ] **AC2.** Для каждого off-road origin'а `RoadNetwork` (или
      `DistrictPlanner`) генерирует road-ответвление от ближайшей
      клетки магистрали до периметра нового квартала (длина —
      `Чебышёвское расстояние` от origin до магистрали).
- [ ] **AC3.** Ответвление добавляется в `roadCells` / `plannedCells`
      проекта так, что `UnitPlanner.nextPosition` может строить юниты
      `depth=1` от road (см. BUG-017/018 контракт — здания соседствуют
      с road через 4-cardinal).
- [ ] **AC4.** Property-тест в новом
      `Tests/CityDeveloperTests/DistrictBranchingPropertyTests.swift`:
      ingest 5 проектов на свежей карте 100×100 → ≥ 2 origin'а
      находятся НЕ на самой магистрали (perpendicular offset ≥
      `minDistrictRadius`).
- [ ] **AC5.** Property-тест: каждый off-road origin имеет валидное
      road-ответвление (есть path из road-клеток от origin до магистрали).
- [ ] **AC6.** Не регрессируют тесты `DistrictNoOverlapPropertyTests`,
      `UnitPlannerLegacyRingOverlapTests`, `DistrictPlannerBiomeAwareTests`.
- [ ] **AC7.** Replay events: branching origin'ы воспроизводятся
      идентично между прогонами (детерминированно от seed).
- [ ] **AC8.** Минимальный визуальный smoke (manual): 4-5 проектов на
      свежей карте — на сцене видна не линия, а «гребёнка»/Y-форма;
      ответвления видны как road-клетки.

### Что НЕ делаем (границы скоупа)

- Не реализуем стратегии `spiral` / `grid` / `template` — только
  `branching`. Остальные → backlog как followup.
- Не делаем Settings UI переключатель стратегий — branching = default,
  не настраивается в этой задаче.
- Не делаем district-placement templates по family — отдельная задача
  после F-25 mature.
- Не меняем формат `CityState` / `ProjectState` (origin / roadCells
  как раньше).
- Не оптимизируем существующую `allocateAlongMagistrale` — branching
  это новая ветка / расширение.
- Не делаем мосты через воду (если ответвление пересекает реку —
  пока пропускаем такие origin'ы или fallback на линейный).
- Не меняем визуал road-клеток.

### Edge cases

- [ ] Маленькая карта (50×50) — branching может упереться в край;
      fallback на линейный.
- [ ] Магистраль не east-west, а другой ориентации — branching
      детектирует ось магистрали (по существующим road-cells direction)
      и offset перпендикулярно.
- [ ] Магистраль изогнута или Г-образная (если такое возможно в текущем
      RoadNetwork) — branching ищет ближайшую точку магистрали для
      ответвления, не предполагает идеальной прямой.
- [ ] Off-road origin попадает в воду (биом `.sea` / `.river`) —
      water-skip из TASK-062/030c отрабатывает первым, branching
      пробует следующий offset.
- [ ] Off-road origin пересекает чужой квартал (cross-project) —
      TASK-056 skip отрабатывает, branching пробует следующий offset.
- [ ] Ответвление пересекает существующее здание (теоретически невозможно
      если road генерируется до юнитов) — fallback на линейный origin.
- [ ] Конкурентные запросы новых origin'ов — main-queue serial гарантирует
      atomic state (как в существующем коде).

### Зависимости

- `DistrictPlanner.allocateNextOrigin` / `allocateAlongMagistrale` —
  паттерн расширения через optional параметры (TASK-056).
- `RoadNetwork` — должна уметь добавлять branch-сегменты (метод типа
  `extendBranchToOrigin(originGrid:from:)`); если такого нет — лид
  добавит.
- TASK-056 (cross-project skip) — branching должен корректно с ним
  совмещаться.
- TASK-062 (water-skip) — также применяется к branching кандидатам.
- TASK-030c (preferred biomes) — branching кандидаты тоже проходят
  через preferred filter.

### Дизайн

Не применимо в этой задаче (нет UI). Visual проверка — manual smoke.

### Done-критерий

_Из bugs.md фикса BUG-026:_ После N origin'ов на магистрали следующий
отходит от магистрали под прямым углом, образуя «гребёнку» / спираль /
решётку. Каждый новый off-road origin получает короткое ответвление от
магистрали к его периметру. Дополнительные стратегии (spiral/grid/template)
+ Settings переключатель + district-placement templates по family —
оформлены backlog-идеями для следующих итераций.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (Opus) · 2026-05-26 · Сложность: middle · Объём: M_

### Анализ текущего состояния

`DistrictPlanner.allocateAlongMagistrale` (`DistrictPlanner.swift:130-196`)
кладёт origin в полосе `mag.y ± offsetPerp=3` со `stepAlongMag=8` —
визуальная «колбаса» = BUG-026. `RoadNetwork.computeLoop`
(`RoadNetwork.swift:266-301`) кладёт ближнюю сторону петли на
`v=±1` от mag → если origin отнесён на v ≥ loopDepth+1=6, петля не
смыкается с mag, нужен явный branch-сегмент. `RoadNetwork` API:
`mainRoadCells / allCells / planDistrict / extendDistrictPlan /
nearestMainRoadPoint` — метода для одиночного branch'а нет, добавим.
CityEngine зовёт `allocateAlongMagistrale` в `applyTaskCompleted:336-342`
— единственная точка интеграции.

### Архитектурное решение

**N-порог:** `DistrictPlanner.branchingThreshold = 3`. Первые 3 origin'а —
old-логика; с 4-го (`currentIndex >= 3`) — branching.

**Branching формула** (mag горизонтальна, gy=midY — assumption):
```
i = currentIndex - branchingThreshold
layer = i / 4 + 1                            // 1,1,1,1, 2,2,2,2 ...
sub = i % 4
uSide = (sub / 2 == 0) ? +1 : -1             // forward/backward по mag.x
vSide = (sub % 2 == 0) ? +1 : -1             // выше/ниже mag.y
magIdx = centerIdx + uSide * layer * stepAlongMag       // stepAlongMag=8
m = mag[magIdx]
perpOffset = minDistrictRadius + (layer - 1) * minDistrictRadius  // 8,16,24
origin = GridPoint(x: m.x, y: m.y + vSide * perpOffset)
```
Origin далеко от mag (≥8) → визуальная гребёнка. Внутри ветки —
существующие water-skip и cross-project-skip циклы (как в старой
allocateAlongMagistrale `:180-192`).

**Road branch** — ответвление по вертикали от `m = nearestMainRoadPoint`
до ближней стороны будущей петли. Клетки: `(m.x, m.y + vSide * v)` для
`v = 1..loopDepth`. Это «периметр квартала» в смысле AC2 = vNear-клетка
ближней стороны петли. Чебышёвская длина branch = `loopDepth` клеток.

**RoadNetwork.extendBranchToOrigin(projectId:origin:otherProjectsClaims:biomeReader:) -> [GridPoint]:**
- `m = nearestMainRoadPoint(to: origin)`; если nil → return [].
- Если `|origin.y - m.y| <= loopDepth` (петля сама дотянется) → return [].
- Строит candidate-клетки `(m.x, m.y + vSide*v)` для `v = 1..loopDepth`,
  `vSide = sign(origin.y - m.y)`.
- **Hard-block:** любая candidate в `otherProjectsClaims` или
  `.sea/.river` (через biomeReader) → return [] (caller bump'нет idx
  и попробует next layer/uSide).
- Иначе `allCells.insert(...)` для каждой и возвращает массив для
  `onRoadCellsAdded?` в live. Дубли с будущей петлёй обрабатываются
  существующим `allCells.contains` guard в `planDistrict:127-129`.

**Replay / CityState:** branch не в `state` (CityState format не меняем).
Replay воссоздаёт branch через новый вызов в `CityEngine.syncRoadNetworkPlans`
(см. шаг 3.5). Determinism: формула чисто арифметическая, метод —
функция от `(mag, origin, claims, biomeReader)`.

### Пошаговая декомпозиция

1. **[AC1]** `DistrictPlanner.swift` — добавить `static let
   branchingThreshold = 3`. В `allocateAlongMagistrale` развилка: при
   `idx >= branchingThreshold` — формула выше (layer/sub/perpOffset);
   иначе — старая ветка. Внутри новой ветки сохранить существующие
   water-skip / cross-project-skip / maxAttempts циклы.

2. **[AC2]** `RoadNetwork.swift` — новый
   `extendBranchToOrigin(projectId:origin:otherProjectsClaims:biomeReader:) -> [GridPoint]`
   по контракту из «Архитектурное решение». Возвращает массив добавленных
   branch-клеток (без mag-клетки `m`).

3. **[AC3]** `CityEngine.swift:392-394` — в legacy ветке `templateName == nil`
   ПЕРЕД `roadNetwork?.planDistrict(...)` вызвать
   `extendBranchToOrigin(projectId: projectKey, origin: origin,
   otherProjectsClaims: otherClaims, biomeReader: biomeReader)`
   (`otherClaims` уже собран на `:329-333`); после `planDistrict` —
   `if !silent, !branchCells.isEmpty { onRoadCellsAdded?(branchCells) }`.
   Templated проекты пропускаем (followup в backlog).

3.5. **[AC7 replay]** `CityEngine.syncRoadNetworkPlans` (`:81-92`) — внутри
   цикла после `restorePlan` вызвать
   `rn.extendBranchToOrigin(projectId: project.id,
   origin: project.districtOrigin, otherProjectsClaims: [],
   biomeReader: biomeReader)` БЕЗ `onRoadCellsAdded` (replay silent).
   Без этого после restart engine `allCells` теряет branch → AC5 fail.
   `claims=[]` корректно: идемпотентность через `allCells` Set.

4. **[AC4+AC5]** Новый `Tests/CityDeveloperTests/DistrictBranchingPropertyTests.swift`
   (паттерн `DistrictNoOverlapPropertyTests` + attach `RoadNetwork` с
   `buildMainRoad(cols:256,rows:256,biomeReader: mock)` ДО ingest).
   - Тест AC4: ingest 5 проектов × 1 task → ≥ 2 origin'а с
     `|origin.y - midY| ≥ 8`.
   - Тест AC5: для каждого off-road origin'а (`|dy| > loopDepth`)
     BFS по 4-cardinal от `(origin.x, origin.y - sign(dy))` через
     `rn.allCells` достигает любой клетки `rn.mainRoadCells`
     (BFS лимит 100 шагов).

5. **[AC6+AC7]** Регресс-фильтры (см. ниже). Если deterministic-тест в
   `DistrictNoOverlapPropertyTests` падает — проверить, что формула чисто
   арифметическая (без Date/UUID/Random).

6. **[AC8]** Manual smoke: ingest 5 task_completed → гребёнка вместо
   линии; задокументировать в `Current.md`.

### Edge cases

- **Маленькая карта (50×50):** `magIdx` guard (`DistrictPlanner.swift:169`)
  + границы `[0,rows)` для `m.y+vSide*perpOffset` → bump idx; fallback
  `mag[centerIdx]` на `:195`.
- **Магистраль не east-west:** `buildMainRoad:59` фиксирует mag по gy=midY.
  Branching полагается на это (vSide вдоль gy). Закомментировать в коде:
  `// MAG-HORIZONTAL ASSUMPTION`.
- **Изогнутая mag (sea-shift):** `buildMainRoad:67-83` локально смещает по
  ±gy, массив сортирован по `k`. `mag[magIdx]` подхватывает реальную клетку;
  `nearestMainRoadPoint:93-105` — Manhattan, не требует прямой. OK.
- **Off-road origin в воде:** water-skip `:180-183` уже в основном loop
  branching ветки. Branch через воду → return [] из extendBranchToOrigin
  (см. контракт) → caller bump idx. «Мосты не делаем» — в скоупе.
- **Cross-project overlap:** `:186-192` cross-project-skip уже в loop'е.
  Branch через чужой footprint — return [] (см. контракт).
- **Branch уже есть:** `allCells` — Set, повторный вызов идемпотентен.
- **Replay-determinism:** формула чистая арифметика; метод — функция от
  (mag, origin, claims). AC7 OK.

### Файлы

**Изменить:** `DistrictPlanner.swift` (формула + константа),
`RoadNetwork.swift` (новый extendBranchToOrigin), `CityEngine.swift`
(~:392 вызов branch + ~:81 syncRoadNetworkPlans patch).

**Создать:** `Tests/CityDeveloperTests/DistrictBranchingPropertyTests.swift`
(2 теста).

**НЕ трогать:** `UnitPlanner.swift` (контракт roadCells/allCells неизменен),
`CityState/ProjectState` (формат не меняем), `GameScene` (branch
отрисуется через существующий `onRoadCellsAdded`), `DistrictTemplatePicker`
/ template path (branching MVP — только legacy projects).

### Команды проверки

```bash
swift build
swift test --filter DistrictBranchingPropertyTests
swift test --filter DistrictNoOverlapPropertyTests
swift test --filter UnitPlannerLegacyRingOverlapTests
swift test --filter DistrictPlannerBiomeAwareTests
swift test                            # полный регресс
```

Manual smoke: запустить app, удалить state.json + events.jsonl, ingest 5
task_completed разных проектов подряд через tasks.jsonl, проверить визуально
что districts расходятся гребёнкой а не линией.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен (визуальный smoke: 4-5 проектов → не линия)

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны
- [ ] +2 property-теста (AC4 perpendicular offset, AC5 road branch path)

#### Обновление документации
- [ ] `Current.md`: F-06 запись упоминает branching strategy
- [ ] `Bugs.md`: BUG-026 закрыт со ссылкой на коммит (с пометкой
      «частично — только branching стратегия; spiral/grid/template/templates
      в backlog»)
- [ ] `Backlog.md`: добавить followups — (1) Spatial-layout стратегии
      Settings переключатель; (2) district-placement templates по family;
      (3) мосты через воду для branching offset.
- [ ] Новые идеи → `Backlog.md`, новые баги → `Bugs.md`

---

## Статус

`[x] ready` — план готов, ожидает исполнителя.
- Lead-trigger: opus (P1 + multi-module: DistrictPlanner + RoadNetwork + property-tests; новый branching algorithm)

## Метаданные
- Создана PM: 2026-05-26
- Spec-review: approved (Opus, 1 круг — N-порог и имя метода extendBranchToOrigin делегированы лиду как design choices, не PM-дыры)
- Lead-разбор: 2026-05-26 (Opus, self plan-review fallback — Agent-tool недоступен)
- Готова к работе: 2026-05-26
- Завершена: —
- Коммит: —
