# CityDeveloper — Каталог юнитов (технический справочник)

> **Это технический справочник, не эталон.** Source of truth — `Concept.md`
> § F-16. При любом расхождении побеждает F-16. Этот файл — рабочая
> сводка для разработки и арт-генерации: rawValue, PNG-имена, удобный
> просмотр всех 50 юнитов в одной таблице.

**См. также:**
- `Concept.md` § F-16 — каноничное описание юнитов и эволюции
- `SpriteGenerationRules.md` — требования к PNG и конвенция имён
- `Sources/CityDeveloper/Data/CityState.swift` — enum `UnitKind` /
  `UnitCategory` (источник rawValue для 12 существующих юнитов)

_Актуально на: 2026-05-22 (по TASK-039)._

---

## Полная таблица (50 юнитов)

> rawValue для существующих 12 юнитов зафиксированы кодом (`CityState.swift:17-28`);
> для новых 38 — рекомендация для TASK-031 (`/lead 031` подтвердит или скорректирует).
> Юнит `raw` (Сырьевая яма) присутствует в коде, но отсутствует в F-16 — в каталог
> **не включён**. Совместимость обеспечивается TASK-037.

| №  | Название (рус)       | rawValue           | Категория      | Terrain        | Size     | minStage | Large | Эволюция              | PNG-имя                                         |
|----|----------------------|--------------------|----------------|----------------|----------|----------|-------|-----------------------|-------------------------------------------------|
| 1  | Землянка             | zemlyanka          | residential    | любой          | 1×1      | 0        | нет   | 2 → Лачуга            | zemlyanka.png                                   |
| 2  | Лачуга               | shack              | residential    | любой          | 1×1      | 0        | нет   | 2 → Дом               | shack.png (stage 1)                             |
| 3  | Хижина               | khizhina           | residential    | лес/горы       | 1×1      | 0        | нет   | 2 → Каменный дом      | khizhina.png                                    |
| 4  | Фермерский дом       | farmhouse          | residential    | луг/река       | 1×1      | 1        | нет   | 2 → Усадьба           | farmhouse.png                                   |
| 5  | Дом                  | house              | residential    | любой          | 1×1      | 1        | нет   | 3 → Доходный дом      | house_stage2.png / house_stage3.png / house_stage4.png |
| 6  | Двухэтажный дом      | two_story_house    | residential    | луг/река       | 1×2      | 2        | нет   | 2 → Доходный дом      | two_story_house.png                             |
| 7  | Каменный дом         | stone_house        | residential    | горы/камни     | 1×1      | 2        | нет   | 2 → Усадьба           | stone_house.png                                 |
| 8  | Таунхаус             | townhouse          | residential    | любой          | 1×2      | 2        | да    | —                     | townhouse.png                                   |
| 9  | Доходный дом         | tenement           | residential    | любой          | 2×2      | 3        | да    | —                     | tenement.png                                    |
| 10 | Усадьба              | manor              | residential    | луг/лес        | 2×2      | 3        | да    | —                     | manor.png                                       |
| 11 | Вилла                | villa              | residential    | луг/река       | 2×2      | 4        | да    | —                     | villa.png (stage 5)                             |
| 12 | Дворец               | dvorets            | residential    | любой          | 3×3      | 5        | да    | —                     | dvorets.png                                     |
| 13 | Колодец              | well               | infrastructure | луг/пустыня    | 1×1      | 0        | да    | —                     | well.png                                        |
| 14 | Дорога               | road               | infrastructure | любой          | 1×1      | 0        | да    | —                     | road.png                                        |
| 15 | Ворота               | gates              | infrastructure | любой          | 1×2      | 1        | да    | —                     | gates.png                                       |
| 16 | Мост                 | bridge             | infrastructure | река/море      | 1×1      | 1        | да    | —                     | bridge.png                                      |
| 17 | Цистерна             | cistern            | infrastructure | пустыня        | 1×1      | 1        | да    | —                     | cistern.png                                     |
| 18 | Маяк                 | lighthouse         | infrastructure | море/река      | 2×2      | 2        | да    | —                     | lighthouse.png                                  |
| 19 | Оросительный канал   | irrigation_canal   | infrastructure | пустыня/луг    | 1×1      | 1        | да    | —                     | irrigation_canal.png                            |
| 20 | Пристань             | pier               | infrastructure | море/река      | 2×2      | 2        | да    | —                     | pier.png                                        |
| 21 | Ферма                | farm               | production     | луг/река       | 2×2      | 0        | да    | —                     | farm.png                                        |
| 22 | Рыболовецкий причал  | fishing_pier       | production     | река/море      | 1×2      | 0        | да    | —                     | fishing_pier.png                                |
| 23 | Мастерская           | workshop           | production     | любой          | 1×1      | 1        | нет   | —                     | workshop_stage2.png / workshop_stage3.png / workshop_stage4.png / workshop_stage5.png |
| 24 | Склад                | warehouse          | production     | любой          | 2×2      | 0        | да    | 3 → Большой склад     | warehouse_stage2.png / warehouse_stage3.png / warehouse_stage4.png / warehouse_stage5.png |
| 25 | Кузница              | smithy             | production     | горы/камни     | 1×1      | 1        | да    | —                     | smithy.png                                      |
| 26 | Гончарня             | pottery            | production     | луг/река       | 1×1      | 1        | да    | —                     | pottery.png                                     |
| 27 | Пивоварня            | brewery            | production     | луг/лес        | 1×2      | 2        | да    | —                     | brewery.png                                     |
| 28 | Лесопилка            | sawmill            | production     | лес            | 1×2      | 1        | да    | —                     | sawmill.png                                     |
| 29 | Каменоломня          | quarry             | production     | горы/камни     | 2×2      | 1        | да    | —                     | quarry.png                                      |
| 30 | Шахта                | mine               | production     | горы           | 2×2      | 2        | да    | —                     | mine.png                                        |
| 31 | Большой склад        | great_warehouse    | production     | любой          | 3×2      | 3        | да    | —                     | great_warehouse.png                             |
| 32 | Завод                | factory            | production     | любой          | 3×3      | 3        | да    | —                     | factory.png                                     |
| 33 | Таверна              | tavern             | social         | любой          | 1×1      | 1        | да    | —                     | tavern.png                                      |
| 34 | Рынок                | market             | social         | любой          | 2×2      | 2        | да    | —                     | market_stage2.png / market_stage3.png / market_stage4.png / market_stage5.png |
| 35 | Площадь              | plaza              | social         | любой          | 2×2      | 2        | да    | —                     | plaza.png                                       |
| 36 | Баня                 | bathhouse          | social         | луг/река       | 2×1      | 2        | да    | —                     | bathhouse.png                                   |
| 37 | Школа                | school             | social         | любой          | 2×1      | 2        | да    | —                     | school.png                                      |
| 38 | Больница             | hospital           | social         | любой          | 2×2      | 3        | да    | —                     | hospital.png                                    |
| 39 | Форум                | forum              | social         | любой          | 3×3      | 3        | да    | —                     | forum_stage3.png / forum_stage4.png / forum_stage5.png |
| 40 | Библиотека           | library            | social         | любой          | 2×2      | 4        | да    | —                     | library.png                                     |
| 41 | Акведук              | aqueduct           | social         | горы/луг       | линейный | 3        | да    | —                     | aqueduct.png                                    |
| 42 | Театр                | theater            | social         | любой          | 3×2      | 4        | да    | —                     | theater.png                                     |
| 43 | Часовня              | chapel             | religious      | любой          | 1×1      | 1        | да    | —                     | chapel.png                                      |
| 44 | Храм                 | temple             | religious      | любой          | 2×2      | 3        | да    | —                     | temple_stage4.png / temple_stage5.png           |
| 45 | Обелиск              | obelisk            | religious      | пустыня        | 1×1      | 4        | да    | —                     | obelisk.png                                     |
| 46 | Собор                | cathedral          | religious      | любой          | 3×3      | 5        | да    | —                     | cathedral.png                                   |
| 47 | Пирамида             | pyramid            | religious      | пустыня        | 4×4      | 5        | да    | —                     | pyramid.png                                     |
| 48 | Сторожевая башня     | watchtower         | military       | любой          | 1×1      | 1        | да    | —                     | watchtower.png                                  |
| 49 | Казармы              | barracks           | military       | любой          | 2×2      | 2        | да    | —                     | barracks.png                                    |
| 50 | Верфь                | shipyard           | military       | море/река      | 3×3      | 3        | да    | —                     | shipyard.png                                    |

