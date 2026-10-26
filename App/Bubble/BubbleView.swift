import AgentCutCore
import SwiftUI

struct BubbleView: View {
    @Bindable var model: BubbleViewModel
    var onReplace: (String) -> Void
    var onCopy: (String) -> Void
    var onClose: () -> Void
    var onOpenSettings: () -> Void

    @FocusState private var questionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if let preview = model.inputPreview {
                Text("Dagli appunti: \(preview)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onExitCommand(perform: onClose)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Sto pensando…").foregroundStyle(.secondary)
            }
        case .streaming(let response):
            responseView(response, finished: false)
        case .done(let response):
            responseView(response, finished: true)
        case .askingQuestion(let previous):
            questionView(previous: previous)
        case .failed(let error):
            errorView(error)
        }
    }

    private func responseView(_ response: ParsedResponse, finished: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label = response.label {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
            BodyText(text: response.body, monospaced: response.kind == .replace)
            if let note = response.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if model.canReplace {
                    Button("Sostituisci") { onReplace(response.body) }
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderedProminent)
                }
                if model.primaryAction == .copy {
                    Button("Copia") { onCopy(response.body) }
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Copia") { onCopy(response.body) }
                        .keyboardShortcut("c", modifiers: .command)
                        .disabled(!finished)
                }
                Button("Chiedi altro…") { model.showQuestionField() }
                Spacer()
                if !finished { ProgressView().controlSize(.mini) }
            }
            .controlSize(.small)
        }
    }

    private func questionView(previous: ParsedResponse?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let previous, previous.kind == .unclear, !previous.body.isEmpty {
                Text(previous.body).font(.callout)
            }
            TextField("Fai una domanda su questo testo…", text: $model.questionText)
                .textFieldStyle(.roundedBorder)
                .focused($questionFocused)
                .onSubmit { model.submitQuestion() }
        }
        .onAppear { questionFocused = true }
    }

    private func errorView(_ error: AgentError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.userMessage, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
            switch error {
            case .notAuthenticated, .cliNotFound:
                Button("Apri Impostazioni", action: onOpenSettings).controlSize(.small)
            default:
                EmptyView()
            }
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Corpo selezionabile che cresce col contenuto fino a 300 pt, poi scorre.
private struct BodyText: View {
    let text: String
    let monospaced: Bool
    @State private var height: CGFloat = 20

    var body: some View {
        ScrollView {
            Text(text)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                })
        }
        .frame(height: min(height, 300))
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
        .onPreferenceChange(HeightKey.self) { height = $0 }
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 20
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

#Preview("Risposta") {
    let model = BubbleViewModel(
        input: .init(text: "SELEC name FROM users GROUP name", source: .clipboard),
        settings: AppSettings(),
        provider: .failure(.cliNotFound(.claudeCode))
    )
    return BubbleView(model: model, onReplace: { _ in }, onCopy: { _ in }, onClose: {}, onOpenSettings: {})
        .onAppear { model.start() }
}
