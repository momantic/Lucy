-- Copies provided text to macOS clipboard.
-- Usage:
-- osascript tools/copy_to_clipboard.applescript "text here"

on run argv
    if (count of argv) is 0 then error "Missing text"
    set the clipboard to item 1 of argv
end run
