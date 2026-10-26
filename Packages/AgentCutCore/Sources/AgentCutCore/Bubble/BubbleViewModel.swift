import Foundation
import Observation

public enum BubbleState: Equatable, Sendable {
    case loading
    case streaming(ParsedResponse)
    case done(ParsedResponse)
    case askingQuestion(previous: ParsedResponse?)
    case failed(AgentError)
}

public enum BubbleAction: Equatable, Sendable {
    case replace, copy
}

@MainActor
@Observable
public final class BubbleViewModel {
    public private(set) var state: BubbleState = .loading
    public var questionText = ""
    public let input: CapturedText

    private let settings: AppSettings
    private let provider: Result<AgentProvider, AgentError>
    private var task: Task<Void, Never>?

    public init(input: CapturedText, settings: AppSettings, provider: Result<AgentProvider, AgentError>) {
        self.input = input
        self.settings = settings
        self.provider = provider
        self.inputPreview = Self.preview(of: input)
    }

    private static func preview(of input: CapturedText) -> String? {
        guard input.source == .clipboard else { return nil }
        let head = input.text.prefix(500)
        let lines = head.split(separator: "\n", omittingEmptySubsequences: false).prefix(3).joined(separator: "\n")
        return lines.count > 160 ? String(lines.prefix(160)) + "…" : lines
    }

    /// Anteprima di cosa è stato inviato, solo quando il testo arriva dagli appunti. Calcolata una volta.
    public let inputPreview: String?

    public var primaryAction: BubbleAction? {
        guard case .done(let response) = state else { return nil }
        switch response.kind {
        case .replace: return .replace
        case .answer: return .copy
        case .unclear: return nil
        }
    }

    public var canReplace: Bool { primaryAction == .replace }

    public func start() {
        run(question: nil)
    }

    public func submitQuestion() {
        let question = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty || !isBlankInput else { return }
        run(question: question.isEmpty ? nil : question)
    }

    public func showQuestionField() {
        cancel()
        let previous: ParsedResponse? = switch state {
        case .done(let r), .streaming(let r): r
        case .askingQuestion(let p): p
        default: nil
        }
        state = .askingQuestion(previous: previous)
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    private var isBlankInput: Bool {
        input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func run(question: String?) {
        cancel()
        if isBlankInput && question == nil {
            state = .askingQuestion(previous: nil)
            return
        }
        let provider: AgentProvider
        switch self.provider {
        case .failure(let error):
            state = .failed(error)
            return
        case .success(let p):
            provider = p
        }

        state = .loading
        let request = PromptBuilder.build(input: input.text, question: question, agent: provider.kind, settings: settings)
        task = Task { [weak self] in
            var parser = ResponseParser()
            do {
                for try await chunk in provider.stream(request) {
                    let parsed = parser.feed(chunk)
                    if parsed.headerComplete { self?.state = .streaming(parsed) }
                }
                guard !Task.isCancelled else { return }
                let final = parser.finish()
                self?.state = final.kind == .unclear ? .askingQuestion(previous: final) : .done(final)
            } catch {
                guard !Task.isCancelled else { return }
                let agentError = error as? AgentError ?? .processFailed(exitCode: -1, stderr: error.localizedDescription)
                self?.state = .failed(agentError)
            }
        }
    }
}
