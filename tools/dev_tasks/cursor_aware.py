from common import SOURCES, backup_sources, restore_backup, compile_lucy, write_apply_report


def run():
    backup_dir = backup_sources()
    app_delegate = SOURCES / "AppDelegate.swift"

    if not app_delegate.exists():
        raise SystemExit("Could not find AppDelegate.swift")

    original = app_delegate.read_text()
    updated = original

    already_has_timer = "var cursorTimer: Timer?" in updated
    already_starts = "startCursorAwareness()" in updated
    already_has_method = "func startCursorAwareness()" in updated

    if already_has_timer and already_starts and already_has_method:
        ok, compile_output = compile_lucy()

        report = write_apply_report(
            "cursor_aware",
            backup_dir,
            ok,
            compile_output,
            ["swift_app/Sources/AppDelegate.swift"],
            "Cursor awareness already appears to be installed. No source changes were needed."
        )

        print("Cursor-aware already installed. No changes needed.")
        print(f"Backup: {backup_dir}")
        print(f"Report: {report}")

        if not ok:
            raise SystemExit(1)

        return

    if not already_has_timer:
        old = """    var wanderTimer: Timer?
    var moodTimer: Timer?
    var animationTimer: Timer?
    var isHidden = false
"""
        new = """    var wanderTimer: Timer?
    var moodTimer: Timer?
    var animationTimer: Timer?
    var cursorTimer: Timer?
    var isHidden = false
"""
        if old not in updated:
            print("Could not find timer property block.")
            raise SystemExit(1)
        updated = updated.replace(old, new, 1)

    if not already_starts:
        old = """        startAnimation()
        startWandering()
        startIdleMoods()
"""
        new = """        startAnimation()
        startWandering()
        startIdleMoods()
        startCursorAwareness()
"""
        if old not in updated:
            print("Could not find startup loop block.")
            raise SystemExit(1)
        updated = updated.replace(old, new, 1)

    if not already_has_method:
        marker = "    func startAnimation() {"
        if marker not in updated:
            print("Could not find startAnimation insertion point.")
            raise SystemExit(1)

        cursor_method = r'''    func startCursorAwareness() {
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            if self.isHidden { return }

            let mouse = NSEvent.mouseLocation
            let frame = self.window.frame
            let center = NSPoint(x: frame.midX, y: frame.midY)

            let dx = mouse.x - center.x
            let dy = mouse.y - center.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance < 90 {
                LucyRuntime.shared.facingRight = dx >= 0
                self.petView.setState(.thinking, mood: "boop?")
            } else if distance < 170 {
                LucyRuntime.shared.facingRight = dx >= 0
                self.petView.setState(.idle, mood: "watching 👀")
            }
        }
    }

'''
        updated = updated.replace(marker, cursor_method + marker, 1)

    app_delegate.write_text(updated)

    ok, compile_output = compile_lucy()

    if not ok:
        restore_backup(backup_dir)
        rollback_ok, rollback_output = compile_lucy()

        report = write_apply_report(
            "cursor_aware_failed",
            backup_dir,
            False,
            compile_output + "\n\nRollback compile OK: " + str(rollback_ok) + "\n" + rollback_output,
            ["swift_app/Sources/AppDelegate.swift"],
            "Compile failed after adding cursor awareness. Sources were rolled back."
        )

        print("Cursor-aware update failed. Rolled back.")
        print(f"Report: {report}")
        raise SystemExit(1)

    report = write_apply_report(
        "cursor_aware",
        backup_dir,
        True,
        compile_output,
        ["swift_app/Sources/AppDelegate.swift"],
        "Added cursor awareness, or filled in missing cursor-awareness pieces."
    )

    print("Applied cursor-aware update.")
    print(f"Backup: {backup_dir}")
    print(f"Report: {report}")


if __name__ == "__main__":
    run()
