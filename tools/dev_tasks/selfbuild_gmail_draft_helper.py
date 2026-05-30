from common import SOURCES, backup_sources, restore_backup, compile_lucy, write_apply_report


GMAIL_HELPER_METHODS = r'''    var lastEmailDraft: String {
        get {
            return UserDefaults.standard.string(forKey: "lucy.lastEmailDraft") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lucy.lastEmailDraft")
        }
    }

    func saveLastEmailDraft(_ draft: String) {
        lastEmailDraft = draft
    }

    func copyTextToClipboard(_ text: String) -> String {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "There is no text to copy yet."
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        return "Copied draft to clipboard."
    }

    func openGmail() -> String {
        return openURL("https://mail.google.com/mail/u/0/#inbox")
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

    if "func openGmail()" not in updated:
        updated = insert_before(
            updated,
            "    func runDevAgentApply(task: String) -> String {",
            GMAIL_HELPER_METHODS
        )
        changed = True

    if "saveLastEmailDraft(draft)" not in updated:
        updated = updated.replace(
            """        let draft = runOllama(prompt: prompt)

        return \"\"\"
        Here is a draft:

        \\(draft)

        I have not sent anything.
        \"\"\"
""",
            """        let draft = runOllama(prompt: prompt)
        saveLastEmailDraft(draft)

        return \"\"\"
        Here is a draft:

        \\(draft)

        I have saved this as your latest email draft.
        I have not sent anything.

        You can now say:
        - copy email draft
        - open gmail
        \"\"\"
"""
        )
        changed = True

    if 'lowered == "copy email draft"' not in updated:
        handler = r'''
        if lowered == "copy email draft"
            || lowered == "copy last email draft"
            || lowered == "copy the email draft" {
            let result = copyTextToClipboard(lastEmailDraft)
            append("Lucy: \(result)\n\n")
            return
        }

        if lowered == "open gmail"
            || lowered == "open google mail"
            || lowered == "open email" {
            let result = openGmail()
            append("Lucy: \(result)\n\n")
            return
        }

'''
        updated = insert_before(
            updated,
            "        if lowered.contains(\"write an email\")",
            handler
        )
        changed = True

    if "/selfbuild add gmail draft helper" not in updated:
        updated = updated.replace(
            "/selfbuild add email helper\n",
            "/selfbuild add email helper\n        /selfbuild add gmail draft helper\n"
        )
        changed = True

    if "write an email to Professor" in updated and "copy email draft" not in updated.split("You can talk naturally:", 1)[0]:
        updated = updated.replace(
            "- write an email to Professor Smith asking about research opportunities\n",
            "- write an email to Professor Smith asking about research opportunities\n        - copy email draft\n        - open gmail\n"
        )
        changed = True

    if not changed:
        ok, compile_output = compile_lucy()
        report = write_apply_report(
            "selfbuild_gmail_draft_helper",
            backup_dir,
            ok,
            compile_output,
            ["swift_app/Sources/ChatWindowController.swift"],
            "Gmail draft helper already appears to be installed. No source changes were needed."
        )
        print("Gmail draft helper already installed.")
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
            "selfbuild_gmail_draft_helper_failed",
            backup_dir,
            False,
            compile_output + "\n\nRollback compile OK: " + str(rollback_ok) + "\n" + rollback_output,
            ["swift_app/Sources/ChatWindowController.swift"],
            "Compile failed after adding Gmail draft helper. Sources were rolled back."
        )
        print("Gmail draft helper selfbuild failed. Rolled back.")
        print(f"Report: {report}")
        raise SystemExit(1)

    report = write_apply_report(
        "selfbuild_gmail_draft_helper",
        backup_dir,
        True,
        compile_output,
        ["swift_app/Sources/ChatWindowController.swift"],
        "Lucy selfbuilt a Gmail draft helper: saves latest email draft, copies it to clipboard, and opens Gmail. It does not send email."
    )

    print("Selfbuilt Gmail draft helper successfully.")
    print(f"Backup: {backup_dir}")
    print(f"Report: {report}")


if __name__ == "__main__":
    run()
