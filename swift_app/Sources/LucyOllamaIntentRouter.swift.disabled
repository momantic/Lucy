import Foundation

struct LucyOllamaIntentResult {
    let action: String
    let reply: String
}

struct LucyChatMessage {
    let role: String
    let content: String
}

class LucyOllamaIntentRouter {
    static let shared = LucyOllamaIntentRouter()

    private let model = "qwen2.5:3b"
    private let endpoint = URL(string: "http://localhost:11434/api/generate")!

    func routeSync(_ userText: String, timeout: TimeInterval = 5.5) -> LucyOllamaIntentResult? {
        let prompt = """
        You are Lucy's local command router.

        Convert the user's message into ONE allowed action.

        Allowed actions:
        - soft_hide
        - come_back
        - gravity_on
        - gravity_off
        - jump
        - dock_perch
        - roam_on
        - roam_off
        - screen_info
        - render_info
        - model_bounds
        - normal_chat

        Rules:
        - Return JSON only.
        - Do not explain.
        - If the user is just chatting, use normal_chat.
        - If the user has typos, infer the intended command.
        - Never invent actions outside the allowed list.

        User message:
        \(userText)

        JSON format:
        {"action":"...", "reply":"..."}
        """

        return generateJSON(prompt: prompt, timeout: timeout)
    }

    func chatSync(history: [LucyChatMessage], userText: String, timeout: TimeInterval = 12.0) -> String? {
        let recentHistory = history.suffix(16).map { message in
            "\(message.role): \(message.content)"
        }.joined(separator: "\n")

        let prompt = """
        You are Lucy, a cute desktop pet spider companion living on the user's Mac.

        Personality:
        - warm, playful, concise
        - remembers what the user said earlier in this chat
        - if asked "what did I say earlier?", answer from the chat history
        - do not claim you remember things that are not in the history
        - keep replies short unless the user asks for detail

        Recent chat:
        \(recentHistory)

        User: \(userText)
        Lucy:
        """

        return generateText(prompt: prompt, timeout: timeout)
    }

    private func generateJSON(prompt: String, timeout: TimeInterval) -> LucyOllamaIntentResult? {
        guard let response = callOllama(prompt: prompt, timeout: timeout, temperature: 0.0, numPredict: 80) else {
            return nil
        }

        let cleaned = Self.extractJSON(from: response)

        guard
            let jsonData = cleaned.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let action = parsed["action"] as? String
        else {
            return nil
        }

        let reply = parsed["reply"] as? String ?? ""
        return LucyOllamaIntentResult(action: action, reply: reply)
    }

    private func generateText(prompt: String, timeout: TimeInterval) -> String? {
        guard let response = callOllama(prompt: prompt, timeout: timeout, temperature: 0.6, numPredict: 180) else {
            return nil
        }

        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func callOllama(prompt: String, timeout: TimeInterval, temperature: Double, numPredict: Int) -> String? {
        let payload: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": temperature,
                "num_predict": numPredict
            ]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let semaphore = DispatchSemaphore(value: 0)
        var finalResponse: String?

        URLSession.shared.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }

            guard error == nil, let data = data else {
                return
            }

            guard
                let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let response = outer["response"] as? String
            else {
                return
            }

            finalResponse = response
        }.resume()

        let result = semaphore.wait(timeout: .now() + timeout)
        if result == .timedOut {
            return nil
        }

        return finalResponse
    }

    static func extractJSON(from text: String) -> String {
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start <= end {
            return String(text[start...end])
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
