import Cocoa
import Foundation


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
        Lucy: Hi, I’m Lucy. Dev Mode v0.5 is active.

        You can talk naturally:
        - open google
        - find cute jumping spider pictures
        - search best mac desktop pet examples
        - search youtube for lucas the spider
        - find me a jumping spider video
        - open wikipedia.org
        - use chrome
        - use safari
        - hide for a bit

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

        """


        scroll.documentView = output

        input = NSTextField(frame: NSRect(x: 15, y: 20, width: 490, height: 30))
        input.placeholderString = "Message Lucy..."
        input.delegate = self

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


    func controlTextDidEndEditing(_ obj: Notification) {
        guard
            let movement = obj.userInfo?["NSTextMovement"] as? Int,
            movement == NSReturnTextMovement
        else {
            return
        }

        sendMessage()
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



        if !userText.hasPrefix("/") && routeNaturalCommand(userText) {
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
