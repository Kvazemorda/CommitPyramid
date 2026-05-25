# TASK-057: Биомное распределение — каждый биом ≥ 5%, доминанта ≤ 55%

## Связь
- **F-15** из Concept.md (Биомы и генерация карты)
- **BUG-008** из Bugs.md (P1)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-25_

### Что хотим

Done-критерий F-15 говорит «карта ≥256×256 с не менее чем 4 разными биомами,
соединёнными плавными переходами». На свежем reset (smoke 2026-05-25) визуально
доминирует **песок** (sand/desert) — занимает ~60-70% карты; лес — узкие полоски
слева; горы — пятно сверху; луг — почти не виден. Жалоба пользователя:
«биомы скучные, всё одинаково».

Описание BUG-008 от 2026-05-23 говорило «80% зелёного grass» — это устарело;
актуально: **доминирует другой биом (desert), но эффект тот же — нет
визуального разнообразия 4-7 биомов**.

Нужно: на свежем seed карта должна иметь минимум 4 заметных биома, каждый из
которых занимает ≥5% площади (исключая sea — он pin'нутый компактный блоб ~5%,
river отключён в BUG-020). Доминирующий биом — не больше 55% карты. Если
дефолтный seed даёт «плохую» карту по этим порогам — на старте автоматически
ретраить с другим seed (или throw для smoke/CI, чтобы баг видно сразу), а не
тихо отдавать пользователю «скучную» карту.

### Пользовательский сценарий

1. Пользователь делает reset карты (через Settings или удаляя `worldmap.json`) —
   игра генерирует новую карту с дефолтным seed.
2. Визуально на свежей карте видны **минимум 4 биома** с заметными участками
   каждого: луг, лес, пустыня, горы (или камни). Нет «моря песка» или «моря
   травы», занимающего 60%+ карты.
3. Если seed дал «несбалансированную» карту (один биом >55% или меньше 4 биомов
   с долей ≥5%) — игра автоматически пробует следующие seed'ы (3-5 попыток)
   до получения сбалансированной карты, либо логирует warning в `errors.log` с
   фактическим распределением и продолжает с тем что есть (не падать).
4. На smoke в Settings → «Сбросить карту» → 5 raз подряд → каждый раз
   получается сбалансированная карта.
5. Проверка через CLI:
   ```bash
   # После reset → запустить статистику биомов (новый смолл-helper или unit test).
   # Ожидание: каждая категория из {meadow, forest, desert, mountain, stone}
   # ≥ 5% карты (256*256 = 65536 клеток → ≥3277 клеток каждого).
   ```

### Acceptance criteria

- [ ] **Инвариант распределения (post-retry):** **после retry** (до 5 попыток
      в `WorldMapProvider` или эквиваленте) карта содержит **≥4 из 5 неводных
      биомов** `{meadow, desert, forest, mountain, stone}`, каждый из них —
      **≥ 3277 клеток** (5% от 65536). Конкретно «какие 4» — не фиксируем
      (любые 4 из 5); 5-й может «провалиться» ниже 5% (например stone в
      жарких seed'ах). Sea — особый случай: pin'нутый блоб, **должен
      присутствовать (≥1 клетка)** но допустимо ≤5%. River — игнорируется
      (отключена в BUG-020).
- [ ] **Доминанта (post-retry):** ни один биом не занимает более **55%**
      карты (35840 клеток). Текущий порог `BiomeClassifier.maxDominantShare
      = 0.55` — должен оставаться, плюс реально срабатывать через retry.
- [ ] **Diversity-константа:** `BiomeClassifier.minDiversity` снизить с
      текущих 6 до **4** (5 неводных биомов минус 1 допустимый провал).
      Текущая семантика `validateDiversity` (throw `insufficientDiversity`)
      сохраняется как **strict-режим**; для production вызов
      `classify(world:strict:)` (или wrapper-метод) с `strict=false`
      возвращает результат без throw + WARN в лог, и WorldMapProvider
      делает retry на основании этого WARN.
- [ ] **Retry на bad seed:** `WorldMapProvider` при генерации карты, если
      первая попытка нарушает инварианты (доминанта >55% или <4 биомов
      ≥5%), инкрементирует seed (seed+1, seed+2, …, seed+4) и пробует
      ещё, до **5 попыток** всего. **Финальный seed** (тот, который дал
      сбалансированную карту, или последний из попыток) сохраняется в
      `worldmap.json` для воспроизводимости — это меняет contract: поле
      `seed` теперь = «фактически использованный», а не «запрошенный».
- [ ] **Fallback при полной неудаче:** если все 5 попыток не дали
      сбалансированную карту → лог WARN с фактическим распределением
      финальной попытки + продолжить с ней (не throw). Это runtime-страховка
      (не релакс AC) — property-тест ниже должен гарантировать, что в
      practice такого не будет.
- [ ] **Логирование:** в `errors.log` (или `ErrorsLog` API) при каждом
      `regenerate` writeать структурированную запись: `requested_seed`,
      `actual_seed`, `attempts`, и map `biome → percent` для финальной карты.
- [ ] **Smoke 5 reset'ов:** «Сбросить карту» в Settings × 5 (или удаление
      `worldmap.json` × 5) → визуально на каждой карте минимум **4 разных
      цвета** соответствующие палитре meadow/desert/forest/mountain/stone
      (нет «моря одного цвета»). Это **косвенно закрывает BUG-006** («цвета
      биомов сломаны — только 2-3 цвета»): если 4 биома видны ≥5% каждый,
      4+ цветов на экране гарантированы. BUG-006 переносится в Закрытые с
      пояснением «закрывается косвенно через TASK-057 — после balanced
      distribution цвета палитры видны автоматически; retest не требуется,
      палитра не менялась».
- [ ] **Property-тест:** добавить
      `Tests/CityDeveloperTests/BiomeDistributionPropertyTests.swift`. Два
      теста:
      - `test_TenSeeds_AfterRetry_AllBalanced`: для 10 захардкоженных
        seeds `[1, 42, 100, 1024, 9999, 12345, 67890, 314159, 271828, 1000000]`
        — **10/10 после retry** проходят инвариант (4+ биомов ≥5%, доминанта
        ≤55%). Если хоть один fail после 5 retry — тест fail.
      - `test_TenSeeds_WithoutRetry_MeasureBaseline`: для тех же 10 seeds —
        информационный counter «сколько проходят БЕЗ retry». Ожидание ≥7/10
        (мера «насколько retry реально нужен»). Этот тест не fail при <7,
        только пишет в `XCTContext` для observability.
- [ ] **Существующие тесты:** baseline 167 pass + 1 skip после TASK-056 не
      падает. `BiomeClassifierTests` существующие кейсы:
      - Если кейс зависит от `minDiversity=6` (throw на bad seed) — нужно
        либо обновить ожидание на `minDiversity=4`, либо явно использовать
        `strict=true` версию в тесте (если wrapper-API введён).
- [ ] **Closes:** BUG-008 переезжает в «Закрытые» с указанием коммита.
      **Перед закрытием — обновить описание BUG-008** в `Bugs.md` (текущее
      «80%+ grass» устарело — заменить на «доминирует один биом >55% карты —
      нет визуального разнообразия 4+ цветов»). F-15 в Current.md остаётся
      ✅, в деталях упомянуть пороги балансировки.
