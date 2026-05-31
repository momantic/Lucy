import Cocoa
import ApplicationServices

struct LucyWindowInfo {
    let appName: String
    let windowTitle: String
    let bounds: CGRect
}

struct LucyScreenAwareness {
    static func frontmostAppName() -> String {
        return NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }

    static func frontmostWindowInfo() -> LucyWindowInfo? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            let appName = window[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let lowerAppName = appName.lowercased()

            // Ignore Lucy itself, Terminal helper noise, Dock/menu/system overlays.
            if lowerAppName.contains("lucy")
                || lowerAppName.contains("dock")
                || lowerAppName.contains("window server")
                || lowerAppName.contains("systemuiserver") {
                continue
            }

            guard let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                continue
            }

            let title = window[kCGWindowName as String] as? String ?? ""

            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat else {
                continue
            }

            if width < 160 || height < 120 {
                continue
            }

            let bounds = CGRect(x: x, y: y, width: width, height: height)
            return LucyWindowInfo(appName: appName, windowTitle: title, bounds: bounds)
        }

        return nil
    }

    static func screenInfoText(lucyFrame: NSRect) -> String {
        let mouse = NSEvent.mouseLocation

        let screenText: String
        if let screen = NSScreen.main {
            let frame = screen.frame
            let visible = screen.visibleFrame
            screenText = """
            screen: \(Int(frame.width))x\(Int(frame.height))
            visible: x \(Int(visible.minX)), y \(Int(visible.minY)), w \(Int(visible.width)), h \(Int(visible.height))
            """
        } else {
            screenText = "screen: unavailable"
        }

        let windowText: String
        if let info = frontmostWindowInfo() {
            windowText = """
            front window app: \(info.appName)
            front window title: \(info.windowTitle.isEmpty ? "(untitled)" : info.windowTitle)
            front window bounds: x \(Int(info.bounds.minX)), y \(Int(info.bounds.minY)), w \(Int(info.bounds.width)), h \(Int(info.bounds.height))
            """
        } else {
            windowText = "front window: unavailable"
        }

        return """
        Front app: \(frontmostAppName())
        Mouse: x \(Int(mouse.x)), y \(Int(mouse.y))

        \(screenText)

        \(windowText)

        Lucy: x \(Int(lucyFrame.minX)), y \(Int(lucyFrame.minY)), w \(Int(lucyFrame.width)), h \(Int(lucyFrame.height))
        """
    }
}
