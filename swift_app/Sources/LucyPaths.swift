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

    static let memoryURL = root
        .appendingPathComponent("memory")
        .appendingPathComponent("memory.json")

    static let settingsURL = root
        .appendingPathComponent("data")
        .appendingPathComponent("settings.json")
}