- [ ] **UI воспроизводимости:** в Settings → «Карта мира» рядом с полем
      seed показать «requested seed: N → actual: N+M (after K retries)» при
      несовпадении (для багрепортов). Если совпадает — показывать только
      одно число. Минимальная правка label, без UI-redesign.

### Что НЕ делаем (границы скоупа)

- НЕ переписываем noise-алгоритм (`NoiseFieldGenerator`, `NoiseMap`) —
  только классификацию.
- НЕ возвращаем реки (BUG-020 won't-fix). River остаётся отключённой.
- НЕ меняем размер карты (256×256), формат `worldmap.json`, версионирование.
- НЕ трогаем `seaBlobRadiusFraction` / `seaBlobCenter` — морской pin-блоб
  остаётся как есть (≈5% карты, нижне-правый угол).
- НЕ балансируем эстетику переходов (плавность simplex/Perlin) — только
  процентное распределение.
- НЕ добавляем UI визуализации статистики биомов (debug overlay) — лог в
  errors.log достаточно.
- **НЕ меняем семантику `validateDiversity` так, чтобы существующие
  `BiomeClassifierTests` падали.** Если тесты проверяют throw на старом
  `minDiversity=6` — либо обновить тесты под `minDiversity=4`, либо
  ввести параметр `strict: Bool = true` (back-compat для тестов) и
  использовать `strict: false` только в новом WorldMapProvider retry-flow.

### Edge cases

- [ ] **Все 5 seed'ов плохие.** Если для дефолтного seed + 4 ретраев ни один
      не даёт сбалансированную карту → fallback на последнюю попытку (лучше
      «несбалансированная карта», чем «нет карты»). В лог — WARN с цифрами.
      **Property-тест должен гарантировать, что для 10 захардкоженных seeds
      такого не возникает** (фикс не оставит проблему «pass только в проде»).
      Fallback — runtime-страховка для будущих seeds, не релаксация AC.
- [ ] **Sea-блоб всегда меньше 5%.** Sea — pin'нутый компактный, по дизайну
      ≤5%. Инвариант распределения **исключает** sea из проверки `≥5%` (но
      требует ≥1 клетку — sea должен присутствовать).
- [ ] **River = 0.** River отключён, в `BiomeKind` enum остаётся, но
      классификатор её не назначает. Инвариант **игнорирует** river.
- [ ] **Маленькая карта (для тестов).** Если кто-то вызвал классификатор на
      16×16 (как в существующих unit-тестах) — пороги `≥5%` могут стать
      нереалистичными (5% от 256 = 12 клеток, для 16×16 = 12 клеток = 5%,
      это OK; но для меньших — нет). PM-дефолт: пороги для production
      256×256; для unit-тестов <128×128 либо мягче, либо явный skip
      проверки на маленьких. Лид выбирает реализацию.
- [ ] **Seed=0 / детерминизм / contract `worldmap.json`.** При seed=0 каждый
      запуск даёт один и тот же результат. Если он несбалансированный —
      retry даст seed=1, 2, 3, 4. **Финальный seed** (тот, что фактически
      использовался) сохраняется в `worldmap.json` как новое значение поля
      `seed`. Это **меняет contract**: до этой задачи `seed` = «запрошенный
      пользователем», после — «фактически использованный после retry».
      Воспроизводимость **сохраняется** (загрузка `worldmap.json` даёт ту
      же карту), но если кто-то полагался на «seed = запрошенный» (например,
      в багрепортах) — это поведение меняется. Mitigation: в UI Settings
      (см. AC «UI воспроизводимости») показывать «requested → actual» при
      несовпадении.
- [ ] **Replay determinism (F-03 / F-15).** Изменение `worldmap.json` формат
      НЕ меняется (только поле seed может отличаться от исходного при retry).
      Существующие events.jsonl при replay не задеваются — карта генерится
      отдельно от event-replay.

### Зависимости

- **Blocked-by:** —
- **Soft-blocks:** —
- Внешние сервисы: —
- Миграции: формат `worldmap.json` (версия, поля) **не меняется**, но
  **семантика `seed`-поля меняется** (см. edge case 4): теперь это
  «фактически использованный после retry», а не «запрошенный пользователем».
  Старые `worldmap.json` загружаются как есть (seed внутри = и запрошенный,
  и фактический одновременно, ретрая не было).
- Связано:
  - **BUG-009** (water-skip в DistrictPlanner) — фикс TASK-030c уже сделан,
    не блокер.
  - **BUG-005** (Reset UI) — отдельный, не блокер (для smoke можно удалить
    файл руками).
  - **BUG-006** (цвета биомов сломаны) — **закрывается косвенно** через
    smoke-AC «4+ цветов видны после фикса» (палитра не менялась, причина
    «только 2-3 цвета» была именно перекошенным распределением).

### Дизайн

Не применимо (логика классификатора, не UI). Палитра биомов (`Palette.swift`)
не меняется — она была обновлена в commit 81b829a (упомянутый в BUG-006).

### Done-критерий

_Из Concept.md F-15:_ «При первом запуске генерируется карта ≥ 256×256 тайлов
с не менее чем 4 разными биомами, соединёнными плавными переходами. Карта
воспроизводима из seed. Кнопка «Сбросить карту» + подтверждение → новая
генерация, кварталы переразмещаются.»

PM-уточнение: фича работает (карта генерится, кнопка есть), но «4 разных
биома» в Done-критерии — это **необходимо но недостаточно**: текущая карта
формально имеет 4+ биомов, но один доминирует 60-70%. Задача добавляет
**измеримые пороги** к существующей фиче — без изменения её базовой формы.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-25_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

**В коде уже есть:**
- `Sources/CityDeveloper/World/BiomeClassifier.swift` — классификатор; константы
  `minDiversity = 6` (нужно → 4), `maxDominantShare = 0.55` (оставляем),
  `minBiomeShare = 0.05` (используется). Метод `classify(world:) throws -> BiomeMap`,
  приватный `validateDiversity(...)` бросает `insufficientDiversity(found:dominantShare:)`.
  Уже логирует распределение в `ErrorsLog`.
- `Sources/CityDeveloper/World/WorldMapProvider.swift` — фасад с
  `regenerate(newSeed:) -> NoiseMap`; **retry-логики нет**, при throw из classify
  падает наверх.
- `Sources/CityDeveloper/World/NoiseMap.swift` — Codable, поле `seed: Int64`
  (семантика изменится: «фактически использованный»).
- `Sources/CityDeveloper/World/NoiseFieldGenerator.swift` — GKPerlinNoise,
  детерминирован по seed. Не трогаем.
- `Sources/CityDeveloper/Game/MapReinitCoordinator.swift` — async-оркестратор
  reinit; в шаге 9 пишет `appSettings.mapSeed = newSeed`. Нужно: писать actual.
- `Sources/CityDeveloper/Data/AppSettings.swift` — `@Published var mapSeed: UInt64 = 0`;
  персистит в UserDefaults (версия 5+). Добавим эфемерное поле `requestedMapSeed`.
- `Sources/CityDeveloper/UI/SettingsView.swift:343` — `MapWorldSection`,
  текст «Текущий seed: \(settings.mapSeed)». Тут надо UI requested→actual.
- `Sources/CityDeveloper/Data/ErrorsLog.swift` — `static func write(_:)` строковый
  лог. API не меняем — формируем структурированную строку в WorldMapProvider.
- `Tests/CityDeveloperTests/BiomeClassifierTests.swift` — 10+ тестов, `testMinimumBiomeDiversity`
  опирается на `unique >= 6` (надо переориентировать на 4 + неводные).
- `concept/Bugs.md` — текущие тексты BUG-008 («80%+ grass»), BUG-006 («только 2-3 цвета»)
  нужно обновить ДО переноса в Закрытые.
- `concept/Current.md` — F-15 ✅, baseline 167 + 1 skip (после TASK-056).

**Связанные модули:**
- `Sources/CityDeveloper/App/AppDelegate.swift:36, 203, 269` — бутстрап
  WorldMapProvider, wire MapReinitCoordinator, resetCity. Сигнатуру init не
  трогаем; контракт `regenerate(newSeed:)` возвращает новый `RegenerateOutcome`.
- `Sources/CityDeveloper/Game/DistrictPlanner.swift` — использует
  `BiomeMapReader.isWater`, на новые пороги не реагирует.
- `Sources/CityDeveloper/Theme/Palette.swift` — цвета биомов, не трогаем.
- `Sources/CityDeveloper/World/WorldSeedStore.swift` — хранит seed в
  UserDefaults; будем сохранять **actual** seed после retry.

**Что переиспользуем:**
- ErrorsLog API as-is.
- Существующее `validateDiversity` — расширяем параметром `strict: Bool`.
- Структура `BiomeMap`, `NoiseMap`, `WorldMapStore.save/load` — без изменений
  схемы.
- `MapReinitCoordinator` — расширяем по контракту использования
  WorldMapProvider.

**Что нужно дописать:**
- В `BiomeClassifier`: тип `ClassificationOutcome` + публичный метод
  `classify(world:strict:) throws -> ClassificationOutcome`. Старый
  `classify(world:)` оборачивается в `strict=true` (back-compat).
- В `WorldMapProvider`: тип `RegenerateOutcome`, retry-цикл до 5 попыток
  (seed, seed+1 … seed+4) с logging.
- В `AppSettings`: `@Published var requestedMapSeed: UInt64 = 0` (не персистится).
- В `MapReinitCoordinator`: использовать новый `RegenerateOutcome`, записывать
  `mapSeed = actual`, `requestedMapSeed = requested`.
- В `SettingsView.MapWorldSection`: условный текст requested → actual.
- В `BiomeClassifierTests`: обновить ожидания `testMinimumBiomeDiversity`
  (4 неводных биома ≥5% вместо 6 unique).
- Новый `Tests/CityDeveloperTests/BiomeDistributionPropertyTests.swift` — 2 теста.
- `concept/Bugs.md`: переписать BUG-008 (актуальный текст), затем перенести
  BUG-008 и BUG-006 в Закрытые.
- `concept/Current.md`: дополнить детали F-15 (пороги, retry).

### Архитектурное решение

Новый контракт классификации **аддитивен** и **back-compat**.

**Важно про static/instance:** все методы `BiomeClassifier` сейчас
**`static`** (struct без storage). Новые методы тоже остаются `static` —
никакого перевода в инстанс-методы. Везде в скелетах ниже —
`BiomeClassifier.classify(...)` (НЕ `BiomeClassifier().classify(...)`).

1. `BiomeClassifier.classify(world:)` остаётся (strict), используется в
   существующих тестах. Семантически = `classify(world:strict: true).map`.
2. Новый `static func classify(world:strict:) throws -> ClassificationOutcome`
   возвращает полную метадату (распределение, dominantShare, неводных-выше-порога).
   При `strict=true` поведение совпадает со старым (throw `insufficientDiversity`
   при нарушении). При `strict=false` — **никогда** не бросает
   `insufficientDiversity`, только пишет WARN в ErrorsLog и возвращает результат
   (даже если `balanced=false`). `sizeMismatch` бросается всегда (это сломанные
   входные данные, не семантика).
3. WorldMapProvider делает retry на `strict=false`: для каждой попытки смотрит
   `outcome.balanced`, выходит при первом успехе. Если все 5 fail — берёт
   последнюю попытку, дополнительный WARN. Финальный seed сохраняется в
   `NoiseMap.seed` (через NoiseFieldGenerator) и `WorldSeedStore.saveSeed`.
4. **Retry-helper унифицирован для init и regenerate.** Вводится приватный
   синхронный helper `private func generateWithRetry(requested: Int64) -> RegenerateOutcome`,
   **не-throwing** (внутри обрабатывает все ошибки: `sizeMismatch` → лог и
   возврат с last successful или, если всех не было — критическая ошибка
   `fatalError` т.к. размер NoiseMap фиксирован 256 и не должен mismatch'ить
   в продакшен-flow). Этот helper вызывается:
   - из `init(...)` при cold start (нет cached worldmap.json или mismatch);
   - из `regenerate(newSeed:)`.
   - Init остаётся **non-throwing** (сигнатура неизменна для AppDelegate).
5. UI requested→actual через `AppSettings.requestedMapSeed` (эфемерно,
   `@Published`, в UserDefaults не пишется → схема `AppSettings` Codable
   не меняется, версия 5+ совместима).
6. **`AppDelegate.resetCity`** пересоздаёт `WorldMapProvider` через `init` —
   и init теперь сам внутри делает retry → resetCity получает retry «бесплатно».
   Дополнительно `resetCity` сохраняет `requestedMapSeed` в AppSettings
   ПЕРЕД пересозданием провайдера, а после — `mapSeed = worldMapProvider.seed`
   (фактический). См. шаг 3.

**Почему так:** минимум изменений в существующем API, существующие
`BiomeClassifierTests` не падают (strict-режим), retry изолирован в
`WorldMapProvider` (один слой, один helper), UI получает данные через
AppSettings без дополнительных каналов.

**Компромисс:** `RegenerateOutcome` нужно прокинуть через
`MapReinitCoordinator` для отображения в UI. Альтернатива — внутри
`regenerate(newSeed:)` обновлять `AppSettings` напрямую — отвергнута, т.к.
WorldMapProvider не должен знать про AppSettings (нарушение слоистости).
Коммуникация идёт по цепочке `WorldMapProvider.regenerate → outcome →
MapReinitCoordinator → AppSettings`.

**Cold-start через init**: outcome не прокидывается наверх (init синхронен,
AppDelegate.resetCity не получает outcome). Решение — `WorldMapProvider`
после `generateWithRetry` запоминает поля `lastRequestedSeed: Int64?` и
`lastAttempts: Int?` как `private(set)` — AppDelegate их читает после
вызова `WorldMapProvider(...)` для обновления AppSettings.requestedMapSeed/mapSeed.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй,
> возвращай задачу через сообщение.

0. **Pre-read: верификация инвариантов (≤10 минут)** `[AC:—]`
   - Прочитать `Sources/CityDeveloper/World/NoiseFieldGenerator.swift`.
     Убедиться (✅ уже верифицировано в Explore + лидом): `generate(seed:size:)`
     всегда возвращает `NoiseMap` с полями `height/temperature/humidity` ровно
     `size*size` (см. `[Float](repeating: 0, count: size * size)`). Это
     обоснование, почему `BiomeClassifierError.sizeMismatch` в
     `generateWithRetry` невозможен в production-flow с `size = NoiseMap.defaultSize`,
     и `fatalError` (см. шаг 2.5) — корректная защита от программного бага,
     а не runtime-condition.
   - Прочитать `Sources/CityDeveloper/Data/AppSettings.swift`. Подтвердить,
     что `Codable`-сериализация изолирована в `struct Persisted` (или иной
     структуре), и сам `AppSettings: ObservableObject` НЕ конформирует Codable
     напрямую. Это нужно для шага 5: новое `@Published var requestedMapSeed`
     не попадёт в persistence автоматически. Если допущение неверно
     (AppSettings сам Codable с автогенерируемыми CodingKeys) — добавить
     явный `CodingKeys` enum без `requestedMapSeed` в рамках шага 5.

1. **BiomeClassifier: ClassificationOutcome + параметр `strict` (все методы static)** `[AC:1,2,3]`
   - Файл: `Sources/CityDeveloper/World/BiomeClassifier.swift`
   - Изменить константу `static let minDiversity: Int = 4` (было 6).
   - Добавить новый тип в этот же файл (рядом с `BiomeClassifierError`):
     ```swift
     struct ClassificationOutcome {
       let map: BiomeMap
       let distribution: [BiomeKind: Int]
       let total: Int
       let dominantShare: Double           // max share среди всех биомов
       let nonWaterAboveThreshold: Int      // count of non-water biomes with share ≥ minBiomeShare
       let seaPresent: Bool                 // ≥1 клетка sea (информационно, НЕ блокирует balanced)
       let balanced: Bool                   // dominantShare ≤ maxDominantShare && nonWaterAboveThreshold ≥ minDiversity
     }
     ```
     **Важно:** `seaPresent` НЕ входит в формулу `balanced`. Причина: `seaBlobCenter`
     и `seaBlobRadiusFraction` фиксированы (см. `BiomeClassifier.swift:51,60`),
     retry seed+k не двигает центр блоба → если блоб «съели» как лужу (<minSeaArea),
     никакой retry не поможет. `seaPresent` — диагностическое поле; если `false` —
     отдельный WARN в ErrorsLog (см. шаг 1, validateDiversity), но retry не
     запускается из-за отсутствия моря. PM-постановка про `≥1 клетку` sea
     отражена в WARN-логе и в самом том, что markSea/seaBlob уже работает
     с pin'нутыми константами.
     `minBiomeShare = 0.05` (уже есть, переиспользуем).
   - **Все методы BiomeClassifier — `static`** (как сейчас). Никаких
     инстансов не создаём.
   - Изменить публичный API: добавить
     `static func classify(world: NoiseMap, strict: Bool) throws -> ClassificationOutcome`.
     Сохранить старый `static func classify(world:) throws -> BiomeMap` как враппер:
     `try classify(world: world, strict: true).map`.
   - Внутри `static func classify(world:strict:)`:
     1. Проверить размеры (`sizeMismatch` throw — как сейчас, **всегда**).
     2. Сформировать `cells: [BiomeKind]` как сейчас (`classifyLand` + `markSea`).
     3. Построить `BiomeMap(width: W, height: H, cells: cells)`.
     4. Посчитать `distribution: [BiomeKind: Int]` (одиночный проход).
     5. Вычислить `dominantShare = Double(distribution.values.max() ?? 0) / Double(total)`.
     6. `nonWaterAboveThreshold` = количество биомов из набора
        `{.meadow, .desert, .forest, .mountain, .stone}`, у которых
        `Double(count) / Double(total) >= minBiomeShare`.
     7. `seaPresent = (distribution[.sea] ?? 0) > 0` (информационно).
     8. `balanced = dominantShare <= maxDominantShare && nonWaterAboveThreshold >= minDiversity`.
     9. Сформировать `outcome = ClassificationOutcome(...)`.
     10. Вызвать `try validateDiversity(outcome: outcome, strict: strict)` — он
        либо ничего не делает (success / non-strict warn), либо бросает
        `insufficientDiversity`.
     11. Вернуть outcome.
   - Заменить `private static func validateDiversity(cells:total:)` на
     `private static func validateDiversity(outcome: ClassificationOutcome, strict: Bool) throws`:
     - Логирование распределения в ErrorsLog оставить как было (используя
       `outcome.distribution` / `outcome.total`).
     - Если `outcome.balanced` → return (success-case логировать как и сейчас).
     - Если `!outcome.balanced`:
       - Всегда писать WARN в ErrorsLog с фактическим распределением (как сейчас).
       - Если `strict == true` → throw `insufficientDiversity(found: outcome.nonWaterAboveThreshold, dominantShare: outcome.dominantShare)`.
       - Если `strict == false` → return (не throw).
     - **Дополнительно:** если `!outcome.seaPresent` — отдельный WARN
       `ErrorsLog.write("BiomeClassifier: sea blob absent (markSea removed all sea cells as < minSeaArea)")`,
       НЕ throw, НЕ влияет на balanced.
   - **Поведенческая совместимость:** старые тесты ожидают throw при
     перекосе → strict=true даёт тот же throw, но с новой семантикой
     `found` (теперь это `nonWaterAboveThreshold`, не `unique`-count).
     Это обновим в шаге 7.
   - Скелет:
     ```swift
     static let minDiversity: Int = 4
     // ...
     static func classify(world: NoiseMap) throws -> BiomeMap {
       try classify(world: world, strict: true).map
     }
     static func classify(world: NoiseMap, strict: Bool) throws -> ClassificationOutcome {
       // build cells, BiomeMap, distribution, outcome metrics
       // try validateDiversity(outcome: outcome, strict: strict)
       // return outcome
     }
     private static func validateDiversity(outcome: ClassificationOutcome, strict: Bool) throws {
       // ErrorsLog.write(...) (mirror current logging)
       if !outcome.balanced && strict {
         throw BiomeClassifierError.insufficientDiversity(
           found: outcome.nonWaterAboveThreshold,
           dominantShare: outcome.dominantShare
         )
       }
     }
     ```

2. **WorldMapProvider: RegenerateOutcome + retry helper (init + regenerate)** `[AC:4,5,6]`
   - Файл: `Sources/CityDeveloper/World/WorldMapProvider.swift`
   - Добавить тип на уровне модуля (или внутри файла):
     ```swift
     struct RegenerateOutcome {
       let map: NoiseMap
       let requestedSeed: Int64
       let actualSeed: Int64
       let attempts: Int           // фактическое число попыток (1..5)
       let finalBalanced: Bool
       let distribution: [BiomeKind: Int]
     }
     ```
   - Добавить `private(set) var lastRequestedSeed: Int64?` и
     `private(set) var lastAttempts: Int?` — для доступа из AppDelegate после
     init (см. шаг 3). Опциональные: при загрузке cached worldmap.json
     остаются `nil`.
   - **Helper:** `private func generateWithRetry(requested: Int64) -> RegenerateOutcome`.
     Синхронный, **non-throwing**. Реализация:
     1. `var lastBalancedSeed: Int64? = nil`; `var lastBalancedMap: NoiseMap? = nil`;
        `var lastBalancedOutcome: ClassificationOutcome? = nil`.
     2. `var lastAnyMap: NoiseMap? = nil`; `var lastAnyOutcome: ClassificationOutcome? = nil`;
        `var lastAnySeed: Int64? = nil`.
     3. `var attemptsUsed = 0`.
     4. Цикл `for attempt in 0..<5`:
        - `trySeed = requested &+ Int64(attempt)`.
        - `let noise = NoiseFieldGenerator.generate(seed: trySeed, size: NoiseMap.defaultSize)`.
        - `attemptsUsed = attempt + 1`.
        - Явный do/catch, **БЕЗ `try?`**:
          ```swift
          do {
            let outcome = try BiomeClassifier.classify(world: noise, strict: false)
            lastAnyMap = noise; lastAnyOutcome = outcome; lastAnySeed = trySeed
            if outcome.balanced {
              lastBalancedSeed = trySeed
              lastBalancedMap = noise
              lastBalancedOutcome = outcome
              break
            } else {
              ErrorsLog.write("WorldMapProvider attempt \(attempt+1)/5 seed=\(trySeed) NOT balanced (dominant=\(String(format: "%.2f", outcome.dominantShare * 100))%, nonWater>=5%: \(outcome.nonWaterAboveThreshold))")
            }
          } catch BiomeClassifierError.sizeMismatch {
            ErrorsLog.write("WorldMapProvider FATAL sizeMismatch at seed=\(trySeed) — abort retry")
            break  // sizeMismatch не лечится retry
          } catch {
            ErrorsLog.write("WorldMapProvider attempt \(attempt+1)/5 seed=\(trySeed) unexpected error: \(error)")
          }
          ```
     5. Выбор chosen-карты:
        - Если есть `lastBalancedMap` → используем её.
        - Иначе если есть `lastAnyMap` → используем её (fallback).
        - Иначе (`sizeMismatch` сразу или странный сбой) — `fatalError(
          "WorldMapProvider: no map produced (sizeMismatch or unexpected). NoiseMap.defaultSize is fixed; this should never happen in production.")`.
     6. Сформировать `outcome` для возврата:
        - `actualSeed = lastBalancedSeed ?? lastAnySeed!`
        - `chosenMap = lastBalancedMap ?? lastAnyMap!`
        - `finalBalanced = (lastBalancedSeed != nil)`
        - `distribution = (lastBalancedOutcome ?? lastAnyOutcome)!.distribution`
     7. Финальный structured WARN/INFO:
        ```
        ErrorsLog.write("WorldMapProvider regenerate requested=\(requested) actual=\(actualSeed) attempts=\(attemptsUsed) balanced=\(finalBalanced) distribution={\(formatDistribution(distribution, total: ...))}")
        ```
        `formatDistribution` — приватная локальная функция, формирует
        `meadow:20.5%,desert:30.2%,...` для биомов с count>0.
     8. **Важно:** chosenMap должна нести `seed = actualSeed`. NoiseFieldGenerator
        уже встраивает seed в возвращаемый NoiseMap (см. NoiseFieldGenerator.generate)
        — проверить в шаге 0 (read), если нет — пересоздать карту через
        `NoiseFieldGenerator.generate(seed: actualSeed, ...)` ещё раз для
        chosen-актуала. **Поскольку в цикле для каждой попытки уже generate
        вызывается с trySeed**, выбранная map уже содержит actualSeed —
        проверка излишня, но в комментарии зафиксировать.
     9. `return RegenerateOutcome(map: chosenMap, requestedSeed: requested, actualSeed: actualSeed, attempts: attemptsUsed, finalBalanced: finalBalanced, distribution: distribution)`.
   - **Изменить `init(seedStore:mapStore:)`** (строки 21–55):
     - Шаг 1 (load seed) — без изменений.
     - Шаг 2 (load map):
       - Если cached map валиден (seed/version/size совпадают) — использовать
         как есть (НЕ retry; AC: cached worldmap = «источник истины», см. edge
         case ниже). `self.lastRequestedSeed = nil`, `self.lastAttempts = nil`.
       - Иначе:
         - `let outcome = generateWithRetry(requested: resolvedSeed)`.
         - `mapStore.save(outcome.map)`.
         - `WorldSeedStore.saveSeed(outcome.actualSeed)`.
         - `self.seed = outcome.actualSeed`, `self.map = outcome.map`.
         - `self.lastRequestedSeed = outcome.requestedSeed`, `self.lastAttempts = outcome.attempts`.
   - **Изменить `regenerate(newSeed:)`** (строки 60–69):
     - Сигнатура: `@discardableResult func regenerate(newSeed: Int64? = nil) -> RegenerateOutcome`.
     - Внутри:
       ```swift
       let requested = newSeed ?? Int64.random(in: .min ... .max)
       let outcome = generateWithRetry(requested: requested)
       seed = outcome.actualSeed
       map = outcome.map
       mapStore.save(outcome.map)
       WorldSeedStore.saveSeed(outcome.actualSeed)
       lastRequestedSeed = outcome.requestedSeed
       lastAttempts = outcome.attempts
       return outcome
       ```

3. **AppDelegate: подхватить новый контракт + resetCity покрыт retry через init** `[AC:4,9]`
   - Файл: `Sources/CityDeveloper/App/AppDelegate.swift`
   - **3.1 — все вызовы `regenerate(newSeed:)`:** найти через
     `grep -n "regenerate(newSeed" Sources/CityDeveloper/App/AppDelegate.swift`.
     Возвращаемый тип сменился `NoiseMap → RegenerateOutcome`. Там, где нужно
     `NoiseMap` — использовать `outcome.map`. Прямых вызовов `regenerate`
     из AppDelegate сейчас нет (regenerate вызывается через MapReinitCoordinator)
     — но проверить grep'ом.
   - **3.2 — `resetCity(replaySince:)` (строки 268–311):** этот путь
     пересоздаёт `WorldMapProvider` через `init`, а не через `regenerate`.
     Init теперь сам делает retry (см. шаг 2 init), поэтому retry работает.
     **Дополнительно** добавить после строки 311 (после пересоздания провайдера):
     ```swift
     // TASK-057: requested/actual seed для UI requested→actual
     appSettings.requestedMapSeed = UInt64(bitPattern: newSeed)
     appSettings.mapSeed = UInt64(bitPattern: worldMapProvider.seed)
     appSettings.save()
     ```
     (`newSeed` — переменная из строки 296; `worldMapProvider.seed` — фактический
     после retry).
   - **3.3 — Wire callbacks после reset:** проверить, что новый
     `worldMapProvider` пере-привязан к `mapReinitCoordinator.worldMapProvider`
     (строка 203 в исходном порядке — но при resetCity провайдер пересоздан, нужно
     обновить ссылку). Найти в строках 313+ есть ли `mapReinitCoordinator.worldMapProvider = worldMapProvider`.
     Если нет — добавить (чтобы будущие reinit использовали новый провайдер,
     а не старый). Если уже есть — без изменений.
   - Изменения: ~5–10 строк.

4. **MapReinitCoordinator: requested/actual в AppSettings** `[AC:4,9]`
   - Файл: `Sources/CityDeveloper/Game/MapReinitCoordinator.swift`
   - В методе `reinit(newSeed: UInt64?) async throws` (строка 64):
     1. Заменить
        `let map = worldMapProvider.regenerate(newSeed: Int64?(newSeed))`
        на:
        ```swift
        let outcome = worldMapProvider.regenerate(newSeed: newSeed.map { Int64(bitPattern: $0) })
        ```
     2. В шаге 9 «Persist новый seed в AppSettings» вместо
        `appSettings.mapSeed = newSeed ?? ...` сделать:
        ```swift
        appSettings.requestedMapSeed = UInt64(bitPattern: outcome.requestedSeed)
        appSettings.mapSeed = UInt64(bitPattern: outcome.actualSeed)
        appSettings.save()
        ```
   - Если в координаторе есть точки, передающие `NoiseMap` дальше
     (например, `scene.handleMapReinitComplete()`) — использовать `outcome.map`.

5. **AppSettings: эфемерное поле `requestedMapSeed`** `[AC:9]`
   - Файл: `Sources/CityDeveloper/Data/AppSettings.swift`
   - Добавить рядом с `mapSeed`:
     ```swift
     @Published var requestedMapSeed: UInt64 = 0
     ```
   - **НЕ** включать в персистенцию.
   - Проверка перед правкой: в `AppSettings.swift` `Codable` реализован
     через отдельную struct `Persisted` (как было обнаружено в Explore-карте),
     а сам `AppSettings` НЕ Codable. Значит, добавление `@Published`-поля в
     `AppSettings` НЕ ломает сериализацию автоматически (поле не попадёт в
     `Persisted`). Главное — не добавлять `requestedMapSeed` в `Persisted`
     и в его `init(from settings: AppSettings)` / `applyTo(settings:)` хелперы.
     **Если** Explore-карта неточна и `AppSettings` сам Codable с
     `CodingKeys` — добавить явный `CodingKeys` enum (без `requestedMapSeed`).
     Исполнитель должен это проверить **первым шагом**.
   - Версия `AppSettings` персистентного формата **не меняется**.
   - **Edge case:** при старте `requestedMapSeed = 0`, `mapSeed` загружен
     из UserDefaults. Если до первого reset они равны (старый кэш) —
     UI покажет «Текущий seed: N» (см. шаг 6, условие
     `requestedMapSeed != 0 && requestedMapSeed != mapSeed`).

6. **SettingsView.MapWorldSection: UI requested → actual** `[AC:9]`
   - Файл: `Sources/CityDeveloper/UI/SettingsView.swift` (строка 343,
     `MapWorldSection`)
   - Найти строку (около 352): `Text("Текущий seed: \(settings.mapSeed)")`.
   - Заменить на условный текст:
     ```swift
     if settings.requestedMapSeed != 0 &&
        settings.requestedMapSeed != settings.mapSeed {
       Text("Seed: requested \(settings.requestedMapSeed) → actual \(settings.mapSeed)")
     } else {
       Text("Текущий seed: \(settings.mapSeed)")
     }
     ```
   - Стилизация — наследует существующую (`.font(.system(...))` и т.п.).
   - Никаких новых state-переменных не добавлять.

7. **Обновить тесты: BiomeClassifierTests + MapReinitCoordinatorTests** `[AC:8]`
   - **7.1 — `Tests/CityDeveloperTests/BiomeClassifierTests.swift`:**
     - Все вызовы — `BiomeClassifier.classify(...)` (static), как сейчас.
     - `testMinimumBiomeDiversity` (строка 35): сейчас проверяет
       `unique >= minDiversity` (6). Заменить на:
       ```swift
       let outcome = try BiomeClassifier.classify(world: noise, strict: false)
       XCTAssertGreaterThanOrEqual(outcome.nonWaterAboveThreshold, 4)
       XCTAssertTrue(outcome.seaPresent)
       ```
     - `testDominantBiomeDoesNotExceedThreshold` (строка 44): уже работает
       с `0.55`, не трогать. Проверить, что не падает.
     - Если есть тесты, явно завязанные на `insufficientDiversity` с
       `found == oldUniqueCount` — обновить ожидание (теперь
       `found = nonWaterAboveThreshold`).
     - Сохранить `testSizeMismatchThrows` без изменений.
   - **7.2 — `Tests/CityDeveloperTests/MapReinitCoordinatorTests.swift`:**
     - `testReinitChangesSeedAndPersists` (строка 42): сейчас проверяет
       `provider.seed == Int64(bitPattern: 42)` и `loaded?.seed == ...`.
       После retry actualSeed может стать `42 + k` (k ∈ 0..4). **Заменить
       проверки на range-aware:**
       ```swift
       let targetSeedRaw: UInt64 = 42
       let requested = Int64(bitPattern: targetSeedRaw)
       try await stack.coord.reinit(newSeed: targetSeedRaw)
       let actual = stack.provider.seed
       XCTAssertTrue(
         actual >= requested && actual <= (requested &+ 4),
         "actual seed \(actual) must be within retry window [\(requested), \(requested + 4)]"
       )
       let loaded = WorldMapStore(url: dir.appendingPathComponent("worldmap.json")).load()
       XCTAssertNotNil(loaded)
       XCTAssertEqual(loaded?.seed, actual, "worldmap.json seed must equal actual (post-retry)")
       ```
     - `testReinitDeletesSnapshot` (строка 57): использует `newSeed: 7`,
       не проверяет seed-значение → не трогать.
     - Остальные `testReinit*` — пробежать глазами; если есть прямые
       сравнения `provider.seed == requested` — обновить аналогично.
   - **Самопроверка:** после правок локально
     `swift test --filter BiomeClassifierTests` и
     `swift test --filter MapReinitCoordinatorTests`, должно быть зелёным.

8. **Новый property-тест: BiomeDistributionPropertyTests** `[AC:7]`
   - Файл: `Tests/CityDeveloperTests/BiomeDistributionPropertyTests.swift` (новый)
   - 10 захардкоженных seeds:
     `[1, 42, 100, 1024, 9999, 12345, 67890, 314159, 271828, 1000000]`
   - **Тест 1: `test_TenSeeds_AfterRetry_AllBalanced`**
     - Для каждого seed симулировать retry: пробовать `seed, seed+1, …, seed+4`,
       классифицировать через `BiomeClassifier.classify(world: noise, strict: false)`.
     - Засчитывать seed как success, если **хоть одна** из 5 попыток вернула
       `outcome.balanced == true`.
     - Ожидание: **10/10** success. Если хотя бы 1 fail — `XCTFail("seed N failed")`.
   - **Тест 2: `test_TenSeeds_WithoutRetry_MeasureBaseline`**
     - Для каждого seed — одна попытка, считать `outcome.balanced`.
     - Не fail при <10. Только `print("Baseline pass rate (no retry): \(passes)/10")`.
     - Никаких XCTAssert, информационный.
   - Скелет (static-вызовы, без `try?`, явный do/catch на `sizeMismatch`):
     ```swift
     import XCTest
     @testable import CityDeveloper

     final class BiomeDistributionPropertyTests: XCTestCase {
       private let seeds: [Int64] = [1, 42, 100, 1024, 9999, 12345, 67890, 314159, 271828, 1000000]

       func test_TenSeeds_AfterRetry_AllBalanced() throws {
         for seed in seeds {
           var success = false
           for attempt in 0..<5 {
             let trySeed = seed &+ Int64(attempt)
             let noise = NoiseFieldGenerator.generate(seed: trySeed, size: NoiseMap.defaultSize)
             do {
               let outcome = try BiomeClassifier.classify(world: noise, strict: false)
               if outcome.balanced { success = true; break }
             } catch {
               XCTFail("unexpected throw for seed=\(trySeed): \(error)")
               return
             }
           }
           XCTAssertTrue(success, "seed \(seed) failed after 5 retries")
         }
       }

       func test_TenSeeds_WithoutRetry_MeasureBaseline() throws {
         var passes = 0
         for seed in seeds {
           let noise = NoiseFieldGenerator.generate(seed: seed, size: NoiseMap.defaultSize)
           let outcome = try BiomeClassifier.classify(world: noise, strict: false)
           if outcome.balanced { passes += 1 }
         }
         print("Baseline pass rate (no retry): \(passes)/10")
       }
     }
     ```
   - **Edge case (карта 256×256):** generate с size=256 — может быть
     медленно. Если суммарное время тестов превышает 30с — пометить
     как известное и оставить; в crunch — отдельный issue.

9. **Bugs.md: обновить BUG-008 описание, закрыть BUG-008 и BUG-006** `[AC:10]`
   - Файл: `concept/Bugs.md`
   - **Шаг 9.1 (ДО закрытия):** найти запись BUG-008 в Активных, заменить
     текст «80%+ карты один биом (зелёный grass), остатки видны только белым»
     на: «доминирует один биом (>55% карты, в т.ч. desert/sand) — нет
     визуального разнообразия 4+ цветов на свежем seed».
   - **Шаг 9.2:** перенести BUG-008 в раздел «Закрытые» с пометкой
     `Закрыт TASK-057, commit <будет добавлен после merge>`.
   - **Шаг 9.3:** перенести BUG-006 в «Закрытые» с текстом «Закрывается
     косвенно через TASK-057 (balanced distribution делает 4+ цвета палитры
     видимыми автоматически); палитра не менялась, retest не требуется.»
   - `git diff concept/Bugs.md` должен показать: одно описание изменено,
     две записи перемещены из «Активные» в «Закрытые».

10. **Current.md: дополнить F-15 порогами** `[AC:10]`
    - Файл: `concept/Current.md`
    - Найти раздел F-15, оставить статус ✅. В деталях упомянуть:
      «Пороги балансировки: `BiomeClassifier.maxDominantShare = 0.55`,
      `minDiversity = 4` (неводных биомов ≥5% каждый), retry до 5 попыток
      в `WorldMapProvider` при bad seed. Финальный seed сохраняется в
      `worldmap.json` (семантика: фактически использованный после retry).»
    - Обновить дату последнего изменения раздела на `2026-05-25`.

### Edge cases (явно обработать)

- [ ] **Все 5 seed'ов плохие.** WorldMapProvider шаг 2.5 — fallback на
  последнюю попытку с WARN. Property-тест в шаге 8 гарантирует, что для
  10 хардкод seeds такого не возникает.
- [ ] **Sea-блоб <5% или полностью «съеден» как лужа.** В
  `ClassificationOutcome.nonWaterAboveThreshold` явно фильтруем по
  `{.meadow, .desert, .forest, .mountain, .stone}` — sea не считается.
  `seaPresent` — отдельное информационное поле; НЕ блокирует `balanced` и
  retry (см. шаг 1, обоснование). `BiomeClassifier.swift:51`
  (`seaBlobRadiusFraction = 0.22`), строка 60 (`seaBlobCenter`) — не трогаем.
  Если `markSea` удалит блоб как лужу при экзотическом seed — WARN в
  ErrorsLog, retry не запускается (центр блоба фиксирован, retry бессмыслен).
- [ ] **River = 0.** `BiomeKind.river` существует, классификатор его не
  назначает (закомментировано после BUG-020). В `nonWaterAboveThreshold`
  не включаем — `river.isWater = true`. Никаких новых проверок.
- [ ] **Маленькая карта (16×16) в unit-тестах.** 5% от 256 = 13 клеток.
  `nonWaterAboveThreshold` использует `count >= total * minBiomeShare` —
  для 16×16 даёт 13 (норма). НО семантически на 16×16 ожидать 4 биомов ≥5%
  нереалистично. Решение: тесты, использующие маленькие карты
  (`BiomeClassifierTests` с 16×16), вызывают `classify(world:strict:false)` —
  получают outcome без throw, можно проверить только конкретные свойства
  (sea, isolated puddles). Не вызывать `classify(world:)` (strict) на
  16×16, если тест не про throw.
- [ ] **Seed=0 + overflow при retry.** `requested &+ Int64(attempt)`:
  `Int64.max + 1` через `&+` оборачивается в `Int64.min`. Это допустимо —
  всё равно даёт детерминированный seed, NoiseFieldGenerator работает с
  любым Int64. Граничный кейс: на практике пользователь не вводит
  `Int64.max - 4`.
- [ ] **AppSettings.requestedMapSeed эфемерно.** При старте всегда `0`,
  даже если `mapSeed != 0` (сохранён с прошлой сессии). UI условие
  `requestedMapSeed != 0 && requestedMapSeed != mapSeed` — при значении 0
  не показывает requested→actual, что корректно (пользователь не делал
  reset в этой сессии).
- [ ] **Cached worldmap.json при init.** Если файл существует и валиден —
  не делаем retry, используем как есть (даже если несбалансирован). Это
  consistent с `worldmap.json` как «источник истины» для replay
  determinism (F-03). Логировать WARN при load несбалансированной кэш-карты
  — опционально, не блокер.
- [ ] **MapReinitCoordinator backup state.json.** Не зависит от retry
  (происходит до `regenerate`), не меняется.
- [ ] **Baseline тестов.** Пред-TASK-057: 167 + 1 skip. Пост-TASK-057:
  167 + 2 (новые property-тесты) + 1 skip = 169 + 1 skip. Существующие
  `BiomeClassifierTests` — 10 тестов, должны проходить после правок
  шага 7.

### Файлы для изменения

- `Sources/CityDeveloper/World/BiomeClassifier.swift` — `minDiversity → 4`,
  тип `ClassificationOutcome`, метод `classify(world:strict:)`,
  расширение `validateDiversity`.
- `Sources/CityDeveloper/World/WorldMapProvider.swift` — тип
  `RegenerateOutcome`, retry-loop в `regenerate(newSeed:)` и в helper
  `generateWithRetry(requested:)`.
- `Sources/CityDeveloper/App/AppDelegate.swift` — обновить вызовы
  `regenerate` под новый возвращаемый тип.
- `Sources/CityDeveloper/Game/MapReinitCoordinator.swift` — использовать
  `outcome.actualSeed/requestedSeed`, обновить `AppSettings`.
- `Sources/CityDeveloper/Data/AppSettings.swift` — `@Published var requestedMapSeed`.
- `Sources/CityDeveloper/UI/SettingsView.swift` — условный текст
  requested → actual в `MapWorldSection`.
- `Tests/CityDeveloperTests/BiomeClassifierTests.swift` — обновить
  ожидания (`testMinimumBiomeDiversity` и зависимые).
- `Tests/CityDeveloperTests/BiomeDistributionPropertyTests.swift` (новый) —
  2 property-теста.
- `concept/Bugs.md` — переписать BUG-008, перенести BUG-008 и BUG-006 в Закрытые.
- `concept/Current.md` — дополнить F-15 порогами.

### Файлы НЕ трогать

- `Sources/CityDeveloper/World/NoiseFieldGenerator.swift` — алгоритм
  noise, изменения сломают детерминизм/семенные тесты.
- `Sources/CityDeveloper/World/NoiseMap.swift` — формат `worldmap.json`,
  миграция не нужна. Только семантика `seed` (тот же тип, новый смысл).
- `Sources/CityDeveloper/World/WorldMapStore.swift` — Codable формат,
  атомарная запись — без изменений.
- `Sources/CityDeveloper/Data/CityState.swift` (BiomeKind enum) — все 7
  значений остаются.
- `Sources/CityDeveloper/Theme/Palette.swift` — палитра обновлена ранее
  (commit 81b829a), не трогаем.
- `Sources/CityDeveloper/Game/DistrictPlanner.swift` — `BiomeMapReader`
  contract не меняется.
- `Sources/CityDeveloper/Data/ErrorsLog.swift` — API as-is, форматирование
  строки выполняется в WorldMapProvider.
- `concept/Concept.md` — Done-критерии F-15 не меняем, дополнения
  только в `Current.md`.
- `Tests/CityDeveloperTests/MapReinitCoordinatorTests.swift` — должен
  продолжать проходить; если падает из-за смены типа `regenerate` —
  поправить ровно те asserts, что прямо зависят от типа (но логика
  reinit не меняется).
- `Tests/CityDeveloperTests/DistrictNoOverlapPropertyTests.swift` —
  TASK-056, не трогать.

### Команды проверки (для DoD)

- Компиляция: `swift build`
- Тесты: `swift test` — ожидание `169 + 1 skip` (167 + 2 новых property).
- Прицельно классификатор: `swift test --filter BiomeClassifierTests`
- Прицельно property: `swift test --filter BiomeDistributionPropertyTests`
- Прицельно reinit: `swift test --filter MapReinitCoordinatorTests`
- Ручная проверка (smoke):
  1. `swift run CityDeveloper` (или из Xcode) → запуск приложения.
  2. Settings → «Сбросить карту» × 5 подряд.
  3. На каждом reset — визуально 4+ разных цветов биомов (нет «моря
     песка/травы»).
  4. Открыть `~/Library/Application Support/CommitPyramid/errors.log` —
     найти 5 структурированных записей `WorldMapProvider regenerate
     requested=X actual=Y attempts=K balanced=true distribution={...}`.
  5. В Settings → если на reset `actual != requested` — текст «Seed:
     requested N → actual M». Если совпадает — «Текущий seed: N».

### Сложность

`senior`

**Обоснование:** 9 файлов (BiomeClassifier, WorldMapProvider, AppDelegate,
MapReinitCoordinator, AppSettings, SettingsView, BiomeClassifierTests,
MapReinitCoordinatorTests, новый property-тест) + 2 doc-файла (Bugs.md,
Current.md). Новые типы (`ClassificationOutcome`, `RegenerateOutcome`),
смена семантики `NoiseMap.seed`-поля (фактический после retry, contract
change для UI/багрепортов), back-compat для 10 BiomeClassifierTests
(strict-режим). Retry-helper унифицирован для двух точек входа (init +
regenerate), требует аккуратной обработки `sizeMismatch` без `try?`.
Координация по цепочке `WorldMapProvider → MapReinitCoordinator →
AppSettings → SettingsView` + параллельная цепочка `WorldMapProvider.init →
AppDelegate.resetCity → AppSettings`. Существующий
`MapReinitCoordinatorTests.testReinitChangesSeedAndPersists` требует
range-aware проверки (а не === requested). Архитектурно — аддитивно, но
нюансов и точек интеграции достаточно для senior.

### Ожидаемое время

M (≤1д) — на верхней границе. Если исполнитель junior — переоформить как L.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: senior_

### Definition of Done

#### Функциональные
- [ ] Инвариант распределения выполняется на дефолтном seed (после retry)
- [ ] Property-тест ловит регрессию (если вернуть `minBiomeShare=0`)
- [ ] Smoke: 5 reset'ов подряд → 5 сбалансированных карт

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Baseline тестов не падает (167 + 1 skip после TASK-056)
- [ ] `errors.log` содержит запись о retry с финальным seed и распределением

#### Обновление документации
- [ ] **Перед закрытием обновить описание BUG-008** в `Bugs.md` (заменить
      устаревший «80%+ grass» на актуальный «доминирует один биом >55% карты»).
- [ ] `Bugs.md`: BUG-008 → «Закрытые» с TASK-057 + commit hash.
- [ ] `Bugs.md`: BUG-006 → «Закрытые» с пояснением «закрывается косвенно
      через TASK-057 (balanced distribution делает 4+ цвета палитры видимыми
      автоматически); палитра не менялась — retest не требуется».
- [ ] `Current.md`: F-15 остаётся ✅, в деталях упомянуть пороги балансировки
      (`maxDominantShare=0.55`, `minDiversity=4`, retry до 5 попыток в
      WorldMapProvider).

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-25
- Spec-review: revised round 1 (Opus, 9 issues) → round 2 approved (Opus подтвердил закрытие всех 9: strict-режим + 4-из-5 + ≥3277 клеток + 10/10 после retry + UI requested→actual + BUG-008 описание обновляется ДО закрытия + BUG-006 явный smoke-AC)
- Готова к работе: 2026-05-25
- Lead-model: opus
- Plan-review: escalated→resolved (round 1 sonnet — 5 critical/high, 4 low; round 2 sonnet — 2 новых valid issues применены: seaPresent убран из balanced, добавлен pre-read шаг 0 для верификации NoiseFieldGenerator)
- Исполнитель: opus (executor) + sonnet (verify) + opus (code-review)
- Code-review: approved (Opus, round 1, 3 non-blocking observations)
- Завершена: 2026-05-25
- Коммит: d13f490
