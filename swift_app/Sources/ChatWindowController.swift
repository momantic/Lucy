import Cocoa
import Foundation

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
        Lucy: Hi, I’m Lucy. Dev Mode v0.4 is active.

        Commands:
        /memory
        /project
        /readself
        /status
        /quiet
        /loud
        /hide
        /selfupdate your request here
        /apply hide-command
        /apply clean-memory
        /patch patch-name
        /patches
        /readpatch latest

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
