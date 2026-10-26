import CoreGraphics

public enum BubblePlacement {
    public enum Edge: Sendable { case top, bottom }

    /// Bordo da tenere fermo quando il fumetto cresce: sotto la selezione cresce verso il basso, sopra verso l'alto.
    public static func fixedEdge(frame: CGRect, anchor: CGRect?, mouse: CGPoint) -> Edge {
        let anchor = anchor ?? CGRect(origin: mouse, size: .zero)
        return frame.minY >= anchor.maxY ? .bottom : .top
    }

    /// Posizione del fumetto in coordinate AppKit: sotto l'ancora, sopra se sotto non c'è spazio, sempre dentro lo schermo.
    public static func frame(size: CGSize, anchor: CGRect?, mouse: CGPoint, visibleFrame: CGRect, gap: CGFloat = 8) -> CGRect {
        let anchor = anchor ?? CGRect(origin: mouse, size: .zero)

        var y = anchor.minY - gap - size.height
        if y < visibleFrame.minY {
            y = anchor.maxY + gap
        }
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - size.height)

        let x = min(max(anchor.minX, visibleFrame.minX), visibleFrame.maxX - size.width)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
