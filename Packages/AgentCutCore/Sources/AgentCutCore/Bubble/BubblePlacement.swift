import CoreGraphics

public enum BubblePlacement {
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
