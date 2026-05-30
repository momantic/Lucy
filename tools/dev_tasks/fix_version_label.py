from common import SOURCES, backup_sources, restore_backup, compile_lucy, write_apply_report


def run():
    backup_dir = backup_sources()
    target = SOURCES / "AppDelegate.swift"

    if not target.exists():
        raise SystemExit("Could not find AppDelegate.swift")

    original = target.read_text()
    updated = original.replace(
        "Lucy Dev Mode v0.4 started",
        "Lucy Dev Mode v0.5 started"
    )

    if updated == original:
        report = write_apply_report(
            "fix_version_label",
            backup_dir,
            True,
            "No source changes were needed.",
            ["swift_app/Sources/AppDelegate.swift"],
            "Startup version label already appears updated."
        )
        print("No version label changes were needed.")
        print(f"Report: {report}")
        return

    target.write_text(updated)
    ok, compile_output = compile_lucy()

    if not ok:
        restore_backup(backup_dir)
        rollback_ok, rollback_output = compile_lucy()
        report = write_apply_report(
            "fix_version_label_failed",
            backup_dir,
            False,
            compile_output + "\n\nRollback compile OK: " + str(rollback_ok) + "\n" + rollback_output,
            ["swift_app/Sources/AppDelegate.swift"],
            "Compile failed after version-label update. Sources were rolled back."
        )
        print("Version-label update failed. Rolled back.")
        print(f"Report: {report}")
        raise SystemExit(1)

    report = write_apply_report(
        "fix_version_label",
        backup_dir,
        True,
        compile_output,
        ["swift_app/Sources/AppDelegate.swift"],
        "Updated Terminal startup label from Dev Mode v0.4 to Dev Mode v0.5."
    )

    print("Applied fix-version-label update.")
    print(f"Backup: {backup_dir}")
    print(f"Report: {report}")


if __name__ == "__main__":
    run()
