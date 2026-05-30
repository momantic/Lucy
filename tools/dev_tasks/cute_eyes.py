from common import SOURCES, backup_sources, restore_backup, compile_lucy, write_apply_report, replace_function


NEW_DRAW_EYES = """    func drawEyes(centerX: CGFloat, centerY: CGFloat, eyeOffsetX: CGFloat) {
        let eyeY = centerY + 32

        let isBlinkFrame = state == .idle && frameIndex % 18 == 0

        if isBlinkFrame {
            NSColor.white.withAlphaComponent(0.95).setStroke()

            let leftBlink = NSBezierPath()
            leftBlink.lineWidth = 3
            leftBlink.lineCapStyle = .round
            leftBlink.move(to: NSPoint(x: centerX - 25, y: eyeY + 10))
            leftBlink.line(to: NSPoint(x: centerX - 5, y: eyeY + 10))
            leftBlink.stroke()

            let rightBlink = NSBezierPath()
            rightBlink.lineWidth = 3
            rightBlink.lineCapStyle = .round
            rightBlink.move(to: NSPoint(x: centerX + 5, y: eyeY + 10))
            rightBlink.line(to: NSPoint(x: centerX + 25, y: eyeY + 10))
            rightBlink.stroke()

            return
        }

        // large cute jumping-spider eyes
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: centerX - 30, y: eyeY, width: 26, height: 29)).fill()
        NSBezierPath(ovalIn: NSRect(x: centerX + 4, y: eyeY, width: 26, height: 29)).fill()

        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: centerX - 21 + eyeOffsetX, y: eyeY + 6, width: 12, height: 14)).fill()
        NSBezierPath(ovalIn: NSRect(x: centerX + 13 + eyeOffsetX, y: eyeY + 6, width: 12, height: 14)).fill()

        // glossy highlights
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: centerX - 18 + eyeOffsetX, y: eyeY + 16, width: 4.5, height: 4.5)).fill()
        NSBezierPath(ovalIn: NSRect(x: centerX + 16 + eyeOffsetX, y: eyeY + 16, width: 4.5, height: 4.5)).fill()

        // tiny secondary sparkle
        NSColor.white.withAlphaComponent(0.65).setFill()
        NSBezierPath(ovalIn: NSRect(x: centerX - 12 + eyeOffsetX, y: eyeY + 10, width: 2.2, height: 2.2)).fill()
        NSBezierPath(ovalIn: NSRect(x: centerX + 22 + eyeOffsetX, y: eyeY + 10, width: 2.2, height: 2.2)).fill()
    }"""


def run():
    backup_dir = backup_sources()
    target = SOURCES / "LucySpriteView.swift"

    if not target.exists():
        raise SystemExit("Could not find LucySpriteView.swift")

    original = target.read_text()

    try:
        updated = replace_function(
            original,
            "    func drawEyes(centerX: CGFloat, centerY: CGFloat, eyeOffsetX: CGFloat) {",
            NEW_DRAW_EYES
        )
    except ValueError as error:
        report = write_apply_report(
            "cute_eyes_failed",
            backup_dir,
            False,
            str(error),
            ["swift_app/Sources/LucySpriteView.swift"],
            "Could not safely replace drawEyes."
        )
        print("Cute-eyes update failed before editing.")
        print(f"Report: {report}")
        raise SystemExit(1)

    if updated == original:
        report = write_apply_report(
            "cute_eyes",
            backup_dir,
            True,
            "No source changes were needed.",
            ["swift_app/Sources/LucySpriteView.swift"],
            "drawEyes already appears to match the cute-eyes version."
        )
        print("No cute-eyes changes were needed.")
        print(f"Report: {report}")
        return

    target.write_text(updated)
    ok, compile_output = compile_lucy()

    if not ok:
        restore_backup(backup_dir)
        rollback_ok, rollback_output = compile_lucy()
        report = write_apply_report(
            "cute_eyes_failed",
            backup_dir,
            False,
            compile_output + "\n\nRollback compile OK: " + str(rollback_ok) + "\n" + rollback_output,
            ["swift_app/Sources/LucySpriteView.swift"],
            "Compile failed after editing. Sources were rolled back."
        )
        print("Cute-eyes update failed. Rolled back.")
        print(f"Report: {report}")
        raise SystemExit(1)

    report = write_apply_report(
        "cute_eyes",
        backup_dir,
        True,
        compile_output,
        ["swift_app/Sources/LucySpriteView.swift"],
        "Made Lucy's eyes larger, glossier, and added idle blink."
    )

    print("Applied cute-eyes update.")
    print(f"Backup: {backup_dir}")
    print(f"Report: {report}")


if __name__ == "__main__":
    run()
