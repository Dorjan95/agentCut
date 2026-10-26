import Testing
@testable import AgentCutCore

struct ResponseParserTests {
    @Test func parsesFullResponse() {
        var p = ResponseParser()
        _ = p.feed("KIND: replace\nLABEL: SQL\nNOTE: fix\n---\nSELECT 1;")
        let r = p.finish()
        #expect(r.kind == .replace)
        #expect(r.label == "SQL")
        #expect(r.note == "fix")
        #expect(r.body == "SELECT 1;")
        #expect(r.headerComplete)
    }

    @Test func streamsAcrossChunkBoundaries() {
        var p = ResponseParser()
        _ = p.feed("KIN")
        let second = p.feed("D: answer\n--")
        #expect(second.headerComplete == false)
        #expect(second.body == "")
        let third = p.feed("-\nciao")
        #expect(third.headerComplete)
        #expect(third.body == "ciao")
        #expect(third.kind == .answer)
    }

    @Test func fallbackWithoutHeader() {
        var p = ResponseParser()
        _ = p.feed("Ecco la query: SELECT 1")
        let r = p.finish()
        #expect(r.kind == .answer)
        #expect(r.body == "Ecco la query: SELECT 1")
    }

    @Test func onlyFirstSeparatorSplits() {
        var p = ResponseParser()
        _ = p.feed("KIND: replace\n---\na\n---\nb")
        #expect(p.finish().body == "a\n---\nb")
    }

    @Test func unknownKindIsAnswer() {
        var p = ResponseParser()
        _ = p.feed("KIND: boh\n---\nx")
        #expect(p.finish().kind == .answer)
    }

    @Test func unclosedHeaderFallsBackOnFinish() {
        var p = ResponseParser()
        _ = p.feed("KIND: replace\nLABEL: x")
        let r = p.finish()
        #expect(r.kind == .answer)
        #expect(r.body == "KIND: replace\nLABEL: x")
    }

    @Test func stripsSingleFence() {
        var p = ResponseParser()
        _ = p.feed("KIND: replace\n---\n```sql\nSELECT 1;\n```\n")
        #expect(p.finish().body == "SELECT 1;")
    }

    @Test func leadingBlankLinesBeforeHeader() {
        var p = ResponseParser()
        _ = p.feed("\n\nkind: unclear\n---\nCosa vuoi fare?")
        let r = p.finish()
        #expect(r.kind == .unclear)
        #expect(r.body == "Cosa vuoi fare?")
    }
}
