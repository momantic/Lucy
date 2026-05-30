from common import SOURCES, backup_sources, restore_backup, compile_lucy, write_apply_report


def run():
    backup_dir = backup_sources()
    target = SOURCES / "AppDelegate.swift"

    if not target.exists():
        raise SystemExit("Could not find AppDelegate.swift")

    original = target.read_text()
    updated = original

    replacements = [
        ("withTimeInterval: 0.35", "withTimeInterval: 0.18"),
        ("withTimeInterval: 2.5", "withTimeInterval: 2.0"),
        ("withTimeInterval: 6.0", "withTimeInterval: 5.0"),
    ]

    for old, new in replacements:
        updated = updated.replace(old, new)

    if updated == original:
        report = write_apply_report(
            "animation_smoother",
            backup_dir,
            True,
            "No source changes were needed.",
            ["swift_app/Sources/AppDelegate.swift"],
            "Animation timing values already appear to be updated."
        )
        print("No animation timing changes were needed.")
        print(f"Report: {report}")
        return

    target.write_text(updated)
    ok, compile_output = compile_lucy()

    if not ok:
        restore_backup(backup_dir)
        rollback_ok, rollback_output = compile_lucy()
        report = write_apply_report(
            "animation_smoother_failed",
            backup_dir,
            False,
            compile_output + "\n\nRollback compile OK: " + str(rollback_ok) + "\n" + rollback_output,
            ["swift_app/Sources/AppDelegate.swift"],
            "Compile failed after editing. Sources were rolled back."
        )
        print("Animation smoother update failed. Rolled back.")
        print(f"Report: {report}")
        raise SystemExit(1)

    report = write_apply_report(
        "animation_smoother",
        backup_dir,
        True,
        compile_output,
        ["swift_app/Sources/AppDelegate.swift"],
        "Updated animation loop timing for smoother movement."
    )

    print("Applied animation-smoother update.")
    print(f"Backup: {backup_dir}")
    print(f"Report: {report}")


if __name__ == "__main__":
    run()
