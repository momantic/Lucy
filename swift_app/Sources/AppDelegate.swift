import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var sceneView: LucySceneView!
    var moodLabel: NSTextField!
    var lastMoodBubbleText = ""
    var lastMoodBubbleChange = Date.distantPast
    var real3DMode = UserDefaults.standard.bool(forKey: "lucy.real3DMode")
    var isDraggingLucy = false
    var lastManualInteraction = Date.distantPast
    var fleeVelocityX: CGFloat = 0
    var fleeVelocityY: CGFloat = 0
    var fleeDodgeBias: CGFloat = 0
    var fleeSpeedBias: CGFloat = 1
    var nextFleePersonalityChange = Date.distantPast
    var fleeBurstUntil = Date.distantPast
    var isPouncing = false
    var nextPounceAllowedAt = Date.distantPast
    var nextIdleScootTime = Date().addingTimeInterval(Double.random(in: 5.0...12.0))
    var autoPerchEnabled = UserDefaults.standard.bool(forKey: "lucy.autoPerchEnabled")
    var nextAutoPerchTime = Date().addingTimeInterval(Double.random(in: 8.0...18.0))
    var isPerching = false
    var gravityModeEnabled = UserDefaults.standard.bool(forKey: "lucy.gravityModeEnabled")
    var gravityVelocityY: CGFloat = 0
    var gravityVelocityX: CGFloat = 0
    var nextGravityJumpTime = Date().addingTimeInterval(Double.random(in: 2.5...6.0))
    var roamEnabled = UserDefaults.standard.bool(forKey: "lucy.roamEnabled")
    var nextRoamActionTime = Date().addingTimeInterval(Double.random(in: 10.0...24.0))
    var window: NSWindow!
    var petView: ClickablePetView!
    var chatController: ChatWindowController?

    var wanderTimer: Timer?
    var moodTimer: Timer?
    var animationTimer: Timer?
    var cursorTimer: Timer?
    var isHidden = false
    var isSoftHidden = false


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

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )

        editMenu.addItem(
            withTitle: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )

        editMenu.addItem(NSMenuItem.separator())

        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )

        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )

        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )

        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        NSApp.mainMenu = mainMenu
    }



    func quitIfAnotherLucyIsAlreadyRunning() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier

        let otherLucys = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID }

        if let existingLucy = otherLucys.first {
            existingLucy.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return true
        }

        return false
    }


    func applicationDidFinishLaunching(_ notification: Notification) {

        if quitIfAnotherLucyIsAlreadyRunning() {
            return
        }


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



    func softHideLucy() {
        setIdleMood("hiding...")
        isSoftHidden = true
        fleeVelocityX = 0
        fleeVelocityY = 0
        gravityVelocityX = 0
        gravityVelocityY = 0
        window.orderOut(nil)
    }

    func comeBackLucy() {
        isSoftHidden = false
        setHappyMood()

        if let screen = NSScreen.main {
            var frame = window.frame
            let visible = screen.visibleFrame

            if frame.origin.x < visible.minX || frame.origin.x > visible.maxX || frame.origin.y < visible.minY - frame.height || frame.origin.y > visible.maxY {
                frame.origin.x = visible.midX - frame.width / 2
                frame.origin.y = visible.midY - frame.height / 2
                window.setFrame(frame, display: true)
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }




    func setupMoodLabel() {
        moodLabel = NSTextField(labelWithString: "")
        moodLabel.alignment = .center
        moodLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        moodLabel.textColor = NSColor.white
        moodLabel.backgroundColor = NSColor(calibratedWhite: 0.05, alpha: 0.62)
        moodLabel.wantsLayer = true
        moodLabel.layer?.cornerRadius = 8
        moodLabel.layer?.masksToBounds = true
        moodLabel.isHidden = true
        moodLabel.translatesAutoresizingMaskIntoConstraints = false

        window.contentView?.addSubview(moodLabel)

        NSLayoutConstraint.activate([
            moodLabel.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            moodLabel.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 8),
            moodLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            moodLabel.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    func showMoodBubble(_ mood: String, force: Bool = false) {
        guard moodLabel != nil else {
            return
        }

        let trimmed = mood.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return
        }

        let now = Date()

        // Prevent rapid flickering when cursor timer updates mood many times per second.
        if !force {
            if trimmed == lastMoodBubbleText {
                return
            }

            if now.timeIntervalSince(lastMoodBubbleChange) < 1.35 {
                return
            }
        }

        lastMoodBubbleText = trimmed
        lastMoodBubbleChange = now

        moodLabel.stringValue = " \(trimmed) "
        moodLabel.alphaValue = 1.0
        moodLabel.isHidden = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if self.lastMoodBubbleText == trimmed {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    self.moodLabel.animator().alphaValue = 0
                } completionHandler: {
                    if self.lastMoodBubbleText == trimmed {
                        self.moodLabel.isHidden = true
                        self.moodLabel.alphaValue = 1.0
                    }
                }
            }
        }
    }


    func setIdleMood(_ mood: String) {
        petView.setState(.idle, mood: mood)
        showMoodBubble(mood)
    }

    func setHopMood(_ mood: String) {
        petView.setState(.hop, mood: mood)
        showMoodBubble(mood)
    }

    func setRandomIdleMood() {
        let moods = ["", "hmm", "｡｡｡", "watching", "tiny thoughts", "soft idle", "curious"]
        let mood = moods.randomElement() ?? ""
        petView.setState(.idle, mood: mood)
        showMoodBubble(mood)
    }

    func setScaredMood() {
        let moods = ["eep!", "ah!", "no touch!", "scary!", "run!", "!!"]
        let mood = moods.randomElement() ?? "eep!"
        petView.setState(.crawl, mood: mood)
        showMoodBubble(mood)
    }

    func setCuriousMood() {
        let moods = ["?", "hmm?", "watching", "curious", "what's that?"]
        let mood = moods.randomElement() ?? "?"
        petView.setState(.thinking, mood: mood)
        showMoodBubble(mood)
    }

    func setHappyMood() {
        let moods = ["hi!", "yay", "hello!", "I'm here", "hehe"]
        let mood = moods.randomElement() ?? "hi!"
        petView.setState(.idle, mood: mood)
        showMoodBubble(mood)
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

            chatController?.onModelBoundsRequested = {
                return self.sceneView.modelBoundsInfoText()
            }

            chatController?.onPerchRequested = {
                self.perchOnActiveWindow()
            }

            chatController?.onAutoPerchChanged = { enabled in
                self.setAutoPerchEnabled(enabled)
            }

            chatController?.onDockPerchRequested = {
                self.perchOnDock()
            }

            chatController?.onJumpRequested = {
                self.jumpFarAway()
            }

            chatController?.onRoamChanged = { enabled in
                self.setRoamEnabled(enabled)
            }

            chatController?.onGravityChanged = { enabled in
                self.setGravityModeEnabled(enabled)
            }

            chatController?.onSoftHideRequested = {
                self.softHideLucy()
            }

            chatController?.onComeBackRequested = {
                self.comeBackLucy()
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




    func setRoamEnabled(_ enabled: Bool) {
        roamEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "lucy.roamEnabled")
        nextRoamActionTime = Date().addingTimeInterval(Double.random(in: 6.0...16.0))
    }

    func dockPerchFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return window.frame
        }

        let visible = screen.visibleFrame
        let full = screen.frame
        var frame = window.frame

        // Estimate Dock zone. If Dock is at bottom, visibleFrame.minY is above screen.minY.
        let dockTopY = visible.minY
        let dockHeight = max(40, dockTopY - full.minY)

        let xChoices: [CGFloat] = [
            visible.minX + visible.width * 0.18,
            visible.minX + visible.width * 0.38,
            visible.minX + visible.width * 0.62,
            visible.minX + visible.width * 0.82
        ]

        let targetX = xChoices.randomElement() ?? visible.midX
        frame.origin.x = targetX - frame.width / 2

        // Put Lucy slightly above the Dock, like she is sitting on it.
        frame.origin.y = full.minY + dockHeight - frame.height * 0.22

        return clampFrameToScreen(frame)
    }

    func perchOnDock() {
        guard !isPerching else {
            return
        }

        setHopMood("perch!")

        isPerching = true
        fleeVelocityX = 0
        fleeVelocityY = 0

        let targetFrame = dockPerchFrame()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Double.random(in: 0.55...0.90)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.window.animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            self.isPerching = false
            self.lastManualInteraction = Date()
        }
    }

    func jumpFarAway() {
        guard !isPerching else {
            return
        }

        setHopMood("jump!")

        guard let screen = NSScreen.main else {
            return
        }

        isPerching = true
        fleeVelocityX = 0
        fleeVelocityY = 0

        let visible = screen.visibleFrame
        var frame = window.frame

        // Pick a far place, preferably away from current position.
        let currentCenter = NSPoint(x: frame.midX, y: frame.midY)

        var candidates: [NSPoint] = []
        for _ in 0..<10 {
            candidates.append(NSPoint(
                x: CGFloat.random(in: visible.minX...(visible.maxX - frame.width)),
                y: CGFloat.random(in: visible.minY...(visible.maxY - frame.height))
            ))
        }

        let target = candidates.max { a, b in
            let da = hypot((a.x + frame.width / 2) - currentCenter.x, (a.y + frame.height / 2) - currentCenter.y)
            let db = hypot((b.x + frame.width / 2) - currentCenter.x, (b.y + frame.height / 2) - currentCenter.y)
            return da < db
        } ?? NSPoint(x: visible.midX, y: visible.midY)

        frame.origin = target
        frame = clampFrameToScreen(frame)

        // Two-stage jump: small lift, then land far away.
        var liftFrame = window.frame
        liftFrame.origin.y += 28

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.window.animator().setFrame(self.clampFrameToScreen(liftFrame), display: true)
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Double.random(in: 0.45...0.75)
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.window.animator().setFrame(frame, display: true)
            } completionHandler: {
                self.isPerching = false
                self.lastManualInteraction = Date()
            }
        }
    }

    func maybeRoam() {
        guard roamEnabled else {
            return
        }

        guard Date() > nextRoamActionTime else {
            return
        }

        nextRoamActionTime = Date().addingTimeInterval(Double.random(in: 16.0...38.0))

        if Bool.random() {
            perchOnDock()
        } else {
            jumpFarAway()
        }
    }



    func setGravityModeEnabled(_ enabled: Bool) {
        gravityModeEnabled = enabled
        
        if enabled {
            setHopMood("gravity!")
        } else {
            setIdleMood("free")
        }
        UserDefaults.standard.set(enabled, forKey: "lucy.gravityModeEnabled")

        fleeVelocityX = 0
        fleeVelocityY = 0
        gravityVelocityY = 0
        gravityVelocityX = 0
        nextGravityJumpTime = Date().addingTimeInterval(Double.random(in: 1.0...3.0))
    }

    func applyGravityStep() {
        guard gravityModeEnabled else {
            return
        }

        guard let screen = NSScreen.main else {
            return
        }

        var frame = window.frame
        let visible = screen.visibleFrame

        // Bottom floor of the usable screen.
        // Lucy's visible 3D body sits above the bottom of her transparent 180x180 window,
        // so allow the window to sink lower until the visible body touches the floor.
        let floorY = visible.minY - frame.height * 0.68

        // Gravity pulls Lucy down. Positive y is upward in AppKit screen coords.
        gravityVelocityY -= 1.15

        // Light horizontal drift for life.
        gravityVelocityX *= 0.96

        let onGround = frame.origin.y <= floorY + 1

        if onGround {
            frame.origin.y = floorY
            gravityVelocityY = max(0, gravityVelocityY)

            // Friction on ground.
            gravityVelocityX *= 0.82

            // Occasionally try to jump.
            if Date() > nextGravityJumpTime {
                nextGravityJumpTime = Date().addingTimeInterval(Double.random(in: 2.2...6.5))

                gravityVelocityY = CGFloat.random(in: 13.0...24.0)
                gravityVelocityX += CGFloat.random(in: -4.5...4.5)

                petView.setState(.hop, mood: "hop!")
            } else {
                petView.setState(.idle, mood: "")
            }
        }

        frame.origin.x += gravityVelocityX
        frame.origin.y += gravityVelocityY

        // Bounce softly off left/right screen edges.
        if frame.origin.x < visible.minX {
            frame.origin.x = visible.minX
            gravityVelocityX = abs(gravityVelocityX) * 0.65
        }

        if frame.origin.x > visible.maxX - frame.width {
            frame.origin.x = visible.maxX - frame.width
            gravityVelocityX = -abs(gravityVelocityX) * 0.65
        }

        // Land on floor.
        if frame.origin.y < floorY {
            frame.origin.y = floorY
            gravityVelocityY = 0
        }

        // Custom gravity clamp:
        // Allow Lucy's transparent window to sink below visibleFrame
        // so her actual visible body can touch the bottom of the screen.
        frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        frame.origin.y = max(floorY, min(frame.origin.y, visible.maxY - frame.height))

        window.setFrame(frame, display: true)
    }


    func setAutoPerchEnabled(_ enabled: Bool) {
        autoPerchEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "lucy.autoPerchEnabled")
        nextAutoPerchTime = Date().addingTimeInterval(Double.random(in: 4.0...10.0))
    }

    func activeWindowAsScreenRect() -> NSRect? {
        guard let frontWindow = LucyScreenAwareness.frontmostWindowInfo() else {
            return nil
        }

        let appName = frontWindow.appName.lowercased()
        if appName.contains("lucy") {
            return nil
        }

        guard let screen = NSScreen.main else {
            return nil
        }

        let screenHeight = screen.frame.height
        let cg = frontWindow.bounds

        return NSRect(
            x: cg.minX,
            y: screenHeight - cg.minY - cg.height,
            width: cg.width,
            height: cg.height
        )
    }

    func choosePerchFrame(on activeWindow: NSRect) -> NSRect {
        var frame = window.frame

        enum PerchSpot: CaseIterable {
            case topLeft
            case topCenter
            case topRight
            case leftSide
            case rightSide
        }

        let spot = PerchSpot.allCases.randomElement() ?? .topRight

        // Lucy's actual visible 3D body is smaller than the 180x180 transparent window.
        // These visual anchor values estimate where her visible body sits inside the window.
        let visualBodyWidth = frame.width * 0.58
        let visualBodyHeight = frame.height * 0.58
        let visualBodyLeftInset = (frame.width - visualBodyWidth) / 2
        let visualBodyBottomInset = frame.height * 0.18

        func setVisualBodyBottomLeft(x: CGFloat, y: CGFloat) {
            frame.origin.x = x - visualBodyLeftInset
            frame.origin.y = y - visualBodyBottomInset
        }

        switch spot {
        case .topLeft:
            // Put Lucy's visible feet/body on the top-left edge.
            setVisualBodyBottomLeft(
                x: activeWindow.minX + 18,
                y: activeWindow.maxY - visualBodyHeight * 1.05
            )

        case .topCenter:
            setVisualBodyBottomLeft(
                x: activeWindow.midX - visualBodyWidth / 2,
                y: activeWindow.maxY - visualBodyHeight * 1.05
            )

        case .topRight:
            setVisualBodyBottomLeft(
                x: activeWindow.maxX - visualBodyWidth - 18,
                y: activeWindow.maxY - visualBodyHeight * 1.05
            )

        case .leftSide:
            setVisualBodyBottomLeft(
                x: activeWindow.minX - visualBodyWidth * 0.45,
                y: activeWindow.midY - visualBodyHeight * 0.85
            )

        case .rightSide:
            setVisualBodyBottomLeft(
                x: activeWindow.maxX - visualBodyWidth * 0.55,
                y: activeWindow.midY - visualBodyHeight * 0.85
            )
        }

        return clampFrameToScreen(frame)
    }

    func perchOnActiveWindow() {
        guard !isPerching else {
            return
        }

        guard let activeWindow = activeWindowAsScreenRect() else {
            return
        }

        let targetFrame = choosePerchFrame(on: activeWindow)

        isPerching = true
        fleeVelocityX = 0
        fleeVelocityY = 0
        sceneView.setAliveMotionPaused(false)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Double.random(in: 0.55...0.95)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.window.animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            self.isPerching = false
            self.lastManualInteraction = Date()
        }
    }

    func maybeAutoPerch() {
        guard autoPerchEnabled else {
            return
        }

        guard Date() > nextAutoPerchTime else {
            return
        }

        nextAutoPerchTime = Date().addingTimeInterval(Double.random(in: 16.0...36.0))
        perchOnActiveWindow()
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



    func pounceAwayFromCursor(mouse: NSPoint) {
        guard !isPouncing else {
            return
        }

        guard Date() > nextPounceAllowedAt else {
            return
        }

        guard let screen = NSScreen.main else {
            return
        }

        isPouncing = true
        nextPounceAllowedAt = Date().addingTimeInterval(Double.random(in: 2.5...5.0))
        fleeVelocityX = 0
        fleeVelocityY = 0

        let visible = screen.visibleFrame
        let current = window.frame
        let center = NSPoint(x: current.midX, y: current.midY)

        let awayX = center.x - mouse.x
        let awayY = center.y - mouse.y
        let length = max(1, sqrt(awayX * awayX + awayY * awayY))
        let normalizedX = awayX / length
        let normalizedY = awayY / length

        var crouchFrame = current
        crouchFrame.origin.y -= 6

        var launchFrame = current
        launchFrame.origin.x += normalizedX * CGFloat.random(in: 180...320)
        launchFrame.origin.y += max(60, normalizedY * CGFloat.random(in: 90...180)) + CGFloat.random(in: 40...90)

        launchFrame.origin.x = max(visible.minX, min(launchFrame.origin.x, visible.maxX - launchFrame.width))
        launchFrame.origin.y = max(visible.minY, min(launchFrame.origin.y, visible.maxY - launchFrame.height))

        var landFrame = launchFrame
        landFrame.origin.y -= CGFloat.random(in: 35...80)
        landFrame.origin.y = max(visible.minY, min(landFrame.origin.y, visible.maxY - landFrame.height))

        setHopMood("pounce!")

        // Crouch.
        sceneView.setPounceVisualPhase(.crouch)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.window.animator().setFrame(self.clampFrameToScreen(crouchFrame), display: true)
        } completionHandler: {
            // Launch/stretch.
            self.sceneView.setPounceVisualPhase(.stretch)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = Double.random(in: 0.28...0.42)
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.window.animator().setFrame(self.clampFrameToScreen(launchFrame), display: true)
            } completionHandler: {
                // Land/bounce.
                self.sceneView.setPounceVisualPhase(.land)

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Double.random(in: 0.18...0.28)
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    self.window.animator().setFrame(self.clampFrameToScreen(landFrame), display: true)
                } completionHandler: {
                    self.sceneView.setPounceVisualPhase(.normal)
                    self.isPouncing = false
                    self.lastManualInteraction = Date()
                }
            }
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

        // Faster flee speed: about 3x previous movement.
        var desiredSpeed = CGFloat(5.4 + closeness * 21.6) * fleeSpeedBias

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
        // Keep high flee speed, but smooth the acceleration so she feels alive instead of teleporty.
        let acceleration = CGFloat(0.11 + closeness * 0.08)
        fleeVelocityX += (targetVX - fleeVelocityX) * acceleration
        fleeVelocityY += (targetVY - fleeVelocityY) * acceleration

        // Cap max velocity to avoid sudden huge jumps from random bursts.
        let maxSpeed = CGFloat(16.5)
        let currentSpeed = max(0.001, sqrt(fleeVelocityX * fleeVelocityX + fleeVelocityY * fleeVelocityY))
        if currentSpeed > maxSpeed {
            fleeVelocityX = fleeVelocityX / currentSpeed * maxSpeed
            fleeVelocityY = fleeVelocityY / currentSpeed * maxSpeed
        }

        // Natural damping so she settles instead of sliding forever.
        fleeVelocityX *= 0.975
        fleeVelocityY *= 0.975

        // Smaller per-frame movement because cursor timer runs faster now.
        // This keeps the same fast feel but makes motion smoother.
        let frameStep = CGFloat(0.42)

        var newFrame = frame
        newFrame.origin.x += fleeVelocityX * frameStep
        newFrame.origin.y += fleeVelocityY * frameStep

        LucyRuntime.shared.facingRight = normalizedX >= 0
        window.setFrame(clampFrameToScreen(newFrame), display: true)
    }


    func startCursorAwareness() {
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            if self.isHidden || self.isSoftHidden { return }

            if self.gravityModeEnabled {
                self.applyGravityStep()
                return
            }

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
                self.setHappyMood()
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
                self.maybeAutoPerch()
                self.maybeRoam()
                self.setRandomIdleMood()
                return
            }

            // Wary zone: she notices the cursor and looks at it, but does not run yet.
            if distance > 150 {
                LucyRuntime.shared.facingRight = dx >= 0
                self.sceneView.lookToward(dx: dx * 0.55, dy: dy * 0.45)
                self.fleeVelocityX *= 0.92
                self.fleeVelocityY *= 0.92
                self.setCuriousMood()
                return
            }

            // Close zone: she actively avoids the cursor.
            if distance > 95 {
                LucyRuntime.shared.facingRight = dx >= 0
                self.sceneView.lookToward(dx: dx, dy: dy)
                if distance < 140
                    && !self.isPouncing
                    && Date() > self.nextPounceAllowedAt
                    && CGFloat.random(in: 0...1) < 0.35 {
                    self.pounceAwayFromCursor(mouse: mouse)
                    return
                }

                self.runAwayFromCursor(mouse: mouse, distance: distance)
                self.setScaredMood()
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
        setupMoodLabel()
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
            if self.isHidden || self.isSoftHidden { return }
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
            if self.isHidden || self.isSoftHidden { return }
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
