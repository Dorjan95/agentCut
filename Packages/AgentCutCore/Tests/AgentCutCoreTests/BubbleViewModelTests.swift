import Foundation
import Testing
@testable import AgentCutCore

/// Provider finto con risposte preimpostate, ritardo opzionale e registrazione delle richieste.
final class FakeProvider: AgentProvider, @unchecked Sendable {
    let kind = AgentKind.claudeCode
    let chunks: [String]
    let hangAfterFirst: Bool
    private(set) var calls = 0
    private(set) var lastRequest: AgentRequest?
    private(set) var terminated = false

    init(_ chunks: [String], hangAfterFirst: Bool = false) {
        self.chunks = chunks
        self.hangAfterFirst = hangAfterFirst
    }

    func stream(_ request: AgentRequest) -> AsyncThrowingStream<String, Error> {
        calls += 1
        lastRequest = request
        let chunks = self.chunks, hang = hangAfterFirst
        return AsyncThrowingStream { c in
            let task = Task {
                for chunk in chunks {
                    c.yield(chunk)
                    if hang { try? await Task.sleep(for: .seconds(5)) }
                }
                c.finish()
            }
            c.onTermination = { [weak self] _ in
                self?.terminated = true
                task.cancel()
            }
        }
    }
}

@MainActor
struct BubbleViewModelTests {
    let selection = CapturedText(text: "SELEC 1", source: .selection)

    func waitUntilSettled(_ vm: BubbleViewModel) async {
        for _ in 0..<200 {
            switch vm.state {
            case .loading, .streaming: try? await Task.sleep(for: .milliseconds(5))
            default: return
            }
        }
    }

    @Test func streamsThenDone() async {
        let vm = BubbleViewModel(input: selection, settings: AppSettings(), provider: .success(FakeProvider(["KIND: replace\nLABEL: SQL\n---\n", "SELECT 1;"])))
        vm.start()
        await waitUntilSettled(vm)
        #expect(vm.state == .done(ParsedResponse(kind: .replace, label: "SQL", body: "SELECT 1;", headerComplete: true)))
        #expect(vm.primaryAction == .replace)
        #expect(vm.canReplace)
    }

    @Test func answerMakesCopyPrimary() async {
        let vm = BubbleViewModel(input: selection, settings: AppSettings(), provider: .success(FakeProvider(["KIND: answer\n---\nSpiegazione"])))
        vm.start()
        await waitUntilSettled(vm)
        #expect(vm.primaryAction == .copy)
        #expect(!vm.canReplace)
    }

    @Test func unclearAsksQuestion() async {
        let vm = BubbleViewModel(input: selection, settings: AppSettings(), provider: .success(FakeProvider(["KIND: unclear\n---\nCosa vuoi?"])))
        vm.start()
        await waitUntilSettled(vm)
        guard case .askingQuestion(let previous) = vm.state else { Issue.record("state \(vm.state)"); return }
        #expect(previous?.body == "Cosa vuoi?")
        #expect(vm.primaryAction == nil)
    }

    @Test func blankInputAsksWithoutCallingProvider() async {
        let provider = FakeProvider(["x"])
        let vm = BubbleViewModel(input: .init(text: "  \n", source: .clipboard), settings: AppSettings(), provider: .success(provider))
        vm.start()
        #expect(vm.state == .askingQuestion(previous: nil))
        #expect(provider.calls == 0)
    }

    @Test func providerFailureShowsError() {
        let vm = BubbleViewModel(input: selection, settings: AppSettings(), provider: .failure(.cliNotFound(.codex)))
        vm.start()
        #expect(vm.state == .failed(.cliNotFound(.codex)))
    }

    @Test func streamErrorShowsError() async {
        final class Failing: AgentProvider, @unchecked Sendable {
            let kind = AgentKind.codex
            func stream(_ request: AgentRequest) -> AsyncThrowingStream<String, Error> {
                AsyncThrowingStream { $0.finish(throwing: AgentError.timedOut) }
            }
        }
        let vm = BubbleViewModel(input: selection, settings: AppSettings(), provider: .success(Failing()))
        vm.start()
        await waitUntilSettled(vm)
        #expect(vm.state == .failed(.timedOut))
    }

    @Test func submitQuestionPassesQuestion() async {
        let provider = FakeProvider(["KIND: answer\n---\nok"])
        let vm = BubbleViewModel(input: selection, settings: AppSettings(), provider: .success(provider))
        vm.questionText = "e in MySQL?"
        vm.submitQuestion()
        await waitUntilSettled(vm)
        #expect(provider.lastRequest?.userPrompt.contains("Domanda: e in MySQL?") == true)
        #expect(vm.state == .done(ParsedResponse(kind: .answer, body: "ok", headerComplete: true)))
    }

    @Test func cancelStopsStreaming() async {
        let provider = FakeProvider(["KIND: replace\n---\nSEL", "ECT"], hangAfterFirst: true)
        let vm = BubbleViewModel(input: selection, settings: AppSettings(), provider: .success(provider))
        vm.start()
        try? await Task.sleep(for: .milliseconds(50))
        vm.cancel()
        for _ in 0..<50 where !provider.terminated { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(provider.terminated)
    }

    @Test func clipboardInputHasPreview() {
        let text = "riga1\nriga2\nriga3\nriga4"
        let vm = BubbleViewModel(input: .init(text: text, source: .clipboard), settings: AppSettings(), provider: .failure(.timedOut))
        #expect(vm.inputPreview == "riga1\nriga2\nriga3")
    }

    @Test func clipboardPreviewIsCapped() {
        let vm = BubbleViewModel(input: .init(text: String(repeating: "a", count: 500), source: .clipboard), settings: AppSettings(), provider: .failure(.timedOut))
        #expect((vm.inputPreview?.count ?? 0) <= 161)
    }

    @Test func selectionInputHasNoPreview() {
        let vm = BubbleViewModel(input: selection, settings: AppSettings(), provider: .failure(.timedOut))
        #expect(vm.inputPreview == nil)
    }
}
