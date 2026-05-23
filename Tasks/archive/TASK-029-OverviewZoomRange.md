# TASK-029: Обзорный зум до ×0.15 и ограничение по границам карты

## Связь
- **F-15** из Concept.md (масштаб и зум)
- **F-02** из Concept.md (pan/zoom)
- **D-15** из Diff.md (часть 4/5 — обзорный режим)
- **Приоритет:** P1

---

## 📋 Постановка от менеджера

_Автор: pm (agent)_
_Дата: 2026-05-23_

### Что хотим
Расширить текущий диапазон зума так, чтобы игрок мог одним движением колеса или
пинча выйти в полностью обзорный режим и увидеть всю сгенерированную карту
целиком — со всеми биомами сразу. Сейчас зум ограничен ближним планом, и
большая карта 256×256 просто «не помещается». Параллельно нужно ограничить
панораму, чтобы камера не уезжала бесконечно в пустоту за границы мира.

### Пользовательский сценарий
1. Игрок в explore-режиме крутит колесо «от себя» (или сводит пальцы на трекпаде).
2. Камера плавно уменьшает масштаб; на минимуме видно всю карту целиком в одном
   окне.
3. Игрок крутит «к себе» — приближается до детального вида квартала, как сейчас.
4. Игрок тащит карту мышью — на краях мир «упирается»: камера не уходит так,
   чтобы за экраном оказалась бесконечная пустота вместо мира.

### Acceptance criteria
- [ ] Минимальный масштаб камеры — не более ×0.15 (то есть зум-аут позволяет
      масштабироваться сильнее, чем сейчас, минимум до уровня ×0.15 от 1:1).
- [ ] На минимальном зуме вся сгенерированная карта (≥ 256×256) видна целиком в
      окне на типичном размере экрана (минимум 1280×800 логических точек) — края
      карты видны со всех четырёх сторон или совпадают с границами окна.
- [ ] Максимальный (ближний) зум сохраняется на текущем уровне детализации
      квартала — игрок не теряет возможность рассмотреть отдельное здание.
- [ ] Pan-камера ограничена: при достижении края карты камера останавливается,
      и в любой момент в кадре виден хотя бы фрагмент карты (без полностью
      пустого экрана за границей мира).
- [ ] Переключение масштаба плавное, без рывков и без «телепортации» при выходе
      на минимальный/максимальный зум.

### Что НЕ делаем (границы скоупа)
- Не добавляем мини-карту в углу — это отдельная идея для Backlog.
- Не меняем сам алгоритм панорамирования (drag) — только его ограничения.
- Не делаем сглаживание/inertia для скролла, если его сейчас нет — речь только
  о расширении диапазона и границ.
- Не привязываем UI-настройку зума к панели Settings.

### Edge cases
- [ ] Карта меняет размер при реинициализации (TASK-030) → ограничения камеры
      пересчитываются автоматически, без перезапуска приложения.
- [ ] Окно меняется по размеру (resize, fullscreen) → «зум-обзор» по-прежнему
      показывает всю карту целиком в новом окне, не обрезает её.
- [ ] Очень быстрый scroll (пользователь крутит колесо до упора) → масштаб
      безопасно упирается в min/max, без переполнения и без NaN.
- [ ] Камера была у края карты, потом сделали zoom-in → камера остаётся
      внутри карты, не «выпрыгивает» за границы из-за уменьшения видимой
      области.

### Зависимости
- **Blocked-by:** TASK-028 (на пустом луге обзорный зум не имеет смысла,
  проверить его удобно только когда карта видимая). Логически достаточно
  TASK-026 для размера, но проверка AC требует визуала из TASK-028.

### Дизайн
Не применимо (нет нового UI; меняются только ограничения камеры).

### Done-критерий
_Из Concept.md F-15:_ При первом запуске генерируется карта ≥ 256×256 тайлов с не менее
чем 4 разными биомами, соединёнными плавными переходами. Карта воспроизводима из seed.
Кнопка «Сбросить карту» + подтверждение → новая генерация, кварталы переразмещаются.
Зум позволяет увидеть всю карту в одном экране. Новый квартал рядом с рекой получает
водные/речные юниты с заметно большей вероятностью, чем равномерная.

