-- Opens LinkedIn feed in Chrome.
-- User manually starts/clicks Post.

tell application "Google Chrome"
    activate
    if (count of windows) = 0 then make new window
    set URL of active tab of front window to "https://www.linkedin.com/feed/"
end tell
