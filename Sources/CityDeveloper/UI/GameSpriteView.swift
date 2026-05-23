import SwiftUI
import SpriteKit

/// NSViewRepresentable-обёртка над SKView, которая форвардит scrollWheel / magnify
/// в сцену. Заменяет SwiftUI SpriteView, не форвардящий эти события на macOS.
struct GameSpriteView: NSViewRepresentable {
    let scene: GameScene

    func makeNSView(context: Context) -> GameSKView {
        let view = GameSKView()
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        view.showsFPS = false
        view.showsNodeCount = false
        view.presentScene(scene)
        return view
    }

    func updateNSView(_ view: GameSKView, context: Context) {}
}

final class GameSKView: SKView {
    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        (scene as? GameScene)?.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        (scene as? GameScene)?.magnify(with: event)
    }
}
