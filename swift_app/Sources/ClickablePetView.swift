import Cocoa

class ClickablePetView: LucySpriteView {
    var onDoubleClick: (() -> Void)?
    var onDrag: ((CGFloat, CGFloat) -> Void)?

    private var mouseDownPoint: NSPoint = .zero
    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        didDrag = false

        if event.clickCount >= 2 {
            onDoubleClick?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        didDrag = true
        onDrag?(event.deltaX, event.deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        // Single clicks intentionally do nothing.
        // This prevents accidental chat opening when grabbing/dragging Lucy.
    }
}
