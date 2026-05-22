# TASK-002: Окно «всегда позади» + статус-бар с переключением режимов

## Связь
- **F-01** Окно «всегда позади» + explore-режим
- **D-01** (частично)
- **Приоритет:** P0

## 📋 Постановка
Сделать окно приложения всегда позади всех окон других приложений и прозрачным к
кликам. Добавить переключение в режим explore (окно поднимается, мышь работает).

## 🛠 Решение
- `CityWindow` — borderless, прозрачный, `collectionBehavior: [.canJoinAllSpaces,
  .stationary, .ignoresCycle]`.
- `WindowModeManager` — два метода: `enterBehindMode()` (level = `.desktopWindow`,
  ignoresMouseEvents = true, orderBack) и `enterExploreMode()` (level = `.normal`,
  ignoresMouseEvents = false, makeKeyAndOrderFront + NSApp.activate).
- `StatusBarController` — NSStatusItem с меню «Открыть город» (key equiv ⌘⌥G только в
  открытом меню) и «Выйти».

## ✅ Definition of Done (факт)
- [x] Окно стартует позади всех приложений, клики проходят насквозь
- [x] Статус-бар «🏛» с меню, переключающим режим
- [x] Переключение мгновенное
- [ ] **Глобальный hotkey ⌘⌥G** — НЕ реализован. Вынесен в TASK-006.

## Артефакты
- `Sources/CityDeveloper/App/CityWindow.swift`
- `Sources/CityDeveloper/App/WindowModeManager.swift`
- `Sources/CityDeveloper/Status/StatusBarController.swift`

## Статус
`[x] done (partial — global hotkey separate)`

## Метаданные
- Создана: 2026-05-21
- Завершена: 2026-05-21 (частично)
