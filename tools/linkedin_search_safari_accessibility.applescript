-- Opens LinkedIn search in Safari.
-- Does not execute JavaScript.
-- Usage:
-- osascript tools/linkedin_search_safari_accessibility.applescript "FDA 510(k) AI agents"

on run argv
    if (count of argv) is 0 then error "Missing topic"
    set topic to item 1 of argv
    set encodedTopic to my urlEncode(topic)
    set targetUrl to "https://www.linkedin.com/search/results/content/?keywords=" & encodedTopic

    tell application "Safari"
        activate
        if (count of windows) = 0 then
            make new document with properties {URL:targetUrl}
        else
            set URL of current tab of front window to targetUrl
        end if
    end tell
end run

on urlEncode(input)
    set theChars to the characters of input
    set encoded to ""
    repeat with c in theChars
        set ch to c as string
        if ch is " " then
            set encoded to encoded & "%20"
        else if ch is "#" then
            set encoded to encoded & "%23"
        else if ch is "&" then
            set encoded to encoded & "%26"
        else if ch is "+" then
            set encoded to encoded & "%2B"
        else if ch is "/" then
            set encoded to encoded & "%2F"
        else if ch is "?" then
            set encoded to encoded & "%3F"
        else
            set encoded to encoded & ch
        end if
    end repeat
    return encoded
end urlEncode
