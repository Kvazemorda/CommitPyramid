import SwiftUI

/// Контекстный popup ввода задачи — появляется при клике по пустой части квартала
/// в explore-режиме (F-17). Стиль соответствует `InspectorOverlayCard`.
struct TaskInputPopupView: View {
    let projectId: String
    var onSubmit: (String) -> Void
    var onCancel: () -> Void

    @State private var draftTitle: String = ""
    @State private var showWarning: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Добавить задачу к проекту \(projectId)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.paletteInkDark)

            TextField("Что сделал?", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { trySubmit() }

            HStack {
                Spacer()
                Button("Отмена") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Добавить") { trySubmit() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(maxWidth: 320)
        .background(Color.paletteSandLight)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.paletteWarning.opacity(showWarning ? 1 : 0), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        .onAppear { focused = true }
    }

    private func trySubmit() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            withAnimation { showWarning = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { showWarning = false }
            }
            return
        }
        onSubmit(String(trimmed.prefix(255)))
    }
}