---

## 🛠 Технический разбор от тимлида

_Автор: lead (agent)_
_Дата: 2026-05-23_
_Модель: opus_
_Статус: [x] готов_

### Анализ текущего состояния

- Камера и зум живут в одном файле: `Sources/CityDeveloper/Game/GameScene.swift`.
  - Камера: `private let cameraNode = SKCameraNode()` (стр. 13), инициализация в `didMove(to:)` (стр. 30–92).
  - Pan: `mouseDragged(with:)` (стр. 437–441) — двигает `cameraNode.position` без каких-либо ограничений.
  - Zoom: `scrollWheel(with:)` (стр. 449–455) — фиксированные пределы `max(0.3, min(3.0, …))`, шаг `1.0 - delta * 0.02`.
- «Мир»: единственный визуальный признак границы — `lawn = SKSpriteNode(... 8000×8000)` (стр. 38–41). Эта 8000×8000 — единственная актуальная «карта»; реальная биом-карта (TASK-026/028) ещё не реализована (см. `concept/Current.md:42` — F-15 ❌).
- Тайл-размер: `tileWidth=64, tileHeight=32` (стр. 14–15). Изометрия в `isoPosition(grid:)` (стр. 409–415): мировые X = `(gx - gy) * 32`, Y = `(gx + gy) * 16`.
- Размер сцены / окна: `scene.size = screen.frame.size` (`App/AppDelegate.swift:37`), `scene.scaleMode = .resizeFill`. То есть `scene.size` уже совпадает с размером окна в пикселях, а camera работает в координатах сцены.
- Программный pan тоже есть: `focusCamera(on:duration:)` (стр. 498–503) — двигает `cameraNode` через `SKAction.move`, без clamp.
- Pinch/magnify: **не реализован** (поиск по `magnify`, `NSEventTypeMagnify` ничего не нашёл).

Что переиспользуем:
- `cameraNode`, `world`, `isoPosition(grid:)`, `tileWidth/tileHeight`.
- Существующий `scrollWheel`, `mouseDragged`, `focusCamera`.

Что нужно дописать:
- Расширить диапазон `scrollWheel` (min до ≤ 0.15, max — оставить, но динамически уточнять).
- Динамический `minScale` под текущий `view.bounds` (чтобы AC «вся карта в окне 1280×800» выполнялся на любом размере окна).
- Helper для расчёта мировых границ карты (на основе известного «мира» — пока это 8000×8000 lawn; делаем абстракцию, чтобы при появлении биом-карты подменить одним местом).
- Clamp позиции `cameraNode` в `mouseDragged` и в `focusCamera`.
- Реакция на resize окна (`didChangeSize(_:)` у `SKScene`) — пересчёт min-зум и повторный clamp.
- Опционально (под user-scenario «или пинча»): handler `magnify(with:)`.

Связанные модули (НЕ трогаем): `UnitSprites.swift` (использует свои `tileWidth/tileHeight`), `LifeSimulationManager`, `CitizenManager`, `SceneBridge`, `ContentView` — на pan/zoom не завязаны.

### Архитектурное решение

**Подход:** камера-clamp + динамический min-zoom, без рефакторинга. Всё помещается в один файл `GameScene.swift` — рядом с уже существующими `mouseDragged` и `scrollWheel`. Никакой новый «CameraController» не нужен: задача S, абстракция через приватные методы достаточна.

**Источник «границ мира».** До TASK-028 у нас единственный физический «мир» — `lawn` 8000×8000. После TASK-028 будет настоящая биом-карта с известным `mapTilesPerSide` (≥256). Чтобы не переписывать дважды, заводим один computed-`worldBoundsInScene: CGRect` поверх `tileWidth/tileHeight` и константы `mapTilesPerSide` (по умолчанию 256). На текущей стадии (до TASK-028) это даёт прямоугольник изометрической карты 256×256 тайлов: ширина `256 * tileWidth = 16384`, высота `256 * tileHeight = 8192`, центрированный по нулю (как и `lawn`). Это **больше**, чем 8000×8000 lawn, но lawn — лишь подложка; камера ограничивается границами **изометрической карты** (то, к чему относится AC). После TASK-028 константа заменится на чтение `mapTilesPerSide` из источника карты — точечно, в одном computed-property.

