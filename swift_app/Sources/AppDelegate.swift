import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var petView: ClickablePetView!
    var chatController: ChatWindowController?

    var wanderTimer: Timer?
    var moodTimer: Timer?
    var animationTimer: Timer?
    var cursorTimer: Timer?
    var isHidden = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Lucy Dev Mode v0.5 started")
        print("Terminal logging is quiet by default. Use /loud inside Lucy chat to enable movement logs.")

        _ = LucyMemory.shared
        LucyDevTools.shared.ensureDirs()

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)

        window = NSWindow(
            contentRect: NSRect(x: screen.midX - 90, y: screen.midY, width: 180, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true

        petView = ClickablePetView(frame: NSRect(x: 0, y: 0, width: 180, height: 160))
        petView.onDoubleClick = {
            self.openChat()
        }

        window.contentView = petView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startAnimation()
        startWandering()
        startIdleMoods()
        startCursorAwareness()
    }

    func openChat() {
        if chatController == nil {
            chatController = ChatWindowController()
            chatController?.onHideRequested = {
                self.hideLucyTemporarily()
            }
        }

        chatController?.show()
    }

    func hideLucyTemporarily() {
        if isHidden { return }

        isHidden = true
        LucyRuntime.shared.hideCount += 1
        petView.setState(.hidden, mood: "hiding")
        window.orderOut(nil)

        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            self.window.makeKeyAndOrderFront(nil)
            self.petView.setState(.idle, mood: "back")
            self.isHidden = false
            LucyRuntime.shared.log("Lucy returned from hiding")
        }
    }

    func startCursorAwareness() {
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            if self.isHidden { return }

            let mouse = NSEvent.mouseLocation
            let frame = self.window.frame
            let center = NSPoint(x: frame.midX, y: frame.midY)

            let dx = mouse.x - center.x
            let dy = mouse.y - center.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance < 90 {
                LucyRuntime.shared.facingRight = dx >= 0
                self.petView.setState(.thinking, mood: "boop?")
            } else if distance < 170 {
                LucyRuntime.shared.facingRight = dx >= 0
                self.petView.setState(.idle, mood: "watching 👀")
            }
        }
    }

    func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { _ in
            self.petView.animateNextFrame()
        }
    }

    func startWandering() {
        wanderTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            if self.isHidden { return }
            guard let screen = NSScreen.main?.visibleFrame else { return }

            var frame = self.window.frame
            let action = Int.random(in: 1...10)

            let nearLeft = frame.origin.x <= screen.minX + 30
            let nearRight = frame.origin.x >= screen.maxX - frame.width - 30
            let nearBottom = frame.origin.y <= screen.minY + 30

            if action == 10 || nearLeft || nearRight || nearBottom {
                if nearLeft {
                    LucyRuntime.shared.facingRight = true
                    self.petView.setState(.idle, mood: "edge →")
                } else if nearRight {
                    LucyRuntime.shared.facingRight = false
                    self.petView.setState(.idle, mood: "← edge")
                } else if nearBottom {
                    self.petView.setState(.idle, mood: "perch")
                } else {
                    self.petView.setState(.idle, mood: "looking")
                }

                LucyRuntime.shared.idleCount += 1
                LucyRuntime.shared.log("Lucy perched")
                return
            }

            if action <= 6 {
                let dx = CGFloat([-35, -20, -10, 10, 20, 35].randomElement()!)
                let dy = CGFloat([-12, 0, 12].randomElement()!)

                LucyRuntime.shared.facingRight = dx >= 0

                frame.origin.x = max(screen.minX, min(frame.origin.x + dx, screen.maxX - frame.width))
                frame.origin.y = max(screen.minY, min(frame.origin.y + dy, screen.maxY - frame.height))

                self.petView.setState(.crawl, mood: LucyRuntime.shared.facingRight ? "crawl →" : "← crawl")
                self.window.setFrame(frame, display: true, animate: true)
                LucyRuntime.shared.crawlCount += 1
                LucyRuntime.shared.log("Lucy crawled")
            } else if action <= 8 {
                let dx = CGFloat([-70, -50, 50, 70].randomElement()!)
                LucyRuntime.shared.facingRight = dx >= 0

                self.petView.setState(.hop, mood: LucyRuntime.shared.facingRight ? "hop →" : "← hop")
                self.performHopArc(dx: dx)
                LucyRuntime.shared.hopCount += 1
                LucyRuntime.shared.log("Lucy hopped with arc")
            } else {
                let moods = ["look 👀", "idle", "hmm", "Lucy"]
                self.petView.setState(.idle, mood: moods.randomElement() ?? "Lucy")
                LucyRuntime.shared.idleCount += 1
                LucyRuntime.shared.log("Lucy idled")
            }
        }
    }

    func performHopArc(dx: CGFloat) {
        guard let screen = NSScreen.main?.visibleFrame else { return }

        let startFrame = self.window.frame
        var endFrame = startFrame

        endFrame.origin.x = max(screen.minX, min(startFrame.origin.x + dx, screen.maxX - startFrame.width))
        endFrame.origin.y = max(screen.minY, min(startFrame.origin.y + 10, screen.maxY - startFrame.height))

        var peakFrame = startFrame
        peakFrame.origin.x = (startFrame.origin.x + endFrame.origin.x) / 2
        peakFrame.origin.y = min(startFrame.origin.y + 70, screen.maxY - startFrame.height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.window.animator().setFrame(peakFrame, display: true)
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.window.animator().setFrame(endFrame, display: true)
            }
        }
    }

    func startIdleMoods() {
        moodTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            if self.isHidden { return }
            let moods = ["Lucy", "watching 👀", "tiny spider", "thinking", "ready"]
            self.petView.setState(.idle, mood: moods.randomElement() ?? "Lucy")
        }
    }
}
