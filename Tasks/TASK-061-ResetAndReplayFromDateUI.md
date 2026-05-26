# TASK-061: Settings — Reset city + Replay из git с указанной даты

## Связь
- **F-14** из Concept.md (Настройки UI)
- **F-20** из Concept.md (Catch-up watcher)
- **BUG-005** из Bugs.md
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-26_

### Что хотим

Дать пользователю возможность «начать заново»: одной кнопкой сбросить
текущий город и переимпортировать все события из подключённых источников
с заданной даты. Сейчас для этого приходится вручную удалять
`state.json` + `events.jsonl` + `catchup-state.json` из Application
Support — нет UI, действие недоступно обычному пользователю.

### Пользовательский сценарий

1. Открыть Settings (`⌘,`) → секция **Reset & Replay**.
2. Видна кнопка `Сбросить город` и DatePicker `Импортировать с:` (по
   умолчанию — `сегодня − 30 дней`).
3. Нажать `Сбросить город` → confirm-alert «Это сотрёт текущий город.
   Все коммиты / задачи / notes из подключённых источников с
   `<выбранная дата>` будут импортированы заново. Продолжить?»
4. Подтверждение → приложение:
   - стирает `state.json` (и snapshot если есть),
   - стирает `events.jsonl` (или архивирует с суффиксом
     `.replay-<ts>.bak` — на усмотрение лида),
   - перезаписывает `catchup-state.json` так, чтобы для всех источников
     `last_check_ts` = выбранная дата,
   - запускает CatchUpScheduler immediate scan.
5. На сцене город «обнуляется» до пустого луга, затем юниты появляются
   по мере импорта (как при первом запуске).
6. Settings закрываются автоматически (или остаются открытыми с
   уведомлением «Импорт запущен», на усмотрение лида).

### Acceptance criteria

- [ ] **AC1.** В секции `Reset & Replay` SettingsView присутствуют:
      DatePicker (тип `.compact` или `.field`), кнопка `Сбросить город`
      (destructive style).
- [ ] **AC2.** Клик по кнопке открывает `confirm`-alert с текстом,
      упоминающим выбранную дату; кнопка `Отмена` ничего не делает,
      кнопка `Сбросить и импортировать` запускает операцию.
- [ ] **AC3.** После подтверждения: `state.json` (и snapshot, если
      `SnapshotStore` есть) удалены/обнулены; `events.jsonl` либо
      удалён, либо переименован в `events.jsonl.replay-<YYYYMMDD-HHMMSS>.bak`;
      `catchup-state.json` пересоздан с `last_check_ts = выбранная дата`
      для всех источников.
- [ ] **AC4.** CatchUpScheduler триггерится сразу после reset —
      пользователь видит, как юниты появляются на сцене в течение
      первых ~30 сек (зависит от объёма коммитов).
- [ ] **AC5.** GameScene корректно обнуляется (все юниты исчезают,
      затем перерисовываются по мере импорта) — нет визуальных
      артефактов / зависших спрайтов / падений FPS.
- [ ] **AC6.** Если ни один git-репо / notes-источник не подключён —
      кнопка `Сбросить город` всё равно работает: стирает state,
      готовит к чистому старту. Сообщение «Источников нет, город
      пуст» (или аналогичное) в confirm-alert.
- [ ] **AC7.** Replay идемпотентен: вторая reset+replay с той же датой
      даёт идентичный итоговый state (детерминизм событий — F-03,
      F-12 гарантия).
- [ ] **AC8.** Reset во время активной операции (CatchUpScheduler
      сканирует) — корректно отменяется текущий scan, затем запускается
      новый с новой `last_check_ts`. Нет race condition (двойного
      импорта одного коммита).

### Что НЕ делаем (границы скоупа)

- Не меняем формат events.jsonl / state.json (только удаление + replay).
- Не добавляем undo для reset (одна операция = бесповоротная, кроме
  `.bak` файла).
- Не делаем partial reset (например, «удалить только проект X»).
- Не трогаем worldmap (карта биомов остаётся, для её сброса есть
  отдельный UI «Карта мира» — TASK-030a).
- Не делаем UI для просмотра/выбора `.bak` файлов — это manual recovery.
- Не делаем progress-bar импорта (CatchUpScheduler работает async,
  пользователь видит результат на сцене).

### Edge cases

- [ ] Reset до того, как любой источник был подключён — пустой replay,
      просто чистый state.
- [ ] Replay-since в будущем (пользователь выбрал завтрашнюю дату) —
      эквивалент «replay since now», ничего не импортируется (или
      validate в UI и не дать выбрать > today).
- [ ] Replay-since очень давний (5 лет назад) — корректный импорт всех
      коммитов; UI не блокируется (CatchUpScheduler уже async).
