import Cocoa
import Foundation

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
