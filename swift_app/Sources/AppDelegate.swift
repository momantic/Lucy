import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var sceneView: LucySceneView!
    var real3DMode = UserDefaults.standard.bool(forKey: "lucy.real3DMode")
    var isDraggingLucy = false
    var lastManualInteraction = Date.distantPast
    var window: NSWindow!
    var petView: ClickablePetView!
    var chatController: ChatWindowController?

    var wanderTimer: Timer?
    var moodTimer: Timer?
    var animationTimer: Timer?
    var cursorTimer: Timer?
    var isHidden = false


    func installAppMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(
            withTitle: "Quit Lucy",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        NSApp.mainMenu = mainMenu
    }


    func applicationDidFinishLaunching(_ notification: Notification) {

        NSApp.setActivationPolicy(.regular)
        installAppMenu()
        NSApp.activate(ignoringOtherApps: true)

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

        sceneView = LucySceneView(frame: NSRect(x: 0, y: 0, width: 180, height: 180))

        petView.onDoubleClick = {
            self.lastManualInteraction = Date()
            self.toggleChat()
        }

        petView.onDrag = { dx, dy in
            self.dragLucyBy(dx: dx, dy: dy)
        }

        sceneView.onDoubleClick = {
            self.lastManualInteraction = Date()
            self.toggleChat()
        }

        sceneView.onDrag = { dx, dy in
            self.dragLucyBy(dx: dx, dy: dy)
        }

        applyPetRenderMode()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startAnimation()
        startWandering()
        startIdleMoods()
        startCursorAwareness()
    }



    func toggleChat() {
        if let chatWindow = chatController?.window, chatWindow.isVisible {
            chatWindow.orderOut(nil)
        } else {
            openChat()
        }
    }

    func closeChat() {
        chatController?.window?.orderOut(nil)
    }


    func openChat() {
        if chatController == nil {
            chatController = ChatWindowController()
            chatController?.onHideRequested = {
                self.hideLucyTemporarily()
            }

            chatController?.onUse3DChanged = { enabled in
                self.petView.setUse3DSprites(enabled)
            }

            chatController?.onSpriteInfoRequested = {
                return self.petView.spriteInfoText()
            }

            chatController?.onReal3DChanged = { enabled in
                self.setReal3DMode(enabled)
            }

            chatController?.onRenderInfoRequested = {
                return self.currentRenderInfo()
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


    func clampFrameToScreen(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.main?.visibleFrame else {
            return frame
        }

        var newFrame = frame
        newFrame.origin.x = max(screen.minX, min(newFrame.origin.x, screen.maxX - newFrame.width))
        newFrame.origin.y = max(screen.minY, min(newFrame.origin.y, screen.maxY - newFrame.height))
        return newFrame
    }

    func dragLucyBy(dx: CGFloat, dy: CGFloat) {
        isDraggingLucy = true
        lastManualInteraction = Date()

        var frame = window.frame
        frame.origin.x += dx
        frame.origin.y -= dy
        window.setFrame(clampFrameToScreen(frame), display: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.isDraggingLucy = false
        }
    }

    func runAwayFromCursor(mouse: NSPoint, distance: CGFloat) {
        guard distance > 1 else {
            return
        }

        let frame = window.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)

        let awayX = center.x - mouse.x
        let awayY = center.y - mouse.y

        let length = max(1, sqrt(awayX * awayX + awayY * awayY))
        let normalizedX = awayX / length
        let normalizedY = awayY / length

        // Gentle speed: closer cursor = slightly faster, but never teleporting.
        let closeness = max(0, min(1, (130 - distance) / 130))
        let step = CGFloat(2.0 + closeness * 7.0)

        var newFrame = frame
        newFrame.origin.x += normalizedX * step
        newFrame.origin.y += normalizedY * step

        LucyRuntime.shared.facingRight = normalizedX >= 0
        window.setFrame(clampFrameToScreen(newFrame), display: true)
    }


    func startCursorAwareness() {
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if self.isHidden { return }

            let mouse = NSEvent.mouseLocation
            let frame = self.window.frame
            let center = NSPoint(x: frame.midX, y: frame.midY)

            let dx = mouse.x - center.x
            let dy = mouse.y - center.y
            let distance = sqrt(dx * dx + dy * dy)

            // If the cursor is actually over Lucy's body/window, stop running.
            // This lets you double-click or drag her.
            let touchZone = frame.insetBy(dx: -8, dy: -8).contains(mouse)

            if touchZone || self.isDraggingLucy {
                self.sceneView.lookToward(dx: dx, dy: dy)
                self.petView.setState(.idle, mood: "hi")
                return
            }

            // Short grace period after dragging/clicking so she does not instantly flee.
            if Date().timeIntervalSince(self.lastManualInteraction) < 0.45 {
                self.sceneView.lookToward(dx: dx, dy: dy)
                return
            }

            // Real 3D Lucy watches the cursor from farther away.
            if distance < 700 {
                LucyRuntime.shared.facingRight = dx >= 0
                self.sceneView.lookToward(dx: dx, dy: dy)
            } else {
                self.sceneView.lookToward(dx: 0, dy: 0)
            }

            // If cursor gets close but is not touching her, Lucy gently avoids it.
            if distance < 145 {
                self.runAwayFromCursor(mouse: mouse, distance: distance)
                self.petView.setState(.crawl, mood: "eep!")
                return
            }

            if distance < 220 {
                self.petView.setState(.idle, mood: "watching 👀")
            }
        }
    }


    func applyPetRenderMode() {
        if real3DMode {
            window.contentView = sceneView
        } else {
            window.contentView = petView
        }
    }

    func setReal3DMode(_ enabled: Bool) {
        real3DMode = enabled
        UserDefaults.standard.set(enabled, forKey: "lucy.real3DMode")
        applyPetRenderMode()
    }

    func currentRenderInfo() -> String {
        if real3DMode {
            return sceneView.renderInfoText()
        }

        return petView.spriteInfoText()
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


    func applicationWillTerminate(_ notification: Notification) {
        animationTimer?.invalidate()
        cursorTimer?.invalidate()
        window?.close()
        chatController?.window?.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }


}
