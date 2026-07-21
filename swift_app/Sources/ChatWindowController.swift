import Cocoa
import Foundation
import Speech
import AVFoundation


class LucySettings {
    static let shared = LucySettings()

    func ensureSettingsFile() {
        let dir = LucyPaths.settingsURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: LucyPaths.settingsURL.path) {
            let initial: [String: Any] = [
                "browser": "Safari"
            ]

            if let data = try? JSONSerialization.data(withJSONObject: initial, options: [.prettyPrinted]) {
                try? data.write(to: LucyPaths.settingsURL)
            }
        }
    }

    func loadSettings() -> [String: Any] {
        ensureSettingsFile()

        guard
            let data = try? Data(contentsOf: LucyPaths.settingsURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ["browser": "Safari"]
        }

        return json
    }

    func browserPreference() -> String {
        let settings = loadSettings()
        return settings["browser"] as? String ?? "Safari"
    }

    func saveBrowserPreference(_ browser: String) {
        ensureSettingsFile()

        var settings = loadSettings()
        settings["browser"] = browser

        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted]) {
            try? data.write(to: LucyPaths.settingsURL)
        }
    }
}


class LucyHeaderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.38, green: 0.25, blue: 0.86, alpha: 1.0),
            NSColor(calibratedRed: 0.88, green: 0.42, blue: 0.82, alpha: 1.0),
            NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.50, alpha: 1.0)
        ])
        gradient?.draw(in: bounds, angle: 18)

        NSColor.white.withAlphaComponent(0.13).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.width - 150, y: bounds.height - 80, width: 190, height: 125)).fill()
        NSColor.white.withAlphaComponent(0.08).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.width - 70, y: -30, width: 105, height: 105)).fill()

        let iconCandidates = [
            LucyPaths.root.appendingPathComponent("lucy-store-icon.png"),
            LucyPaths.root.appendingPathComponent("assets").appendingPathComponent("lucy_icon_1024.png"),
            Bundle.main.resourceURL?.appendingPathComponent("LucyStoreIcon.png")
        ].compactMap { $0 }

        if let iconURL = iconCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
           let image = NSImage(contentsOf: iconURL) {
            let glowRect = NSRect(x: 13, y: bounds.midY - 29, width: 58, height: 58)
            NSColor.white.withAlphaComponent(0.24).setFill()
            NSBezierPath(roundedRect: glowRect, xRadius: 19, yRadius: 19).fill()

            let iconRect = NSRect(x: 19, y: bounds.midY - 23, width: 46, height: 46)
            image.draw(in: iconRect)
        }

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .left

        ("Lucy" as NSString).draw(
            in: NSRect(x: 82, y: bounds.midY + 1, width: bounds.width - 110, height: 28),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 24, weight: .heavy),
                .foregroundColor: NSColor.white,
                .paragraphStyle: titleStyle
            ]
        )

        ("Your cozy desktop companion for natural requests." as NSString).draw(
            in: NSRect(x: 83, y: bounds.midY - 22, width: bounds.width - 105, height: 22),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
                .paragraphStyle: titleStyle
            ]
        )
    }
}


class LucyChatBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.98, green: 0.96, blue: 1.00, alpha: 0.96),
            NSColor(calibratedRed: 0.93, green: 0.96, blue: 1.00, alpha: 0.94),
            NSColor(calibratedRed: 1.00, green: 0.95, blue: 0.98, alpha: 0.92)
        ])
        gradient?.draw(in: bounds, angle: 270)

        NSColor(calibratedRed: 0.58, green: 0.36, blue: 0.98, alpha: 0.08).setFill()
        NSBezierPath(ovalIn: NSRect(x: -78, y: bounds.height - 170, width: 230, height: 230)).fill()

        NSColor(calibratedRed: 1.00, green: 0.53, blue: 0.72, alpha: 0.08).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.width - 160, y: 36, width: 220, height: 220)).fill()
    }
}


class ChatWindowController: NSObject, NSTextFieldDelegate {
    private var pendingReminderRequest: String?
    private var pendingCalendarRequest: String?
    private var pendingNoteRequest: String?
    private var pendingRegistryToolName: String?
    private var pendingRegistryToolRequest: String?
    private var pendingGoalApprovedToolName: String?
    private var pendingGoalOriginalRequest: String?

    struct LucyToolRegistry: Decodable {
        let tools: [LucyRegisteredTool]
    }

    struct LucyRegisteredTool: Decodable {
        let name: String
        let path: String
        let dry_run: Bool?
        let purpose: String?
        let requires_approval_for_real_action: Bool?
        let pair_base: String?
        let role: String?
        let intent_prefixes: [String]?
    }

    var conversationHistory: [LucyChatMessage] = []


    var audioEngine = AVAudioEngine()
    var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask: SFSpeechRecognitionTask?
    var isListening = false

    var window: NSWindow!
    var output: NSTextView!
    var input: NSTextField!
    let model = "qwen2.5:1.5b"
    var preferredBrowser = LucySettings.shared.browserPreference()

    var onHideRequested: (() -> Void)?
    var onUse3DChanged: ((Bool) -> Void)?
    var onReal3DChanged: ((Bool) -> Void)?
    var onRenderInfoRequested: (() -> String)?
    var onScreenInfoRequested: (() -> String)?
    var onModelBoundsRequested: (() -> String)?
    var onPerchRequested: (() -> Void)?
    var onAutoPerchChanged: ((Bool) -> Void)?
    var onDockPerchRequested: (() -> Void)?
    var onJumpRequested: (() -> Void)?
    var onRoamChanged: ((Bool) -> Void)?
    var onGravityChanged: ((Bool) -> Void)?
    var onSoftHideRequested: (() -> Void)?
    var onComeBackRequested: (() -> Void)?
    var onSpriteInfoRequested: (() -> String)?

    override init() {
        super.init()
        buildWindow()
    }

