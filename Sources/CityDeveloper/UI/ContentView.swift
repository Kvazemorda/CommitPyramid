import SwiftUI
import SpriteKit

struct ContentView: View {
    let scene: GameScene
    @ObservedObject var engine: CityEngine
    @ObservedObject var modeManager: WindowModeManager
    @ObservedObject var bridge: SceneBridge
    let journalController: JournalWindowController
    /// Источник конфигурации источников данных (репо/notes) — нужен инспектору
    /// для расшифровки UnitState.taskSource в человекочитаемое имя.
    @ObservedObject var appSettings: AppSettings
    /// Текущий путь к tasks.jsonl — показывается в инспекторе для юнитов,
    /// у которых source==nil (события из tasks.jsonl без явного source-ключа).
    let tasksJsonlPath: URL

    // Panel state поднят сюда, чтобы сохранялся между открытиями окна журнала
    @State private var collapsed: Bool = false
    @State private var selectedProject: String? = nil
    @State private var dateFrom: Date = Date()
    @State private var dateTo: Date = Date()
    @State private var didInitDates: Bool = false
    @State private var journalKindFilter: JournalKindFilter = .all

    // Отдельный gate для кнопки журнала: показывается только ПОСЛЕ
    // завершения transition в explore (AC3). Меняется через asyncAfter.
    @State private var buttonVisible: Bool = false

    // F-17: контекстный popup — клик по пустой части квартала
    @State private var contextInput: SceneBridge.InputRequest? = nil
    @FocusState private var rootFocused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                GameSpriteView(scene: scene)
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // SwiftUI overlay-карточка инспектора: trailing center.
                // allowsHitTesting(false) — клики проходят через карточку к SpriteView.
                InspectorOverlayCard(
                    bridge: bridge,
                    appSettings: appSettings,
                    tasksJsonlPath: tasksJsonlPath
                )
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
                            didInitDates: $didInitDates,
                            journalKindFilter: $journalKindFilter
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

                // F-17: контекстный popup задачи, позиционируется в точке клика.
                // viewPoint уже в системе SKView (origin top-left, Y вниз) —
                // та же система, что у SwiftUI внутри GeometryReader.
                if let ci = contextInput {
                    let popupW: CGFloat = 320, popupH: CGFloat = 140
                    let clampedX = min(max(ci.viewPoint.x, popupW / 2 + 8),
                                       geo.size.width - popupW / 2 - 8)
                    let clampedY = min(max(ci.viewPoint.y, popupH / 2 + 8),
                                       geo.size.height - popupH / 2 - 8)
                    TaskInputPopupView(
                        projectId: ci.projectId,
                        onSubmit: { title in
                            engine.ingestTaskCompletion(
                                project: ci.projectId,
                                title: title,
                                taskId: nil,
                                source: "journal",
                                ts: Date()
                            )
                            withAnimation(.easeOut(duration: 0.15)) {
                                contextInput = nil
                            }
                        },
                        onCancel: {
                            withAnimation(.easeOut(duration: 0.15)) {
                                contextInput = nil
                            }
                        }
                    )
                    .frame(width: popupW)
                    .position(x: clampedX, y: clampedY)
                    .transition(.opacity)
                    .zIndex(1000)
                }
            }
            .focusable()
            .focused($rootFocused)
            .onAppear { rootFocused = true }
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
                    contextInput = nil
                }
            }
            .onAppear {
                // На случай старта приложения сразу в explore-режиме.
                buttonVisible = modeManager.isExplore
            }
            .onReceive(bridge.inputRequest) { req in
                withAnimation(.easeIn(duration: 0.2)) {
                    contextInput = req
                }
            }
            .onKeyPress(.escape) {
                if contextInput != nil {
                    withAnimation(.easeOut(duration: 0.15)) { contextInput = nil }
                    return .handled
                }
                return .ignored
            }
        }
    }
}