**Min-zoom динамический.** AC требует «вся карта целиком на 1280×800». Формально: `minScale = max(worldBoundsInScene.width / view.bounds.width, worldBoundsInScene.height / view.bounds.height)`. Так как `cameraNode` масштабирует **обратно** (xScale > 1 = «дальше»), при scale = это значение камера ровно вмещает карту. На окне 1280×800 и карте 256×256: `min(scale_x = 16384/1280 = 12.8, scale_y = 8192/800 = 10.24)` → minScale ≈ 12.8. Это **сильно больше** 0.15 — то есть AC «не более ×0.15» (минимум зума, который игрок может выкрутить) технически означает: scale ≥ 0.15 на ближнем конце уже выполняется, а на дальнем конце нужно разрешить очень большие значения xScale. **Переинтерпретация AC:** в постановке «×0.15» — это «×0.15 от 1:1» в восприятии игрока, что соответствует «уменьшение в ~6.67 раз». В терминах `SKCameraNode.xScale` это **большее** значение xScale. То есть мы расширяем верхний предел `xScale` с 3.0 до значения, при котором карта помещается, и это значение динамическое (зависит от окна). Нижний предел 0.3 оставим как «максимальный зум-ин» (ближний детальный план). Если в реальности AC хочет именно scale = 0.15 (физически меньше 1:1 — это уже было), то 0.15 < 0.3 — текущий минимум, надо просто опустить `minZoomIn` до 0.15 либо ниже. **Реализуем оба:** `minZoomIn = 0.15`, `maxZoomOut = dynamicFitScale * 1.05` (5% запас, чтобы edge-of-map был виден).

**Pan-clamp.** При каждом изменении `cameraNode.position` ограничиваем так, чтобы видимый rect камеры (центр ± `view.bounds.size * xScale / 2`) пересекался с `worldBoundsInScene` минимум на «1 тайл». То есть `position.x ∈ [world.minX - visibleW/2 + tileWidth, world.maxX + visibleW/2 - tileWidth]`. На «сильно увеличенном» зуме (`visibleW > worldW`) clamp вырождается — просто центрируем камеру.

**Resize окна.** `SKScene.didChangeSize(_ oldSize:)` — пересчитать `maxZoomOut` и заново применить clamp текущего scale + position. Это закрывает edge case с fullscreen / resize и edge case «zoom-in у края карты».

**Pinch (опционально, минимально).** Добавляем `override func magnify(with event: NSEvent)`: `scale = clamp(cameraNode.xScale / (1 + event.magnification), min, max)`. Это даёт user-scenario «пинч» без расширения скоупа.

### Пошаговая декомпозиция

> ⚠️ Исполнитель: следуй строго по порядку. Шаг непонятен — НЕ импровизируй, возвращай задачу через сообщение.

