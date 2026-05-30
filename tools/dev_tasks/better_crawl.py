from common import SOURCES, backup_sources, restore_backup, compile_lucy, write_apply_report, replace_function


NEW_DRAW_LEGS = """    func drawLegs(centerX: CGFloat, centerY: CGFloat, legSwing: CGFloat) {
        NSColor.black.setStroke()

        let phase = frameIndex % 4

        let frontSwing: CGFloat
        let midSwing: CGFloat
        let backSwing: CGFloat

        switch state {
        case .crawl:
            frontSwing = CGFloat([10, 2, -10, -2][phase])
            midSwing = CGFloat([-8, -2, 8, 2][phase])
            backSwing = CGFloat([6, -4, -6, 4][phase])
        case .hop:
            frontSwing = CGFloat([4, -2, -6, 2][phase])
            midSwing = CGFloat([-3, 3, -3, 3][phase])
            backSwing = CGFloat([-8, -4, 4, 8][phase])
        case .thinking:
            frontSwing = CGFloat([1, 0, -1, 0][phase])
            midSwing = CGFloat([0, 1, 0, -1][phase])
            backSwing = CGFloat([-1, 0, 1, 0][phase])
        default:
            frontSwing = CGFloat([2, 0, -2, 0][phase])
            midSwing = CGFloat([-1, 1, -1, 1][phase])
            backSwing = CGFloat([1, -1, 1, -1][phase])
        }

        let direction = facingMultiplier()

        let legs: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-28, 6, -68, 34 + frontSwing, frontSwing),
            (-31, -3, -74, 4 + midSwing, midSwing),
            (-28, -13, -66, -34 + backSwing, backSwing),
            (-15, -24, -40, -58 - backSwing, backSwing),

            (28, 6, 68, 34 - frontSwing, -frontSwing),
            (31, -3, 74, 4 - midSwing, -midSwing),
            (28, -13, 66, -34 - backSwing, -backSwing),
            (15, -24, 40, -58 + backSwing, -backSwing)
        ]

        for leg in legs {
            let path = NSBezierPath()
            path.lineWidth = 4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            let shoulder = NSPoint(x: centerX + leg.0, y: centerY + leg.1)
            let foot = NSPoint(x: centerX + leg.2 + (leg.4 * 0.25 * direction), y: centerY + leg.3)
            let knee = NSPoint(
                x: (shoulder.x + foot.x) / 2 + (leg.4 * 0.45 * direction),
                y: (shoulder.y + foot.y) / 2 + 7
            )

            path.move(to: shoulder)
            path.curve(to: foot, controlPoint1: knee, controlPoint2: knee)
            path.stroke()
        }
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
            "    func drawLegs(centerX: CGFloat, centerY: CGFloat, legSwing: CGFloat) {",
            NEW_DRAW_LEGS
        )
    except ValueError as error:
        report = write_apply_report(
            "better_crawl_failed",
            backup_dir,
            False,
            str(error),
            ["swift_app/Sources/LucySpriteView.swift"],
            "Could not safely replace drawLegs."
        )
        print("Better-crawl update failed before editing.")
        print(f"Report: {report}")
        raise SystemExit(1)

    if updated == original:
        report = write_apply_report(
            "better_crawl",
            backup_dir,
            True,
            "No source changes were needed.",
            ["swift_app/Sources/LucySpriteView.swift"],
            "drawLegs already appears to match the better-crawl version."
        )
        print("No better-crawl changes were needed.")
        print(f"Report: {report}")
        return

    target.write_text(updated)
    ok, compile_output = compile_lucy()

    if not ok:
        restore_backup(backup_dir)
        rollback_ok, rollback_output = compile_lucy()
        report = write_apply_report(
            "better_crawl_failed",
            backup_dir,
            False,
            compile_output + "\n\nRollback compile OK: " + str(rollback_ok) + "\n" + rollback_output,
            ["swift_app/Sources/LucySpriteView.swift"],
            "Compile failed after editing. Sources were rolled back."
        )
        print("Better-crawl update failed. Rolled back.")
        print(f"Report: {report}")
        raise SystemExit(1)

    report = write_apply_report(
        "better_crawl",
        backup_dir,
        True,
        compile_output,
        ["swift_app/Sources/LucySpriteView.swift"],
        "Replaced straight leg strokes with curved, phase-based leg motion for a more spider-like crawl."
    )

    print("Applied better-crawl update.")
    print(f"Backup: {backup_dir}")
    print(f"Report: {report}")


if __name__ == "__main__":
    run()
