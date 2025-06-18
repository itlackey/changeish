#!/usr/bin/env bash
set -e
REPO="itlackey/changeish"
SCRIPT_NAME="changes.sh"
PROMPT_NAME="changelog_prompt.md"
get_latest_release() {
  curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | \
    grep '"tag_name"' | \
    sed -E 's/.*"([^"]+)".*/\1/'
}


INSTALL_DIR=""
VERSION=$(get_latest_release)

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done


# Determine install directory for script
if [[ -w /usr/local/bin ]]; then
    INSTALL_DIR="/usr/local/bin"
elif [[ -d "$HOME/.local/bin" ]]; then
    INSTALL_DIR="$HOME/.local/bin"
else
    INSTALL_DIR="$HOME/bin"
    mkdir -p "$INSTALL_DIR"
fi

# Build base URL
BASE_URL="https://raw.githubusercontent.com/$REPO/$VERSION"

# Download script to install dir
curl -fsSL -o "$INSTALL_DIR/changeish" "$BASE_URL/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/changeish"
echo "Installed changeish to $INSTALL_DIR"

# Download prompt to current directory
curl -fsSL -o "$PROMPT_NAME" "$BASE_URL/$PROMPT_NAME"
echo "Downloaded $PROMPT_NAME to $(pwd)"

# Warn if INSTALL_DIR is not in PATH
case ":$PATH:" in
  *:"$INSTALL_DIR":*)
    # Already in PATH, no warning
    ;;
  *)
    echo "Warning: $INSTALL_DIR is not in your PATH. Add it to use changeish from anywhere."
    ;;
esac