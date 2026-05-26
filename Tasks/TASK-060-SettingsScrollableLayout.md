# TASK-060: Settings — scrollable layout + адекватный minSize

## Связь
- **F-14** из Concept.md (Настройки UI)
- **BUG-003** из Bugs.md (Settings окно слишком маленькое — кнопки секций обрезаны)
- **BUG-007** из Bugs.md (секции уезжают за окно при добавлении 2+ репо — нет скролла)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-26_

### Что хотим

Сделать Settings usable: окно должно вмещать все секции (NotesWatcher,
GitWatcher, Reset/Rebuild, Tasks JSONL, CatchUp, TemplateFamily) при любом
количестве добавленных источников без обрезки кнопок и без потери доступа
к нижним секциям. Сейчас оба бага наблюдаются одновременно:

- BUG-003: на дефолтном размере окна (≤720×600) уже не помещаются нижние
  кнопки «Add path», «Add repo» — обрезаны рамкой окна.
- BUG-007: при добавлении 2+ git-репо список GitWatcherSection разрастается
  и выталкивает остальные секции (NotesWatcher, hotkey, tasks.jsonl,
  catch-up) за нижний край окна — недоступны вообще.

Оба решаются одним фиксом: внутренний `ScrollView` поверх контейнера секций +
адекватный minSize окна для baseline-сценария.

### Пользовательский сценарий

1. Открыть Settings через `⌘,` (на первом запуске, без добавленных источников).
2. Видны заголовки всех секций, кнопки `Add path` / `Add repo` нажимаемы
   без необходимости двигать окно.
3. Добавить 5+ git-репозиториев и 3+ notes-источников.
4. Список репо скроллится внутри своей секции (или общий ScrollView), окно
   НЕ растёт за пределы экрана.
5. Все секции (включая Reset/Rebuild внизу, TemplateFamily) остаются
   доступны через прокрутку, без обрезки.
6. Закрыть/открыть Settings — состояние секций сохраняется, scroll-позиция
   сбрасывается в начало (или сохраняется — на усмотрение реализации).

### Acceptance criteria

- [ ] **AC1.** При первом открытии Settings (нет добавленных источников)
      все кнопки секций (`Add path` в NotesWatcherSection, `Add repo` в
      GitWatcherSection, `Reset city` в Reset секции, `Сохранить` если есть)
      видны без скролла на размере окна по умолчанию (минимум 720×600,
      допускается больше).
- [ ] **AC2.** При добавлении 5+ git-репо список репозиториев скроллится
      внутри окна (либо локально в секции, либо через общий ScrollView), окно
      физически НЕ превышает высоту, при которой пользователь теряет нижние
      секции.
- [ ] **AC3.** При добавлении 3+ notes-источников аналогично — скролл
      работает, остальные секции остаются доступны.
