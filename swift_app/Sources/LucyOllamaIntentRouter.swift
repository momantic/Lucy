import Foundation

struct LucyOllamaIntentResult {
    let action: String
    let reply: String
}

class LucyOllamaIntentRouter {
    static let shared = LucyOllamaIntentRouter()

    private let model = "qwen2.5:3b"
    private let endpoint = URL(string: "http://localhost:11434/api/generate")!

    func routeSync(_ userText: String, timeout: TimeInterval = 4.5) -> LucyOllamaIntentResult? {
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

        let payload: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": 0.0,
                "num_predict": 80
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
        var finalResult: LucyOllamaIntentResult?

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

            let cleaned = Self.extractJSON(from: response)

            guard
                let jsonData = cleaned.data(using: .utf8),
                let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                let action = parsed["action"] as? String
            else {
                return
            }

            let reply = parsed["reply"] as? String ?? ""
            finalResult = LucyOllamaIntentResult(action: action, reply: reply)
        }.resume()

        let result = semaphore.wait(timeout: .now() + timeout)
        if result == .timedOut {
            return nil
        }

        return finalResult
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
