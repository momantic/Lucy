#!/bin/zsh
set -e

echo "Lucy Bridge is running."
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
    echo "Lucy: researching visible LinkedIn content and drafting locally with MLX..."
    echo "Lucy: I will copy the final draft to your clipboard. You review and post manually."
    echo ""

    tools/lucy_linkedin_local.sh "$INPUT"

    echo ""
    echo "Lucy: Done. Open LinkedIn composer and press Command+V."
    echo ""
  else
    echo "Lucy: I only handle the LinkedIn local MLX command in this bridge right now."
    echo "Try: Lucy, write me a LinkedIn post about FDA 510(k) regulatory AI medical device software"
    echo ""
  fi
done