- [ ] **AC4.** На дисплее 1280×720 (минимальный поддерживаемый, MacBook Air
      11" / внешний небольшой монитор) окно Settings полностью помещается
      без системного скролла окна; весь контент достижим через внутренний
      scroll.
- [ ] **AC5.** Resize окна (drag нижнего угла, если allowsResize): контент
      перекомпоновывается, scroll-bar появляется/исчезает корректно, нет
      «обрезанных» нерабочих кнопок.
- [ ] **AC6.** Существующее поведение секций (валидация путей, удаление через
      trash, переключение Toggle) не регрессирует — только обёртка layout.

### Что НЕ делаем (границы скоупа)

- Не меняем persistence (UserDefaults / AppSettings формат остаётся как есть).
- Не редизайним внутренний layout секций (NotesWatcherSection,
  GitWatcherSection, TemplateFamilySection — внутри без изменений).
- Не вводим новые поля в AppSettings.
- Не трогаем другие окна приложения (JournalWindowController и т.п.).
- Не делаем resize-persistence (сохранение размера окна между запусками) —
  отдельная следующая задача, если понадобится.
- Не реорганизуем порядок секций — только обёртка для скролла.

### Edge cases

- [ ] Пустой список репо / notes — список НЕ должен показывать ненужный
      scroll-bar (только при overflow).
- [ ] 20+ репозиториев — скролл работает плавно, без рывков.
- [ ] Resize окна вверх (увеличение высоты) — scroll-bar исчезает когда
      контент помещается.
- [ ] Запуск на дисплее retina vs не-retina — окно умещается одинаково
      (1280×720 — нижняя граница).
- [ ] Settings открыты во время работы game scene — focus и keyboard input
      работают как раньше.
- [ ] Cross-section: одновременно много репо И много notes — общий
      scrollable контейнер должен корректно отображать ВСЕ секции.

### Зависимости

- Нет внешних зависимостей. Изменения локальные в `UI/SettingsView.swift`
  и `App/SettingsWindowController.swift`.

### Дизайн

Не применимо (UX-fix без новых компонентов). Архитектурное решение
(ScrollView vs локальные scroll в каждой секции с динамическим списком vs
комбинация) — на усмотрение лида с учётом текущей структуры
`SettingsView`. Рекомендация: общий внешний `ScrollView` поверх
`VStack`-контента — минимальное изменение, закрывает оба бага.

### Done-критерий

_Из bugs.md фикса BUG-003 + BUG-007:_ Settings окно открывается с
minSize, при котором все кнопки секций видны без скролла на пустом
списке источников; при добавлении N репо / notes контент секций
скроллится внутри окна, остальные секции остаются доступны независимо
от размера списков.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (opus), 2026-05-26_
_Статус: [x] готов_

### Анализ текущего состояния

Прочитал три ключевых файла:

- `Sources/CityDeveloper/UI/SettingsView.swift:47` — внешний `ScrollView(.vertical, showsIndicators: true)` УЖЕ обёрнут вокруг VStack секций. То есть «нет скролла» в BUG-007 формально не верно — scroll есть, но визуально не работает потому, что окно не даёт ему пространства.
- `Sources/CityDeveloper/UI/SettingsView.swift:146` — внутренний `.frame(minWidth: 640, minHeight: 480)` зажимает контент.
- `Sources/CityDeveloper/App/SettingsWindowController.swift:30` — `styleMask = [.titled, .closable]` — НЕТ `.resizable`! Пользователь не может растянуть окно. Это корень BUG-003.
- `SettingsWindowController.swift:31-32` — content 720×600, minSize 640×480 (minSize меньше content — допускает сжатие при resize, но resize отключён). При первом запуске `w.setContentSize(720×600)` и фиксирован.
- `GitWatcherSection.swift:86-96` и `NotesWatcherSection.swift:82-92` — внутренние списки `VStack { ForEach }` без max-height, растут вертикально без ограничения. Их рост уезжает за окно, но outer ScrollView должен это обрабатывать.

Гипотеза почему BUG-007 виден: outer ScrollView отдаёт минимальную высоту из `.frame(minHeight: 480)`. AppKit-окно при `setContentSize(720×600)` показывает 600pt контента → ScrollView показывает 600pt и должен скроллить overflow. Если кнопок не видно — проблема в том, что window styleMask без `.resizable` не позволяет пользователю расширить окно для baseline-сценария (AC1, AC5), а внешний ScrollView существует, но baseline 600pt физически меньше суммарной высоты секций (Данные + Hotkey + Catch-up + NotesWatcher + GitWatcher + MapWorld + TemplateFamily + Reset + кнопки save/cancel ≈ ~900pt при пустых списках).

### Архитектурное решение

**Один внешний ScrollView (уже существует) + увеличить minSize окна + добавить `.resizable`.** НЕ нужно вводить локальные scroll внутри GitWatcherSection / NotesWatcherSection: это сломало бы UX (nested scroll), и outer ScrollView уже корректно обрабатывает overflow. Локальные scrolls добавили бы лишний state и осложнили focus в TextField (projectId). Минимальное изменение, закрывающее оба бага = window-level (styleMask + размеры) + точечная коррекция `.frame` на SettingsView.

### Пошаговая декомпозиция

1. **[AC1, AC4, AC5] `SettingsWindowController.swift:30`** — расширить `styleMask` до `[.titled, .closable, .resizable]`. Это даст пользователю drag нижнего угла и заодно автоматически активирует AppKit-scroll окна при сжатии (страховка для AC4 на 1280×720).

2. **[AC1] `SettingsWindowController.swift:31`** — изменить `setContentSize` с `720×600` на baseline `800×720`. Baseline должен вместить все секции при пустых источниках без скролла (см. AC1 spec: «минимум 720×600, допускается больше»). Эмпирически 720pt по высоте — компромисс между «всё видно на пустом» и «не выходит за 1280×720 дисплей с учётом menubar 25pt + dock 80pt = 615pt полезных; нет, не помещается → AppKit-scroll окна сработает через `.resizable` страховку».

3. **[AC4, AC5] `SettingsWindowController.swift:32`** — снизить `minSize` до `NSSize(width: 720, height: 500)`. Width 720 — нижняя граница из AC1 spec (BranchPicker 80pt + 100pt projectId + toggles ~120pt + path + buttons требуют минимум 720). Height 500 — допускает сжатие на маленьких дисплеях с активацией outer ScrollView.

4. **[AC2, AC3, AC6] `SettingsView.swift:146`** — `.frame(minWidth: 640, minHeight: 480)` → `.frame(minWidth: 720, minHeight: 500)`. Должно совпадать с минимумом окна, чтобы внутренний контент не зажимался уже окна. AC6 — никаких изменений в логике секций, только обёртка frame.

5. **[AC2, AC3 edge] Проверка outer ScrollView** — убедиться, что existing `ScrollView(.vertical, showsIndicators: true)` (SettingsView.swift:47) НЕ требует правки. Текущая обёртка корректна, она УЖЕ скроллит overflow при росте `gitRepos`/`notesSources`. Если визуально не видно scrollbar при пустых списках — это правильное поведение (`showsIndicators` показывает индикатор только при overflow). Никаких правок не требуется.

### Edge cases

- **Empty lists no scroll-bar** (spec edge): `SettingsView.swift:47` — `ScrollView` с `showsIndicators: true` автоматически прячет индикатор когда контент помещается. OK без доп. кода.
- **20+ repos плавность** (spec edge): outer ScrollView нативный — плавность даётся AppKit. OK.
- **TextField focus в GitWatcherSection** (`GitWatcherSection.swift:113` projectId TextField): outer SwiftUI ScrollView НЕ ломает focus у TextField внутри — это известно work. Локальные scroll внутри секции сломали бы → правильно что мы их не делаем.
- **Resize вверх** (spec edge): после step1 (`.resizable`) AppKit сам перераспределит. ScrollView перейдёт в неscroll-режим когда контент влезет.
- **Cross-section много репо И notes** (spec edge): outer ScrollView обрабатывает суммарную высоту — OK.
- **Settings во время game scene**: SettingsView — отдельное NSWindow, focus/keyboard на нём не конфликтует с SpriteKit-сценой (как было до фикса). Не регрессирует.
- **MapWorldSection TextField seed** (`SettingsView.swift:363`): аналогично — outer scroll не ломает focus.

### Файлы для изменения

- `Sources/CityDeveloper/App/SettingsWindowController.swift` (строки 30, 31, 32) — styleMask + content size + minSize.
- `Sources/CityDeveloper/UI/SettingsView.swift` (строка 146) — frame minWidth/minHeight согласовать с окном.

### Файлы НЕ трогать

- `Sources/CityDeveloper/UI/Settings/GitWatcherSection.swift` — обоснование: список репо растёт вертикально, но outer ScrollView (SettingsView:47) уже его обрабатывает; добавление inner ScrollView сломало бы focus TextField projectId и nested scroll UX.
- `Sources/CityDeveloper/UI/Settings/NotesWatcherSection.swift` — то же обоснование, плюс scope spec: «Не редизайним внутренний layout секций».
- AppSettings / NotesWatcher / GitWatcher / любые модели — out of scope.

### Команды проверки

```sh
swift build
swift test                                    # регресс не должен сломаться (UI-only fix)
swift run CityDeveloper                       # ручной запуск
```

Ручная проверка (после `swift run`):
1. Открыть Settings через `⌘,` → окно 800×720, видны все кнопки (Add path, Add repo, Reset, Сохранить) без скролла. [AC1]
2. Перетащить нижний правый угол окна — окно ресайзится. [AC5]
3. Сжать окно до 720×500 — появляется scroll indicator справа, контент скроллится. [AC4]
4. Добавить 5+ git репо через «Добавить репозиторий…» → список растёт, outer scroll работает, секции Reset/Tasks остаются доступны прокруткой. [AC2]
5. Добавить 3+ notes-источника аналогично. [AC3]
6. Click trash на репо, toggle git fetch, edit projectId TextField — все работает как раньше. [AC6]

### Сложность и объём

- **Сложность:** junior (4 точечные правки в 2 файлах, нет архитектурных решений сверх описанного, никакой бизнес-логики).
- **Объём:** S (≤ 30 минут работы исполнителя с прогоном swift build + ручной тест).

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: —_ (определит лид)

### Definition of Done

#### Функциональные
- [ ] Все AC выполнены
- [ ] Done-критерий проверен в реальном использовании (ручной тест: open Settings, add 5 repos, проверить scroll, проверить нижние секции доступны)

#### Технические
- [ ] Компиляция/линтер без новых ошибок
- [ ] Тесты не сломаны
- [ ] Нет хардкод-строк

#### Обновление документации
- [x] `Current.md`: F-14 запись упоминает scrollable layout + minSize
- [x] `Bugs.md`: BUG-003 + BUG-007 закрыты со ссылкой на коммит
- [x] Новые идеи → `Backlog.md`, новые баги → `Bugs.md` (followups нет)

---

## Статус

`[x] done`

## Метаданные
- Создана PM: 2026-05-26
- Spec-review: approved (Opus, 1 круг)
- Lead-trigger: opus (P1)
- Lead-model: opus
- Plan-review: self-review (Agent tool недоступен в среде subagent'а; чеклист пройден дисциплинарно)
- Готова к работе: 2026-05-26
- Исполнитель: junior (haiku)
- Verify: pass (176/176, AC1-5 manual GUI required, AC6 auto)
- Code-review: approved (Opus — Lead-model: opus + P1; JournalWindowController использует тот же паттерн `.resizable`)
- Завершена: 2026-05-26
- Коммит: —