**Примечания к таблице:**

- **Акведук (№ 41)** — линейный (не клеточный) юнит, размер в F-16 = `—`. Требует
  отдельной обработки в планировщике (см. TASK-035). В колонке Size указано `линейный`.
- **Юниты с `large = да` и эволюцией:** Доходный дом (`tenement`), Усадьба (`manor`),
  Большой склад (`great_warehouse`) — цели эволюции, `large = true`, не эволюционируют
  дальше.
- **terrain = «любой»** записан явно для 23 юнитов — не пустая ячейка.
- **PNG-имена для stage-юнитов (12 существующих):**
  - `shack.png` — Лачуга (residential stage 1, единственный вариант)
  - `house_stage2.png`, `house_stage3.png`, `house_stage4.png` — Дом (stages 2–4)
  - `villa.png` — Вилла (residential stage 5)
  - `warehouse_stage2..5.png`, `workshop_stage2..5.png` — Склад, Мастерская
  - `market_stage2..5.png`, `forum_stage3..5.png`, `temple_stage4..5.png`, `obelisk.png`
  - Источник: `SpriteGenerationRules.md` § 3, строки 63–73.

---

## Эволюционные цепочки

Эволюция — визуальная подмена клетки при достижении порога количества юнитов данного
типа в квартале. Источник — F-16.

