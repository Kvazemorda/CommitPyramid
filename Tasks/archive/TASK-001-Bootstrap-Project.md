# TASK-001: Bootstrap проекта (Swift Package + базовое окно)

## Связь
- Подготовка к F-01, F-02 (фундамент, без D-XX напрямую)
- **Приоритет:** P0

---

## 📋 Постановка от менеджера

_Автор: assistant_
_Дата: 2026-05-21_

### Что хотим
Создать минимальный работающий каркас macOS-приложения CityDeveloper: Swift Package
executable, который запускается, открывает окно, рисует пустую SwiftUI View с тестовым
SpriteKit-сценой внутри (например, заглушка с лугом и одним кубиком). Цель — иметь
точку входа, в которую будут вкладываться все последующие задачи.

### Пользовательский сценарий
1. Из терминала запускаю `swift run CityDeveloper`.
2. Открывается окно приложения с тестовой сценой.
3. Окно нормально закрывается, приложение завершается.

### Acceptance criteria
- [ ] `swift build` проходит без ошибок и без warnings
- [ ] `swift run CityDeveloper` запускает приложение
- [ ] Открывается NSWindow с SwiftUI ContentView
- [ ] В ContentView виден `SKView` со сценой (зелёный фон + один спрайт)
- [ ] Закрытие окна корректно завершает процесс

### Дизайн
Не применимо — заглушка.

### Done-критерий
Каркас собирается и запускается; есть точка входа для последующих задач.

---

## 🛠 Технический разбор от тимлида

_Автор: assistant (lead-mode)_
_Дата: 2026-05-21_
_Статус: [x] готов_

### Архитектурное решение
Используем Swift Package Manager (executable target), потому что полного Xcode нет, а
SPM поддерживает SwiftUI и SpriteKit на macOS 14+ при наличии CLT и SDK. Структура:

```
CityDeveloper/
├── Package.swift
├── Sources/
│   └── CityDeveloper/
│       ├── CityDeveloperApp.swift   ← @main, App protocol
│       ├── App/
│       │   ├── AppDelegate.swift    ← NSApplicationDelegate
│       │   └── WindowConfigurator.swift
│       ├── UI/
│       │   └── ContentView.swift    ← SwiftUI хост для SpriteKit
│       └── Game/
│           └── GameScene.swift      ← SKScene с заглушкой
└── Resources/                       ← пусто, на будущее
```

### Пошаговая декомпозиция
1. Создать `Package.swift` (Swift 5.10 tools, macOS 14, executable target).
2. `Sources/CityDeveloper/CityDeveloperApp.swift` — `@main`, `App` protocol, `WindowGroup`.
3. `Sources/CityDeveloper/UI/ContentView.swift` — `SpriteView` обёртка вокруг
   `GameScene()`.
4. `Sources/CityDeveloper/Game/GameScene.swift` — `SKScene` с зелёным фоном
   `SKColor(red: 0.29, green: 0.40, blue: 0.25, alpha: 1.0)` (nileGreen из
   DesignConcept) и одним `SKShapeNode` посередине.
5. Скомпилировать `swift build`.

### Edge cases
- [ ] CLT без Xcode — SPM должен справиться. Если упадёт на SwiftUI — придётся
      переходить на чистый AppKit для bootstrap.
- [ ] macOS deployment target — указываем 14.0 минимум.

### Файлы для изменения
- `Package.swift` (создать)
- `Sources/CityDeveloper/*` (создать)

### Команды проверки
- Компиляция: `swift build`
- Запуск: `swift run CityDeveloper`

### Сложность: `middle`
### Объём: S

---

## ✅ Исполнение

### Definition of Done
- [ ] `swift build` проходит
- [ ] `swift run` запускает приложение, видно окно с заглушкой
- [ ] `Current.md`: добавить инфо о появлении кода (но F-01/F-02 ещё ❌)

---

### Definition of Done (факт)
- [x] `swift build` проходит
- [x] `swift run CityDeveloper` запускает приложение
- [x] Открывается NSWindow (через AppKit + NSHostingView)
- [x] В ContentView виден `SKView` со сценой (зелёный фон + центральная отметка)
- [x] Закрытие через статус-бар «Выйти» корректно завершает процесс

Артефакты:
- `Package.swift`
- `Sources/CityDeveloper/main.swift`
- `Sources/CityDeveloper/App/AppDelegate.swift`
- `Sources/CityDeveloper/UI/ContentView.swift`
- `Sources/CityDeveloper/Game/GameScene.swift`
- `Sources/CityDeveloper/Theme/Palette.swift`

**Примечание:** Архитектурное решение в процессе работы изменено — отказались от
SwiftUI App protocol (`@main`) в пользу AppKit `NSApplicationDelegate` + `NSHostingView`,
потому что для F-01 требуется полный контроль над `NSWindow` (level, collectionBehavior,
ignoresMouseEvents), который SwiftUI WindowGroup не даёт.

## Статус
`[x] done`

## Метаданные
- Создана: 2026-05-21
- Завершена: 2026-05-21
