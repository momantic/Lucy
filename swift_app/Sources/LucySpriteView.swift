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

        if state == .hidden {
            drawHiddenState()
            return
        }

        drawLucyBody()
        drawMoodText()
    }

    func drawHiddenState() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center

        let dots = ["·", "· ·", "· · ·", "· ·"][frameIndex % 4] as NSString

        dots.draw(
            in: NSRect(x: 0, y: bounds.midY - 12, width: bounds.width, height: 30),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 28),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: style
            ]
        )
    }

    func drawLucyBody() {
        let centerX: CGFloat = bounds.midX
        let baseCenterY: CGFloat = bounds.midY + 20

        let phase = frameIndex % 4

        let bodyYOffset: CGFloat
        let bodyScaleX: CGFloat
        let bodyScaleY: CGFloat
        let legSwing: CGFloat
        let eyeOffsetX: CGFloat

        switch state {
        case .idle:
            bodyYOffset = (phase == 0 || phase == 2) ? 0 : 2
            bodyScaleX = 1.0
            bodyScaleY = 1.0
            legSwing = (phase % 2 == 0) ? -2 : 2
            eyeOffsetX = 0

        case .crawl:
            bodyYOffset = (phase % 2 == 0) ? -1 : 2
            bodyScaleX = 1.04
            bodyScaleY = 0.98
            legSwing = (phase % 2 == 0) ? -9 : 9
            eyeOffsetX = (phase % 2 == 0) ? -2 : 2

        case .hop:
            if phase == 0 {
                bodyYOffset = -5
                bodyScaleX = 1.12
                bodyScaleY = 0.88
            } else if phase == 1 || phase == 2 {
                bodyYOffset = 14
                bodyScaleX = 0.94
                bodyScaleY = 1.12
            } else {
                bodyYOffset = 2
                bodyScaleX = 1.0
                bodyScaleY = 1.0
            }
            legSwing = (phase % 2 == 0) ? -5 : 5
            eyeOffsetX = 0

        case .thinking:
            bodyYOffset = (phase % 2 == 0) ? 0 : 1
            bodyScaleX = 1.0
            bodyScaleY = 1.0
            legSwing = (phase % 2 == 0) ? -1 : 1
            eyeOffsetX = CGFloat([-3, 0, 3, 0][phase])

        case .hidden:
            bodyYOffset = 0
            bodyScaleX = 1.0
            bodyScaleY = 1.0
            legSwing = 0
            eyeOffsetX = 0
        }

        let centerY = baseCenterY + bodyYOffset

        drawLegs(centerX: centerX, centerY: centerY, legSwing: legSwing)
        drawBody(centerX: centerX, centerY: centerY, scaleX: bodyScaleX, scaleY: bodyScaleY)
        drawEyes(centerX: centerX, centerY: centerY, eyeOffsetX: eyeOffsetX)
    }

    func drawBody(centerX: CGFloat, centerY: CGFloat, scaleX: CGFloat, scaleY: CGFloat) {
        let bodyWidth = 68 * scaleX
        let bodyHeight = 56 * scaleY
        let headWidth = 56 * scaleX
        let headHeight = 46 * scaleY

        let bodyRect = NSRect(
            x: centerX - bodyWidth / 2,
            y: centerY - bodyHeight / 2 - 4,
            width: bodyWidth,
            height: bodyHeight
        )

        let headRect = NSRect(
            x: centerX - headWidth / 2,
            y: centerY + 8,
            width: headWidth,
            height: headHeight
        )

        NSColor.black.setFill()
        NSBezierPath(ovalIn: bodyRect).fill()
        NSBezierPath(ovalIn: headRect).fill()

        // soft belly highlight
        NSColor(calibratedWhite: 0.18, alpha: 1.0).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: centerX - 18,
                y: centerY - 12,
                width: 36,
                height: 24
            )
        ).fill()
    }

    func drawLegs(centerX: CGFloat, centerY: CGFloat, legSwing: CGFloat) {
        NSColor.black.setStroke()

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
            path.lineJoinStyle = .round

            path.move(to: NSPoint(x: centerX + leg.0, y: centerY + leg.1))
            path.line(to: NSPoint(x: centerX + leg.2, y: centerY + leg.3))
            path.stroke()
        }
    }

    func drawEyes(centerX: CGFloat, centerY: CGFloat, eyeOffsetX: CGFloat) {
        let eyeY = centerY + 34

        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: centerX - 21, y: eyeY, width: 17, height: 19)).fill()
        NSBezierPath(ovalIn: NSRect(x: centerX + 4, y: eyeY, width: 17, height: 19)).fill()

        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: centerX - 15 + eyeOffsetX, y: eyeY + 5, width: 7, height: 8)).fill()
        NSBezierPath(ovalIn: NSRect(x: centerX + 10 + eyeOffsetX, y: eyeY + 5, width: 7, height: 8)).fill()

        // tiny eye highlights
        NSColor.white.withAlphaComponent(0.8).setFill()
        NSBezierPath(ovalIn: NSRect(x: centerX - 13 + eyeOffsetX, y: eyeY + 10, width: 2.5, height: 2.5)).fill()
        NSBezierPath(ovalIn: NSRect(x: centerX + 12 + eyeOffsetX, y: eyeY + 10, width: 2.5, height: 2.5)).fill()
    }

    func drawMoodText() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style
        ]

        let displayMood: String

        if state == .thinking {
            let dots = ["", ".", "..", "..."][frameIndex % 4]
            displayMood = "\(mood)\(dots)"
        } else {
            displayMood = mood
        }

        let text = displayMood as NSString
        text.draw(
            in: NSRect(x: 0, y: 12, width: bounds.width, height: 24),
            withAttributes: attrs
        )
    }
}
