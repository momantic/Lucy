import Cocoa
import Foundation

class LucySpriteView: NSView {
    var state: LucyState = .idle
    var frameIndex = 0
    var mood = "Lucy"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.12).cgColor
        layer?.cornerRadius = 20
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setState(_ newState: LucyState, mood newMood: String? = nil) {
        state = newState
        frameIndex = 0

        if let newMood = newMood {
            mood = newMood
        }

        needsDisplay = true
    }

    func animateNextFrame() {
        frameIndex += 1
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawLucyBody()
        drawMoodText()
    }

    func drawLucyBody() {
        let centerX: CGFloat = bounds.midX
        let centerY: CGFloat = bounds.midY + 20

        let wobble = CGFloat((frameIndex % 2 == 0) ? -2 : 2)

        let bodyRect = NSRect(
            x: centerX - 34,
            y: centerY - 28 + wobble,
            width: 68,
            height: 56
        )

        let headRect = NSRect(
            x: centerX - 28,
            y: centerY + 10 + wobble,
            width: 56,
            height: 46
        )

        NSColor.black.setFill()
        NSBezierPath(ovalIn: bodyRect).fill()
        NSBezierPath(ovalIn: headRect).fill()

        drawLegs(centerX: centerX, centerY: centerY, wobble: wobble)
        drawEyes(centerX: centerX, centerY: centerY, wobble: wobble)
    }

    func drawLegs(centerX: CGFloat, centerY: CGFloat, wobble: CGFloat) {
        NSColor.black.setStroke()

        let legSwing = CGFloat((frameIndex % 2 == 0) ? -5 : 5)

        let legs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-28, 4, -65, 30 + legSwing),
            (-30, -5, -70, 0 - legSwing),
            (-26, -15, -60, -35 + legSwing),
            (-14, -24, -35, -55 - legSwing),

            (28, 4, 65, 30 - legSwing),
            (30, -5, 70, 0 + legSwing),
            (26, -15, 60, -35 - legSwing),
            (14, -24, 35, -55 + legSwing)
        ]

        for leg in legs {
            let path = NSBezierPath()
            path.lineWidth = 4
            path.lineCapStyle = .round

            path.move(to: NSPoint(x: centerX + leg.0, y: centerY + leg.1 + wobble))
            path.line(to: NSPoint(x: centerX + leg.2, y: centerY + leg.3 + wobble))
            path.stroke()
        }
    }

    func drawEyes(centerX: CGFloat, centerY: CGFloat, wobble: CGFloat) {
        let eyeY = centerY + 34 + wobble

        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: centerX - 19, y: eyeY, width: 15, height: 17)).fill()
        NSBezierPath(ovalIn: NSRect(x: centerX + 4, y: eyeY, width: 15, height: 17)).fill()

        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: centerX - 14, y: eyeY + 4, width: 6, height: 7)).fill()
        NSBezierPath(ovalIn: NSRect(x: centerX + 9, y: eyeY + 4, width: 6, height: 7)).fill()
    }

    func drawMoodText() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style
        ]

        let text = mood as NSString
        text.draw(
            in: NSRect(x: 0, y: 12, width: bounds.width, height: 24),
            withAttributes: attrs
        )
    }
}
