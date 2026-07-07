import Foundation

final class LucyLocalLLMIntentRouter {
    static let shared = LucyLocalLLMIntentRouter()

    private init() {}

    func chatSync(
        history: [LucyChatMessage],
        userText: String,
        projectMemory: String? = nil,
        projectContext: String? = nil,
        timeout: TimeInterval = 60.0
    ) -> String? {
        var prompt = """
        You are Lucy, a cute local-first Mac desktop AI companion.

        You run fully locally using Lucy's configured local model provider.
        Be helpful, concise, warm, and practical.

        Project truth rule:
        - If the user asks about Lucy's own code, project status, tools, model provider, local models, Qwen, files, build status, or implementation details, do not guess from general knowledge.
        - Say that you need to use Lucy's local project tools/self-loop to inspect the project.
        - Current known model runtime: auto-selected local provider, MLX on Apple Silicon and llama.cpp/GGUF on Intel Macs.

        Critical safety:
        - Never claim you sent, will send, or can directly send messages/emails.
        - For iMessage, email, or other communication tasks, say you can prepare a draft for the user to review.
        - If the user says "try again", "nothing happened", or "continue", do not pretend to perform the task in normal chat. The app should route that to the agent loop.

        """

        if let projectMemory, !projectMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += """

            Project memory:
            \(projectMemory)

            """
        }

        if let projectContext, !projectContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += """

            Project context:
            \(projectContext)

            """
        }

        if !history.isEmpty {
            prompt += "\nRecent conversation:\n"
            for message in history.suffix(12) {
                prompt += "\(message.role): \(message.content)\n"
            }
        }

        prompt += """

        User: \(userText)
        Lucy:
        """

        return runLocalLLMGenerate(prompt: prompt, maxTokens: 512, timeout: timeout)
    }

    private func runLocalLLMGenerate(prompt: String, maxTokens: Int, timeout: TimeInterval) -> String {
        let process = Process()
        let python = ProcessInfo.processInfo.environment["PYTHON"] ?? "python3"
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            python,
            "tools/providers/local_llm.py",
            "--purpose",
            "chat",
            "--max-tokens",
            String(maxTokens),
            "--stdin"
        ]

        process.currentDirectoryURL = LucyPaths.root

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let inputPipe = Pipe()
        process.standardInput = inputPipe

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
                return "My local model took too long to answer. On older Intel Macs, try a smaller GGUF model."
            }

            let output = String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            let error = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            if process.terminationStatus != 0 {
                return "I had trouble talking to my local model:\n\(error.isEmpty ? output : error)"
            }

            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "I could not start my local model. Error: \(error.localizedDescription)"
        }
    }
}

typealias LucyMLXIntentRouter = LucyLocalLLMIntentRouter
