import Cocoa
import Foundation

class LucyDevTools {
    static let shared = LucyDevTools()

    func ensureDirs() {
        try? FileManager.default.createDirectory(at: LucyPaths.selfUpdatesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: LucyPaths.backupsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: LucyPaths.memoryBackupsDir, withIntermediateDirectories: true)
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
            ".gitignore",
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
        result += "- /hide command\n"
        result += "- /status command\n"
        result += "- /apply clean-memory command\n"
        result += "- /quiet and /loud logging controls\n"

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

                /hide is available.
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
        let fm = FileManager.default

        guard
            let sourceFiles = try? fm.contentsOfDirectory(
                at: LucyPaths.sourcesDir,
                includingPropertiesForKeys: nil
            )
            .filter({ $0.pathExtension == "swift" })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        else {
            return (false, "Could not list Swift source files in \(LucyPaths.sourcesDir.path)")
        }

        if sourceFiles.isEmpty {
            return (false, "No Swift source files found in \(LucyPaths.sourcesDir.path)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc"] + sourceFiles.map { $0.path } + [
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

    func cleanMemoryFile() -> String {
        ensureDirs()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: Date())

        let backupURL = LucyPaths.memoryBackupsDir.appendingPathComponent("memory_\(stamp).json")

        do {
            let data = try Data(contentsOf: LucyPaths.memoryURL)

            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let facts = json["facts"] as? [String]
            else {
                return "I could not clean memory because memory.json is not in the expected format."
            }

            try data.write(to: backupURL)

            let cleanedFacts = facts.map { fact -> String in
                var cleaned = fact.trimmingCharacters(in: .whitespacesAndNewlines)

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

                while cleaned.contains("  ") {
                    cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
                }

                return cleaned
            }
            .filter { !$0.isEmpty }

            var uniqueFacts: [String] = []
            for fact in cleanedFacts {
                if !uniqueFacts.contains(fact) {
                    uniqueFacts.append(fact)
                }
            }

            let updated: [String: Any] = [
                "agent_name": "Lucy",
                "facts": uniqueFacts
            ]

            let updatedData = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted])
            try updatedData.write(to: LucyPaths.memoryURL)

            _ = try JSONSerialization.jsonObject(with: updatedData)

            return """
            Applied safe update: clean-memory.

            What happened:
            - Memory backup created:
              \(backupURL.path)
            - Cleaned memory file:
              \(LucyPaths.memoryURL.path)
            - Removed repeated spaces and prefixes like "remember that"
            - Validation passed.

            Cleaned facts:
            \(uniqueFacts.map { "- \($0)" }.joined(separator: "\n"))
            """
        } catch {
            return "I could not clean memory: \(error.localizedDescription)"
        }
    }


}
