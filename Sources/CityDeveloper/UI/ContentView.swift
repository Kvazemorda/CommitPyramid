import SwiftUI
import SpriteKit

struct ContentView: View {
    let scene: GameScene
    @ObservedObject var engine: CityEngine
    @ObservedObject var modeManager: WindowModeManager
    @ObservedObject var bridge: SceneBridge
    let journalController: JournalWindowController

    // Panel state поднят сюда, чтобы сохранялся между открытиями окна журнала
    @State private var collapsed: Bool = false
    @State private var selectedProject: String? = nil
    @State private var dateFrom: Date = Date()
    @State private var dateTo: Date = Date()
    @State private var didInitDates: Bool = false

    // Отдельный gate для кнопки журнала: показывается только ПОСЛЕ
    // завершения transition в explore (AC3). Меняется через asyncAfter.
    @State private var buttonVisible: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SpriteView(scene: scene, preferredFramesPerSecond: 60)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // SwiftUI overlay-карточка инспектора: trailing center.
            // allowsHitTesting(false) — клики проходят через карточку к SpriteView.
            InspectorOverlayCard(bridge: bridge)
                .allowsHitTesting(false)

            if buttonVisible {
                Button {
                    journalController.show(
                        engine: engine,
                        bridge: bridge,
                        collapsed: $collapsed,
                        selectedProject: $selectedProject,
                        dateFrom: $dateFrom,
                        dateTo: $dateTo,
                        didInitDates: $didInitDates
                    )
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Журнал событий")
                .padding(.trailing, 16)
                .padding(.bottom, 24)
                .transition(.opacity)
            }
        }
        .onChange(of: modeManager.isExplore) { _, newValue in
            if newValue {
                // Показываем кнопку только после завершения transition.
                // 0.20 ≥ длительности .easeOut(0.18), используемой в WindowModeManager.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    // Guard: режим мог быстро переключиться обратно в behind.
                    if modeManager.isExplore {
                        withAnimation(.easeOut(duration: 0.18)) {
                            buttonVisible = true
                        }
                    }
                }
            } else {
                // Выход из explore — кнопку прячем немедленно.
                buttonVisible = false
            }
        }
        .onAppear {
            // На случай старта приложения сразу в explore-режиме.
            buttonVisible = modeManager.isExplore
        }
    }
}
