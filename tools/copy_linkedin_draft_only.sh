#!/bin/zsh
set -e

POST="/tmp/lucy_linkedin_post.txt"

if [ ! -f "$POST" ]; then
  echo "Missing draft post: $POST"
  echo "Run: tools/linkedin_full_draft_auto.sh \"topic here\""
  exit 1
fi

cat "$POST" | pbcopy

echo "Copied LinkedIn draft to clipboard."
echo "Now go to LinkedIn composer and press Command+V manually."
