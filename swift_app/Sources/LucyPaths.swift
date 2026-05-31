import Foundation

struct LucyPaths {
    static let root: URL = {
        let homeLucy = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("lucy")

        if FileManager.default.fileExists(atPath: homeLucy.path) {
            return homeLucy
        }

        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        if FileManager.default.fileExists(atPath: current.appendingPathComponent("swift_app").path) {
            return current
        }

        var url = Bundle.main.bundleURL

        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("swift_app").path) {
                return url
            }

            url.deleteLastPathComponent()
        }

        return homeLucy
    }()

    static let sourcesDir = root
        .appendingPathComponent("swift_app")
        .appendingPathComponent("Sources")

    static let binaryFile = root
        .appendingPathComponent("swift_app")
        .appendingPathComponent("Lucy")

    // Legacy single-file path used by old dev tools.
    // Keep this so LucyDevTools.swift still compiles.
    static let swiftFile = sourcesDir
        .appendingPathComponent("main.swift")

    static let selfUpdatesDir = root
        .appendingPathComponent("self_updates")

    static let backupsDir = root
        .appendingPathComponent("backups")

    static let memoryBackupsDir = backupsDir
        .appendingPathComponent("memory")

    static let memoryURL = root
        .appendingPathComponent("memory")
        .appendingPathComponent("memory.json")

    static let settingsURL = root
        .appendingPathComponent("data")
        .appendingPathComponent("settings.json")
}
