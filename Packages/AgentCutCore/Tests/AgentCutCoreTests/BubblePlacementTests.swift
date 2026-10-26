import CoreGraphics
import Testing
@testable import AgentCutCore

struct BubblePlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let size = CGSize(width: 360, height: 200)

    @Test func belowAnchor() {
        let f = BubblePlacement.frame(size: size, anchor: CGRect(x: 100, y: 500, width: 200, height: 20), mouse: .zero, visibleFrame: screen)
        #expect(f.origin == CGPoint(x: 100, y: 292))
        #expect(f.size == size)
    }

    @Test func flipsAboveWhenNoRoom() {
        let f = BubblePlacement.frame(size: size, anchor: CGRect(x: 100, y: 100, width: 200, height: 20), mouse: .zero, visibleFrame: screen)
        #expect(f.origin.y == 128)
    }

    @Test func clampsRightEdge() {
        let f = BubblePlacement.frame(size: size, anchor: CGRect(x: 1300, y: 500, width: 50, height: 20), mouse: .zero, visibleFrame: screen)
        #expect(f.origin.x == 1080)
    }

    @Test func usesMouseWhenNoAnchor() {
        let f = BubblePlacement.frame(size: size, anchor: nil, mouse: CGPoint(x: 400, y: 600), visibleFrame: screen)
        #expect(f.origin == CGPoint(x: 400, y: 392))
    }

    @Test func clampsTopWhenAboveOverflows() {
        let tall = CGSize(width: 360, height: 880)
        let f = BubblePlacement.frame(size: tall, anchor: CGRect(x: 100, y: 450, width: 10, height: 10), mouse: .zero, visibleFrame: screen)
        #expect(f.minY >= screen.minY)
        #expect(f.maxY <= screen.maxY)
    }
}
