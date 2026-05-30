import Cocoa
import Foundation

enum LucyState {
    case idle
    case crawl
    case hop
    case thinking
    case hidden
}

class LucyPaths {
    static let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    static let memoryURL = root.appendingPathComponent("memory").appendingPathComponent("memory.json")
    static let selfUpdatesDir = root.appendingPathComponent("self_updates")
    static let backupsDir = root.appendingPathComponent("backups")
    static let swiftFile = root.appendingPathComponent("swift_app").appendingPathComponent("Lucy.swift")
    static let binaryFile = root.appendingPathComponent("swift_app").appendingPathComponent("Lucy")
}

class LucyMemory {
    static let shared = LucyMemory()

    func ensureMemoryFile() {
        let memoryDir = LucyPaths.memoryURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: memoryDir, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: LucyPaths.memoryURL.path) {
            let initial: [String: Any] = [
                "agent_name": "Lucy",
                "facts": [
                    "Lucy is a local-first AI desktop pet.",
                    "Lucy should stay 100 percent free to run.",
                    "Lucy is visually inspired by a cute jumping spider.",
                    "Lucy should eventually self-update, self-adjust, and self-upgrade safely."
                ]
            ]

            if let data = try? JSONSerialization.data(withJSONObject: initial, options: [.prettyPrinted]) {
                try? data.write(to: LucyPaths.memoryURL)
            }
        }
    }

    func loadFacts() -> [String] {
        ensureMemoryFile()

        guard
            let data = try? Data(contentsOf: LucyPaths.memoryURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let facts = json["facts"] as? [String]
        else {
            return []
        }

        return facts
    }

    func cleanFact(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let prefixes = [
            "remember that",
            "remember this",
            "from now on,"
        ]

        for prefix in prefixes {
            if cleaned.lowercased().hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return cleaned
    }

    func saveFact(_ fact: String) {
        ensureMemoryFile()

        let cleaned = cleanFact(fact)
        if cleaned.isEmpty { return }

        var facts = loadFacts()

        if !facts.contains(cleaned) {
            facts.append(cleaned)
        }

        let updated: [String: Any] = [
            "agent_name": "Lucy",
            "facts": facts
        ]

        if let data = try? JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted]) {
            try? data.write(to: LucyPaths.memoryURL)
        }
    }

    func maybeRemember(_ text: String) -> Bool {
        let lowered = text.lowercased()

        let triggers = [
            "remember that",
            "remember this",
            "from now on",
            "i prefer",
            "i like",
            "i don't like",
            "my name is"
        ]

        if triggers.contains(where: { lowered.contains($0) }) {
            saveFact(text)
            return true
        }

        return false
    }

    func userFacts() -> [String] {
        return loadFacts().filter { fact in
            let lowered = fact.lowercased()
            return !lowered.contains("lucy is")
                && !lowered.contains("lucy should")
                && !lowered.contains("lucy is visually")
        }
    }

    func memoryPromptText() -> String {
        let facts = loadFacts()

        if facts.isEmpty {
            return "No saved memories yet."
        }

        return facts.map { "- \($0)" }.joined(separator: "\n")
    }

    func memoryResponseText() -> String {
        let facts = userFacts()

        if facts.isEmpty {
            return "I don't have any personal memories saved yet."
        }

        var response = "I remember:\n"
        for fact in facts {
            response += "- \(fact)\n"
        }

        return response
    }
}

class LucyDevTools {
    static let shared = LucyDevTools()

    func ensureDirs() {
        try? FileManager.default.createDirectory(at: LucyPaths.selfUpdatesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: LucyPaths.backupsDir, withIntermediateDirectories: true)
    }

    func projectSummary() -> String {
        let fm = FileManager.default
        let root = LucyPaths.root

        let importantFiles = [
            "swift_app/Lucy.swift",
            "swift_app/Lucy",
            "memory/memory.json",
            "self_updates/",
            "backups/",
            "README.md"
        ]

        var result = "Lucy project root:\n\(root.path)\n\nImportant files:\n"

        for item in importantFiles {
            let path = root.appendingPathComponent(item).path
            let exists = fm.fileExists(atPath: path)
            result += "- \(exists ? "✅" : "❌") \(item)\n"
        }

        result += "\nCurrent abilities:\n"
        result += "- Floating native Mac pet window\n"
        result += "- Click and double-click interactions\n"
        result += "- Placeholder animation states\n"
        result += "- Local Ollama chat\n"
        result += "- Local memory file\n"
        result += "- Dev Mode proposal writing\n"
        result += "- Safe built-in apply flow for /apply hide-command\n"
        result += "- Chat command /hide hides Lucy for 5 seconds\n"

        return result
    }

    func readSwiftPreview() -> String {
        guard let text = try? String(contentsOf: LucyPaths.swiftFile, encoding: .utf8) else {
            return "I could not read swift_app/Lucy.swift."
        }

        let lines = text.components(separatedBy: .newlines)
        let preview = lines.prefix(80).joined(separator: "\n")

        return "Preview of swift_app/Lucy.swift, first 80 lines:\n\n\(preview)"
    }