| Порог | From (rawValue)  | → | To (rawValue)   | Примечание                                          |
|-------|------------------|---|-----------------|-----------------------------------------------------|
| 2     | zemlyanka        | → | shack           | цель — обычный residential                          |
| 2     | shack            | → | house           | цель — обычный residential                          |
| 2     | khizhina         | → | stone_house     | цель — обычный residential                          |
| 3     | house            | → | tenement        | цель `large = true`, не эволюционирует дальше       |
| 2     | stone_house      | → | manor           | цель `large = true`, не эволюционирует дальше       |
| 2     | two_story_house  | → | tenement        | цель `large = true`, не эволюционирует дальше       |
| 2     | farmhouse        | → | manor           | цель `large = true`, не эволюционирует дальше       |
| 3     | warehouse        | → | great_warehouse | цель `large = true`, не эволюционирует дальше       |

Все 8 целевых юнитов — large, дальше не эволюционируют. См. F-16 § Эволюционные цепочки.

---

## Категории

| Категория      | UnitCategory rawValue | Юнитов | Ground-color (Palette token)     | Примечание                                               |
|----------------|-----------------------|--------|----------------------------------|----------------------------------------------------------|
| Жилое          | residential           | 12     | Palette.sandLight                | существующий                                             |
| Инфраструктура | infrastructure        | 8      | Palette.sandMid                  | существующий                                             |
| Производство   | production            | 12     | Palette.clay.darkened(0.10)      | существующий                                             |
| Социальное     | social                | 10     | Palette.parchment                | существующий                                             |
| Религиозное    | religious             | 5      | TBD (см. TASK-032 / TASK-036)    | новая категория, добавляется в TASK-031                  |
| Военное        | military              | 3      | TBD (см. TASK-032 / TASK-036)    | новая категория, добавляется в TASK-031                  |

**Ссылки:**
- `Sources/CityDeveloper/Data/CityState.swift` — enum `UnitCategory` (строки 33–38)
- `Sources/CityDeveloper/Game/UnitSprites.swift` — `categoricalGroundColor` (строки 99–106)
- `Sources/CityDeveloper/Theme/Palette.swift` — токены цвета (строки 5–19)

---

## Связанные документы и задачи

- `Concept.md` § F-16 — source of truth, эталон (каталог 50 юнитов, эволюция)
- `SpriteGenerationRules.md` — требования к PNG, конвенция имён (§ 1 тех-параметры,
  § 4 правила генерации)
- `Diff.md` D-16 — общая диффовая фича «50 юнитов», текущий статус

**Задачи D-16 (открыты, закрываются по мере готовности):**
- TASK-031 — расширение `UnitKind` enum (финальные rawValue для 38 новых юнитов)
- TASK-032 — placeholder-спрайты для новых категорий (ground-color токены religious/military)
- TASK-033 — terrain-веса в планировщике (biome-предпочтения из F-16)
- TASK-034 — эволюционные цепочки в движке (визуальная подмена по порогу)
- TASK-035 — планировщик (размещение с учётом terrain, minStage, large; акведук)
- TASK-036 — stage-tier для новых юнитов (расширение `makeCategoricalBuilding`)
- TASK-040 — финальные PNG-ассеты для всех 50 юнитов

_Документ обновляется по мере закрытия задач D-16._