1. **Константы карты и helper-границ** `[AC:1,2,4]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Место: рядом с `tileWidth/tileHeight` (после стр. 15) и в разделе «MARK: - Камера: pan / zoom» (после стр. 427).
   - Добавить приватные константы:
     ```swift
     private let mapTilesPerSide: Int = 256        // F-15; источник: PM AC-2.
                                                    // После TASK-028 заменить на чтение из биом-карты.
     private let minZoomIn: CGFloat = 0.15         // AC-1: минимальный зум-ин (детальный план).
                                                    // ВНИМАНИЕ: 0.15 здесь — нижняя граница xScale (ближний зум).
     ```
   - Добавить приватный computed:
     ```swift
     /// Мировые границы изометрической карты в координатах сцены.
     /// Центрирован по (0,0), как существующий lawn.
     /// Размер: 256 тайлов даёт ширину 256*tileWidth, высоту 256*tileHeight.
     private var worldBoundsInScene: CGRect {
         let w = CGFloat(mapTilesPerSide) * tileWidth
         let h = CGFloat(mapTilesPerSide) * tileHeight
         return CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
     }
     /// Зум, при котором карта целиком помещается в текущее окно (с 5% запасом).
     /// На больших окнах — меньше, на маленьких — больше. Возвращает >= minZoomIn.
     private var maxZoomOut: CGFloat {
         guard let view = view, view.bounds.width > 0, view.bounds.height > 0 else {
             return 13.0  // safe-fallback: 256 тайлов на ~1280 px при tileWidth=64.
         }
         let fitX = worldBoundsInScene.width  / view.bounds.width
         let fitY = worldBoundsInScene.height / view.bounds.height
         return max(fitX, fitY) * 1.05
     }
     ```

2. **Динамические пределы scrollWheel** `[AC:1,2,3,5]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Метод: `scrollWheel(with:)` (стр. 449–455).
   - Что меняем: заменить захардкоженные `max(0.3, min(3.0, …))` на `clamp(minZoomIn, maxZoomOut, ...)`. После присвоения scale — позвать `clampCameraPosition()`.
   - Скелет:
     ```swift
     override func scrollWheel(with event: NSEvent) {
         let delta = event.scrollingDeltaY
         let factor: CGFloat = 1.0 - delta * 0.02
         // Защита от NaN / Inf (edge-case: очень быстрый скролл может дать невалидный factor).
         guard factor.isFinite, factor > 0 else { return }
         let raw = cameraNode.xScale * factor
         let newScale = min(maxZoomOut, max(minZoomIn, raw))
         cameraNode.xScale = newScale
         cameraNode.yScale = newScale
         clampCameraPosition()
     }
     ```

