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

        You run fully locally using Apple MLX.
        Be helpful, concise, warm, and practical.

        Project truth rule:
        - If the user asks about Lucy's own code, project status, tools, model provider, MLX, Qwen, files, build status, or implementation details, do not guess from general knowledge.
        - Say that you need to use Lucy's local project tools/self-loop to inspect the project.
        - Current known model runtime: MLX.
        - Current known default model: mlx-community/Qwen2.5-3B-Instruct-4bit.

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

        return runMLXGenerate(prompt: prompt, maxTokens: 512)
    }

    private func runMLXGenerate(prompt: String, maxTokens: Int) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            "-m",
            "mlx_lm",
            "generate",
            "--model",
            "mlx-community/Qwen2.5-3B-Instruct-4bit",
            "--prompt",
            prompt,
            "--max-tokens",
            String(maxTokens),
            "--verbose",
            "False"
        ]

        process.currentDirectoryURL = LucyPaths.root

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            let error = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            if process.terminationStatus != 0 {
                return "I had trouble talking to my MLX local brain:\n\(error.isEmpty ? output : error)"
            }

            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "I could not start my MLX local brain. Error: \(error.localizedDescription)"
        }
    }
}
