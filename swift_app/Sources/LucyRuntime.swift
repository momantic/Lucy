import Cocoa
import Foundation

class LucyRuntime {
    static let shared = LucyRuntime()

    var verboseLogging = false
    var startTime = Date()
    var crawlCount = 0
    var hopCount = 0
    var idleCount = 0
    var clickCount = 0
    var hideCount = 0
    var chatCount = 0
    var facingRight = true

    func log(_ message: String) {
        if verboseLogging {
            print(message)
        }
    }

    func statusText() -> String {
        let uptime = Int(Date().timeIntervalSince(startTime))

        return """
        Lucy Runtime Status

        Uptime: \(uptime) seconds
        Verbose logging: \(verboseLogging ? "on" : "off")

        Activity:
        - Clicks: \(clickCount)
        - Chats opened: \(chatCount)
        - Crawls: \(crawlCount)
        - Hops: \(hopCount)
        - Idles: \(idleCount)
        - Hides: \(hideCount)

        Current mode:
        - Dev Mode v0.5
        - Local MLX chat
        - Local memory
        - Safe self-update proposal flow
        - Safe built-in apply flow
        """
    }
}
