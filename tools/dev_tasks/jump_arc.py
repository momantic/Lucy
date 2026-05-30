from common import SOURCES, backup_sources, restore_backup, compile_lucy, write_apply_report


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        raise ValueError("Expected block not found.")
    return text.replace(old, new, 1)


def run():
    backup_dir = backup_sources()
    target = SOURCES / "AppDelegate.swift"

    if not target.exists():
        raise SystemExit("Could not find AppDelegate.swift")

    original = target.read_text()
    updated = original

    if "func performHopArc" in updated:
        ok, compile_output = compile_lucy()
        report = write_apply_report(
            "jump_arc",
            backup_dir,
            ok,
            compile_output,
            ["swift_app/Sources/AppDelegate.swift"],
            "Jump arc already installed. No source changes were needed."
        )
        print("Jump arc already installed.")
        print(f"Report: {report}")
        if not ok:
            raise SystemExit(1)
        return

    old_hop_block = """                let dx = CGFloat([-60, -40, 40, 60].randomElement()!)
                let dy = CGFloat([30, 45].randomElement()!)

                LucyRuntime.shared.facingRight = dx >= 0

                frame.origin.x = max(screen.minX, min(frame.origin.x + dx, screen.maxX - frame.width))
                frame.origin.y = max(screen.minY, min(frame.origin.y + dy, screen.maxY - frame.height))

                self.petView.setState(.hop, mood: LucyRuntime.shared.facingRight ? "hop →" : "← hop")
                self.window.setFrame(frame, display: true, animate: true)
                LucyRuntime.shared.hopCount += 1
                LucyRuntime.shared.log("Lucy hopped")
"""

    new_hop_block = """                let dx = CGFloat([-70, -50, 50, 70].randomElement()!)
                LucyRuntime.shared.facingRight = dx >= 0

                self.petView.setState(.hop, mood: LucyRuntime.shared.facingRight ? "hop →" : "← hop")
                self.performHopArc(dx: dx)
                LucyRuntime.shared.hopCount += 1
                LucyRuntime.shared.log("Lucy hopped with arc")
"""

    try:
        updated = replace_once(updated, old_hop_block, new_hop_block)
    except ValueError:
        print("Could not find old hop block. No changes made.")
        report = write_apply_report(
            "jump_arc_failed",
            backup_dir,
            False,
            "Old hop block not found.",
            ["swift_app/Sources/AppDelegate.swift"],
            "The task could not safely locate the old hop movement block."
        )
        print(f"Report: {report}")
        raise SystemExit(1)

    insert_marker = "    func startIdleMoods() {"

    hop_method = r'''    func performHopArc(dx: CGFloat) {
        guard let screen = NSScreen.main?.visibleFrame else { return }

        let startFrame = self.window.frame
        var endFrame = startFrame

        endFrame.origin.x = max(screen.minX, min(startFrame.origin.x + dx, screen.maxX - startFrame.width))
        endFrame.origin.y = max(screen.minY, min(startFrame.origin.y + 10, screen.maxY - startFrame.height))

        var peakFrame = startFrame
        peakFrame.origin.x = (startFrame.origin.x + endFrame.origin.x) / 2
        peakFrame.origin.y = min(startFrame.origin.y + 70, screen.maxY - startFrame.height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.window.animator().setFrame(peakFrame, display: true)
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.window.animator().setFrame(endFrame, display: true)
            }
        }
    }

'''

    if insert_marker not in updated:
        print("Could not find startIdleMoods insertion point.")
        raise SystemExit(1)

    updated = updated.replace(insert_marker, hop_method + insert_marker, 1)
    target.write_text(updated)

    ok, compile_output = compile_lucy()

    if not ok:
        restore_backup(backup_dir)
        rollback_ok, rollback_output = compile_lucy()
        report = write_apply_report(
            "jump_arc_failed",
            backup_dir,
            False,
            compile_output + "\n\nRollback compile OK: " + str(rollback_ok) + "\n" + rollback_output,
            ["swift_app/Sources/AppDelegate.swift"],
            "Compile failed after adding jump arc. Sources were rolled back."
        )
        print("Jump arc update failed. Rolled back.")
        print(f"Report: {report}")
        raise SystemExit(1)

    report = write_apply_report(
        "jump_arc",
        backup_dir,
        True,
        compile_output,
        ["swift_app/Sources/AppDelegate.swift"],
        "Added two-stage hop arc animation so Lucy jumps upward then lands instead of sliding."
    )

    print("Applied jump-arc update.")
    print(f"Backup: {backup_dir}")
    print(f"Report: {report}")


if __name__ == "__main__":
    run()
