# TASK-005: Базовая изометрическая визуализация (плейсхолдеры)

## Связь
- **F-02** Изометрический рендер (частично)
- **F-06** Project-District и размещение (частично)
- **F-07** Состав и баланс юнитов (частично)
- **F-08** Стадии (частично)
- **D-02 / D-06 / D-07 / D-08**
- **Приоритет:** P0

## 📋 Постановка
Чтобы можно было увидеть результат event sourcing — реализовать минимальную визуализацию:
кварталы с детерминированным размещением, юниты-плейсхолдеры с типом и стадией.

## 🛠 Решение
- `GameScene` хранит `world: SKNode`, камера — `SKCameraNode`.
- Изометрические координаты: `screenX = (gx - gy) * (tileW/2)`,
  `screenY = (gx + gy) * (tileH/2)` (tileW=64, tileH=32).
- Юнит = `SKShapeNode` ромб-плитка `sandLight` + параллелепипед-здание цвета юнита,
  высота зависит от типа и `tier` (= stage).
- Над центром квартала — подпись `parchment`-badge с именем проекта.
- Камера: pan через `mouseDragged`, zoom через `scrollWheel` (диапазон 0.3-3.0).
- `DistrictPlanner.allocateNextOrigin(currentIndex:)` — растущая спираль, шаг 14 клеток
  между центрами кварталов.
- `UnitPlanner.nextUnitKind(forTaskIndex:stage:)` — детерминированный паттерн на 20
  шагов, продвижение `shack → house → villa` при росте stage.
- `StageRules.computeStage(taskCount:ageDays:)` — порог по количеству задач + возраст.

## ✅ Definition of Done (факт)
- [x] При получении события `task_completed` в сцене появляется юнит с анимацией fade+scale
- [x] Новый проект получает свой квартал по спирали от центра
- [x] Над каждым кварталом видна badge с именем проекта
- [x] Pan/zoom работают
- [ ] Настоящие тайлы через `SKTileMapNode` — НЕ сделано (плейсхолдеры из SKShapeNode)
- [ ] Визуальная подмена sprite-tier при stage-up — НЕ сделано (только высота меняется)
- [ ] Приоритет руин — НЕ сделано (зависит от F-09)
- [ ] Строгая валидация пропорций юнитов — НЕ сделано

## Артефакты
- `Sources/CityDeveloper/Game/GameScene.swift` (рендер, изометрия, камера)
- `Sources/CityDeveloper/Game/DistrictPlanner.swift`
- `Sources/CityDeveloper/Game/UnitPlanner.swift`
- `Sources/CityDeveloper/Game/StageRules.swift`
- `Sources/CityDeveloper/Game/CityEngine.swift` (склейка)

## Что осталось (выделить в отдельные таски)
- TASK-007: настоящий `SKTileMapNode` + изометрические тайлы (D-02)
- TASK-008: визуальный апгрейд по стадиям, замена sprite-tier (D-08)
- TASK-009: приоритет руин при размещении (D-06, зависит от F-09)
- TASK-010: валидация пропорций UnitPlanner (D-07)

## Статус
`[x] done (partial — основа MVP, доработки в TASK-007..010)`

## Метаданные
- Создана: 2026-05-21
- Завершена: 2026-05-21 (partial)
