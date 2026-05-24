import SwiftUI

/// Popover showing the 4 built-in parsing patterns with examples.
struct NotesPatternsPopover: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Шаблоны парсинга задач")
                    .font(.system(size: 15, weight: .semibold))

                Text("Парсер построчно проходит .md-файл и пытается сопоставить каждую строку с одним из 4 шаблонов. Первый совпавший — выигрывает. Из строки извлекаются projectId (= имя квартала в городе) и title (= название юнита, ≤ 500 символов).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Правила для projectId:")
                    .font(.caption.bold())
                    .padding(.top, 4)
                Text("• разрешены латинские буквы, цифры, `_` и `-`. Пробелы, кириллица, точки — НЕ работают;\n• regex-фрагмент: `[A-Za-z0-9_-]+`;\n• для шаблона №4 запрещены ключевые слова: `project`, `system`, `null`, `none` (case-insensitive).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                patternsTable

                Divider()

                Text("Подсказки и edge-cases")
                    .font(.system(size: 13, weight: .semibold))

                Text("• Строка должна быть закрыта чекбоксом `[x]` (заглавная `[X]` не подходит) или ~~зачёркнута~~ — иначе строка игнорируется.\n• Несколько `#тегов` — побеждает ПОСЛЕДНИЙ (шаблон №2 матчит хвост строки).\n• Title очищается от лишних пробелов по краям; внутри пробелы остаются как есть.\n• Если в одной строке смешать шаблон №1 и №4 — выигрывает №1 (приоритет сверху вниз).\n• Повторная обработка той же строки не происходит: для каждого источника хранится sidecar JSON с SHA-256 уже импортированных строк (или, в режиме delete-processed, строка удаляется из .md-файла после импорта).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .frame(minWidth: 520, maxWidth: 620, minHeight: 400, idealHeight: 560)
    }

    // MARK: - Table

    private var patternsTable: some View {
        VStack(alignment: .leading, spacing: 14) {
            patternBlock(
                number: "1",
                pattern: "- [x] [project: <id>] <title>",
                description: "Явная пометка projectId в квадратных скобках в начале — самый надёжный шаблон, нет конфликтов с тегами или двоеточием в title.",
                examples: [
                    ("- [x] [project: myapp] починил баг авторизации",
                     "project = «myapp», title = «починил баг авторизации»"),
                    ("- [x] [project: outbyte-web] деплой v2.4 на staging",
                     "project = «outbyte-web», title = «деплой v2.4 на staging»"),
                    ("- [x] [project: notes] добавил пункт: купить молоко",
                     "project = «notes», title = «добавил пункт: купить молоко» (двоеточие в title — ок)"),
                ]
            )
            Divider()
            patternBlock(
                number: "2",
                pattern: "- [x] <title> #<project>",
                description: "Twitter-стиль: `#тег` в конце строки указывает на квартал. Удобно если ведёшь общий to-do и помечаешь принадлежность хэштегом.",
                examples: [
                    ("- [x] добавил тёмную тему #myapp",
                     "project = «myapp», title = «добавил тёмную тему»"),
                    ("- [x] подготовил отчёт за квартал #finance",
                     "project = «finance», title = «подготовил отчёт за квартал»"),
                    ("- [x] обсудили #design в Slack #marketing",
                     "project = «marketing» (берётся ПОСЛЕДНИЙ тег), title = «обсудили #design в Slack»"),
                ]
            )
            Divider()
            patternBlock(
                number: "3",
                pattern: "~~<title>~~ #<project>",
                description: "Зачёркивание Markdown'ом (`~~текст~~`) вместо чекбокса. Удобно если ты не пользуешься чекбоксами, а вычёркиваешь сделанное.",
                examples: [
                    ("~~fix login crash~~ #myapp",
                     "project = «myapp», title = «fix login crash»"),
                    ("~~созвон с клиентом 30 мин~~ #consulting",
                     "project = «consulting», title = «созвон с клиентом 30 мин»"),
                ]
            )
            Divider()
            patternBlock(
                number: "4",
                pattern: "- [x] <project>: <title>",
                description: "Двоеточие после projectId. Лаконично, но конфликтует с заголовками вида «TODO: сделать X», поэтому проверяется ПОСЛЕДНИМ и не работает для зарезервированных слов.",
                examples: [
                    ("- [x] myapp: исправил краш при запуске",
                     "project = «myapp», title = «исправил краш при запуске»"),
                    ("- [x] backend: оптимизировал запрос /api/users",
                     "project = «backend», title = «оптимизировал запрос /api/users»"),
                    ("- [x] project: придумал название",
                     "❌ строка ИГНОРИРУЕТСЯ — слово `project` зарезервировано"),
                ]
            )
        }
    }

    private func patternBlock(
        number: String,
        pattern: String,
        description: String,
        examples: [(String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(number)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 14, alignment: .trailing)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pattern)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(examples.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(examples[i].0)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.07))
                                .cornerRadius(4)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(examples[i].1)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, 4)
                    }
                }
            }
        }
    }
}