- [ ] Множество git-репо (5+) — все получают одинаковый `last_check_ts`.
- [ ] Reset в момент, когда `MapReinitCoordinator.isReiniting` (другой
      reset уже запущен) — confirm-alert второй раз не открывается
      (button disabled) или ждёт завершения.
- [ ] Удаление `events.jsonl` пока EventLog держит файловый handle —
      нужно корректно закрыть log/release handle перед `FileManager.removeItem`.
- [ ] App quit в момент replay — на следующем запуске CatchUpScheduler
      продолжит с того же `last_check_ts` (idempotent).

### Зависимости

- TASK-020 (F-20 CatchUpScheduler) — переиспользуем `triggerImmediateScan()`
  и `catchup-state.json` формат.
- TASK-030b (MapReinitCoordinator) — паттерн atomic pause→stop→restart
  возможен для переиспользования (но это decision лида, для reset+replay
  может быть проще).
- F-03/F-12 (event sourcing + snapshots) — гарантирует, что replay
  идемпотентен.

### Дизайн

Секция `Reset & Replay` в `SettingsView`:
- Заголовок «Reset & Replay» (или «Сбросить и переимпортировать»).
- DatePicker «Импортировать с:» (default = today − 30d, range = past
  10 years .. today).
- Кнопка `Сбросить город` (style destructive — красная в SwiftUI).
- Confirm-alert через стандартный `.alert(...)` API.
- Размещение: вместо или рядом с существующей «Reset & Rebuild»
  секцией (если она есть в текущем SettingsView от TASK-030a/TASK-051) —
  лид определит, объединить или сделать рядом.

### Done-критерий

_Из bugs.md фикса BUG-005:_ Settings → Reset section должна
содержать кнопку «Reset city», DatePicker «Replay since»,
подтверждение «Сотрётся текущий город. Все коммиты с указанной
даты будут импортированы заново».

---

## 🛠 Технический разбор от тимлида

_Статус: [ ] нужен разбор_

> Заполняется командой `/lead 061`.

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен в реальном использовании (ручной reset+replay
      с подключённым git-репо)

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны
- [ ] Тест на идемпотентность replay (AC7) — property-style или integration

#### Обновление документации
- [ ] `Current.md`: F-14 / F-20 запись упоминает reset+replay UI
- [ ] `Bugs.md`: BUG-005 закрыт со ссылкой на коммит
- [ ] Новые идеи → `Backlog.md`, новые баги → `Bugs.md`

---

## Статус

`[x] spec-flawed`

> ⚠️ **Нужно разбить (отложено до следующего /sync):**
> Spec-review (Opus) пометил задачу как L (8 AC × 7 edge cases × 6 модулей:
> SettingsView, CityEngine, CatchUpScheduler, EventLog, StateStore, SnapshotStore + integration-tests).
> По правилу «Split L tasks into M» — следующий цикл создаст:
> - **TASK-061a:** Settings UI + reset CityState/events/catchup-state +
>   immediate scan trigger (AC1-AC4, AC6, edge cases про future/past date,
>   нет источников). Чистая UI + file-IO работа. Объём — M.
> - **TASK-061b:** Идемпотентность replay + race-condition guard (AC7, AC8,
>   edge cases про concurrent scan / file handle / app quit during replay).
>   Engine-уровень + integration test с git fixture. Объём — M.
>
> Дополнительные правки из spec-review (применятся при создании 061a/061b):
> - AC3: зафиксировать стратегию `.bak` rename (одна, без альтернатив).
> - AC4: разделить на (a) `scanInProgress=true` в ≤1 сек после кнопки,
>   (b) первый юнит на сцене в ≤30 сек на тестовом репо с ≥10 коммитов.
> - AC5: measurable вместо визуального — `scene.unitNodes.isEmpty == true`
>   сразу после reset; `nodeCount == state.units.count` после scan end;
>   FPS ≥ 50 за 5 сек.
> - AC7: test fixture в `Tests/Fixtures/replay-repo/` с фиксированными коммитами;
>   state-hash сравнение между двумя прогонами.
> - AC8: выбрать одну стратегию (рекомендация — «button disabled пока isReiniting»).
> - Done-критерий: единый канон с UI-текстом (русский «Импортировать с:» или
>   английский «Replay since») — согласовать с пользователем.

## Метаданные
- Создана PM: 2026-05-26
- Spec-review: needs-revision (Opus, 1 круг — задача L, требует разбиения на 061a/061b)
- Spec-flaw отмечен: 2026-05-26
- Следующий шаг: при следующем `/sync` /pm разобьёт на 061a/061b
- Готова к работе: —
- Завершена: —
- Коммит: —
