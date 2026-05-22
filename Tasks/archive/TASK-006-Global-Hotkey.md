# TASK-006: Глобальный hotkey ⌘⌥G для переключения explore-режима

## Связь
- **F-01** Окно «всегда позади» + explore-режим
- **D-01** (закрывает остаток)
- **Приоритет:** P0

## 📋 Постановка
Сейчас переключение в explore-режим возможно только через статус-бар, что неудобно
(особенно когда руки на клавиатуре). Нужен глобальный системный hotkey ⌘⌥G — работает
из любого приложения без необходимости accessibility prompt.

## 🛠 Технический разбор (ready for run)

### Анализ
- В behind-режиме `cityWindow.ignoresMouseEvents = true` — кликнуть в окно нельзя.
- `NSEvent.addGlobalMonitor(...)` требует accessibility permission (Privacy → Accessibility),
  что неудобно для пользователя.
- **Carbon `RegisterEventHotKey`** работает без accessibility permission и переживает
  переключение приложений. API дeprecated, но всё ещё стабильно.

### План
1. Создать `App/GlobalHotkey.swift` — обёртка над Carbon API.
2. Регистрировать hotkey в `AppDelegate.applicationDidFinishLaunching`.
3. Дефолтная комбинация: kVK_ANSI_G (keyCode = 5) + cmdKey + optionKey.
4. Handler — `modeManager.toggle()` через DispatchQueue.main.

### Каркас кода (фрагмент)

```swift
import Carbon

final class GlobalHotkey {
    private var hotKeyRef: EventHotKeyRef?
    private var handler: () -> Void = {}
    private var eventHandlerRef: EventHandlerRef?

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        var hotKeyID = EventHotKeyID(signature: OSType(0x43545944), id: 1)  // 'CTYD'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(),
                            0, &hotKeyRef)

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let unmanaged = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, ctx in
            let me = Unmanaged<GlobalHotkey>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { me.handler() }
            return noErr
        }, 1, &spec, unmanaged, &eventHandlerRef)
    }

    deinit {
        if let h = hotKeyRef { UnregisterEventHotKey(h) }
        if let e = eventHandlerRef { RemoveEventHandler(e) }
    }
}
```

### Edge cases
- Конфликт с уже зарегистрированным hotkey другого приложения — RegisterEventHotKey
  вернёт ошибку. Залогировать и fallback: показать в статус-баре «Hotkey не доступен».
- Если settings UI появится (F-14) — позволить переназначить комбинацию.

### Файлы
- Создать: `Sources/CityDeveloper/App/GlobalHotkey.swift`
- Изменить: `Sources/CityDeveloper/App/AppDelegate.swift` (зарегистрировать)

### Команды проверки
- `swift build`
- Запуск, нажатие ⌘⌥G в любом приложении → окно поднимается в explore. Повторный ⌘⌥G →
  обратно в behind.

### Сложность: middle
### Объём: S

## Статус
`[x] done` _(2026-05-22)_

## ✅ Definition of Done (факт)
- [x] `App/GlobalHotkey.swift` — обёртка над Carbon `RegisterEventHotKey` / `InstallEventHandler`
- [x] Регистрируется в `AppDelegate.applicationDidFinishLaunching` (kVK_ANSI_G + cmdKey | optionKey)
- [x] Handler дёргает `modeManager.toggle()` через `DispatchQueue.main.async`
- [x] Конфликт регистрации (другое приложение уже занимает ⌘⌥G) — логируется через `NSLog`, приложение не падает
- [x] `unregister()` вызывается в `deinit`
