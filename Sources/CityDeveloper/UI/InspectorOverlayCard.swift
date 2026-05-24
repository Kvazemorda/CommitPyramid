import SwiftUI

/// SwiftUI-overlay карточки инспектора в screen-fixed позиции.
/// Не путать с SpriteKit-попапом `InspectorPanel` — он живёт в world-coords
/// и остаётся как-есть. Эта карточка — отдельный визуальный слой поверх
/// `SpriteView`, прижатый к правой стороне по вертикальному центру окна.
///
/// Источник истины — `SceneBridge.selectedUnitInfo`, обновляется в
/// `GameScene.showInspector(forUnitId:)` и `hideInspector()`.
struct InspectorOverlayCard: View {
    @ObservedObject var bridge: SceneBridge
    @ObservedObject var appSettings: AppSettings
    let tasksJsonlPath: URL

    var body: some View {
        Group {
            if let info = bridge.selectedUnitInfo {
                cardView(unit: info.0, project: info.1)
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private func cardView(unit: UnitState, project: ProjectState) -> some View {
        let source = TaskSourceFormatter.format(
            taskSource: unit.taskSource,
            settings: appSettings,
            tasksJsonlPath: tasksJsonlPath
        )
        return VStack(alignment: .leading, spacing: 6) {
            Text(project.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.paletteInkDark)

            Text("Жителей: \(bridge.populationByProject[project.id] ?? 0)")
                .font(.system(size: 10))
                .foregroundColor(.paletteInkDark.opacity(0.6))

            Text("\(unit.kind.label), stage \(unit.tier)")
                .font(.system(size: 10))
                .foregroundColor(.paletteInkDark.opacity(0.6))

            Text(unit.taskTitle ?? "(без названия)")
                .font(.system(size: 12))
                .foregroundColor(.paletteInkDark)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("Источник: \(source.short)")
                .font(.system(size: 10))
                .foregroundColor(.paletteInkDark.opacity(0.6))
                .lineLimit(2)
                .truncationMode(.middle)
                .help(source.full)

            Text(Self.dateFormatter.string(from: unit.taskTs))
                .font(.system(size: 10))
                .foregroundColor(.paletteInkDark.opacity(0.5))
        }
        .padding(12)
        .frame(maxWidth: 260, alignment: .leading)
        .background(Color.paletteSandLight)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        .padding(.trailing, 16)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy HH:mm"
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = .current
        return f
    }()
}
