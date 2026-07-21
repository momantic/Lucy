import Foundation

struct LucyPaths {
    static let root: URL = {
        let fm = FileManager.default

        func isLucyProjectRoot(_ url: URL) -> Bool {
            fm.fileExists(atPath: url.appendingPathComponent("tools/providers/local_llm.py").path)
                || fm.fileExists(atPath: url.appendingPathComponent("swift_app").path)
        }

        func firstExistingLucyRoot(startingAt start: URL) -> URL? {
            var url = start

            for _ in 0..<10 {
                if isLucyProjectRoot(url) {
                    return url
                }

                let parent = url.deletingLastPathComponent()
                if parent.path == url.path {
                    break
                }
                url = parent
            }

            return nil
        }

        if let envRoot = ProcessInfo.processInfo.environment["LUCY_PROJECT_ROOT"],
           !envRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: NSString(string: envRoot).expandingTildeInPath)
            if isLucyProjectRoot(url) {
                return url
            }
        }

        let current = URL(fileURLWithPath: fm.currentDirectoryPath)
        if let root = firstExistingLucyRoot(startingAt: current) {
            return root
        }

        if let root = firstExistingLucyRoot(startingAt: Bundle.main.bundleURL) {
            return root
        }

        let home = fm.homeDirectoryForCurrentUser
        let explicitCandidates = [
            home.appendingPathComponent("Documents/Lucy"),
            home.appendingPathComponent("Lucy"),
            home.appendingPathComponent("lucy")
        ]

        for candidate in explicitCandidates {
            if isLucyProjectRoot(candidate) {
                return candidate
            }
        }

        return home.appendingPathComponent("Documents/Lucy")
    }()

    static let memoryURL = root
        .appendingPathComponent("memory")
        .appendingPathComponent("memory.json")

    static let settingsURL = root
        .appendingPathComponent("data")
        .appendingPathComponent("settings.json")

    static func localLLMPythonExecutable() -> String {
        let fm = FileManager.default

        if let envPython = ProcessInfo.processInfo.environment["PYTHON"],
           !envPython.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envPython
        }

        let bundledLocalLLMPython = root
            .appendingPathComponent(".venv-local-llm")
            .appendingPathComponent("bin")
            .appendingPathComponent("python")

        if fm.isExecutableFile(atPath: bundledLocalLLMPython.path) {
            return bundledLocalLLMPython.path
        }

        return "python3"
    }
}