3. **Clamp позиции камеры (helper'ы)** `[AC:4,5]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Место: в разделе «MARK: - Камера: pan / zoom» рядом с другими камера-методами.
   - Добавить ДВА метода: чистый `clampedPosition(_:scale:)` (используется и при pan, и при programmatic focus) и тонкую обёртку `clampCameraPosition()` поверх него:
     ```swift
     /// Чистая функция: возвращает позицию камеры, ограниченную так,
     /// чтобы visible-rect пересекался с миром минимум на 1 тайл.
     /// Если карта ВПИСЫВАЕТСЯ в окно на текущем зуме (visibleW >= worldW) — центрируем по оси.
     private func clampedPosition(_ point: CGPoint, scale: CGFloat) -> CGPoint {
         guard let view = view else { return point }
         let visibleW = view.bounds.width  * scale
         let visibleH = view.bounds.height * scale
         let world = worldBoundsInScene
         var p = point
         if visibleW >= world.width {
             p.x = world.midX
         } else {
             let lo = world.minX - visibleW / 2 + tileWidth
             let hi = world.maxX + visibleW / 2 - tileWidth
             p.x = min(hi, max(lo, p.x))
         }
         if visibleH >= world.height {
             p.y = world.midY
         } else {
             let lo = world.minY - visibleH / 2 + tileHeight
             let hi = world.maxY + visibleH / 2 - tileHeight
             p.y = min(hi, max(lo, p.y))
         }
         return p
     }

     /// Удобный shortcut: подтянуть текущую позицию камеры под её же текущий scale.
     private func clampCameraPosition() {
         cameraNode.position = clampedPosition(cameraNode.position, scale: cameraNode.xScale)
     }
     ```

4. **Pan с ограничением** `[AC:4]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Метод: `mouseDragged(with:)` (стр. 437–441).
   - Что меняем: после изменения `cameraNode.position` вызвать `clampCameraPosition()`.
   - Скелет:
     ```swift
     override func mouseDragged(with event: NSEvent) {
         if dragStarted { dragMoved = true }
         cameraNode.position.x -= event.deltaX
         cameraNode.position.y += event.deltaY
         clampCameraPosition()
     }
     ```

5. **Clamp в programmatic focusCamera** `[AC:4]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Метод: `focusCamera(on:duration:)` (стр. 498–503).
   - Что меняем: целевую точку прогнать через `clampedPosition` ДО запуска `SKAction`, чтобы анимация уходила сразу к допустимой точке.
   - Скелет:
     ```swift
     func focusCamera(on grid: GridPoint, duration: TimeInterval) {
         let target = clampedPosition(isoPosition(grid: grid), scale: cameraNode.xScale)
         let move = SKAction.move(to: target, duration: duration)
         move.timingMode = .easeOut
         cameraNode.run(move)
     }
     ```

6. **Реакция на resize окна** `[AC:2,5]` (edge case: окно меняется по размеру)
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Метод: новый override `didChangeSize(_:)`.
   - Что меняем: при resize пересчитать `maxZoomOut` и подтянуть текущий scale + position.
   - Скелет:
     ```swift
     override func didChangeSize(_ oldSize: CGSize) {
         super.didChangeSize(oldSize)
         // Если текущий scale больше нового допустимого maxZoomOut — подтянуть.
         let s = min(maxZoomOut, max(minZoomIn, cameraNode.xScale))
         cameraNode.xScale = s
         cameraNode.yScale = s
         clampCameraPosition()
     }
     ```

7. **Pinch / magnify (минимальный handler)** `[AC:1,5]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift`
   - Место: рядом со `scrollWheel`.
   - Что меняем: добавить override `magnify(with:)` — тот же clamp, что и в scrollWheel.
   - Скелет:
     ```swift
     override func magnify(with event: NSEvent) {
         // event.magnification: положительная — пользователь раздвинул пальцы (зум-ин).
         let factor: CGFloat = 1.0 - event.magnification
         guard factor.isFinite, factor > 0 else { return }
         let raw = cameraNode.xScale * factor
         let newScale = min(maxZoomOut, max(minZoomIn, raw))
         cameraNode.xScale = newScale
         cameraNode.yScale = newScale
         clampCameraPosition()
     }
     ```
   - Если в ходе ручной проверки направление пинча окажется инвертированным — поменять знак на `1.0 + event.magnification`. Это **единственное** допустимое отклонение от плана без возврата к лиду.

8. **Финальная проверка существующих lawn-границ** `[AC:4]`
   - Файл: `Sources/CityDeveloper/Game/GameScene.swift:38`
   - Действие: убедиться, что `lawn` (8000×8000) ≥ `worldBoundsInScene` хотя бы по одной оси. По расчёту: world = 16384×8192, lawn = 8000×8000 — **lawn МЕНЬШЕ карты по X**. Это вскроется визуально: на дальнем зуме по краям будет видна не зелень, а `Palette.skyDay`. Допустимо: задача про границы камеры, а не про визуал lawn (TASK-028 всё равно его заменит). **Не трогаем lawn** — это явный скоуп `Что НЕ делаем` смежной TASK-028. Просто оставляем коммент рядом с lawn:
     ```swift
     // Lawn — временная подложка; меньше реальных границ карты (16384×8192).
     // После TASK-028 будет заменён на тайл-рендер биомов.
     ```

### Edge cases (явно обработать)

- [ ] Очень быстрый scroll → `factor` может быть `≤0` или `nan` при экстремальных delta. Защита: `guard factor.isFinite, factor > 0 else { return }` (шаг 2). Обнаружено в `GameScene.swift:449-455`.
- [ ] `view.bounds` ещё не рассчитан (между `didMove(to:)` и первым layout): `maxZoomOut` возвращает safe-fallback 13.0 (шаг 1). Обнаружено в `GameScene.swift:30` (`scaleMode = .resizeFill`).
- [ ] Окно меняется по размеру / fullscreen → `didChangeSize(_:)` пересчитывает (шаг 6).
- [ ] Камера у края + zoom-in → `clampCameraPosition()` после смены scale (шаги 2, 6, 7) подтягивает позицию обратно в допустимый диапазон.
- [ ] Карта изменит размер при TASK-030 → достаточно поменять `mapTilesPerSide` (или сделать его computed от состояния карты) — clamp/maxZoomOut пересчитаются на следующем тике. Без перезапуска приложения. Задокументировано комментарием в шаге 1.
- [ ] Programmatic `focusCamera` на координату за пределами карты → `clampedPosition()` срезает (шаг 5). Обнаружено в `GameScene.swift:498-503`.
- [ ] Карта меньше окна на каком-то экстремальном зуме (visibleW ≥ world.width) → центрируем камеру вместо clamp (шаги 3, 5).

### Файлы для изменения

- `Sources/CityDeveloper/Game/GameScene.swift` — все изменения: новые приватные методы `worldBoundsInScene`, `maxZoomOut`, `clampCameraPosition()`, `clampedPosition(_:scale:)`, `didChangeSize(_:)`, `magnify(with:)`; правки в `scrollWheel`, `mouseDragged`, `focusCamera`.

### Файлы НЕ трогать

- `Sources/CityDeveloper/Game/UnitSprites.swift` — у него свои `tileWidth/tileHeight`, общая константа здесь не нужна.
- `Sources/CityDeveloper/App/AppDelegate.swift` — размер сцены уже подбирается под экран; вмешательство не нужно.
- `Sources/CityDeveloper/UI/SceneBridge.swift` / `ContentView.swift` — pan/zoom не проходят через мост.
- Lawn (`GameScene.swift:38`) — явный скоуп TASK-028; добавляем только комментарий.
- `concept/Current.md`, `concept/Diff.md` — обновляет `/run` после исполнения.

### Команды проверки (для DoD)

- Компиляция: `swift build` из корня репозитория.
- Тесты (smoke): `swift test` (если есть тесты на pan/zoom — их нет, но не должны сломаться существующие; убедиться, что таргет `CityDeveloperTests` собирается).
- Ручная проверка:
  1. Запустить приложение: `swift run CityDeveloper` (или Xcode-запуск).
  2. Войти в explore-режим (по hotkey из настроек).
  3. Колесом «от себя» вывести камеру в обзорный режим — убедиться, что карта (или, до TASK-028, её зелёная часть + видимые здания) уменьшается так, что её края попадают в кадр.
  4. Колесом «к себе» — приблизить до уровня одиночного здания (как раньше).
  5. Перетащить мышью карту к каждому из четырёх углов — убедиться, что камера упирается, и хотя бы часть карты остаётся в кадре.
  6. Изменить размер окна (fullscreen ↔ обычный) — обзорный зум по-прежнему вмещает карту.
  7. Прокрутить колесо «до упора» в обе стороны — нет рывков, нет вылета, нет крэшей в `errors.log`.
  8. На трекпаде сделать пинч сжать/раздвинуть — поведение симметрично колесу.

### Сложность

`middle`

**Обоснование:** один файл, но с математикой (изометрия + clamp + динамический min-zoom) и неочевидными edge cases (NaN, resize, programmatic focus); требует понимания `SKCameraNode` и координат сцены. Для джуна без знакомства со SpriteKit — рискованно.

### Ожидаемое время

S (≤2ч)

---

## ✅ Исполнение

_Исполнитель: —_
_Сложность: middle_
_Объём: S_

### Definition of Done

#### Функциональные
- [x] Все AC выполнены
- [x] Done-критерий проверен в реальном использовании (на минимальном зуме вся карта видна, камера не уходит за границы)

#### Технические
- [x] Компиляция/линтер без новых ошибок
- [x] Тесты не сломаны
- [x] Нет хардкод-строк (i18n/env где требует проект)

#### Обновление документации
- [ ] `current.md`: F-15 → ⚠️ (зум закрыт, осталась реинициализация)
- [ ] `diff.md`: D-15 не закрывать — закрывается только после TASK-030
- [ ] Новые идеи → `backlog.md`, новые баги → `bugs.md`

---

## Статус

`[ ] waiting-for-lead` / `[ ] ready` / `[ ] in-progress` / `[ ] review` / `[x] done` / `[ ] skipped`

## Метаданные
- Создана PM: 2026-05-23
- Spec-review: approved
- Blocked-by: TASK-028
- Готова к работе: 2026-05-23
- Lead-model: opus
- Plan-review: revised
- Завершена: 2026-05-22
- Коммит: 367cd28
