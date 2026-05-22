# TASK-003: Event sourcing (events.jsonl + replay)

## Связь
- **F-03** Event sourcing
- **D-03**
- **Приоритет:** P0

## 📋 Постановка
Все изменения состояния города идут через append-only лог `events.jsonl`. При старте
игра реплеит лог и восстанавливает состояние.

## 🛠 Решение
- `GameEvent` (Codable) — id, ts, kind (`task_completed`, `unit_built`, `stage_up`,
  `decay_tick`, `fire`, `restore`, `ruins_cleared`), project, title, taskId, source.
- `EventLog` — открытый файловый handle на append; `readAll()` парсит \n-separated JSON.
- `CityEngine.replayFromLog()` вызывается в init, применяет события молча (без UI
  callback).
- `CityEngine.ingestTaskCompletion(...)` — единая точка входа: пишет событие в лог +
  применяет к state + дёргает UI callback.

## ✅ Definition of Done (факт)
- [x] `events.jsonl` пополняется без перезаписи прошлых строк
- [x] Удаление `state.json` не теряет данные (state восстанавливается из лога)
- [x] Smoke-тест: 3 строки в `tasks.jsonl` → 3 строки в `events.jsonl`; перезапуск без
      новых данных → лог не растёт (replay не дублирует)
- [x] Системные события (unit_built/stage_up) определены, но в MVP не пишутся отдельно —
      выводятся из task_completed. Будут добавлены при работе над decay (F-09).

## Артефакты
- `Sources/CityDeveloper/Data/GameEvent.swift`
- `Sources/CityDeveloper/Data/EventLog.swift`
- `Sources/CityDeveloper/Data/ErrorsLog.swift`
- `Sources/CityDeveloper/Data/AppPaths.swift`
- `Sources/CityDeveloper/Game/CityEngine.swift`
- `Sources/CityDeveloper/Data/CityState.swift`

## Статус
`[x] done`

## Метаданные
- Создана: 2026-05-21
- Завершена: 2026-05-21
