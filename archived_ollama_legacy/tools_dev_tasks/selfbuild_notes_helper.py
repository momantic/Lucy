from common import SOURCES, backup_sources, restore_backup, compile_lucy, write_apply_report


NOTES_HELPER_METHODS = r'''    func escapeAppleScriptString(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    func writeAppleNote(title: String, body: String) -> String {
        let safeTitle = escapeAppleScriptString(title)
        let safeBody = escapeAppleScriptString(body)

        let script = """
        tell application "Notes"
            activate
            make new note with properties {name:"\(safeTitle)", body:"\(safeBody)"}
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let out = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                return "Created a new Apple Notes note titled: \(title)"
            }

            let details = [out, err]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")

            return """
            I tried to create the note, but macOS blocked or failed the AppleScript.

            Details:
            \(details)

            You may need to allow Terminal/Lucy automation permissions in:
            System Settings → Privacy & Security → Automation
            """
        } catch {
            return "Could not run Apple Notes automation: \(error.localizedDescription)"
        }
    }

    func createMotivationalNote(from request: String) -> String {
        let prompt = """
        You are Lucy, a kind local AI desktop pet.

        The user wants a motivational note in Apple Notes.

        User request:
        \(request)

        Write a short motivational note.
        Requirements:
        - 2 to 5 sentences
        - warm, encouraging, and personal
        - no clichés if possible
        - output only the note body
        """

        let noteBody = stripTerminalEscapes(runOllama(prompt: prompt))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let finalBody = noteBody.isEmpty
            ? "You are building something real. Keep going, one small step at a time."
            : noteBody

        return writeAppleNote(title: "Motivation from Lucy", body: finalBody)
    }

'''


def insert_before(text: str, marker: str, insertion: str) -> str:
    if marker not in text:
        raise ValueError(f"Could not find marker: {marker}")
    return text.replace(marker, insertion + "\n" + marker, 1)


def run():
    backup_dir = backup_sources()
    target = SOURCES / "ChatWindowController.swift"

    if not target.exists():
        raise SystemExit("Could not find ChatWindowController.swift")

    original = target.read_text()
    updated = original
    changed = False

    if "func writeAppleNote(title: String, body: String)" not in updated:
        updated = insert_before(
            updated,
            "    func runSelfBuild(goal: String) -> String {",
            NOTES_HELPER_METHODS
        )
        changed = True

    if 'lowered.contains("notes app")' not in updated:
        handler = r'''
        if lowered.contains("notes app")
            || lowered.contains("apple notes")
            || lowered.contains("write a note")
            || lowered.contains("create a note") {

            append("Lucy: writing a note in Apple Notes...\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.createMotivationalNote(from: userText)

                DispatchQueue.main.async {
                    self.append("Lucy:\n\(result)\n\n")
                }
            }

            return
        }

'''
        updated = insert_before(
            updated,
            "        if !userText.hasPrefix(\"/\") && routeNaturalSelfBuild(userText) {",
            handler
        )
        changed = True

    if "/selfbuild add notes helper" not in updated:
        updated = updated.replace(
            "/selfbuild add gmail draft helper\n",
            "/selfbuild add gmail draft helper\n        /selfbuild add notes helper\n"
        )
        changed = True

    if not changed:
        ok, compile_output = compile_lucy()
        report = write_apply_report(
            "selfbuild_notes_helper",
            backup_dir,
            ok,
            compile_output,
            ["swift_app/Sources/ChatWindowController.swift"],
            "Notes helper already appears to be installed. No source changes were needed."
        )
        print("Notes helper already installed.")
        print(f"Report: {report}")
        if not ok:
            raise SystemExit(1)
        return

    target.write_text(updated)

    ok, compile_output = compile_lucy()

    if not ok:
        restore_backup(backup_dir)
        rollback_ok, rollback_output = compile_lucy()
        report = write_apply_report(
            "selfbuild_notes_helper_failed",
            backup_dir,
            False,
            compile_output + "\n\nRollback compile OK: " + str(rollback_ok) + "\n" + rollback_output,
            ["swift_app/Sources/ChatWindowController.swift"],
            "Compile failed after adding Notes helper. Sources were rolled back."
        )
        print("Notes helper selfbuild failed. Rolled back.")
        print(f"Report: {report}")
        raise SystemExit(1)

    report = write_apply_report(
        "selfbuild_notes_helper",
        backup_dir,
        True,
        compile_output,
        ["swift_app/Sources/ChatWindowController.swift"],
        "Lucy selfbuilt an Apple Notes helper. It can create new notes via AppleScript. It does not delete or edit existing notes."
    )

    print("Selfbuilt Notes helper successfully.")
    print(f"Backup: {backup_dir}")
    print(f"Report: {report}")


if __name__ == "__main__":
    run()
