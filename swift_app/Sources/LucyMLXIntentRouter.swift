import Foundation

final class LucyMLXIntentRouter {
    static let shared = LucyMLXIntentRouter()

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

        You run fully locally using Lucy's local model provider.
        Be helpful, concise, warm, and practical.

        Project truth rule:
        - If the user asks about Lucy's own code, project status, tools, model provider, MLX, Qwen, files, build status, or implementation details, do not guess from general knowledge.
        - Say that Lucy can only answer from visible app state and configured tools, not by inspecting or modifying her own code at runtime.
        - Current known model runtime: local provider abstraction.
        - Current known default model: configured in data/model_provider.json.

        Critical safety:
        - Never claim you sent, will send, or can directly send messages/emails.
        - For iMessage, email, or other communication tasks, say you can prepare a draft for the user to review.
        - If a task is not supported by an explicit tool, explain the limitation clearly instead of pretending it was done.

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

        return runLocalModelGenerate(prompt: prompt, maxTokens: 512, timeout: timeout)
    }

    private func runLocalModelGenerate(prompt: String, maxTokens: Int, timeout: TimeInterval) -> String {
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
            "chat",
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
