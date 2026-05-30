from common import SOURCES, backup_sources, restore_backup, compile_lucy, write_apply_report


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        raise ValueError(f"Could not find expected block:\n{old[:200]}...")
    return text.replace(old, new, 1)


def run():
    backup_dir = backup_sources()
    target = SOURCES / "ChatWindowController.swift"

    if not target.exists():
        raise SystemExit("Could not find ChatWindowController.swift")

    original = target.read_text()
    updated = original

    # Add helper methods before runDevAgentApply.
    helper_marker = "    func runDevAgentApply(task: String) -> String {"

    helpers = r'''    func stripPolitePrefix(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let prefixes = [
            "lucy,",
            "lucy ",
            "hey lucy,",
            "hey lucy ",
            "can you ",
            "could you ",
            "please "
        ]

        var changed = true
        while changed {
            changed = false
            let lowered = cleaned.lowercased()

            for prefix in prefixes {
                if lowered.hasPrefix(prefix) {
                    cleaned = String(cleaned.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                    break
                }
            }
        }

        return cleaned
    }

    func routeNaturalCommand(_ userText: String) -> Bool {
        let cleaned = stripPolitePrefix(userText)
        let lowered = cleaned.lowercased()

        if lowered == "hide"
            || lowered == "hide for a bit"
            || lowered == "go hide"
            || lowered == "disappear"
            || lowered == "hide lucy" {
            append("Lucy: okay, I’ll hide for 5 seconds.\n\n")
            onHideRequested?()
            return true
        }

        if lowered == "open google"
            || lowered == "open google.com"
            || lowered == "go to google"
            || lowered == "open google in browser" {
            let result = openURL("https://www.google.com")
            append("Lucy: \(result)\n\n")
            return true
        }

        if lowered == "open youtube"
            || lowered == "go to youtube" {
            let result = openURL("https://www.youtube.com")
            append("Lucy: \(result)\n\n")
            return true
        }

        if lowered == "use chrome"
            || lowered == "use google chrome"
            || lowered == "switch to chrome"
            || lowered == "open things in chrome" {
            let result = setBrowserPreference("Google Chrome")
            append("Lucy: \(result)\n\n")
            return true
        }

        if lowered == "use safari"
            || lowered == "switch to safari"
            || lowered == "open things in safari" {
            let result = setBrowserPreference("Safari")
            append("Lucy: \(result)\n\n")
            return true
        }

        if lowered == "use default browser"
            || lowered == "use system default browser" {
            let result = setBrowserPreference("default")
            append("Lucy: \(result)\n\n")
            return true
        }

        if lowered.hasPrefix("search youtube for ") {
            let query = String(cleaned.dropFirst("search youtube for ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !query.isEmpty {
                let result = openYouTubeSearch(query)
                append("Lucy: \(result)\n\n")
                return true
            }
        }

        if lowered.hasPrefix("youtube ") {
            let query = String(cleaned.dropFirst("youtube ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !query.isEmpty {
                let result = openYouTubeSearch(query)
                append("Lucy: \(result)\n\n")
                return true
            }
        }

        if lowered.hasPrefix("find me ") && lowered.contains("youtube") {
            var query = cleaned
            query = query.replacingOccurrences(of: "find me", with: "", options: [.caseInsensitive])
            query = query.replacingOccurrences(of: "on youtube", with: "", options: [.caseInsensitive])
            query = query.replacingOccurrences(of: "youtube", with: "", options: [.caseInsensitive])
            query = query.trimmingCharacters(in: .whitespacesAndNewlines)

            if !query.isEmpty {
                let result = openYouTubeSearch(query)
                append("Lucy: \(result)\n\n")
                return true
            }
        }

        if lowered.hasPrefix("find me ") && lowered.contains("video") {
            var query = cleaned
            query = query.replacingOccurrences(of: "find me", with: "", options: [.caseInsensitive])
            query = query.replacingOccurrences(of: "a video", with: "", options: [.caseInsensitive])
            query = query.replacingOccurrences(of: "video", with: "", options: [.caseInsensitive])
            query = query.trimmingCharacters(in: .whitespacesAndNewlines)

            if !query.isEmpty {
                let result = openYouTubeSearch(query)
                append("Lucy: \(result)\n\n")
                return true
            }
        }

        if lowered.hasPrefix("open ") && lowered.contains(".") {
            var url = String(cleaned.dropFirst("open ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !url.lowercased().hasPrefix("http://") && !url.lowercased().hasPrefix("https://") {
                url = "https://\(url)"
            }

            let result = openURL(url)
            append("Lucy: \(result)\n\n")
            return true
        }

        return false
    }

'''

    if "func routeNaturalCommand" not in updated:
        updated = replace_once(updated, helper_marker, helpers + "\n" + helper_marker)

    # Add command intro.
    if "/dev natural-commands" not in updated:
        updated = updated.replace(
            "/dev cursor-aware\n",
            "/dev cursor-aware\n        /dev natural-commands\n"
        )

    # Add dev command handler.
    dev_handler = r'''
        if lowered == "/dev natural-commands" {
            append("Lucy: asking my local dev agent to improve my natural command routing...\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runDevAgentApply(task: "natural-commands")

                DispatchQueue.main.async {
                    self.append("Lucy Dev Agent:\n\(result)\n\n")
                }
            }

            return
        }

'''

    if 'lowered == "/dev natural-commands"' not in updated:
        updated = updated.replace(
            '        if lowered == "/dev cursor-aware" {',
            dev_handler + '\n        if lowered == "/dev cursor-aware" {'
        )

    # Route natural commands before memory/normal Ollama chat.
    route_call = r'''
        if !userText.hasPrefix("/") && routeNaturalCommand(userText) {
            return
        }

'''

    if "routeNaturalCommand(userText)" not in updated:
        updated = updated.replace(
            "        let remembered = LucyMemory.shared.maybeRemember(userText)",
            route_call + "        let remembered = LucyMemory.shared.maybeRemember(userText)"
        )

    target.write_text(updated)

    ok, compile_output = compile_lucy()

    if not ok:
        restore_backup(backup_dir)
        rollback_ok, rollback_output = compile_lucy()

        report = write_apply_report(
            "natural_commands_failed",
            backup_dir,
            False,
            compile_output + "\n\nRollback compile OK: " + str(rollback_ok) + "\n" + rollback_output,
            ["swift_app/Sources/ChatWindowController.swift"],
            "Compile failed after adding natural command routing. Sources were rolled back."
        )

        print("Natural-commands update failed. Rolled back.")
        print(f"Report: {report}")
        raise SystemExit(1)

    report = write_apply_report(
        "natural_commands",
        backup_dir,
        True,
        compile_output,
        ["swift_app/Sources/ChatWindowController.swift"],
        "Added lightweight natural language routing for open Google, YouTube searches, browser preference, hide, and open URL."
    )

    print("Applied natural-commands update.")
    print(f"Backup: {backup_dir}")
    print(f"Report: {report}")


if __name__ == "__main__":
    run()
