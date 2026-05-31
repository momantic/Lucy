from common import SOURCES, backup_sources, restore_backup, compile_lucy, write_apply_report


def run():
    backup_dir = backup_sources()
    target = SOURCES / "ChatWindowController.swift"

    if not target.exists():
        raise SystemExit("Could not find ChatWindowController.swift")

    original = target.read_text()
    updated = original

    if 'lowered == "/time"' in updated:
        ok, compile_output = compile_lucy()
        report = write_apply_report(
            "generated_builtin_time_command",
            backup_dir,
            ok,
            compile_output,
            ["swift_app/Sources/ChatWindowController.swift"],
            "/time already exists. No source changes were needed."
        )
        print("/time command already installed.")
        print(f"Report: {report}")
        if not ok:
            raise SystemExit(1)
        return

    handler = '''        if lowered == "/time" || lowered == "time" || lowered == "what time is it" {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .medium
            let now = formatter.string(from: Date())

            append("Lucy: The current time is \\(now).\\n\\n")
            return
        }

'''

    marker = '        if lowered == "/ping" || lowered == "ping" {'

    if marker not in updated:
        marker = '        if lowered == "/memory"\n'

    if marker not in updated:
        report = write_apply_report(
            "generated_builtin_time_command_failed",
            backup_dir,
            False,
            "Could not find safe insertion point.",
            ["swift_app/Sources/ChatWindowController.swift"],
            "No source changes were made."
        )
        print("Could not find insertion point.")
        print(f"Report: {report}")
        raise SystemExit(1)

    updated = updated.replace(marker, handler + marker, 1)
    target.write_text(updated)

    ok, compile_output = compile_lucy()

    if not ok:
        restore_backup(backup_dir)
        rollback_ok, rollback_output = compile_lucy()
        report = write_apply_report(
            "generated_builtin_time_command_failed",
            backup_dir,
            False,
            compile_output + "\n\nRollback compile OK: " + str(rollback_ok) + "\n" + rollback_output,
            ["swift_app/Sources/ChatWindowController.swift"],
            "Compile failed after adding /time. Sources were rolled back."
        )
        print("/time command failed. Rolled back.")
        print(f"Report: {report}")
        raise SystemExit(1)

    report = write_apply_report(
        "generated_builtin_time_command",
        backup_dir,
        True,
        compile_output,
        ["swift_app/Sources/ChatWindowController.swift"],
        "Added /time command that replies with the current date and time."
    )

    print("Added /time command successfully.")
    print(f"Report: {report}")


if __name__ == "__main__":
    run()
