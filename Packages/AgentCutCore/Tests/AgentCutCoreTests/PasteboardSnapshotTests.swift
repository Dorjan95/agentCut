import AppKit
import Testing
@testable import AgentCutCore

struct PasteboardSnapshotTests {
    let pasteboard = NSPasteboard(name: .init("agentcut.test.\(UUID())"))

    @Test func restoresString() {
        pasteboard.clearContents()
        pasteboard.setString("originale", forType: .string)
        let snapshot = PasteboardSnapshot(capturing: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("x", forType: .string)
        snapshot.restore(to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "originale")
    }

    @Test func restoresAllTypes() {
        pasteboard.clearContents()
        let first = NSPasteboardItem()
        first.setString("a", forType: .string)
        first.setData(Data([1, 2, 3]), forType: .png)
        let second = NSPasteboardItem()
        second.setString("file:///tmp/x.txt", forType: .fileURL)
        pasteboard.writeObjects([first, second])

        let snapshot = PasteboardSnapshot(capturing: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("x", forType: .string)
        snapshot.restore(to: pasteboard)

        let items = pasteboard.pasteboardItems ?? []
        #expect(items.count == 2)
        #expect(items.first?.string(forType: .string) == "a")
        #expect(items.first?.data(forType: .png) == Data([1, 2, 3]))
        #expect(items.last?.string(forType: .fileURL) == "file:///tmp/x.txt")
    }

    @Test func restoresEmpty() {
        pasteboard.clearContents()
        let snapshot = PasteboardSnapshot(capturing: pasteboard)
        pasteboard.setString("x", forType: .string)
        snapshot.restore(to: pasteboard)
        #expect(pasteboard.string(forType: .string) == nil)
        #expect((pasteboard.pasteboardItems ?? []).isEmpty)
    }
}
