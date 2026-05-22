import Foundation

/// Тонкий мост между SwiftUI-панелью и SpriteKit GameScene.
/// Не держит сильных ссылок на scene; все вызовы — на main queue.
final class SceneBridge: ObservableObject {
    weak var scene: GameScene?

    /// Текущий выбранный юнит для SwiftUI overlay-карточки.
    /// Источник истины — `GameScene.showInspector(forUnitId:)` / `hideInspector()`.
    @Published var selectedUnitInfo: (UnitState, ProjectState)? = nil

    /// Плавно центрирует камеру на изометрической позиции gridPoint.
    func focusOn(gridPoint: GridPoint) {
        scene?.focusCamera(on: gridPoint, duration: 0.4)
    }

    /// Плавно центрирует камеру на юните и открывает попап-инспектор.
    func focusOnUnit(_ unit: UnitState) {
        scene?.focusCamera(on: unit.position, duration: 0.4)
        scene?.showInspector(forUnitId: unit.id)
        // Передаём key-фокус главному окну (cityWindow), чтобы SpriteView получал ввод.
        scene?.view?.window?.makeKey()
    }
}
