import Foundation
import Combine

/// Тонкий мост между SwiftUI-панелью и SpriteKit GameScene.
/// Не держит сильных ссылок на scene; все вызовы — на main queue.
final class SceneBridge: ObservableObject {
    weak var scene: GameScene?

    /// Текущий выбранный юнит для SwiftUI overlay-карточки.
    /// Источник истины — `GameScene.showInspector(forUnitId:)` / `hideInspector()`.
    @Published var selectedUnitInfo: (UnitState, ProjectState)? = nil

    /// Активное количество жителей по projectId. Обновляется
    /// `CitizenManager.tick()` (≈ раз в 2 сек). Пустой словарь — pre-tick.
    @Published var populationByProject: [String: Int] = [:]

    // MARK: - F-17 Journal Input

    /// Запрос контекстного ввода задачи: projectId + позиция в системе SKView
    /// (origin top-left, Y вниз) — та же, что SwiftUI GeometryReader внутри ContentView.
    struct InputRequest {
        let projectId: String
        /// Точка в координатах SKView (NSView-система, origin top-left).
        let viewPoint: CGPoint
    }

    /// Publisher для контекстного popup: клик по пустой клетке квартала.
    /// GameScene отправляет, ContentView подписывается через `.onReceive`.
    let inputRequest = PassthroughSubject<InputRequest, Never>()

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
