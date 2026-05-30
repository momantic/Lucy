import Cocoa
import Foundation

class LucyPaths {
    static let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    static let memoryURL = root.appendingPathComponent("memory").appendingPathComponent("memory.json")
    static let settingsURL = root.appendingPathComponent("data").appendingPathComponent("settings.json")
    static let selfUpdatesDir = root.appendingPathComponent("self_updates")
    static let backupsDir = root.appendingPathComponent("backups")
    static let memoryBackupsDir = root.appendingPathComponent("backups").appendingPathComponent("memory")
    static let swiftFile = root.appendingPathComponent("swift_app").appendingPathComponent("Lucy.swift")
    static let sourcesDir = root.appendingPathComponent("swift_app").appendingPathComponent("Sources")
    static let binaryFile = root.appendingPathComponent("swift_app").appendingPathComponent("Lucy")
}
