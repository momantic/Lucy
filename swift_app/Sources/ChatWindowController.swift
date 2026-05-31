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


class ChatWindowController: NSObject, NSTextFieldDelegate {

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

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))

        let scroll = NSScrollView(frame: NSRect(x: 15, y: 70, width: 590, height: 375))
        scroll.hasVerticalScroller = true

        output = NSTextView(frame: NSRect(x: 0, y: 0, width: 590, height: 375))
        output.isEditable = false
        output.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        output.string = """
        Lucy: Hi, I’m Lucy. Dev Mode v0.5 is active. Click Listen to speak with me.

        You can use flexible wording. I will try to understand typos and different phrasings:\n        \n        Examples:
        - open google
        - find cute jumping spider pictures
        - search best mac desktop pet examples
        - search youtube for lucas the spider
        - find me a jumping spider video
        - open wikipedia.org
        - use chrome
        - use safari
        - hide for a bit
        - write an email to Professor Smith asking about research opportunities
        - write an email to johndoe@gmail.com asking to schedule a meeting

        Useful commands:
        /memory
        /project
        /readself
        /status
        /settings
        /browser Google Chrome
        /browser Safari
        /youtube search terms
        /openurl https://example.com
        /openapp Safari
        /devstatus
        /dev animation-smoother
        /dev cute-eyes
        /dev better-crawl
        /dev cursor-aware
        /dev natural-commands
        /autodev roadmap
        /autodev next
        /build your goal here
        /develop your goal here

        """


        scroll.documentView = output

        input = NSTextField(frame: NSRect(x: 15, y: 20, width: 390, height: 30))
        input.placeholderString = "Message Lucy..."
        input.delegate = self

        let listenButton = NSButton(frame: NSRect(x: 415, y: 20, width: 90, height: 30))
        listenButton.title = "Listen"
        listenButton.target = self
        listenButton.action = #selector(startDictation)

        let sendButton = NSButton(frame: NSRect(x: 515, y: 20, width: 90, height: 30))
        sendButton.title = "Send"
        sendButton.target = self
        sendButton.action = #selector(sendMessage)

        root.addSubview(scroll)
        root.addSubview(input)
        root.addSubview(listenButton)
        root.addSubview(sendButton)

        window.contentView = root
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        append("Lucy: Stopped listening. Press Enter or Send when ready.\n\n")
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

        let userText = rawText

        input.stringValue = ""
        append("You: \(userText)\n")

        let lowered = userText.lowercased()


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



        if lowered == "/reflect" || lowered == "reflect" {
            append("Lucy:\n\(lucyReflection())\n\n")
            return
        }

        if lowered == "/goals" || lowered == "what are your goals" || lowered == "what are your goals?" {
            append("Lucy:\n\(lucyGoalsSummary())\n\n")
            return
        }

        if lowered == "/plan" || lowered == "what should you do next" || lowered == "what should you do next?" {
            append("Lucy:\n\(lucyNextPlan())\n\n")
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

        if lowered == "/project" {
            append("Lucy:\n\(LucyDevTools.shared.projectSummary())\n\n")
            return
        }

        if lowered == "/readself" {
            append("Lucy:\n\(LucyDevTools.shared.readSwiftPreview())\n\n")
            return
        }



        if lowered == "/dev animation-smoother" {
            append("Lucy: asking my local dev agent to smooth my animation...\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runDevAgentApply(task: "animation-smoother")

                DispatchQueue.main.async {
                    self.append("Lucy Dev Agent:\n\(result)\n\n")
                }
            }

            return
        }








        if lowered.hasPrefix("/selfbuild ") {
            let goal = String(userText.dropFirst("/selfbuild ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if goal.isEmpty {
                append("Lucy: Tell me what to selfbuild. Example: /selfbuild add email helper\n\n")
                return
            }

            append("Lucy: I’ll try to selfbuild this safely:\n\(goal)\n\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runSelfBuild(goal: goal)

                DispatchQueue.main.async {
                    self.append("Lucy Selfbuild:\n\(result)\n\n")
                }
            }

            return
        }


        if lowered == "/autopilot once" {
            append("Lucy: starting one autopilot tick.\n\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runAutopilot(iterations: 1)

                DispatchQueue.main.async {
                    self.append("Lucy Autopilot:\n\(result)\n\n")
                }
            }

            return
        }

        if lowered.hasPrefix("/autopilot ") {
            let rawCount = String(userText.dropFirst("/autopilot ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let count = Int(rawCount) ?? 1

            append("Lucy: starting autopilot for \(max(1, min(count, 5))) tick(s).\n\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runAutopilot(iterations: count)

                DispatchQueue.main.async {
                    self.append("Lucy Autopilot:\n\(result)\n\n")
                }
            }

            return
        }


        if lowered == "/self" || lowered == "/think" {
            append("Lucy: thinking about what safe command I should give myself...\n\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runSelfLoop()

                DispatchQueue.main.async {
                    self.append("Lucy Self Loop:\n\(result)\n\n")
                }
            }

            return
        }



        if lowered.hasPrefix("/develop ") {
            let goal = String(userText.dropFirst("/develop ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if goal.isEmpty {
                append("Lucy: Tell me what to develop. Example: /develop add a safer notes manager\n\n")
                return
            }

            append("Lucy: I will try to develop this capability myself:\n\(goal)\n\n")
            append("Lucy: I will generate a dev task, run it, compile myself, and report back.\n\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runLucyDeveloper(goal: goal)

                DispatchQueue.main.async {
                    self.append("Lucy Developer:\n\(result)\n\n")
                }
            }

            return
        }


        if lowered.hasPrefix("/build ") {
            let goal = String(userText.dropFirst("/build ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if goal.isEmpty {
                append("Lucy: Tell me what to build after /build.\n\n")
                return
            }

            append("Lucy: I’ll try to update my own code for this goal:\n\(goal)\n\n")
            append("Lucy: I will only edit my project files, compile after the change, and roll back if it breaks.\n\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runBuilderGoal(goal)

                DispatchQueue.main.async {
                    self.append("Lucy Builder:\n\(result)\n\n")
                }
            }

            return
        }


        if lowered == "/autodev next" {
            append("Lucy: running my next local autodev task.\n\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runAutoDevNext()

                DispatchQueue.main.async {
                    self.append("Lucy Autodev:\n\(result)\n\n")
                }
            }

            return
        }


        if lowered == "/autodev roadmap" {
            append("Lucy: starting my local autodev roadmap. I’ll stop if a task fails.\n\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runAutoDevRoadmap()

                DispatchQueue.main.async {
                    self.append("Lucy Autodev:\n\(result)\n\n")
                }
            }

            return
        }


        if lowered == "/devstatus" {
            append("Lucy: running local dev agent status check...\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runDevAgentStatus()

                DispatchQueue.main.async {
                    self.append("Lucy Dev Agent:\n\(result)\n\n")
                }
            }

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
            append("Lucy: okay, I’ll hide for 5 seconds.\n\n")
            onHideRequested?()
            return
        }


        if lowered == "/apply clean-memory" {
            append("Lucy: applying safe built-in update: clean-memory...\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = LucyDevTools.shared.cleanMemoryFile()

                DispatchQueue.main.async {
                    self.append("Lucy:\n\(result)\n\n")
                }
            }

            return
        }

        if lowered == "/apply hide-command" {
            append("Lucy: applying safe built-in update: hide-command...\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = LucyDevTools.shared.applyHideCommandUpdate()

                DispatchQueue.main.async {
                    self.append("Lucy:\n\(result)\n\n")
                }
            }

            return
        }



        if lowered == "/patches" {
            append("Lucy:\n\(LucyDevTools.shared.listPatchPlans())\n\n")
            return
        }

        if lowered.hasPrefix("/readpatch ") {
            let name = String(userText.dropFirst("/readpatch ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if name.isEmpty {
                append("Lucy: Tell me which patch to read. Example: /readpatch latest\n\n")
                return
            }

            append("Lucy:\n\(LucyDevTools.shared.readPatchPlan(name: name))\n\n")
            return
        }

        if lowered.hasPrefix("/patch ") {
            let patchName = String(userText.dropFirst("/patch ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if patchName.isEmpty {
                append("Lucy: Tell me the patch name after /patch.\n\n")
                return
            }

            let result = LucyDevTools.shared.createPatchPlan(name: patchName)
            append("Lucy:\n\(result)\n\n")
            return
        }

        if lowered.hasPrefix("/selfupdate ") {
            let request = String(userText.dropFirst("/selfupdate ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if request.isEmpty {
                append("Lucy: Tell me what self-update you want after /selfupdate.\n\n")
                return
            }

            append("Lucy: drafting a self-update proposal...\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let proposal = self.askOllamaForSelfUpdate(request)
                let saved = LucyDevTools.shared.createSelfUpdateProposal(
                    request: request,
                    ollamaAnswer: proposal
                )

                DispatchQueue.main.async {
                    self.append("Lucy:\n\(proposal)\n\n\(saved)\n\n")
                }
            }

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

        if !userText.hasPrefix("/") && routeNaturalSelfBuild(userText) {
            return
        }

        if !userText.hasPrefix("/") && routeNaturalCommand(userText) {
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

        append("Lucy: thinking...\n")

        DispatchQueue.global(qos: .userInitiated).async {
            let answer = self.askOllama(userText)

            DispatchQueue.main.async {
                self.append("Lucy: \(answer)\n\n")
            }
        }
    }

    func append(_ text: String) {
        output.string += text
        output.scrollToEndOfDocument(nil)
    }

    func ollamaPathAndArgs() -> (String, [String]) {
        let possiblePaths = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama"
        ]

        if let ollamaPath = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return (ollamaPath, ["run", model])
        }

        return ("/usr/bin/env", ["ollama", "run", model])
    }

    func runOllama(prompt: String) -> String {
        let process = Process()
        let (path, args) = ollamaPathAndArgs()

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

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
            process.waitUntilExit()

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            if process.terminationStatus != 0 {
                let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown Ollama error."
                return "I had trouble talking to Ollama:\n\(errorText)"
            }

            let rawText = String(data: data, encoding: .utf8) ?? "I did not get a response."
            return stripTerminalEscapes(rawText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "I could not start Ollama. Error: \(error.localizedDescription)"
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
        - selfbuild
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
        - If the user asks Lucy to add/build/teach/give herself a capability, use selfbuild.
        - If unsure, use chat.
        - Correct obvious typos mentally.
        - Keep query/email_request concise but preserve meaning.

        User message:
        \(userText)
        """

        let raw = runOllama(prompt: prompt)

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
            append("Lucy: okay, I’ll hide for 5 seconds.\n\n")
            onHideRequested?()
            return true

        case "selfbuild":
            let goal = intent["query"] as? String ?? userText
            append("Lucy: I understand this as a selfbuild request.\n\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runSelfBuild(goal: goal)

                DispatchQueue.main.async {
                    self.append("Lucy Selfbuild:\n\(result)\n\n")
                }
            }

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

            Possible future selfbuild:
            /selfbuild add notes manager
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

            Possible future selfbuild:
            /selfbuild add notes manager
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


    func routeNaturalSelfBuild(_ userText: String) -> Bool {
        let cleaned = stripPolitePrefix(userText)
        let lowered = cleaned.lowercased()

        let asksToBuild = lowered.contains("build")
            || lowered.contains("add")
            || lowered.contains("give yourself")
            || lowered.contains("make yourself")
            || lowered.contains("teach yourself")
            || lowered.contains("selfbuild")
            || lowered.contains("upgrade yourself")

        if !asksToBuild {
            return false
        }

        if lowered.contains("email") || lowered.contains("draft") {
            append("Lucy: I understand this as a selfbuild request for email drafting.\n\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runSelfBuild(goal: "add email helper")

                DispatchQueue.main.async {
                    self.append("Lucy Selfbuild:\n\(result)\n\n")
                }
            }

            return true
        }

        if lowered.contains("gmail") {
            if lowered.contains("draft") || lowered.contains("helper") || lowered.contains("add") || lowered.contains("build") || lowered.contains("give yourself") {
                append("Lucy: I understand this as a selfbuild request for a safe Gmail draft helper.\n\n")

                DispatchQueue.global(qos: .userInitiated).async {
                    let result = self.runSelfBuild(goal: "add gmail draft helper")

                    DispatchQueue.main.async {
                        self.append("Lucy Selfbuild:\n\(result)\n\n")
                    }
                }

                return true
            }

            append("""
            Lucy: I understand you want Gmail control.

            I can build/use a safe Gmail draft helper, but I will not send emails automatically.
            Safe flow:
            - draft email text
            - copy draft to clipboard
            - open Gmail
            - you review and send manually

            Try:
            give yourself Gmail draft helper

            I did not edit my code.

            """)
            return true
        }

        if lowered.contains("animation")
            || lowered.contains("crawl")
            || lowered.contains("jump")
            || lowered.contains("spider") {
            append("Lucy: I can improve animation through my existing dev/autodev tasks. Try /autodev roadmap or /dev better-crawl.\n\n")
            return true
        }

        append("""
        Lucy: I heard a selfbuild-style request, but I do not have a safe template for it yet.

        Available selfbuild templates:
        - email helper

        Try:
        give yourself email drafting ability

        I did not edit my code.

        """)
        return true
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
                let result = openURL("https://www.google.com")
                append("Lucy: \(result)\n\n")
                return true
            }

            let encoded = cleanedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanedQuery
            let result = openURL("https://www.google.com/search?q=\(encoded)")
            append("Lucy: \(result)\n\n")
            return true
        }

        func youtubeSearch(_ query: String) -> Bool {
            let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

            if cleanedQuery.isEmpty {
                let result = openURL("https://www.youtube.com")
                append("Lucy: \(result)\n\n")
                return true
            }

            let result = openYouTubeSearch(cleanedQuery)
            append("Lucy: \(result)\n\n")
            return true
        }

        if lowered == "hide"
            || lowered == "hide for a bit"
            || lowered == "go hide"
            || lowered == "disappear"
            || lowered == "hide lucy" {
            append("Lucy: okay, I’ll hide for 5 seconds.\n\n")
            onHideRequested?()
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
            let result = setBrowserPreference("Google Chrome")
            append("Lucy: \(result)\n\n")
            return true
        }

        if lowered == "use safari"
            || lowered == "switch to safari"
            || lowered == "open things in safari" {
            let result = setBrowserPreference("Safari")
            append("Lucy: \(result)\n\n")
            return true
        }

        if lowered == "use default browser"
            || lowered == "use system default browser" {
            let result = setBrowserPreference("default")
            append("Lucy: \(result)\n\n")
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

            let result = openURL(url)
            append("Lucy: \(result)\n\n")
            return true
        }

        return false
    }






    func runSelfCommand(_ command: String) -> String {
        switch command {
        case "/status":
            return LucyRuntime.shared.statusText()

        case "/settings":
            return "Settings:\n- Browser: \(preferredBrowser)\n- Settings file: \(LucyPaths.settingsURL.path)"

        case "/devstatus":
            return runDevAgentStatus()

        case "/autodev roadmap":
            return runAutoDevRoadmap()

        case "/autodev next":
            return runAutoDevNext()

        case "/dev animation-smoother":
            return runDevAgentApply(task: "animation-smoother")

        case "/dev cute-eyes":
            return runDevAgentApply(task: "cute-eyes")

        case "/dev better-crawl":
            return runDevAgentApply(task: "better-crawl")

        case "/dev cursor-aware":
            return runDevAgentApply(task: "cursor-aware")

        case "/dev natural-commands":
            return runDevAgentApply(task: "natural-commands")

        default:
            return "I refused to run an unsafe or unknown self-command: \(command)"
        }
    }

    func chooseSelfCommand() -> (String, String) {
        // Simple deterministic self-command policy for v1.
        // Later this can be model-assisted, but still restricted to this allowlist.

        let status = LucyRuntime.shared.statusText()
        let browser = preferredBrowser

        if browser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ("/settings", "My browser setting looks empty, so I should inspect settings.")
        }

        if LucyRuntime.shared.clickCount == 0 && LucyRuntime.shared.chatCount == 0 {
            return ("/status", "I just started and do not have much activity yet, so I should check my status.")
        }

        if status.contains("Dev Mode") {
            return ("/devstatus", "I should verify that my local dev agent can still compile and inspect my project.")
        }

        return ("/autodev next", "My basic status looks okay, so I should run the next safe autodev task.")
    }


    func runAutopilot(iterations: Int) -> String {
        let safeIterations = max(1, min(iterations, 5))

        var report = """
        Autopilot run started.

        Planned ticks: \(safeIterations)

        """

        for index in 1...safeIterations {
            report += "\n--- Tick \(index) ---\n"
            let result = runSelfLoop()
            report += result
            report += "\n"

            // Basic stop condition: if a result says compile failed or refused,
            // stop instead of chaining more actions.
            let lowered = result.lowercased()
            if lowered.contains("compile ok: false")
                || lowered.contains("failed")
                || lowered.contains("refused")
                || lowered.contains("timed out") {
                report += "\nAutopilot stopped early because the last tick looked unsafe or failed.\n"
                break
            }
        }

        report += "\nAutopilot run complete."
        return report
    }


    func runSelfLoop() -> String {
        let choice = chooseSelfCommand()
        let command = choice.0
        let reason = choice.1

        let result = runSelfCommand(command)

        return """
        Self-command decision:

        I chose:
        \(command)

        Why:
        \(reason)

        Result:
        \(result)
        """
    }






    func lucyGoalsSummary() -> String {
        return """
        My long-term goals:

        1. Become a cute animated jumping-spider desktop companion.
        2. Help you operate your Mac through safe, approved actions.
        3. Remember useful preferences and context locally.
        4. Recognize what I can and cannot do.
        5. Selfbuild missing safe capabilities when possible.
        6. Improve myself through dev tasks, autodev, and self-command loops.
        7. Avoid destructive actions unless a safe approval flow exists.

        My current short-term goals:

        - Make my capability manager smarter.
        - Recognize unsupported requests instead of pretending.
        - Add safer selfbuild templates.
        - Improve my animation and personality.
        - Eventually package myself as a clickable Mac app.
        """
    }

    func lucyReflection() -> String {
        let status = LucyRuntime.shared.statusText()
        let capabilities = capabilitiesSummary()
        let limitations = limitationsSummary()

        return """
        Reflection:

        I am Lucy, a local-first Mac desktop pet and agent.

        What I know about myself:
        - I live in the Lucy project folder.
        - I can chat, remember things, search, open apps, draft Gmail messages, and create Apple Notes.
        - I can run safe self-commands and autodev tasks.
        - I have a capability registry and selfbuild templates.

        Current runtime:
        \(status)

        Capabilities:
        \(capabilities)

        Limitations:
        \(limitations)

        My honest self-assessment:
        I am not truly conscious, but I now have a working self-model. I can describe my identity, goals, abilities, limits, and safe improvement paths. The next step toward stronger agency is to make my capability manager recognize unsupported requests and either selfbuild a safe template or clearly refuse.
        """
    }

    func lucyNextPlan() -> String {
        return """
        My suggested next self-improvement plan:

        Step 1:
        Add an unsupported-capability detector.
        Reason: If you ask me to delete a note, send an email, or do something I cannot safely do, I should recognize the missing capability instead of falling into generic chat.

        Step 2:
        Add a notes-manager template.
        Reason: I can create notes now, but I cannot safely list/edit/delete notes yet.

        Step 3:
        Improve selfbuild routing.
        Reason: I should map more natural requests to known templates automatically.

        Step 4:
        Improve animation/personality.
        Reason: I should feel more alive as a pet, not just a tool.

        Recommended next command:
        /selfbuild add unsupported capability detector
        """
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
            - selfbuild templates
            - autodev roadmap
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

        Available selfbuild templates:
        \(available.isEmpty ? "- none listed" : available.joined(separator: "\n"))

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
        - Create new Apple Notes notes.
        - Run safe dev/autodev tasks.
        - Selfbuild known templates like email helper, Gmail draft helper, and Notes helper.
        - Give myself safe commands through /self and /autopilot.

        Things I should NOT do yet:
        - Send emails automatically.
        - Delete notes automatically.
        - Delete files automatically.
        - Click destructive buttons.
        - Make purchases.
        - Run arbitrary Terminal commands outside my project.
        - Edit code outside the Lucy project.

        If you ask for something I cannot safely do yet, I should:
        1. Recognize the missing capability.
        2. Tell you what is missing.
        3. Suggest or selfbuild a safe template if one exists.
        4. Avoid pretending I did it.
        """
    }

    func selfIdentitySummary() -> String {
        return """
        I am Lucy.

        I am a local-first Mac desktop AI pet and agent.
        I live in this project:
        \(LucyPaths.root.path)

        My current architecture:
        - Swift/AppKit floating desktop pet
        - local Ollama chat
        - local memory
        - capability registry
        - dev task system
        - autodev roadmap
        - self-command loop
        - selfbuild templates

        My long-term goal:
        become a cute animated jumping-spider desktop companion that can safely improve herself, add new abilities, operate your Mac with approval, and help you without you manually coding every feature.
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

        if status == "available_template" || status == "unknown" {
            let buildResult = runSelfBuild(goal: "add notes helper")

            if buildResult.lowercased().contains("successfully")
                || buildResult.lowercased().contains("already installed") {
                updateCapabilityStatus(id: "apple_notes_writer", status: "installed")
                return """
                I installed my Apple Notes helper.

                Now I will create the note.

                \(createMotivationalNote(from: request))
                """
            }

            return """
            I tried to install my Apple Notes helper, but it did not complete.

            \(buildResult)
            """
        }

        return "I do not have a safe capability path for Apple Notes yet."
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

        let noteBody = stripTerminalEscapes(runOllama(prompt: prompt))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let finalBody = noteBody.isEmpty
            ? "You are building something real. Keep going, one small step at a time."
            : noteBody

        return writeAppleNote(title: "Motivation from Lucy", body: finalBody)
    }


    func runSelfBuild(goal: String) -> String {
        let loweredGoal = goal.lowercased()

        let taskName: String

        if loweredGoal.contains("notes") || loweredGoal.contains("note") {
            taskName = "selfbuild-notes-helper"
        } else if loweredGoal.contains("gmail") {
            taskName = "selfbuild-gmail-draft-helper"
        } else if loweredGoal.contains("email") {
            taskName = "selfbuild-email-helper"
        } else {
            return """
            I do not have a safe selfbuild template for that yet.

            Available selfbuild templates:
            - /selfbuild add email helper

            I did not edit my code.
            """
        }

        return runDevAgentApply(task: taskName)
    }



    func runLucyDeveloper(goal: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "tools/lucy_developer.py", goal]
        process.currentDirectoryURL = LucyPaths.root

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()

            let timeoutSeconds = 300.0
            let deadline = Date().addingTimeInterval(timeoutSeconds)

            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.2)
            }

            if process.isRunning {
                process.terminate()
                return "Lucy Developer timed out after \(Int(timeoutSeconds)) seconds. I stopped it safely."
            }

            let out = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            let combined = [out, err]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")

            return combined.isEmpty ? "Lucy Developer finished with no output." : combined
        } catch {
            return "Could not run Lucy Developer: \(error.localizedDescription)"
        }
    }


    func runBuilderGoal(_ goal: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "tools/lucy_builder.py", "goal", goal]
        process.currentDirectoryURL = LucyPaths.root

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()

            let timeoutSeconds = 90.0
            let deadline = Date().addingTimeInterval(timeoutSeconds)

            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.2)
            }

            if process.isRunning {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.5)

                if process.isRunning {
                    process.interrupt()
                }

                return """
                Builder timed out after \(Int(timeoutSeconds)) seconds.

                I stopped the build attempt so I would not stay stuck thinking forever.

                Try a smaller build goal, for example:
                /build add a simple /ping command that replies pong

                Or use safer task commands:
                /autodev roadmap
                /autodev next
                /dev better-crawl
                """
            }

            let out = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            let combined = [out, err]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")

            if combined.isEmpty {
                return "Builder finished with no output."
            }

            return combined
        } catch {
            return "Could not run Lucy Builder: \(error.localizedDescription)"
        }
    }


    func runAutoDevNext() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "tools/lucy_autodev.py", "next"]
        process.currentDirectoryURL = LucyPaths.root

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let out = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            let combined = [out, err]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")

            if combined.isEmpty {
                return "Autodev next finished with no output."
            }

            return combined
        } catch {
            return "Could not run autodev next: \(error.localizedDescription)"
        }
    }


    func runAutoDevRoadmap() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "tools/lucy_autodev.py", "roadmap"]
        process.currentDirectoryURL = LucyPaths.root

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let out = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            let combined = [out, err]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")

            if combined.isEmpty {
                return "Autodev finished with no output."
            }

            return combined
        } catch {
            return "Could not run autodev roadmap: \(error.localizedDescription)"
        }
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


    func runDevAgentApply(task: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "tools/lucy_dev_agent.py", "apply", task]
        process.currentDirectoryURL = LucyPaths.root

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let out = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            let combined = [out, err].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")

            if combined.isEmpty {
                return "Dev agent apply finished with no output."
            }

            return combined
        } catch {
            return "Could not run dev agent apply: \(error.localizedDescription)"
        }
    }


    func runDevAgentStatus() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "tools/lucy_dev_agent.py", "status"]
        process.currentDirectoryURL = LucyPaths.root

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let out = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            let combined = [out, err].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")

            if combined.isEmpty {
                return "Dev agent finished with no output."
            }

            return combined
        } catch {
            return "Could not run dev agent: \(error.localizedDescription)"
        }
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

        let draft = runOllama(prompt: prompt)
        let cleanDraft = stripTerminalEscapes(draft)
        let parsed = parseEmailDraft(cleanDraft)

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

        return """
        I drafted the email and opened Gmail compose.

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

        let draft = runOllama(prompt: prompt)
        let cleanDraft = stripTerminalEscapes(draft)
        saveLastEmailDraft(cleanDraft)

        return """
        Here is a draft:

        \(cleanDraft)

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

        let revised = stripTerminalEscapes(runOllama(prompt: prompt))
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


    func askOllama(_ userText: String) -> String {
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

        return runOllama(prompt: prompt)
    }

    func askOllamaForSelfUpdate(_ request: String) -> String {
        let project = LucyDevTools.shared.projectSummary()
        let swiftPreview = LucyDevTools.shared.readSwiftPreview()

        let prompt = """
        You are Lucy, a local-first Mac desktop pet and AI agent.

        The user wants you to eventually self-update, self-adjust, and self-upgrade.
        For now you are only allowed to create safe self-update proposals.
        You must not claim you edited files.

        User request:
        \(request)

        Current project:
        \(project)

        Current code preview:
        \(swiftPreview)

        Write a practical self-update proposal with:
        1. Goal
        2. Files likely changed
        3. Exact behavior to add/change
        4. Risks
        5. Manual approval needed
        6. Test plan

        Keep it concise and grounded in the actual project.
        """

        return runOllama(prompt: prompt)
    }
}
