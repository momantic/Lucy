-- Pastes current clipboard into the focused field.
-- Requires Accessibility permission.

tell application "System Events"
    keystroke "v" using command down
end tell
