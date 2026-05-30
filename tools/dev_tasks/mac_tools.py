from common import SOURCES, backup_sources, restore_backup, compile_lucy, write_apply_report, replace_function


NEW_OPEN_TOOL_METHODS = r'''    func openURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else {
            return "That URL does not look valid."
        }

        NSWorkspace.shared.open(url)
        return "Opened URL: \(urlString)"
    }

    func openYouTubeSearch(_ query: String) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = "https://www.youtube.com/results?search_query=\(encoded)"
        return openURL(url)
    }

    func openApp(_ appName: String) -> String {
        let workspace = NSWorkspace.shared

        if workspace.launchApplication(appName) {
            return "Opened app: \(appName)"
        }

        return "I could not open app: \(appName). Try the exact app name, like Safari, Google Chrome, or Terminal."
    }

'''


def run():
    backup_dir = backup_sources()
    target = SOURCES / "ChatWindowController.swift"

    if not target.exists():
        raise SystemExit("Could not find ChatWindowController.swift")

    original = target.read_text()
    updated = original

    # Add command list items.
    if "/youtube search terms" not in updated:
        updated = updated.replace(
            "/dev cursor-aware\n",
            "/dev cursor-aware\n        /youtube search terms\n        /openurl https://example.com\n        /openapp Safari\n"
        )

    # Add helper methods before runDevAgentApply.
    if "func openYouTubeSearch" not in updated:
        updated = updated.replace(
            "    func runDevAgentApply(task: String) -> String {",
            NEW_OPEN_TOOL_METHODS + "\n    func runDevAgentApply(task: String) -> String {"
        )

    # Add command handlers before /dev cursor-aware.
    handler = r'''
        if lowered.hasPrefix("/youtube ") {
            let query = String(userText.dropFirst("/youtube ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if query.isEmpty {
                append("Lucy: Tell me what to search on YouTube. Example: /youtube cute jumping spider\n\n")
                return
            }

            let result = openYouTubeSearch(query)
            append("Lucy: \(result)\n\n")
            return
        }

        if lowered.hasPrefix("/openurl ") {
            let url = String(userText.dropFirst("/openurl ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if url.isEmpty {
                append("Lucy: Give me a URL after /openurl.\n\n")
                return
            }

            let result = openURL(url)
            append("Lucy: \(result)\n\n")
            return
        }

        if lowered.hasPrefix("/openapp ") {
            let appName = String(userText.dropFirst("/openapp ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if appName.isEmpty {
                append("Lucy: Tell me the app name after /openapp. Example: /openapp Safari\n\n")
                return
            }

            let result = openApp(appName)
            append("Lucy: \(result)\n\n")
            return
        }

'''
    if 'lowered.hasPrefix("/youtube ")' not in updated:
        updated = updated.replace(
            '        if lowered == "/dev cursor-aware" {',
            handler + '\n        if lowered == "/dev cursor-aware" {'
        )

    target.write_text(updated)

    ok, compile_output = compile_lucy()

    if not ok:
        restore_backup(backup_dir)
        rollback_ok, rollback_output = compile_lucy()
        report = write_apply_report(
            "mac_tools_failed",
            backup_dir,
            False,
            compile_output + "\n\nRollback compile OK: " + str(rollback_ok) + "\n" + rollback_output,
            ["swift_app/Sources/ChatWindowController.swift"],
            "Compile failed after adding Mac tools. Sources were rolled back."
        )
        print("Mac tools update failed. Rolled back.")
        print(f"Report: {report}")
        raise SystemExit(1)

    report = write_apply_report(
        "mac_tools",
        backup_dir,
        True,
        compile_output,
        ["swift_app/Sources/ChatWindowController.swift"],
        "Added /youtube, /openurl, and /openapp tools so Lucy can open web searches, URLs, and Mac apps."
    )

    print("Applied mac-tools update.")
    print(f"Backup: {backup_dir}")
    print(f"Report: {report}")


if __name__ == "__main__":
    run()
