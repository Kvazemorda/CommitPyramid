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
        VStack(alignment: .leading, spacing: 6) {
            Text(project.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.paletteInkDark)

            Text("\(Self.russianKind(unit.kind)), stage \(unit.tier)")
                .font(.system(size: 10))
                .foregroundColor(.paletteInkDark.opacity(0.6))

            Text(unit.taskTitle ?? "(без названия)")
                .font(.system(size: 12))
                .foregroundColor(.paletteInkDark)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

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

    private static func russianKind(_ kind: UnitKind) -> String {
        switch kind {
        case .shack:     return "Лачуга"
        case .house:     return "Дом"
        case .villa:     return "Вилла"
        case .well:      return "Колодец"
        case .road:      return "Дорога"
        case .warehouse: return "Склад"
        case .workshop:  return "Мастерская"
        case .raw:       return "Сырьевая яма"
        case .market:    return "Рынок"
        case .forum:     return "Форум"
        case .temple:    return "Храм"
        case .obelisk:   return "Обелиск"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy HH:mm"
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = .current
        return f
    }()
}
