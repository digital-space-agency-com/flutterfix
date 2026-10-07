#!/bin/bash
# Tests the Claude token on your clipboard in isolation, and stores it as a
# GitHub secret only if the test passes. The token is never printed.
#
# 1. Run `claude setup-token` and copy the token it prints (sk-ant-...).
# 2. Run:  scripts/store-claude-token.sh owner/app-repo
#
# Type the command rather than pasting it: pasting replaces the clipboard, and
# the token would be lost.
set -u
REPO="${1:?Usage: store-claude-token.sh owner/repo}"

# The terminal wraps the long token over two lines when you copy it; join them.
t="$(pbpaste | tr -d '\n\r ')"
echo "token length: ${#t} (expected about 100 to 110)"

case "$t" in
  sk-ant-*) ;;
  *)
    echo "The clipboard does not hold a token (it should start with sk-ant-)."
    echo "Copy the token again, then run this script. Do not copy anything else first."
    exit 1
    ;;
esac

# A throwaway config folder so your own logged-in session cannot hide a bad token.
if CLAUDE_CONFIG_DIR="$(mktemp -d)" CLAUDE_CODE_OAUTH_TOKEN="$t" claude -p "reply with the single word ok"; then
  printf '%s' "$t" | gh secret set CLAUDE_CODE_OAUTH_TOKEN -R "$REPO" && echo "STORED in $REPO"
else
  echo "The token was rejected, so it was NOT stored."
  echo "Run 'claude setup-token' again and copy the new token."
  exit 1
fi