    func createSelfUpdateProposal(request: String, ollamaAnswer: String) -> String {
        ensureDirs()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"

        let fileName = "proposal_\(formatter.string(from: Date())).md"
        let url = LucyPaths.selfUpdatesDir.appendingPathComponent(fileName)

        let body = """
        # Lucy Self-Update Proposal

        ## User Request

        \(request)

        ## Lucy's Proposal

        \(ollamaAnswer)

        ## Safety Rule

        This is only a proposal. Lucy has not edited code yet.

        Future safe apply flow:
        1. Backup the current file.
        2. Create a patch.
        3. Ask for user approval.
        4. Apply only inside the Lucy project folder.
        5. Compile with swiftc.
        6. Roll back if compile fails.

        """

        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            return "Self-update proposal saved to:\n\(url.path)"
        } catch {
            return "I could not save the proposal: \(error.localizedDescription)"
        }
    }

    func applyHideCommandUpdate() -> String {
        ensureDirs()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: Date())

        let backupURL = LucyPaths.backupsDir.appendingPathComponent("Lucy_\(stamp).swift")

        do {
            let currentSource = try String(contentsOf: LucyPaths.swiftFile, encoding: .utf8)

            // v0.2 safe apply demo:
            // The running source already includes the hide command.
            // This proves Lucy can backup, rewrite, compile, and report.
            try currentSource.write(to: backupURL, atomically: true, encoding: .utf8)
            try currentSource.write(to: LucyPaths.swiftFile, atomically: true, encoding: .utf8)

            let compileResult = compileLucy()

            if compileResult.success {
                return """
                Applied safe update: hide-command.

                What happened:
                - Backup created:
                  \(backupURL.path)
                - Source file rewritten safely:
                  \(LucyPaths.swiftFile.path)
                - Compile check passed.

                You can now type /hide in Lucy chat to hide her for 5 seconds.
                """
            } else {
                try? String(contentsOf: backupURL, encoding: .utf8)
                    .write(to: LucyPaths.swiftFile, atomically: true, encoding: .utf8)

                return """
                Update failed compile check, so I rolled back.

                Backup:
                \(backupURL.path)

                Compile error:
                \(compileResult.output)
                """
            }
        } catch {
            return "I could not apply the update: \(error.localizedDescription)"
        }
    }

    func compileLucy() -> (success: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swiftc",
            LucyPaths.swiftFile.path,
            "-o",
            LucyPaths.binaryFile.path
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let out = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let combined = [out, err].filter { !$0.isEmpty }.joined(separator: "\n")

            return (process.terminationStatus == 0, combined.isEmpty ? "No compiler output." : combined)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

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
            print("Lucy double clicked")
            setState(.thinking, mood: "chat")
            onDoubleClick?()
        } else {
            clickCount += 1
            let messages = ["tap tap...", "watching 👀", "ready", "hi!", "boop", "clicked \(clickCount)"]
            setState(.thinking, mood: messages.randomElement() ?? "Lucy")
            print("Lucy clicked")
        }
    }
}

class ChatWindowController: NSObject {
    var window: NSWindow!
    var output: NSTextView!
    var input: NSTextField!
    let model = "qwen2.5:1.5b"

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
        Lucy: Hi, I’m Lucy. Dev Mode v0.2 is active.

        Commands:
        /memory
        /project
        /readself
        /hide
        /selfupdate your request here
        /apply hide-command

        """

        scroll.documentView = output

        input = NSTextField(frame: NSRect(x: 15, y: 20, width: 490, height: 30))
        input.placeholderString = "Message Lucy..."

        let sendButton = NSButton(frame: NSRect(x: 515, y: 20, width: 90, height: 30))
        sendButton.title = "Send"
        sendButton.target = self
        sendButton.action = #selector(sendMessage)

        root.addSubview(scroll)
        root.addSubview(input)
        root.addSubview(sendButton)

        window.contentView = root
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func sendMessage() {
        let userText = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if userText.isEmpty { return }

        input.stringValue = ""
        append("You: \(userText)\n")

        let lowered = userText.lowercased()

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

        if lowered == "/hide" || lowered.contains("hide lucy") || lowered.contains("go hide") {
            append("Lucy: okay, I’ll hide for 5 seconds.\n\n")
            onHideRequested?()
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

            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "I did not get a response."
        } catch {
            return "I could not start Ollama. Error: \(error.localizedDescription)"
        }
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

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var petView: ClickablePetView!
    var chatController: ChatWindowController?

    var wanderTimer: Timer?
    var moodTimer: Timer?
    var animationTimer: Timer?
    var isHidden = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Lucy Dev Mode v0.2 started")

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
        petView.setState(.hidden, mood: "hiding")
        window.orderOut(nil)

        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            self.window.makeKeyAndOrderFront(nil)
            self.petView.setState(.idle, mood: "back")
            self.isHidden = false
            print("Lucy returned from hiding")
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
                print("Lucy crawled")
            } else if action <= 8 {
                let dx = CGFloat([-60, -40, 40, 60].randomElement()!)
                let dy = CGFloat([30, 45].randomElement()!)

                frame.origin.x = max(screen.minX, min(frame.origin.x + dx, screen.maxX - frame.width))
                frame.origin.y = max(screen.minY, min(frame.origin.y + dy, screen.maxY - frame.height))

                self.petView.setState(.hop, mood: "hop!")
                self.window.setFrame(frame, display: true, animate: true)
                print("Lucy hopped")
            } else {
                let moods = ["look 👀", "idle", "hmm", "Lucy"]
                self.petView.setState(.idle, mood: moods.randomElement() ?? "Lucy")
                print("Lucy idled")
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
