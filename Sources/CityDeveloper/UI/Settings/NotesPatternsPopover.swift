import SwiftUI

/// Popover showing the 4 built-in parsing patterns with examples.
struct NotesPatternsPopover: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Шаблоны парсинга задач")
                .font(.system(size: 15, weight: .semibold))

            Divider()

            patternsTable

            Divider()

            Text("Совпадения проверяются в порядке сверху вниз.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(minWidth: 480, maxWidth: 560)
    }

    // MARK: - Table

    private var patternsTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            patternRow(
                number: "1",
                pattern: "- [x] [project: <id>] <title>",
                example: "- [x] [project: myapp] починил баг авторизации",
                note: "project = myapp, title = «починил баг авторизации»"
            )
            Divider()
            patternRow(
                number: "2",
                pattern: "- [x] <title> #<project>",
                example: "- [x] добавил тёмную тему #myapp",
                note: "project = myapp, title = «добавил тёмную тему»"
            )
            Divider()
            patternRow(
                number: "3",
                pattern: "~~<title>~~ #<project>",
                example: "~~fix login~~ #myapp",
                note: "project = myapp, title = «fix login»"
            )
            Divider()
            patternRow(
                number: "4",
                pattern: "- [x] <project>: <title>",
                example: "- [x] myapp: исправил краш при запуске",
                note: "project = myapp; зарезервировано: project, system, null, none"
            )
        }
    }

    private func patternRow(number: String, pattern: String, example: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(number)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 14, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pattern)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                    Text(example)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.07))
                        .cornerRadius(4)
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
