from common import SOURCES, backup_sources, restore_backup, compile_lucy, write_apply_report


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        raise ValueError(f"Could not find expected block:\n{old[:200]}...")
    return text.replace(old, new, 1)


def run():
    backup_dir = backup_sources()
    app_delegate = SOURCES / "AppDelegate.swift"

    if not app_delegate.exists():
        raise SystemExit("Could not find AppDelegate.swift")

    original = app_delegate.read_text()
    updated = original

    # 1. Add a timer property.
    updated = replace_once(
        updated,
        """    var wanderTimer: Timer?
    var moodTimer: Timer?
    var animationTimer: Timer?
    var isHidden = false
""",
        """    var wanderTimer: Timer?
    var moodTimer: Timer?
    var animationTimer: Timer?
    var cursorTimer: Timer?
    var isHidden = false
"""
    )

    # 2. Start cursor awareness after other loops.
    updated = replace_once(
        updated,
        """        startAnimation()
        startWandering()
        startIdleMoods()
""",
        """        startAnimation()
        startWandering()
        startIdleMoods()
        startCursorAwareness()
"""
    )

    # 3. Add cursor awareness method before startAnimation().
    marker = "    func startAnimation() {"
    if "func startCursorAwareness()" not in updated:
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
        "Added a cursor-awareness loop so Lucy notices the mouse nearby and reacts with watching/boop moods."
    )

    print("Applied cursor-aware update.")
    print(f"Backup: {backup_dir}")
    print(f"Report: {report}")


if __name__ == "__main__":
    run()
