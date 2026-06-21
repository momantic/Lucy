#!/bin/zsh
set -e

echo "Lucy Clipboard Bridge is running."
echo "This version avoids Swift/OCR and does not need Command Line Tools."
echo ""
echo "Type a Lucy command, then press Enter."
echo "Example:"
echo "Lucy, write me a LinkedIn post about FDA 510(k) regulatory AI medical device software"
echo ""
echo "Type /quit to stop."
echo ""

while true; do
  printf "You: "
  IFS= read -r INPUT

  if [ "$INPUT" = "/quit" ]; then
    echo "Lucy Bridge stopped."
    exit 0
  fi

  LOWER=$(echo "$INPUT" | tr '[:upper:]' '[:lower:]')

  if echo "$LOWER" | grep -q "linkedin post about\|write me a linkedin post about\|draft a linkedin post about\|make me a linkedin post about"; then
    echo ""
    echo "Lucy: I’ll open LinkedIn. Copy the page text when I ask, then I’ll draft locally with MLX."
    echo ""

    tools/lucy_linkedin_local_clipboard.sh "$INPUT"

    echo ""
    echo "Lucy: Done. Open LinkedIn composer and press Command+V."
    echo ""
  else
    echo "Lucy: This bridge only handles LinkedIn local MLX drafting right now."
    echo ""
  fi
done
