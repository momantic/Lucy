import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var petView: ClickablePetView!
    var chatController: ChatWindowController?

    var wanderTimer: Timer?
    var moodTimer: Timer?
    var animationTimer: Timer?
    var isHidden = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Lucy Dev Mode v0.4 started")
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

    func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            self.petView.animateNextFrame()
        }
    }

    func startWandering() {
        wanderTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            if self.isHidden { return }
            guard let screen = NSScreen.main?.visibleFrame else { return }

            var frame = self.window.frame
            let action = Int.random(in: 1...10)

            if action <= 6 {
                let dx = CGFloat([-35, -20, -10, 10, 20, 35].randomElement()!)
                let dy = CGFloat([-12, 0, 12].randomElement()!)

                frame.origin.x = max(screen.minX, min(frame.origin.x + dx, screen.maxX - frame.width))
                frame.origin.y = max(screen.minY, min(frame.origin.y + dy, screen.maxY - frame.height))

                self.petView.setState(.crawl, mood: "crawl")
                self.window.setFrame(frame, display: true, animate: true)
                LucyRuntime.shared.crawlCount += 1
                LucyRuntime.shared.log("Lucy crawled")
            } else if action <= 8 {
                let dx = CGFloat([-60, -40, 40, 60].randomElement()!)
                let dy = CGFloat([30, 45].randomElement()!)

                frame.origin.x = max(screen.minX, min(frame.origin.x + dx, screen.maxX - frame.width))
                frame.origin.y = max(screen.minY, min(frame.origin.y + dy, screen.maxY - frame.height))

                self.petView.setState(.hop, mood: "hop!")
                self.window.setFrame(frame, display: true, animate: true)
                LucyRuntime.shared.hopCount += 1
                LucyRuntime.shared.log("Lucy hopped")
            } else {
                let moods = ["look 👀", "idle", "hmm", "Lucy"]
                self.petView.setState(.idle, mood: moods.randomElement() ?? "Lucy")
                LucyRuntime.shared.idleCount += 1
                LucyRuntime.shared.log("Lucy idled")
            }
        }
    }

    func startIdleMoods() {
        moodTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { _ in
            if self.isHidden { return }
            let moods = ["Lucy", "watching 👀", "tiny spider", "thinking", "ready"]
            self.petView.setState(.idle, mood: moods.randomElement() ?? "Lucy")
        }
    }
}