    func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 260, y: 260, width: 620, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Talk to Lucy"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear

        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))
        root.material = .sidebar
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor

        let background = LucyChatBackgroundView(frame: root.bounds)
        background.autoresizingMask = [.width, .height]

        let header = LucyHeaderView(frame: NSRect(x: 0, y: 382, width: 620, height: 78))
        header.autoresizingMask = [.width, .minYMargin]
        header.wantsLayer = true
        header.layer?.cornerRadius = 16
        header.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        let transcriptCard = NSView(frame: NSRect(x: 15, y: 66, width: 590, height: 304))
        transcriptCard.autoresizingMask = [.width, .height]
        transcriptCard.wantsLayer = true
        transcriptCard.layer?.cornerRadius = 20
        transcriptCard.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.53).cgColor
        transcriptCard.layer?.borderColor = NSColor.white.withAlphaComponent(0.72).cgColor
        transcriptCard.layer?.borderWidth = 1
        transcriptCard.layer?.shadowColor = NSColor.black.cgColor
        transcriptCard.layer?.shadowOpacity = 0.12
        transcriptCard.layer?.shadowRadius = 16
        transcriptCard.layer?.shadowOffset = CGSize(width: 0, height: -5)

        let scroll = NSScrollView(frame: NSRect(x: 22, y: 74, width: 576, height: 288))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 16
        scroll.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.36).cgColor
        scroll.autoresizingMask = [.width, .height]

        output = NSTextView(frame: NSRect(x: 0, y: 0, width: 576, height: 288))
        output.isEditable = false
        output.isSelectable = true
        output.font = NSFont.systemFont(ofSize: 14.5, weight: .regular)
        output.textColor = .labelColor
        output.backgroundColor = .clear
        output.insertionPointColor = NSColor(calibratedRed: 0.58, green: 0.36, blue: 0.98, alpha: 1.0)
        output.textContainerInset = NSSize(width: 18, height: 16)
        output.textContainer?.lineFragmentPadding = 0


        scroll.documentView = output

        input = NSTextField(frame: NSRect(x: 15, y: 18, width: 390, height: 36))
        input.placeholderString = "Ask Lucy anything…"
        input.delegate = self
        input.font = NSFont.systemFont(ofSize: 14.5, weight: .medium)
        input.wantsLayer = true
        input.layer?.cornerRadius = 13
        input.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.75).cgColor
        input.layer?.borderColor = NSColor(calibratedRed: 0.62, green: 0.45, blue: 0.96, alpha: 0.25).cgColor
        input.layer?.borderWidth = 1

        let listenButton = NSButton(frame: NSRect(x: 415, y: 18, width: 90, height: 36))
        listenButton.title = "🎙 Listen"
        listenButton.target = self
        listenButton.action = #selector(startDictation)
        listenButton.bezelStyle = .rounded
        listenButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        listenButton.contentTintColor = NSColor(calibratedRed: 0.44, green: 0.31, blue: 0.74, alpha: 1.0)

        let sendButton = NSButton(frame: NSRect(x: 515, y: 18, width: 90, height: 36))
        sendButton.title = "Send ✨"
        sendButton.target = self
        sendButton.action = #selector(sendMessage)
        sendButton.bezelStyle = .rounded
        sendButton.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        sendButton.contentTintColor = NSColor(calibratedRed: 0.74, green: 0.26, blue: 0.68, alpha: 1.0)

        root.addSubview(background)
        root.addSubview(header)
        root.addSubview(transcriptCard)
        root.addSubview(scroll)
        root.addSubview(input)
        root.addSubview(listenButton)
        root.addSubview(sendButton)

        window.contentView = root

        append("""
        Lucy: Hi, I’m Lucy ✨

        Start typing naturally — no slash commands needed.

        Try things like:
        • open google
        • find cute jumping spider pictures
        • search youtube for lucas the spider
        • open wikipedia.org
        • use chrome / use safari
        • hide for a bit, then come back
        • write an email to someone@example.com asking to meet

        """)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func prepareForTermination() {
        stopListening(shouldAppend: false)
        window?.orderOut(nil)
        window?.delegate = nil
    }


    func controlTextDidEndEditing(_ obj: Notification) {
        guard
            let movement = obj.userInfo?["NSTextMovement"] as? Int,
            movement == NSReturnTextMovement
        else {
            return
        }

        sendMessage()
    }



    @objc func startDictation() {
        if isListening {
            stopListening()
            return
        }

        requestSpeechPermissions { allowed in
            DispatchQueue.main.async {
                if allowed {
                    self.startListening()
                } else {
                    self.append("""
                    Lucy: I need microphone and speech-recognition permission to listen.

                    Check:
                    System Settings → Privacy & Security → Microphone
                    System Settings → Privacy & Security → Speech Recognition

                    Then allow Lucy.

                    """)
                }
            }
        }
    }

    func requestSpeechPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            if speechStatus != .authorized {
                completion(false)
                return
            }

            if #available(macOS 14.0, *) {
                AVAudioApplication.requestRecordPermission { micAllowed in
                    completion(micAllowed)
                }
            } else {
                AVCaptureDevice.requestAccess(for: .audio) { micAllowed in
                    completion(micAllowed)
                }
            }
        }
    }

    func startListening() {
        recognitionTask?.cancel()
        recognitionTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            append("Lucy: I could not create a speech recognition request.\n\n")
            return
        }

        recognitionRequest.shouldReportPartialResults = true

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            append("Lucy: Speech recognition is not available right now.\n\n")
            return
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        input.stringValue = ""
        input.becomeFirstResponder()

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                let spokenText = result.bestTranscription.formattedString

                DispatchQueue.main.async {
                    self.input.stringValue = spokenText
                }

                if result.isFinal {
                    DispatchQueue.main.async {
                        self.stopListening()
                    }
                }
            }

            if error != nil {
                DispatchQueue.main.async {
                    self.stopListening()
                }
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        do {
            try audioEngine.start()
            isListening = true
            append("Lucy: Listening... speak now. Click Listen again to stop, then press Enter to send.\n\n")
        } catch {
            append("Lucy: I could not start listening: \(error.localizedDescription)\n\n")
            stopListening()
        }
    }

    func stopListening(shouldAppend: Bool = true) {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        if shouldAppend {
            append("Lucy: Stopped listening. Press Enter or Send when ready.\n\n")
        }
    }

    @objc func sendMessage() {
        let rawText = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawText.isEmpty { return }

        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count > 1 {
            input.stringValue = ""

            for line in lines {
                input.stringValue = line
                sendMessage()
            }

            input.stringValue = ""
            return
        }

        var userText = rawText

        input.stringValue = ""
        append("You: \(userText)\n")

        let loweredEarly = userText
            .lowercased()
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "!", with: " ")
            .replacingOccurrences(of: "?", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Priority local intent commands before any fuzzy/LLM routing.
        // These EXECUTE actions, not just chat about them.

        if loweredEarly.contains("come back")
            || loweredEarly.contains("come abck")
            || loweredEarly.contains("comeback")
            || loweredEarly.contains("come here")
            || loweredEarly.contains("show yourself")
            || loweredEarly.contains("show lucy")
            || loweredEarly.contains("bring lucy back") {
            onComeBackRequested?()
            append("Lucy: I’m back.\n\n")
            return
        }

        if loweredEarly.contains("roam off")
            || loweredEarly.contains("turn off roam")
            || loweredEarly.contains("stop roaming")
            || loweredEarly.contains("stop roam")
            || loweredEarly.contains("disable roam")
            || loweredEarly.contains("stop wandering") {
            onRoamChanged?(false)
            append("Lucy: roam mode is off.\n\n")
            return
        }

        if loweredEarly.contains("roam on")
            || loweredEarly.contains("turn on roam")
            || loweredEarly.contains("start roaming")
            || loweredEarly.contains("enable roam")
            || loweredEarly.contains("wander around") {
            onRoamChanged?(true)
            append("Lucy: roam mode is on.\n\n")
            return
        }

        if loweredEarly.contains("hide until")
            || loweredEarly == "hide"
            || loweredEarly.contains("hide lucy")
            || loweredEarly.contains("go hide")
            || loweredEarly.contains("disappear")
            || loweredEarly.contains("go away for now") {
            onSoftHideRequested?()
            append("Lucy: okay, I’ll hide. Say `come back` when you want me back.\n\n")
            return
        }

        if loweredEarly.contains("gravity off")
            || loweredEarly.contains("turn off gravity")
            || loweredEarly.contains("stop gravity")
            || loweredEarly.contains("stop falling") {
            onGravityChanged?(false)
            append("Lucy: gravity mode is off.\n\n")
            return
        }

        if loweredEarly.contains("gravity on")
            || loweredEarly.contains("turn on gravity")
            || loweredEarly.contains("fall down")
            || loweredEarly.contains("falling physics")
            || loweredEarly.contains("physics thing") {
            onGravityChanged?(true)
            append("Lucy: gravity mode is on.\n\n")
            return
        }

        if loweredEarly.contains("jump")
            || loweredEarly.contains("hop away")
            || loweredEarly.contains("move somewhere far")
            || loweredEarly.contains("go somewhere far") {
            onJumpRequested?()
            append("Lucy: jumping away!\n\n")
            return
        }

        if loweredEarly.contains("dock")
            && (loweredEarly.contains("sit") || loweredEarly.contains("perch") || loweredEarly.contains("go")) {
            onDockPerchRequested?()
            append("Lucy: perching near the Dock.\n\n")
            return
        }

        if userText.hasPrefix("/") {
            let resolvedCommand = resolveSlashCommand(userText)
            if resolvedCommand.hasPrefix("/__unknown__ ") {
                let result = runSlashCommand(resolvedCommand)
                append("Lucy:\n\(result)\n\n")
                return
            }
            userText = resolvedCommand
        }

        conversationHistory.append(LucyChatMessage(role: "User", content: userText))

        let lowered = userText.lowercased()

        if lowered.hasPrefix("/tool ") || lowered == "/tool" {
            let result = runSandboxToolCommand(userText)
            append("Lucy:\n\(result)\n\n")
            return
        }

        // Normal chat should not be hijacked by broad tool-registry prefixes like
        // "open ", "find ", or "write an email ". Keep sandbox tools available
        // through explicit /tool commands and pending approvals, but let natural
        // requests continue to Lucy's built-in natural command, email, and chat routes.
        if looksLikeGenericApproval(userText),
           let pendingTool = pendingRegistryToolName,
           let pendingRequest = pendingRegistryToolRequest {
            let result = runSandboxToolCommand("/tool \(pendingTool) " + pendingRequest)
            append("Lucy:\nCreating the approved action now through the tool registry.\n\n\(result)\n\n")
            pendingRegistryToolName = nil
            pendingRegistryToolRequest = nil
            return
        }

        if looksLikeNoteApproval(userText), let pending = pendingNoteRequest {
            let result = runSandboxToolCommand("/tool notes_create_approved " + pending)
            append("Lucy:\nCreating the approved note now.\n\n\(result)\n\n")
            pendingNoteRequest = nil
            return
        }

        if looksLikeNoteRequest(userText) {
            pendingNoteRequest = userText
            let result = runSandboxToolCommand("/tool notes_dry_run " + userText)
            append("Lucy:\nI think this is a note request, so I ran a dry-run preview.\n\n\(result)\n\nSay `yes create it` if you want me to create this Notes.app note.\n\n")
            return
        }

        if looksLikeCalendarApproval(userText), let pending = pendingCalendarRequest {
            let result = runSandboxToolCommand("/tool calendar_create_approved " + pending)
            append("Lucy:\nCreating the approved calendar event now.\n\n\(result)\n\n")
            pendingCalendarRequest = nil
            return
        }

        if looksLikeCalendarRequest(userText) {
            pendingCalendarRequest = userText
            let result = runSandboxToolCommand("/tool calendar_dry_run " + userText)
            append("Lucy:\nI think this is a calendar request, so I ran a dry-run preview.\n\n\(result)\n\nSay `yes create it` if you want me to create this Calendar.app event.\n\n")
            return
        }

        if looksLikeReminderApproval(userText), let pending = pendingReminderRequest {
            let result = runSandboxToolCommand("/tool reminders_create_approved " + pending)
            append("Lucy:\nCreating the approved reminder now.\n\n\(result)\n\n")
            pendingReminderRequest = nil
            return
        }

        if looksLikeReminderRequest(userText) {
            pendingReminderRequest = userText
            let result = runSandboxToolCommand("/tool reminders_dry_run " + userText)
            append("Lucy:\nI think this is a reminder request, so I ran a dry-run preview.\n\n\(result)\n\nSay `yes create it` if you want me to create it later. Real Reminders.app creation is not enabled yet, so approval is currently dry-run only.\n\n")
            return
        }





        if lowered == "/copydraft" {
            let postURL = URL(fileURLWithPath: "/tmp/lucy_linkedin_post.txt")
            if let draft = try? String(contentsOf: postURL, encoding: .utf8),
               !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(draft, forType: .string)
                append("Lucy: Copied the saved LinkedIn draft to your clipboard.\n\n")
                append("Lucy: Preview:\n\n\(draft)\n\n")
                
            } else {
                append("Lucy: I could not find a saved draft at /tmp/lucy_linkedin_post.txt.\n\n")
            }
            return
        }


        if routeLinkedInPostDraft(userText) {
            return
        }


        if !userText.hasPrefix("/")
            && firstEmailAddress(in: userText) != nil
            && (
                lowered.contains("email")
                || lowered.contains("mail")
                || lowered.contains("write")
                || lowered.contains("draft")
                || lowered.contains("message")
            ) {

            append("Lucy: drafting the email and opening Gmail compose...\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.draftEmailForGmailCompose(userText)

                DispatchQueue.main.async {
                    self.append("Lucy:\n\(result)\n\n")
                }
            }

            return
        }

        if lowered == "/whoami" || lowered == "who are you" || lowered == "what are you" {
            append("Lucy:\n\(selfIdentitySummary())\n\n")
            return
        }

        if lowered == "/capabilities" || lowered == "what can you do" || lowered == "what can you do?" {
            append("Lucy:\n\(capabilitiesSummary())\n\n")
            return
        }

        if lowered == "/limitations" || lowered == "what can you not do" || lowered == "what can't you do" {
            append("Lucy:\n\(limitationsSummary())\n\n")
            return
        }

        if lowered == "/time" || lowered == "time" || lowered == "what time is it" {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .medium
            let now = formatter.string(from: Date())

            append("Lucy: The current time is \(now).\n\n")
            return
        }




        if lowered == "/real3d on" {
            onReal3DChanged?(true)
            append("Lucy: Real 3D SceneKit mode is on.\n\n")
            return
        }

        if lowered == "/real3d off" {
            onReal3DChanged?(false)
            append("Lucy: Real 3D SceneKit mode is off.\n\n")
            return
        }



        if lowered == "/perch dock" {
            onDockPerchRequested?()
            append("Lucy: perching near the Dock.\n\n")
            return
        }

        if lowered == "/jump" {
            onJumpRequested?()
            append("Lucy: jumping away!\n\n")
            return
        }



        if lowered == "/hide"
            || lowered == "hide"
            || lowered == "hide lucy"
            || lowered.contains("hide until")
            || lowered.contains("go hide")
            || lowered.contains("disappear") {
            onSoftHideRequested?()
            append("Lucy: okay, I’ll hide. Say `come back` when you want me back.\n\n")
            return
        }

        if lowered == "/comeback"
            || lowered == "/come back"
            || lowered == "come back"
            || lowered == "come back lucy"
            || lowered == "lucy come back"
            || lowered == "show yourself"
            || lowered == "show lucy" {
            onComeBackRequested?()
            append("Lucy: I’m back.\n\n")
            return
        }

        if lowered == "/gravity on" {
            onGravityChanged?(true)
            append("Lucy: gravity mode is on. I’ll try to jump, but I keep falling back down.\n\n")
            return
        }

        if lowered == "/gravity off" {
            onGravityChanged?(false)
            append("Lucy: gravity mode is off.\n\n")
            return
        }

        if lowered == "/roam on" {
            onRoamChanged?(true)
            append("Lucy: roam mode is on. I’ll occasionally perch or jump around.\n\n")
            return
        }

        if lowered == "/roam off" {
            onRoamChanged?(false)
            append("Lucy: roam mode is off.\n\n")
            return
        }

        if lowered == "/perch" || lowered == "perch" {
            onPerchRequested?()
            append("Lucy: finding a place to perch.\n\n")
            return
        }

        if lowered == "/perch auto" {
            onAutoPerchChanged?(true)
            append("Lucy: auto-perch is on. I’ll occasionally sit on active windows.\n\n")
            return
        }

        if lowered == "/perch off" {
            onAutoPerchChanged?(false)
            append("Lucy: auto-perch is off.\n\n")
            return
        }


        if lowered == "/modelbounds" {
            let result = onModelBoundsRequested?() ?? "Model bounds are not wired."
            append("Lucy Model Bounds:\n\(result)\n\n")
            return
        }

        if lowered == "/renderinfo" {
            let result = onRenderInfoRequested?() ?? "Render info is not wired."
            append("Lucy Render Info:\n\(result)\n\n")
            return
        }

        if lowered == "/spriteinfo" {
            let result = onSpriteInfoRequested?() ?? "Sprite info is not wired."
            append("Lucy Sprite Info:\n\(result)\n\n")
            return
        }


        if lowered == "/use3d on" {
            onUse3DChanged?(true)
            append("Lucy: 3D sprite mode is on.\n\n")
            return
        }

        if lowered == "/use3d off" {
            onUse3DChanged?(false)
            append("Lucy: 3D sprite mode is off. I will use my old drawn body.\n\n")
            return
        }



        if lowered == "/quit" || lowered == "quit lucy" || lowered == "close lucy" {
            append("Lucy: okay, closing now.\n\n")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.terminate(nil)
            }
            return
        }


        if lowered == "/ping" || lowered == "ping" {
            append("Lucy: pong\n\n")
            return
        }

        if lowered == "/memory"
            || lowered.contains("what do you remember")
            || lowered.contains("what do you know about me") {

            append("Lucy: \(LucyMemory.shared.memoryResponseText())\n\n")
            return
        }

        if lowered == "/status" {
            append("Lucy:\n\(LucyRuntime.shared.statusText())\n\n")
            return
        }

        if lowered == "/quiet" {
            LucyRuntime.shared.verboseLogging = false
            append("Lucy: Quiet mode on. I’ll stop spamming Terminal movement logs.\n\n")
            return
        }

        if lowered == "/loud" {
            LucyRuntime.shared.verboseLogging = true
            append("Lucy: Loud mode on. I’ll print movement logs to Terminal again.\n\n")
            return
        }

        if lowered == "/hide" || lowered.contains("hide lucy") || lowered.contains("go hide") {
            append("Lucy: okay, I’ll hide. Say `come back` when you want me back.\n\n")
            onSoftHideRequested?()
            return
        }

        if lowered == "/settings" {
            append("Lucy: Settings:\n")
            append("- Browser: \(preferredBrowser)\n")
            append("- Settings file: \(LucyPaths.settingsURL.path)\n\n")
            return
        }


        if lowered.hasPrefix("/browser ") {
            let browser = String(userText.dropFirst("/browser ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if browser.isEmpty {
                append("Lucy: Tell me the browser after /browser. Example: /browser Google Chrome\n\n")
                return
            }

            let result = setBrowserPreference(browser)
            append("Lucy: \(result)\n\n")
            return
        }


        if lowered.hasPrefix("/youtube ") {
            let query = String(userText.dropFirst("/youtube ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if query.isEmpty {
                append("Lucy: Tell me what to search on YouTube. Example: /youtube cute jumping spider\n\n")
                return
            }

            let result = openYouTubeSearch(query)
            append("Lucy: \(result)\n\n")
            return
        }


        if !userText.hasPrefix("/") && routeNaturalCommand(userText) {
            return
        }

        if lowered.hasPrefix("/openurl ") {
            let url = String(userText.dropFirst("/openurl ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if url.isEmpty {
                append("Lucy: Give me a URL after /openurl.\n\n")
                return
            }

            let result = openURL(url)
            append("Lucy: \(result)\n\n")
            return
        }

        if lowered.hasPrefix("/openapp ") {
            let appName = String(userText.dropFirst("/openapp ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if appName.isEmpty {
                append("Lucy: Tell me the app name after /openapp. Example: /openapp Safari\n\n")
                return
            }

            let result = openApp(appName)
            append("Lucy: \(result)\n\n")
            return
        }






        if lowered == "open gmail with this draft"
            || lowered == "open gmail with the draft"
            || lowered == "open gmail draft"
            || lowered == "put it in gmail"
            || lowered == "open this in gmail" {
            let result = openGmailWithLastDraft()
            append("Lucy: \(result)\n\n")
            return
        }

        if looksLikeEmailRevisionRequest(lowered) {
            append("Lucy: revising your latest email draft...\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.reviseLastEmailDraft(userText)

                DispatchQueue.main.async {
                    self.append("Lucy:\n\(result)\n\n")
                }
            }

            return
        }


        if lowered == "copy email draft"
            || lowered == "copy last email draft"
            || lowered == "copy the email draft" {
            let result = copyTextToClipboard(lastEmailDraft)
            append("Lucy: \(result)\n\n")
            return
        }

        if lowered == "open gmail"
            || lowered == "open google mail"
            || lowered == "open email" {
            let result = openGmail()
            append("Lucy: \(result)\n\n")
            return
        }

        if lowered.contains("write an email")
            || lowered.contains("write a email")
            || lowered.contains("write me email")
            || lowered.contains("write me an email")
            || lowered.contains("write me a email")
            || lowered.contains("draft an email")
            || lowered.contains("draft a email")
            || lowered.contains("draft me email")
            || lowered.contains("draft me an email")
            || lowered.contains("draft me a email")
            || lowered.hasPrefix("email ") {

            if firstEmailAddress(in: userText) != nil {
                append("Lucy: drafting the email and opening Gmail compose...\n")

                DispatchQueue.global(qos: .userInitiated).async {
                    let result = self.draftEmailForGmailCompose(userText)

                    DispatchQueue.main.async {
                        self.append("Lucy:\n\(result)\n\n")
                    }
                }

                return
            }

            append("Lucy: drafting an email for you...\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.draftEmailFromRequest(userText)

                DispatchQueue.main.async {
                    self.append("Lucy:\n\(result)\n\n")
                }
            }

            return
        }




        if !userText.hasPrefix("/")
            && (
                lowered.contains("notes app")
                || lowered.contains("apple notes")
                || lowered.contains("write a note")
                || lowered.contains("create a note")
            ) {

            append("Lucy: I will check whether I have Apple Notes writing capability.\n\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.ensureNotesCapabilityThenCreateNote(request: userText)

                DispatchQueue.main.async {
                    self.append("Lucy Capability Manager:\n\(result)\n\n")
                }
            }

            return
        }


        if !userText.hasPrefix("/"), let unsupported = unsupportedCapabilityResponse(for: userText) {
            append("Lucy:\n\(unsupported)\n\n")
            return
        }


        if !userText.hasPrefix("/") && routeAIIntent(userText) {
            return
        }

        let remembered = LucyMemory.shared.maybeRemember(userText)

        if remembered {
            append("Lucy: I saved that to memory.\n\n")
            return
        }


        if userText.hasPrefix("/") {
            let result = runSlashCommand(resolveSlashCommand(userText))
            append("Lucy:\n\(result)\n\n")
            return
        }

        append("Lucy: thinking...\n")

        let historySnapshot = conversationHistory
        let userTextSnapshot = userText

        DispatchQueue.global(qos: .userInitiated).async {
            let reply = LucyMLXIntentRouter.shared.chatSync(
                history: historySnapshot,
                userText: userTextSnapshot,
                timeout: 12.0
            ) ?? "Hmm, I had trouble thinking for a second."

            DispatchQueue.main.async {
                self.conversationHistory.append(LucyChatMessage(role: "Lucy", content: reply))
                self.append("Lucy: \(reply)\n\n")
            }
        }

        return
    }

    func append(_ text: String) {
        let baseFont = NSFont.systemFont(ofSize: 14.5, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        paragraphStyle.paragraphSpacing = 5

        var color = NSColor.labelColor
        var font = baseFont

        if text.hasPrefix("You:") {
            color = NSColor(calibratedRed: 0.26, green: 0.34, blue: 0.78, alpha: 1.0)
            font = NSFont.systemFont(ofSize: 14.5, weight: .semibold)
        } else if text.hasPrefix("Lucy") {
            color = NSColor(calibratedRed: 0.58, green: 0.22, blue: 0.62, alpha: 1.0)
            font = NSFont.systemFont(ofSize: 14.5, weight: .medium)
        }

        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        )

        output.textStorage?.append(attributed)
        output.scrollToEndOfDocument(nil)
    }

    func runMLX(prompt: String, purpose: String = "chat", maxTokens: Int = 512, timeout: TimeInterval = 120.0) -> String {
        let process = Process()
        let python = LucyPaths.localLLMPythonExecutable()
        let providerRelativePath = "tools/providers/local_llm.py"
        let providerURL = LucyPaths.root.appendingPathComponent(providerRelativePath)

        guard FileManager.default.fileExists(atPath: providerURL.path) else {
            return "I had trouble talking to my local model:\nCould not find \(providerRelativePath) under Lucy project root: \(LucyPaths.root.path)"
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            python,
            providerRelativePath,
            "--purpose",
            purpose,
            "--max-tokens",
            String(maxTokens),
            "--timeout",
            String(Int(timeout)),
            "--stdin"
        ]
        process.currentDirectoryURL = LucyPaths.root

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()

            if let data = prompt.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }

            inputPipe.fileHandleForWriting.closeFile()

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }

            if process.isRunning {
                process.terminate()
                return "I had trouble talking to my local model:\nTimed out after \(Int(timeout)) seconds."
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            if process.terminationStatus != 0 {
                let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown local model error."
                let fallbackOutput = String(data: data, encoding: .utf8) ?? ""
                return "I had trouble talking to my local model:\n\(errorText.isEmpty ? fallbackOutput : errorText)"
            }

            let rawText = String(data: data, encoding: .utf8) ?? "I did not get a response."
            return stripTerminalEscapes(rawText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "I could not start my local model. Error: \(error.localizedDescription)"
        }
    }



    func shellQuote(_ text: String) -> String {
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func runShell(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let out = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            let details = [out, err]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")

            if process.terminationStatus == 0 {
                if details.isEmpty {
                    return "Opened successfully.\nCommand: \(command)"
                }
                return "Opened successfully.\nCommand: \(command)\n\(details)"
            }

            return "Command failed.\nCommand: \(command)\n\(details)"
        } catch {
            return "Could not run command: \(error.localizedDescription)"
        }
    }

    func setBrowserPreference(_ browser: String) -> String {
        let cleaned = browser.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.lowercased() == "default" {
            preferredBrowser = "default"
            LucySettings.shared.saveBrowserPreference("default")
            return "Browser preference set to system default and saved."
        }

        preferredBrowser = cleaned
        LucySettings.shared.saveBrowserPreference(cleaned)
        return "Browser preference set to: \(preferredBrowser) and saved."
    }

    func browserCommandPrefix() -> String {
        if preferredBrowser.lowercased() == "default" {
            return "open"
        }

        return "open -a \(shellQuote(preferredBrowser))"
    }

    func activatePreferredBrowserCommand() -> String {
        if preferredBrowser.lowercased() == "default" {
            return ""
        }

        let escapedBrowser = preferredBrowser.replacingOccurrences(of: "\"", with: "\\\"")
        return "; osascript -e 'tell application \"\(escapedBrowser)\" to activate'"
    }

    func openURL(_ urlString: String) -> String {
        guard URL(string: urlString) != nil else {
            return "That URL does not look valid."
        }

        let command = "\(browserCommandPrefix()) \(shellQuote(urlString))\(activatePreferredBrowserCommand())"
        return runShell(command)
    }

    func openYouTubeSearch(_ query: String) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = "https://www.youtube.com/results?search_query=\(encoded)"
        return openURL(url)
    }

    func openApp(_ appName: String) -> String {
        return runShell("open -a \(shellQuote(appName)); osascript -e 'tell application \(shellQuote(appName)) to activate'")
    }

    func stripPolitePrefix(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let prefixes = [
            "lucy,",
            "lucy ",
            "hey lucy,",
            "hey lucy ",
            "can you ",
            "could you ",
            "please "
        ]

        var changed = true
        while changed {
            changed = false
            let lowered = cleaned.lowercased()

            for prefix in prefixes {
                if lowered.hasPrefix(prefix) {
                    cleaned = String(cleaned.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                    break
                }
            }
        }

        return cleaned
    }

    func normalizedLinkedInDraftIntent(_ text: String) -> String {
        return stripPolitePrefix(text)
            .lowercased()
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "!", with: " ")
            .replacingOccurrences(of: "?", with: " ")
            .replacingOccurrences(of: "linekdin", with: "linkedin")
            .replacingOccurrences(of: "linkdin", with: "linkedin")
            .replacingOccurrences(of: "linkedn", with: "linkedin")
            .replacingOccurrences(of: "alinkedin", with: "a linkedin")
            .replacingOccurrences(of: "wirte", with: "write")
            .replacingOccurrences(of: "wrtie", with: "write")
            .replacingOccurrences(of: "wriet", with: "write")
            .replacingOccurrences(of: "drfat", with: "draft")
            .replacingOccurrences(of: "drafr", with: "draft")
            .replacingOccurrences(of: "psot", with: "post")
            .replacingOccurrences(of: "pst", with: "post")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func looksLikeLinkedInPostDraftRequest(_ text: String) -> Bool {
        let normalized = normalizedLinkedInDraftIntent(text)
        if normalized.hasPrefix("/") {
            return false
        }

        let hasLinkedIn = normalized.contains("linkedin")
        let hasPost = normalized.contains("post")
        let hasDraftVerb = normalized.contains("write")
            || normalized.contains("draft")
            || normalized.contains("make")
            || normalized.contains("create")
            || normalized.contains("prepare")

        return hasLinkedIn && hasPost && hasDraftVerb
    }

    func routeLinkedInPostDraft(_ userText: String) -> Bool {
        guard looksLikeLinkedInPostDraftRequest(userText) else {
            return false
        }

        append("Lucy: drafting locally with Lucy’s local model provider now...\n")
        append("Lucy: researching LinkedIn with Browser Bridge, analyzing results, then drafting locally. I will print the draft here.\n\n")

        append("Lucy Progress\n[⟳] Research\n[ ] Analysis\n[ ] Writing\n[ ] Done\n\n")

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            self.append("Lucy Progress\n[✓] Research started\n[⟳] Reading LinkedIn page\n[ ] Analysis\n[ ] Writing\n[ ] Done\n\n")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.append("Lucy Progress\n[✓] Research\n[⟳] Extracting themes/signals\n[ ] Writing\n[ ] Done\n\n")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 24) {
            self.append("Lucy Progress\n[✓] Research\n[✓] Analysis\n[⟳] Writing synthesized draft\n[ ] Done\n\n")
        }

        try? FileManager.default.removeItem(atPath: "/tmp/lucy_linkedin_post.txt")
        try? FileManager.default.removeItem(atPath: "/tmp/lucy_linkedin_mlx_output.md")

        DispatchQueue.global(qos: .userInitiated).async {
            let escaped = userText.replacingOccurrences(of: "'", with: "'\\''")
            let python = LucyPaths.localLLMPythonExecutable()
            let command = "cd \(self.shellQuote(LucyPaths.root.path)) && PYTHONUNBUFFERED=1 \(self.shellQuote(python)) -u tools_created_by_lucy/lucy_linkedin_direct.py '\(escaped)'"
            self.runShellStreaming(command)

            DispatchQueue.main.async {
                let postURL = URL(fileURLWithPath: "/tmp/lucy_linkedin_post.txt")
                if let draft = try? String(contentsOf: postURL, encoding: .utf8),
                   !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Draft already printed by tool. No clipboard/copy step needed.
                } else {
                    self.append("Lucy: I could not find /tmp/lucy_linkedin_post.txt after drafting.\n\n")
                }
            }
        }

        return true
    }



    func extractJSONBlock(_ text: String) -> String? {
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}")
        else {
            return nil
        }

        return String(text[start...end])
    }

    func classifyIntent(_ userText: String) -> [String: Any]? {
        let prompt = """
        You are Lucy's intent router.

        Convert the user's message into exactly one JSON object.
        Do not answer the user.
        Do not include markdown.
        Do not include explanations.

        Allowed intents:
        - youtube_search
        - google_search
        - open_url
        - open_app
        - set_browser
        - gmail_compose
        - email_draft
        - hide
        - chat

        JSON schema:
        {
          "intent": "...",
          "query": "...",
          "url": "...",
          "app": "...",
          "browser": "...",
          "recipient": "...",
          "email_request": "...",
          "confidence": 0.0
        }

        Rules:
        - If the user asks to find/search/look up something generally, use google_search.
        - If the user asks for a video, YouTube, yt, clip, or watch, use youtube_search.
        - If the user asks to write/draft/email someone and includes an email address, use gmail_compose.
        - If the user asks to write/draft an email but no email address is included, use email_draft.
        - If the user asks to open a website/domain, use open_url.
        - If the user asks to open an app, use open_app.
        - If the user says use Chrome/Safari/default browser, use set_browser.
        - If the user asks Lucy to hide/disappear/go away, use hide.
        - If unsure, use chat.
        - Correct obvious typos mentally.
        - Keep query/email_request concise but preserve meaning.

        User message:
        \(userText)
        """

        let raw = runMLX(prompt: prompt)

        guard let jsonText = extractJSONBlock(raw),
              let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return json
    }

    func routeAIIntent(_ userText: String) -> Bool {
        guard let intent = classifyIntent(userText) else {
            return false
        }

        let name = (intent["intent"] as? String ?? "chat").lowercased()
        let confidence = intent["confidence"] as? Double ?? 0.0

        if confidence < 0.55 || name == "chat" {
            return false
        }

        switch name {
        case "youtube_search":
            let query = intent["query"] as? String ?? userText
            let result = openYouTubeSearch(query)
            append("Lucy: \(result)\n\n")
            return true

        case "google_search":
            let query = intent["query"] as? String ?? userText
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let result = openURL("https://www.google.com/search?q=\(encoded)")
            append("Lucy: \(result)\n\n")
            return true

        case "open_url":
            var url = intent["url"] as? String ?? ""
            if url.isEmpty {
                url = intent["query"] as? String ?? ""
            }

            if url.isEmpty {
                return false
            }

            if !url.lowercased().hasPrefix("http://") && !url.lowercased().hasPrefix("https://") {
                url = "https://\(url)"
            }

            let result = openURL(url)
            append("Lucy: \(result)\n\n")
            return true

        case "open_app":
            let app = intent["app"] as? String ?? intent["query"] as? String ?? ""
            if app.isEmpty { return false }

            let result = openApp(app)
            append("Lucy: \(result)\n\n")
            return true

        case "set_browser":
            let browser = intent["browser"] as? String ?? intent["query"] as? String ?? ""
            if browser.isEmpty { return false }

            let result = setBrowserPreference(browser)
            append("Lucy: \(result)\n\n")
            return true

        case "gmail_compose":
            let recipient = intent["recipient"] as? String ?? firstEmailAddress(in: userText) ?? ""
            let request = intent["email_request"] as? String ?? userText

            if recipient.isEmpty {
                let result = draftEmailFromRequest(userText)
                append("Lucy:\n\(result)\n\n")
                return true
            }

            let combinedRequest = "\(request) Recipient: \(recipient)"
            let result = draftEmailForGmailCompose(combinedRequest)
            append("Lucy:\n\(result)\n\n")
            return true

        case "email_draft":
            let request = intent["email_request"] as? String ?? userText
            let result = draftEmailFromRequest(request)
            append("Lucy:\n\(result)\n\n")
            return true

        case "hide":
            append("Lucy: okay, I’ll hide. Say `come back` when you want me back.\n\n")
            onSoftHideRequested?()
            return true
        default:
            return false
        }
    }



    func unsupportedCapabilityResponse(for userText: String) -> String? {
        let lowered = userText.lowercased()

        let mentionsNote = lowered.contains("note") || lowered.contains("notes")
        let destructive = lowered.contains("delete")
            || lowered.contains("remove")
            || lowered.contains("erase")
            || lowered.contains("destroy")
            || lowered.contains("clear")

        let wantsEdit = lowered.contains("edit")
            || lowered.contains("update")
            || lowered.contains("change")
            || lowered.contains("modify")
            || lowered.contains("rewrite")

        if mentionsNote && destructive {
            return """
            I understand you want me to delete a note.

            I can create new Apple Notes notes, but I do not have a safe Notes deletion capability yet.

            Deleting notes is risky because I could delete the wrong one. A safe Notes Manager should:
            1. list matching notes first
            2. show the exact title/date/content preview
            3. ask you to confirm the exact note
            4. delete only after confirmation

            I did not delete anything.

            This capability is not enabled yet.
            """
        }

        if mentionsNote && wantsEdit {
            return """
            I understand you want me to edit or update a note.

            I can create new Apple Notes notes, but I do not have a safe Notes editing capability yet.

            Editing notes is risky because I need to identify the exact note first. A safe Notes Manager should:
            1. list candidate notes
            2. ask which note you mean
            3. preview the change
            4. update only after confirmation

            I did not edit anything.

            This capability is not enabled yet.
            """
        }

        if lowered.contains("send") && (lowered.contains("email") || lowered.contains("gmail") || lowered.contains("mail")) {
            return """
            I understand you want me to send an email.

            I can draft emails and open Gmail compose with the recipient, subject, and body filled in.
            I will not click Send automatically yet.

            Sending messages is a high-impact action, so the current safe flow is:
            1. I draft the email.
            2. I open Gmail compose.
            3. You review it.
            4. You click Send manually.

            I did not send anything.
            """
        }

        if lowered.contains("delete") && (lowered.contains("file") || lowered.contains("folder") || lowered.contains("project")) {
            return """
            I understand you want me to delete a file or folder.

            I do not have a safe file deletion capability.
            I can work inside my own project with backups and rollback, but I should not delete arbitrary files.

            I did not delete anything.
            """
        }

        if lowered.contains("buy")
            || lowered.contains("purchase")
            || lowered.contains("order ")
            || lowered.contains("checkout")
            || lowered.contains("pay ") {
            return """
            I understand this may involve buying, ordering, paying, or checking out.

            I do not have a purchase/payment capability, and I should not make purchases automatically.

            I did not buy or pay for anything.
            """
        }

        if lowered.contains("password")
            || lowered.contains("login for me")
            || lowered.contains("sign in for me")
            || lowered.contains("2fa")
            || lowered.contains("verification code") {
            return """
            I understand this may involve credentials, login, passwords, or verification codes.

            I should not handle sensitive credentials directly.
            I can help explain steps, but you should enter passwords and verification codes yourself.

            I did not access or submit credentials.
            """
        }

        return nil
    }

    func routeNaturalCommand(_ userText: String) -> Bool {
        let cleaned = stripPolitePrefix(userText)
        let lowered = cleaned.lowercased()

        func removePhrases(_ input: String, _ phrases: [String]) -> String {
            var result = input

            for phrase in phrases {
                result = result.replacingOccurrences(of: phrase, with: "", options: [.caseInsensitive])
            }

            while result.contains("  ") {
                result = result.replacingOccurrences(of: "  ", with: " ")
            }

            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func googleSearch(_ query: String) -> Bool {
            let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

            if cleanedQuery.isEmpty {
                _ = openURL("https://www.google.com")
                append("Lucy: Opening Google for you.\n\n")
                return true
            }

            let encoded = cleanedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanedQuery
            _ = openURL("https://www.google.com/search?q=\(encoded)")
            append("Lucy: Searching Google for “\(cleanedQuery)”.\n\n")
            return true
        }

        func youtubeSearch(_ query: String) -> Bool {
            let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

            if cleanedQuery.isEmpty {
                _ = openURL("https://www.youtube.com")
                append("Lucy: Opening YouTube for you.\n\n")
                return true
            }

            _ = openYouTubeSearch(cleanedQuery)
            append("Lucy: Searching YouTube for “\(cleanedQuery)”.\n\n")
            return true
        }

        if lowered == "hide"
            || lowered == "hide for a bit"
            || lowered == "go hide"
            || lowered == "disappear"
            || lowered == "hide lucy" {
            append("Lucy: okay, I’ll hide. Say `come back` when you want me back.\n\n")
            onSoftHideRequested?()
            return true
        }

        if lowered == "open google"
            || lowered == "open google.com"
            || lowered == "go to google"
            || lowered == "open google in browser" {
            return googleSearch("")
        }

        if lowered == "open youtube"
            || lowered == "go to youtube" {
            return youtubeSearch("")
        }

        if lowered == "use chrome"
            || lowered == "use google chrome"
            || lowered == "switch to chrome"
            || lowered == "open things in chrome" {
            _ = setBrowserPreference("Google Chrome")
            append("Lucy: Okay — I’ll use Google Chrome for links.\n\n")
            return true
        }

        if lowered == "use safari"
            || lowered == "switch to safari"
            || lowered == "open things in safari" {
            _ = setBrowserPreference("Safari")
            append("Lucy: Okay — I’ll use Safari for links.\n\n")
            return true
        }

        if lowered == "use default browser"
            || lowered == "use system default browser" {
            _ = setBrowserPreference("default")
            append("Lucy: Okay — I’ll use your system default browser.\n\n")
            return true
        }

        if lowered.hasPrefix("search youtube for ")
            || lowered.hasPrefix("searfch youtube for ")
            || lowered.hasPrefix("serach youtube for ")
            || lowered.hasPrefix("youtube ") {

            let query = removePhrases(cleaned, [
                "search youtube for",
                "searfch youtube for",
                "serach youtube for",
                "youtube"
            ])

            return youtubeSearch(query)
        }

        if lowered.hasPrefix("find me ") && lowered.contains("youtube") {
            let query = removePhrases(cleaned, [
                "find me",
                "on youtube",
                "youtube"
            ])

            return youtubeSearch(query)
        }

        if lowered.hasPrefix("find me ") && lowered.contains("video") {
            let query = removePhrases(cleaned, [
                "find me",
                "a video",
                "video"
            ])

            return youtubeSearch(query)
        }

        let mentionsGoogle = lowered.contains("google")
            || lowered.contains("googel")
            || lowered.contains("gogle")
            || lowered.contains("googl")

        if mentionsGoogle && (lowered.hasPrefix("find ") || lowered.hasPrefix("search ")) {
            let query = removePhrases(cleaned, [
                "find",
                "search",
                "on google",
                "on googel",
                "on gogle",
                "on googl",
                "google",
                "googel",
                "gogle",
                "googl",
                "for"
            ])

            return googleSearch(query)
        }

        // Default behavior: find/search means Google search.
        if lowered.hasPrefix("find ") || lowered.hasPrefix("search ") {
            let query = removePhrases(cleaned, [
                "find",
                "search",
                "for"
            ])

            return googleSearch(query)
        }

        if lowered.hasPrefix("open ") && lowered.contains(".") {
            var url = String(cleaned.dropFirst("open ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !url.lowercased().hasPrefix("http://") && !url.lowercased().hasPrefix("https://") {
                url = "https://\(url)"
            }

            _ = openURL(url)
            append("Lucy: Opening \(url).\n\n")
            return true
        }

        return false
    }

    func resolveSlashCommand(_ rawCommand: String) -> String {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return trimmed }

        let command = String(first).lowercased()
        let rest = parts.count > 1 ? " " + String(parts[1]) : ""

        let known = [
            "/memory", "/status", "/tool", "/quit", "/settings",
            "/use3d", "/real3d", "/renderinfo", "/modelbounds",
            "/browser", "/youtube", "/openurl", "/openapp"
        ]

        if known.contains(command) {
            return command + rest
        }

        let ranked = known
            .map { ($0, levenshteinDistance(command, $0)) }
            .sorted { $0.1 < $1.1 }

        if let best = ranked.first, best.1 <= 2 {
            return best.0 + rest
        }

        let suggestions = ranked.prefix(3).map { $0.0 }.joined(separator: ", ")
        return "/__unknown__ \(command) \(suggestions)"
    }

    func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)

        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            previous = current
        }

        return previous[b.count]
    }

    func registryToolPairs() -> [String: (dryRun: String, approved: String)] {
        let root = lucyDetectedProjectRootPath()
        let registryURL = URL(fileURLWithPath: root)
            .appendingPathComponent("tools_created_by_lucy")
            .appendingPathComponent("tool_registry.json")

        guard let data = try? Data(contentsOf: registryURL) else {
            return [:]
        }

        guard let registry = try? JSONDecoder().decode(LucyToolRegistry.self, from: data) else {
            return [:]
        }

        var dryRuns: [String: String] = [:]
        var approved: [String: String] = [:]

        for tool in registry.tools {
            if tool.name.hasSuffix("_dry_run") {
                let base = String(tool.name.dropLast("_dry_run".count))
                dryRuns[base] = tool.name
            } else if tool.name.hasSuffix("_create_approved") {
                let base = String(tool.name.dropLast("_create_approved".count))
                approved[base] = tool.name
            }
        }

        var pairs: [String: (dryRun: String, approved: String)] = [:]
        for (base, dryName) in dryRuns {
            if let approvedName = approved[base] {
                pairs[base] = (dryRun: dryName, approved: approvedName)
            }
        }

        return pairs
    }

    func registryToolBaseForNaturalRequest(_ text: String) -> String? {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if lowered.hasPrefix("/") {
            return nil
        }

        let root = lucyDetectedProjectRootPath()
        let registryURL = URL(fileURLWithPath: root)
            .appendingPathComponent("tools_created_by_lucy")
            .appendingPathComponent("tool_registry.json")

        guard let data = try? Data(contentsOf: registryURL) else {
            return nil
        }

        guard let registry = try? JSONDecoder().decode(LucyToolRegistry.self, from: data) else {
            return nil
        }

        var bestBase: String?
        var bestPrefixLength = -1

        for tool in registry.tools {
            guard let base = tool.pair_base else {
                continue
            }

            guard registryToolPairs()[base] != nil else {
                continue
            }

            let prefixes = tool.intent_prefixes ?? []
            for rawPrefix in prefixes {
                let prefix = rawPrefix.lowercased()
                if lowered.hasPrefix(prefix) && prefix.count > bestPrefixLength {
                    bestBase = base
                    bestPrefixLength = prefix.count
                }
            }
        }

        return bestBase
    }

    func looksLikeGenericApproval(_ text: String) -> Bool {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let approvals = [
            "yes",
            "yes create it",
            "create it",
            "do it",
            "confirm",
            "approved",
            "yes please",
            "yes save it",
            "save it",
            "yes schedule it",
            "schedule it"
        ]
        return approvals.contains(lowered)
    }

    func looksLikeNoteRequest(_ text: String) -> Bool {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if lowered.hasPrefix("/") {
            return false
        }

        let starts = [
            "create a note ",
            "create note ",
            "make a note ",
            "make note ",
            "add a note ",
            "add note "
        ]

        return starts.contains(where: { lowered.hasPrefix($0) })
    }

    func looksLikeNoteApproval(_ text: String) -> Bool {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let approvals = [
            "yes",
            "yes create it",
            "create it",
            "do it",
            "confirm",
            "approved",
            "yes please",
            "yes save it",
            "save it"
        ]

        return approvals.contains(lowered)
    }

    func looksLikeCalendarRequest(_ text: String) -> Bool {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if lowered.hasPrefix("/") {
            return false
        }

        let starts = [
            "schedule ",
            "schedule a meeting ",
            "schedule meeting ",
            "create calendar event ",
            "add calendar event ",
            "add event ",
            "set up meeting "
        ]

        return starts.contains(where: { lowered.hasPrefix($0) })
    }

    func looksLikeCalendarApproval(_ text: String) -> Bool {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let approvals = [
            "yes",
            "yes create it",
            "create it",
            "do it",
            "confirm",
            "approved",
            "yes please",
            "yes schedule it",
            "schedule it"
        ]

        return approvals.contains(lowered)
    }

    func looksLikeReminderApproval(_ text: String) -> Bool {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let approvals = [
            "yes",
            "yes create it",
            "create it",
            "do it",
            "confirm",
            "approved",
            "yes please"
        ]

        return approvals.contains(lowered)
    }

    func looksLikeReminderRequest(_ text: String) -> Bool {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if lowered.hasPrefix("/") {
            return false
        }

        let reminderStarts = [
            "remind me ",
            "remind me to ",
            "reminder ",
            "set a reminder ",
            "set reminder "
        ]

        if reminderStarts.contains(where: { lowered.hasPrefix($0) }) {
            return true
        }

        // Conservative extra pattern: "tomorrow at 3pm call mom" should not trigger yet.
        // Keep this narrow until dry-run behavior is reliable.
        return false
    }

    func lucyDetectedProjectRootPath() -> String {
        return LucyPaths.root.path
    }

    func runSandboxToolCommand(_ rawCommand: String) -> String {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)

        guard pieces.count >= 2 else {
            return "Usage: /tool <tool_name> <request>\nExample: /tool reminders_dry_run remind me tomorrow at 3pm to call mom"
        }

        let toolName = String(pieces[1])
        let request = pieces.count >= 3 ? String(pieces[2]) : ""

        let allowedNamePattern = #"^[A-Za-z0-9_-]+$"#
        if toolName.range(of: allowedNamePattern, options: .regularExpression) == nil {
            return "Rejected tool name: \(toolName)\nTool names may only contain letters, numbers, underscores, and hyphens."
        }

        let root = lucyDetectedProjectRootPath()
        let registryPath = root + "/tools_created_by_lucy/tool_registry.json"
        let fm = FileManager.default

        guard fm.fileExists(atPath: registryPath) else {
            return "Tool registry not found: \(registryPath)"
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: registryPath))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let tools = json?["tools"] as? [[String: Any]] ?? []

            guard let tool = tools.first(where: { ($0["name"] as? String) == toolName }) else {
                let names = tools.compactMap { $0["name"] as? String }.joined(separator: ", ")
                return "Unknown sandbox tool: \(toolName)\nAvailable tools: \(names.isEmpty ? "(none)" : names)"
            }

            guard let relativePath = tool["path"] as? String else {
                return "Tool \(toolName) has no path in tool_registry.json."
            }

            guard relativePath.hasPrefix("tools_created_by_lucy/") else {
                return "Rejected tool path outside sandbox: \(relativePath)"
            }

            let toolPath = root + "/" + relativePath
            guard fm.fileExists(atPath: toolPath) else {
                return "Tool file not found: \(toolPath)"
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.currentDirectoryURL = URL(fileURLWithPath: root)
            process.arguments = [toolPath, request]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                return """
                Sandbox tool failed: \(toolName)
                Exit code: \(process.terminationStatus)

                stderr:
                \(error)

                stdout:
                \(output)
                """
            }

            return """
            Sandbox tool: \(toolName)
            Tool result:
            \(output)
            """

        } catch {
            return "Failed to run sandbox tool \(toolName): \(error)"
        }
    }

    func runSlashCommand(_ command: String) -> String {
        if command.hasPrefix("/__unknown__ ") {
            let pieces = command.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            let unknown = pieces.count > 1 ? String(pieces[1]) : command
            let suggestions = pieces.count > 2 ? String(pieces[2]) : "/status, /settings, /youtube"

            if unknown == "/copydraft" {
                let postURL = URL(fileURLWithPath: "/tmp/lucy_linkedin_post.txt")
                if let draft = try? String(contentsOf: postURL, encoding: .utf8),
                   !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(draft, forType: .string)
                    return "Saved LinkedIn draft preview:\n\n\(draft)"
                } else {
                    return "I could not find a saved draft at /tmp/lucy_linkedin_post.txt."
                }
            }

            return "Unknown command: \(unknown)\nTry one of: \(suggestions)."
        }

        switch command {
        case "/status":
            return LucyRuntime.shared.statusText()

        case "/settings":
            return "Settings:\n- Browser: \(preferredBrowser)\n- Settings file: \(LucyPaths.settingsURL.path)"

        default:
            return "Unknown or disabled command: \(command)"
        }
    }

    func capabilitiesSummary() -> String {
        let url = LucyPaths.root.appendingPathComponent("data").appendingPathComponent("capabilities.json")

        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let capabilities = json["capabilities"] as? [[String: Any]]
        else {
            return """
            I could not read my capability registry.

            Installed abilities I know I have:
            - chat
            - memory
            - Google search / open URLs
            - YouTube search
            - Gmail draft compose
            - Apple Notes creation
            """
        }

        var installed: [String] = []
        var available: [String] = []
        var unknown: [String] = []

        for capability in capabilities {
            let id = capability["id"] as? String ?? "unknown"
            let status = capability["status"] as? String ?? "unknown"
            let description = capability["description"] as? String ?? ""

            let line = "- \(id): \(description)"

            if status == "installed" {
                installed.append(line)
            } else if status == "available_template" {
                available.append(line)
            } else {
                unknown.append(line)
            }
        }
        return """
        My capability registry:

        Installed:
        \(installed.isEmpty ? "- none listed" : installed.joined(separator: "\n"))

        Unknown/other:
        \(unknown.isEmpty ? "- none listed" : unknown.joined(separator: "\n"))
        """
    }

    func limitationsSummary() -> String {
        return """
        Current limitations:

        Things I can do:
        - Search Google and YouTube.
        - Open websites and apps.
        - Draft emails and open Gmail compose for you to review.
        - Copy the latest email draft.
        - Create new Apple Notes notes when the Notes helper is available.
        - Preview approved Notes, Calendar, and Reminder actions through the tool registry.

        Things I should NOT do yet:
        - Send emails automatically.
        - Delete notes automatically.
        - Delete files automatically.
        - Click destructive buttons.
        - Make purchases.
        - Run arbitrary Terminal commands.
        - Modify my own code at runtime.

        If you ask for something I cannot safely do, I should tell you clearly instead of pretending I did it.
        """
    }

    func selfIdentitySummary() -> String {
        return """
        I am Lucy.

        I am a local-first Mac desktop companion.
        I live in this project:
        \(LucyPaths.root.path)

        My current architecture:
        - Swift/AppKit floating desktop pet
        - local model-provider chat
        - local memory
        - capability registry
        - explicit local tools for search, browser/app opening, Gmail drafts, Notes, Calendar, and Reminders

        My goal is to be a cute, practical desktop companion that helps with safe user-approved tasks.
        """
    }

    func capabilityStatus(_ id: String) -> String {
        guard
            let data = try? Data(contentsOf: LucyPaths.root.appendingPathComponent("data").appendingPathComponent("capabilities.json")),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let capabilities = json["capabilities"] as? [[String: Any]]
        else {
            return "unknown"
        }

        return capabilities.first(where: { $0["id"] as? String == id })?["status"] as? String ?? "unknown"
    }

    func updateCapabilityStatus(id: String, status: String) {
        let url = LucyPaths.root.appendingPathComponent("data").appendingPathComponent("capabilities.json")

        guard
            let data = try? Data(contentsOf: url),
            var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            var capabilities = json["capabilities"] as? [[String: Any]]
        else {
            return
        }

        for index in capabilities.indices {
            if capabilities[index]["id"] as? String == id {
                capabilities[index]["status"] = status
            }
        }

        json["capabilities"] = capabilities

        if let updated = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? updated.write(to: url)
        }
    }

    func ensureNotesCapabilityThenCreateNote(request: String) -> String {
        let status = capabilityStatus("apple_notes_writer")

        if status == "installed" {
            return createMotivationalNote(from: request)
        }

        return "Apple Notes writing is not enabled in the capability registry. I did not try to modify my own code."
    }

    func escapeAppleScriptString(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    func writeAppleNote(title: String, body: String) -> String {
        let safeTitle = escapeAppleScriptString(title)
        let safeBody = escapeAppleScriptString(body)

        let script = """
        tell application "Notes"
            activate
            make new note with properties {name:"\(safeTitle)", body:"\(safeBody)"}
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let out = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                return "Created a new Apple Notes note titled: \(title)"
            }

            let details = [out, err]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")

            return """
            I tried to create the note, but macOS blocked or failed the AppleScript.

            Details:
            \(details)

            You may need to allow Terminal/Lucy automation permissions in:
            System Settings → Privacy & Security → Automation
            """
        } catch {
            return "Could not run Apple Notes automation: \(error.localizedDescription)"
        }
    }

    func createMotivationalNote(from request: String) -> String {
        let prompt = """
        You are Lucy, a kind local AI desktop pet.

        The user wants a motivational note in Apple Notes.

        User request:
        \(request)

        Write a short motivational note.
        Requirements:
        - 2 to 5 sentences
        - warm, encouraging, and personal
        - no clichés if possible
        - output only the note body
        """

        let noteBody = stripTerminalEscapes(runMLX(prompt: prompt))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let finalBody = noteBody.isEmpty
            ? "You are building something real. Keep going, one small step at a time."
            : noteBody

        return writeAppleNote(title: "Motivation from Lucy", body: finalBody)
    }

    var lastEmailDraft: String {
        get {
            return UserDefaults.standard.string(forKey: "lucy.lastEmailDraft") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lucy.lastEmailDraft")
        }
    }


    func stripTerminalEscapes(_ text: String) -> String {
        var output: [Character] = []
        var cursor = 0
        let chars = Array(text)
        var i = 0

        func clampCursor() {
            if cursor < 0 { cursor = 0 }
            if cursor > output.count { cursor = output.count }
        }

        while i < chars.count {
            let ch = chars[i]

            // ESC sequences from terminal-style model output.
            if ch == "\u{001B}" {
                i += 1

                if i < chars.count && chars[i] == "[" {
                    i += 1
                    var numberText = ""
                    var finalChar: Character = "\0"

                    while i < chars.count {
                        let c = chars[i]

                        if c.isNumber {
                            numberText.append(c)
                            i += 1
                            continue
                        }

                        if c == ";" || c == "?" || c == " " {
                            i += 1
                            continue
                        }

                        finalChar = c
                        i += 1
                        break
                    }

                    let n = Int(numberText) ?? 1

                    switch finalChar {
                    case "D":
                        // Cursor left.
                        cursor -= n
                        clampCursor()

                    case "C":
                        // Cursor right.
                        cursor += n
                        clampCursor()

                    case "K":
                        // Clear from cursor to end of line.
                        if cursor < output.count {
                            output.removeSubrange(cursor..<output.count)
                        }

                    case "A", "B", "H", "J", "m":
                        // Ignore other common terminal controls.
                        break

                    default:
                        break
                    }

                    continue
                }

                // Skip unknown ESC sequence.
                continue
            }

            // Backspace.
            if ch == "\u{0008}" {
                if cursor > 0 {
                    cursor -= 1
                    output.remove(at: cursor)
                }
                i += 1
                continue
            }

            // Ignore other non-newline control characters.
            if let scalar = String(ch).unicodeScalars.first {
                let value = scalar.value
                if (value < 32 && ch != "\n" && ch != "\t") || value == 127 {
                    i += 1
                    continue
                }
            }

            // Normal character, respecting cursor overwrite behavior.
            if cursor < output.count {
                output[cursor] = ch
            } else {
                output.append(ch)
            }

            cursor += 1
            i += 1
        }

        var cleaned = String(output)

        // Cleanup common duplicated fragments left by terminal redraws.
        cleaned = cleaned.replacingOccurrences(
            of: #"\b([A-Za-z]{2,})\1\b"#,
            with: "$1",
            options: .regularExpression
        )

        return cleaned
    }


    func saveLastEmailDraft(_ draft: String) {
        lastEmailDraft = draft
    }

    func copyTextToClipboard(_ text: String) -> String {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "There is no saved email draft to copy yet."
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        return "Copied the latest email draft to clipboard."
    }

    func openGmail() -> String {
        return openURL("https://mail.google.com/mail/u/0/#inbox")
    }

    func firstEmailAddress(in text: String) -> String? {
        let pattern = #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text)
        else {
            return nil
        }

        return String(text[swiftRange])
    }

    func removeEmailAddress(from text: String) -> String {
        guard let email = firstEmailAddress(in: text) else {
            return text
        }

        return text.replacingOccurrences(of: email, with: "")
            .replacingOccurrences(of: "()", with: "")
            .replacingOccurrences(of: "( )", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parseEmailDraft(_ draft: String) -> (subject: String, body: String) {
        let lines = draft.components(separatedBy: .newlines)

        var subject = "Draft email"
        var bodyLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.lowercased().hasPrefix("subject:") {
                let parsed = String(trimmed.dropFirst("subject:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !parsed.isEmpty {
                    subject = parsed
                }
            } else {
                bodyLines.append(line)
            }
        }

        var body = bodyLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if body.isEmpty {
            body = draft
        }

        return (subject, body)
    }

    func gmailComposeURL(to recipient: String, subject: String, body: String) -> String {
        let encodedTo = recipient.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? recipient
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body

        return "https://mail.google.com/mail/?view=cm&fs=1&to=\(encodedTo)&su=\(encodedSubject)&body=\(encodedBody)"
    }

    func isLocalModelFailure(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("i had trouble talking to my local model")
            || lowered.contains("i could not start my local model")
            || lowered.contains("could not find tools/providers/local_llm.py")
            || lowered.contains("can't open file")
    }

    func fallbackEmailParts(for request: String, recipient: String? = nil) -> (subject: String, body: String) {
        let cleanedRequest = request
            .replacingOccurrences(of: "Recipient:", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let greeting = recipient?.isEmpty == false ? "Hello," : "Dear [Recipient],"
        let topic = cleanedRequest.isEmpty ? "your request" : cleanedRequest
        let subject = "Following up"
        let body = """
        \(greeting)

        I wanted to follow up regarding \(topic). Please let me know what works best for you.

        Best,
        Mo
        """

        return (subject, body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func draftEmailForGmailCompose(_ request: String) -> String {
        guard let recipient = firstEmailAddress(in: request) else {
            return draftEmailFromRequest(request)
        }

        let cleanedRequest = removeEmailAddress(from: request)

        let prompt = """
        You are Lucy, a helpful local AI desktop pet.

        Draft an email based on this request:
        \(cleanedRequest)

        Recipient email:
        \(recipient)

        Requirements:
        - Include a clear subject line.
        - Keep it polished, natural, and concise.
        - Do not invent specific facts.
        - Do not say you sent the email.
        - The sender is Mo.
        - Sign the email as Mo.

        Output format exactly:
        Subject: ...

        Dear ...,

        ...

        Best,
        Mo
        """

        let draft = runMLX(prompt: prompt)
        let cleanDraft = stripTerminalEscapes(draft)
        let usedFallbackDraft = isLocalModelFailure(cleanDraft)
        var parsed = parseEmailDraft(cleanDraft)

        if usedFallbackDraft {
            parsed = fallbackEmailParts(for: cleanedRequest, recipient: recipient)
        }

        let cleanSubject = stripTerminalEscapes(parsed.subject)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let cleanBody = stripTerminalEscapes(parsed.body)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fullDraft = """
        To: \(recipient)
        Subject: \(cleanSubject)

        \(cleanBody)
        """

        saveLastEmailDraft(fullDraft)

        let composeURL = gmailComposeURL(
            to: recipient,
            subject: cleanSubject,
            body: cleanBody
        )

        let openResult = openURL(composeURL)

        let fallbackNote = usedFallbackDraft
            ? "\nNote: I could not reach the local model, so I used a safe editable template instead of putting the model error into the email body.\n"
            : ""

        return """
        I drafted the email and opened Gmail compose.
        \(fallbackNote)
        \(fullDraft)

        \(openResult)

        I have not sent anything. Please review it and click Send yourself if it looks good.
        """
    }


    func draftEmailFromRequest(_ request: String) -> String {
        var cleaned = request.trimmingCharacters(in: .whitespacesAndNewlines)

        let removablePhrases = [
            "write an email for me",
            "write an email",
            "draft an email for me",
            "draft an email",
            "email for me"
        ]

        for phrase in removablePhrases {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: "", options: [.caseInsensitive])
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            return """
            I can draft it. Tell me:
            - who it is for
            - what you want to say
            - the tone, like polite, casual, professional, or short
            """
        }

        let prompt = """
        You are Lucy, a helpful local AI desktop pet.

        Draft an email based on this request:
        \(request)

        Requirements:
        - Include a clear subject line.
        - Keep it polished and natural.
        - Do not invent specific facts.
        - If recipient/name/details are missing, write a useful draft with placeholders.
        - Do not send the email. Only draft it.

        Output format:
        Subject: ...

        Dear ...,

        ...

        Best,
        Mo
        """

        let draft = runMLX(prompt: prompt)
        let cleanDraft = stripTerminalEscapes(draft)
        let usedFallbackDraft = isLocalModelFailure(cleanDraft)
        let finalDraft: String

        if usedFallbackDraft {
            let fallback = fallbackEmailParts(for: request)
            finalDraft = """
            Subject: \(fallback.subject)

            \(fallback.body)
            """
            .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            finalDraft = cleanDraft
        }

        saveLastEmailDraft(finalDraft)

        let fallbackNote = usedFallbackDraft
            ? "\nNote: I could not reach the local model, so I used a safe editable template instead of putting the model error into the email body.\n"
            : ""

        return """
        Here is a draft:
        \(fallbackNote)
        \(finalDraft)

        I saved this as your latest email draft.
        I have not sent anything.

        You can now say:
        - copy email draft
        - open gmail
        - make it shorter
        - make it more professional
        - make it warmer
        - open gmail with this draft
        """
    }



    func reviseLastEmailDraft(_ instruction: String) -> String {
        let currentDraft = lastEmailDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if currentDraft.isEmpty {
            return "I do not have a saved email draft to revise yet. Ask me to write an email first."
        }

        let prompt = """
        You are Lucy, a helpful local AI desktop pet.

        Revise this email draft according to the user's instruction.

        User instruction:
        \(instruction)

        Current draft:
        \(currentDraft)

        Requirements:
        - Preserve the original intent.
        - Do not invent specific facts.
        - Keep the sender as Mo.
        - Sign as Mo.
        - Output only the revised email.
        - Include the subject if the current draft includes one.
        """

        let revised = stripTerminalEscapes(runMLX(prompt: prompt))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        saveLastEmailDraft(revised)

        return """
        I revised the email draft:

        \(revised)

        I saved this as your latest email draft.
        You can say:
        - copy email draft
        - open gmail with this draft
        """
    }

    func openGmailWithLastDraft() -> String {
        let draft = lastEmailDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if draft.isEmpty {
            return "I do not have a saved email draft to open in Gmail yet."
        }

        let recipient = firstEmailAddress(in: draft) ?? ""
        let parsed = parseEmailDraft(draft)

        let cleanSubject = stripTerminalEscapes(parsed.subject)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let cleanBody = stripTerminalEscapes(parsed.body)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if recipient.isEmpty {
            let result = openGmail()
            return """
            I opened Gmail, but I could not find a recipient email address in the saved draft.

            I also copied the draft to your clipboard so you can paste it manually.

            \(copyTextToClipboard(draft))

            \(result)
            """
        }

        let composeURL = gmailComposeURL(
            to: recipient,
            subject: cleanSubject,
            body: cleanBody
        )

        return openURL(composeURL)
    }

    func looksLikeEmailRevisionRequest(_ lowered: String) -> Bool {
        let phrases = [
            "make it shorter",
            "make it longer",
            "make it warmer",
            "make it colder",
            "make it friendlier",
            "make it more professional",
            "make it less formal",
            "make it more formal",
            "make it casual",
            "make it concise",
            "make it polite",
            "make it sound better",
            "rewrite it",
            "revise it",
            "edit it",
            "improve it",
            "shorter",
            "more professional",
            "warmer",
            "less formal"
        ]

        return phrases.contains { lowered.contains($0) }
    }


    func askMLX(_ userText: String) -> String {
        let memoryText = LucyMemory.shared.memoryPromptText()

        let prompt = """
        You are Lucy, a tiny local AI desktop pet on the user's MacBook.

        Personality:
        - cute, curious, friendly
        - like a helpful jumping spider companion
        - practical and honest
        - concise

        Rules:
        - You are 100 percent local-first.
        - Do not use or suggest paid APIs for core functions.
        - Do not claim you opened apps or changed files unless a tool exists.
        - Use saved memory when it is relevant.

        Saved memory:
        \(memoryText)

        User: \(userText)

        Lucy:
        """

        return runMLX(prompt: prompt)
    }
    private func runShellStreaming(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.count > 0, let chunk = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.append(chunk)
                }
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
        } catch {
            DispatchQueue.main.async {
                self.append("Lucy: Streaming shell failed: \(error.localizedDescription)\n")
            }
        }
    }


}
