import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var sceneView: LucySceneView!
    var real3DMode = UserDefaults.standard.bool(forKey: "lucy.real3DMode")
    var isDraggingLucy = false
    var lastManualInteraction = Date.distantPast
    var fleeVelocityX: CGFloat = 0
    var fleeVelocityY: CGFloat = 0
    var fleeDodgeBias: CGFloat = 0
    var fleeSpeedBias: CGFloat = 1
    var nextFleePersonalityChange = Date.distantPast
    var fleeBurstUntil = Date.distantPast
    var nextIdleScootTime = Date().addingTimeInterval(Double.random(in: 5.0...12.0))
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
        fleeVelocityX = 0
        fleeVelocityY = 0

        var frame = window.frame
        frame.origin.x += dx
        frame.origin.y -= dy
        window.setFrame(clampFrameToScreen(frame), display: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.isDraggingLucy = false
        }
    }


    func maybeDoIdleScoot() {
        let now = Date()
        guard now > nextIdleScootTime else {
            return
        }

        nextIdleScootTime = now.addingTimeInterval(Double.random(in: 7.0...16.0))

        // Small self-directed shift. Feels alive, not like fleeing.
        var frame = window.frame
        frame.origin.x += CGFloat.random(in: -18...18)
        frame.origin.y += CGFloat.random(in: -10...14)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Double.random(in: 0.35...0.65)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.window.animator().setFrame(self.clampFrameToScreen(frame), display: true)
        }
    }


    func runAwayFromCursor(mouse: NSPoint, distance: CGFloat) {
        guard distance > 1 else {
            return
        }

        let now = Date()
        let frame = window.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)

        let awayX = center.x - mouse.x
        let awayY = center.y - mouse.y

        let length = max(1, sqrt(awayX * awayX + awayY * awayY))
        let normalizedX = awayX / length
        let normalizedY = awayY / length

        // Update personality less often so she curves naturally instead of jittering.
        if now > nextFleePersonalityChange {
            nextFleePersonalityChange = now.addingTimeInterval(Double.random(in: 0.45...1.15))
            fleeDodgeBias = CGFloat.random(in: -0.42...0.42)
            fleeSpeedBias = CGFloat.random(in: 0.88...1.22)

            // Rare little "panic hop" burst.
            if CGFloat.random(in: 0...1) < 0.18 {
                fleeBurstUntil = now.addingTimeInterval(Double.random(in: 0.16...0.32))
            }
        }

        let closeness = max(0, min(1, (165 - distance) / 165))

        // Curved path: persistent side bias, stronger when cursor is close.
        let dodge = fleeDodgeBias * closeness
        let dodgeX = -normalizedY * dodge
        let dodgeY = normalizedX * dodge

        var desiredSpeed = CGFloat(1.8 + closeness * 7.2) * fleeSpeedBias

        if now < fleeBurstUntil {
            desiredSpeed *= CGFloat.random(in: 1.35...1.65)
        }

        // Normalize after dodge so diagonal dodges do not become too fast.
        let moveX = normalizedX + dodgeX
        let moveY = normalizedY + dodgeY
        let moveLength = max(0.001, sqrt(moveX * moveX + moveY * moveY))

        let targetVX = (moveX / moveLength) * desiredSpeed
        let targetVY = (moveY / moveLength) * desiredSpeed

        // Smooth acceleration/deceleration.
        let acceleration = CGFloat(0.18 + closeness * 0.12)
        fleeVelocityX += (targetVX - fleeVelocityX) * acceleration
        fleeVelocityY += (targetVY - fleeVelocityY) * acceleration

        // Tiny natural damping so she settles instead of sliding forever.
        fleeVelocityX *= 0.985
        fleeVelocityY *= 0.985

        var newFrame = frame
        newFrame.origin.x += fleeVelocityX
        newFrame.origin.y += fleeVelocityY

        LucyRuntime.shared.facingRight = normalizedX >= 0
        window.setFrame(clampFrameToScreen(newFrame), display: true)
    }


    func startCursorAwareness() {
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
            if self.isHidden { return }

            let mouse = NSEvent.mouseLocation
            let frame = self.window.frame
            let center = NSPoint(x: frame.midX, y: frame.midY)

            let dx = mouse.x - center.x
            let dy = mouse.y - center.y
            let distance = sqrt(dx * dx + dy * dy)

            // If the cursor is actually over Lucy's approximate body area, stop running.
            // This lets you double-click or drag her.
            let bodyZone = NSRect(
                x: frame.midX - frame.width * 0.28,
                y: frame.midY - frame.height * 0.26,
                width: frame.width * 0.56,
                height: frame.height * 0.52
            )

            let normalizedX = (mouse.x - bodyZone.midX) / max(1, bodyZone.width / 2)
            let normalizedY = (mouse.y - bodyZone.midY) / max(1, bodyZone.height / 2)
            let touchZone = normalizedX * normalizedX + normalizedY * normalizedY <= 1.0

            if touchZone || self.isDraggingLucy {
                self.fleeVelocityX *= 0.55
                self.fleeVelocityY *= 0.55
                self.sceneView.setAliveMotionPaused(true)
                self.petView.setState(.idle, mood: "hi")
                return
            } else {
                self.sceneView.setAliveMotionPaused(false)
            }

            // Short grace period after dragging/clicking so she does not instantly flee.
            if Date().timeIntervalSince(self.lastManualInteraction) < 0.45 {
                self.sceneView.lookToward(dx: 0, dy: 0)
                return
            }

            // Far away: Lucy does her own thing. No cursor tracking.
            if distance > 300 {
                self.fleeVelocityX *= 0.90
                self.fleeVelocityY *= 0.90
                self.sceneView.lookToward(dx: 0, dy: 0)
                self.maybeDoIdleScoot()
                self.petView.setState(.idle, mood: "")
                return
            }

            // Wary zone: she notices the cursor and looks at it, but does not run yet.
            if distance > 150 {
                LucyRuntime.shared.facingRight = dx >= 0
                self.sceneView.lookToward(dx: dx * 0.55, dy: dy * 0.45)
                self.fleeVelocityX *= 0.92
                self.fleeVelocityY *= 0.92
                self.petView.setState(.idle, mood: "watching")
                return
            }

            // Close zone: she actively avoids the cursor.
            if distance > 95 {
                LucyRuntime.shared.facingRight = dx >= 0
                self.sceneView.lookToward(dx: dx, dy: dy)
                self.runAwayFromCursor(mouse: mouse, distance: distance)
                self.petView.setState(.crawl, mood: "eep!")
                return
            }

            // Very close but not touching the body zone: panic scoot, still gentle.
            LucyRuntime.shared.facingRight = dx >= 0
            self.sceneView.lookToward(dx: dx, dy: dy)
            self.runAwayFromCursor(mouse: mouse, distance: distance)
            self.petView.setState(.crawl, mood: "!")
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
