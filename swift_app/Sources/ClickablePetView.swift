import Cocoa
import Foundation

class ClickablePetView: LucySpriteView {
    var clickCount = 0
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            LucyRuntime.shared.chatCount += 1
            LucyRuntime.shared.log("Lucy double clicked")
            setState(.thinking, mood: "chat")
            onDoubleClick?()
        } else {
            clickCount += 1
            LucyRuntime.shared.clickCount += 1

            let messages = [
                "tap tap...",
                "watching 👀",
                "ready",
                "hi!",
                "boop",
                "clicked \(clickCount)"
            ]

            setState(.thinking, mood: messages.randomElement() ?? "Lucy")
            LucyRuntime.shared.log("Lucy clicked")
        }
    }
}
