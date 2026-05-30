from common import SOURCES, backup_sources, restore_backup, compile_lucy, write_apply_report


EMAIL_HELPER_METHOD = r'''    func draftEmailFromRequest(_ request: String) -> String {
        var cleaned = request.trimmingCharacters(in: .whitespacesAndNewlines)

        let removablePhrases = [
            "write an email for me",
            "write an email",
            "draft an email for me",
            "draft an email",
            "email for me"
        ]

        for phrase in removablePhrases {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: "", options: [.caseInsensitive])
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            return """
            I can draft it. Tell me:
            - who it is for
            - what you want to say
            - the tone, like polite, casual, professional, or short
            """
        }

        let prompt = """
        You are Lucy, a helpful local AI desktop pet.

        Draft an email based on this request:
        \(request)

        Requirements:
        - Include a clear subject line.
        - Keep it polished and natural.
        - Do not invent specific facts.
        - If recipient/name/details are missing, write a useful draft with placeholders.
        - Do not send the email. Only draft it.

        Output format:
        Subject: ...

        Dear ...,

        ...

        Best,
        Mo
        """

        let draft = runOllama(prompt: prompt)

        return """
        Here is a draft:

        \(draft)

        I have not sent anything.
        """
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

    if "func draftEmailFromRequest" not in updated:
        updated = insert_before(
            updated,
            "    func askOllama(_ userText: String) -> String {",
            EMAIL_HELPER_METHOD
        )
        changed = True

    if 'lowered.contains("write an email")' not in updated:
        handler = r'''
        if lowered.contains("write an email")
            || lowered.contains("draft an email")
            || lowered.hasPrefix("email ") {

            append("Lucy: drafting an email for you...\n")

            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.draftEmailFromRequest(userText)

                DispatchQueue.main.async {
                    self.append("Lucy:\n\(result)\n\n")
                }
            }

            return
        }

'''
        updated = insert_before(
            updated,
            "        if !userText.hasPrefix(\"/\") && routeNaturalCommand(userText) {",
            handler
        )
        changed = True

    if "write an email to Professor" not in updated:
        updated = updated.replace(
            "- hide for a bit\n",
            "- hide for a bit\n        - write an email to Professor Smith asking about research opportunities\n"
        )
        changed = True

    if not changed:
        ok, compile_output = compile_lucy()
        report = write_apply_report(
            "selfbuild_email_helper",
            backup_dir,
            ok,
            compile_output,
            ["swift_app/Sources/ChatWindowController.swift"],
            "Email helper already appears to be installed. No source changes were needed."
        )
        print("Email helper already installed.")
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
            "selfbuild_email_helper_failed",
            backup_dir,
            False,
            compile_output + "\n\nRollback compile OK: " + str(rollback_ok) + "\n" + rollback_output,
            ["swift_app/Sources/ChatWindowController.swift"],
            "Compile failed after adding email helper. Sources were rolled back."
        )
        print("Email helper selfbuild failed. Rolled back.")
        print(f"Report: {report}")
        raise SystemExit(1)

    report = write_apply_report(
        "selfbuild_email_helper",
        backup_dir,
        True,
        compile_output,
        ["swift_app/Sources/ChatWindowController.swift"],
        "Lucy selfbuilt an email drafting helper. Natural requests like 'write an email...' now draft email text in chat."
    )

    print("Selfbuilt email helper successfully.")
    print(f"Backup: {backup_dir}")
    print(f"Report: {report}")


if __name__ == "__main__":
    run()
