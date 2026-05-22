import SwiftUI

struct ProjectCard: View {
    let project: ProjectState
    let population: Int
    let onTap: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = .current
        return f
    }()

    private var decayColor: Color {
        switch project.decayLevel {
        case 0:         return .paletteSuccess
        case 1, 2:      return .paletteWarning
        default:        return .paletteDanger
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Decay indicator bar (4 pt)
                Rectangle()
                    .fill(decayColor)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.paletteInkDark)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text("Юнитов: \(project.unitIds.count)")
                        Text("Stage \(project.stage)")
                        Text("Жителей: \(population)")
                        Text(Self.dateFormatter.string(from: project.lastActivityAt))
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.paletteInkDark.opacity(0.6))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .background(Color.paletteSandLight)
        .cornerRadius(10)
    }
}
