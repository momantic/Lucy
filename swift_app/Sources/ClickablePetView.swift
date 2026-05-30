import Cocoa
import Foundation

class ClickablePetView: NSView {
    var label: NSTextField!
    var clickCount = 0

    var state: LucyState = .idle
    var frameIndex = 0
    var mood = "Lucy"

    let idleFrames = ["🕷️", "🕷︎", "🕷️", "🕷︎"]
    let crawlFrames = ["🕷️", "🕸️", "🕷︎", "🕷️"]
    let hopFrames = ["🕷️", "🕷️", "🕷️"]
    let thinkingFrames = ["🕷️?", "🕷️.", "🕷️..", "🕷️..."]
    let hiddenFrames = ["…", "…", "…"]

    var onDoubleClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.12).cgColor
        layer?.cornerRadius = 20

        label = NSTextField(labelWithString: "🕷️\nLucy")
        label.font = NSFont.systemFont(ofSize: 48)
        label.alignment = .center
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.isBordered = false
        label.isEditable = false
        label.frame = NSRect(x: 0, y: 20, width: 180, height: 120)

        addSubview(label)
        updateFrame()
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

        updateFrame()
    }

    func currentFrames() -> [String] {
        switch state {
        case .idle:
            return idleFrames
        case .crawl:
            return crawlFrames
        case .hop:
            return hopFrames
        case .thinking:
            return thinkingFrames
        case .hidden:
            return hiddenFrames
        }
    }

    func updateFrame() {
        let frames = currentFrames()
        let body = frames[frameIndex % frames.count]
        label.stringValue = "\(body)\n\(mood)"
    }

    func animateNextFrame() {
        frameIndex += 1
        updateFrame()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            LucyRuntime.shared.chatCount += 1
            LucyRuntime.shared.log("Lucy double clicked")
            setState(.thinking, mood: "chat")
            onDoubleClick?()
        } else {
            clickCount += 1
            LucyRuntime.shared.clickCount += 1
            let messages = ["tap tap...", "watching 👀", "ready", "hi!", "boop", "clicked \(clickCount)"]
            setState(.thinking, mood: messages.randomElement() ?? "Lucy")
            LucyRuntime.shared.log("Lucy clicked")
        }
    }
}
