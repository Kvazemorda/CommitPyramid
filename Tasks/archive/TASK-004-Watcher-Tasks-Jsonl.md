# TASK-004: Watcher `tasks.jsonl`

## Связь
- **F-04** Watcher tasks.jsonl
- **D-04**
- **Приоритет:** P0

## 📋 Постановка
Игра следит за внешним файлом `tasks.jsonl` (его пишет крон-агент пользователя).
Каждая новая строка → валидация → событие `task_completed` в `events.jsonl`. Read-only,
offset персистится.

## 🛠 Решение
- `TasksJsonlWatcher` — `DispatchSource.makeFileSystemObjectSource` с `eventMask:
  [.write, .extend, .rename, .delete]`. Параллельно держит offset в
  `IngestionState` (`~/Library/Application Support/CityDeveloper/ingestion-state.json`).
- При write/extend — читает только хвост от offset до конца, парсит построчно по `\n`,
  частичные строки (без терминатора) оставляет на следующий тик.
- При rename/delete — закрывает fd, заново открывает (handles ротацию файла).
- При размере файла меньше offset (truncate) — сбрасывает offset в 0.
- Валидация: `TaskRecord.validate()` (непустые project + title, версия <=1, title
  обрезается до 500). Строки с `#` — комментарии.

## ✅ Definition of Done (факт)
- [x] Новая строка в `tasks.jsonl` → юнит в течение 2 сек (подтверждено smoke-тестом)
- [x] Offset персистится между запусками (ingestion-state.json)
- [x] Битая JSON-строка не ломает watcher (логируется в errors.log)
- [x] Замена файла обрабатывается корректно (handled rename/delete)

## Артефакты
- `Sources/CityDeveloper/Data/TasksJsonlWatcher.swift`
- `Sources/CityDeveloper/Data/IngestionState.swift`
- `Sources/CityDeveloper/Data/TaskRecord.swift`

## Статус
`[x] done`

## Метаданные
- Создана: 2026-05-21
- Завершена: 2026-05-21
