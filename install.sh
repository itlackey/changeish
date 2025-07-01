#!/usr/bin/env sh
set -eu

# Repository and filenames
REPO="itlackey/changeish"
SCRIPT_NAME="changes.sh"
PROMPT_DIR="prompts"
INSTALL_DIR=""
APP_DIR=""
VERSION=""
INSTALL_DIR_OVERRIDE=""

# 1. Remove existing changeish binary or symlink
if command -v changeish >/dev/null 2>&1; then
  OLD_PATH="$(command -v changeish)"
  rm -f "$OLD_PATH"
fi

# 2. Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR_OVERRIDE="$2"
      shift 2
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  # no extra shift
  break
done

# 3. Determine INSTALL_DIR
if [ -n "$INSTALL_DIR_OVERRIDE" ]; then
  INSTALL_DIR="$INSTALL_DIR_OVERRIDE"
elif [ -n "${INSTALL_PREFIX:-}" ]; then
  INSTALL_DIR="$INSTALL_PREFIX"
elif [ -w "/usr/local/bin" ]; then
  INSTALL_DIR="/usr/local/bin"
elif [ -d "$HOME/.local/bin" ]; then
  INSTALL_DIR="$HOME/.local/bin"
else
  INSTALL_DIR="$HOME/bin"
fi

# 4. Determine VERSION if not set
if [ -z "$VERSION" ]; then
  VERSION="$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | awk -F '"' '/"tag_name"/ {print $4; exit}')"
fi

# 5. Detect platform
detect_platform() {
  OS="$(uname -s)"
  case "$OS" in
    Linux*)
      if [ -f /etc/wsl.conf ] || grep -qi microsoft /proc/version 2>/dev/null; then
        printf 'windows'
      else
        printf 'linux'
      fi
      ;;
    Darwin*) printf 'macos' ;;
    CYGWIN*|MINGW*|MSYS*) printf 'windows' ;;
    *) printf 'unsupported' ;;
  esac
}
PLATFORM="$(detect_platform)"
if [ "$PLATFORM" = "unsupported" ]; then
  printf 'Error: Unsupported OS: %s\n' "$(uname -s)" >&2
  exit 1
fi

# 6. Compute APP_DIR based on PLATFORM
compute_app_dir() {
  case "$PLATFORM" in
    linux)
      printf '%s/changeish' "${XDG_DATA_HOME:-$HOME/.local/share}"
      ;;
    windows)
      printf '%s/changeish' "${LOCALAPPDATA:-$HOME/AppData/Local}"
      ;;
    macos)
      printf '%s/Library/Application Scripts/com.github.%s' "$HOME" "${REPO}"
      ;;
    *)
      printf 'Error: Unsupported platform: %s\n' "${PLATFORM}" >&2
      exit 1
      ;;
  esac
}
APP_DIR="$(compute_app_dir)"

# 7. Display planned installation
printf 'Installing version %s\n' "$VERSION"
printf 'Prompts → %s/%s\n' "$APP_DIR" "$PROMPT_DIR"
printf 'Changes.sh → %s/%s and symlink/copy at %s/changeish\n' "$APP_DIR" "$SCRIPT_NAME" "$INSTALL_DIR"

# 8. Create necessary directories
mkdir -p "$INSTALL_DIR" "$APP_DIR/$PROMPT_DIR"

# 9. Check Git version for sparse-checkout
if ! command -v git >/dev/null 2>&1; then
  printf 'Error: git is required to use changeish.\n' >&2
  exit 1
fi

# 10. Fetch prompts
TMP="$(mktemp -d)"
git  -c advice.detachedHead=false clone -q --depth 1 --branch "$VERSION" "https://github.com/$REPO.git" "$TMP"
cp -R "$TMP/$PROMPT_DIR"/* "$APP_DIR/$PROMPT_DIR/"
cp "$TMP/$SCRIPT_NAME" "$APP_DIR/"
chmod +x "$APP_DIR/$SCRIPT_NAME"

# 11. Install changes.sh and create symlink or fallback copy
if [ "$PLATFORM" = "windows" ]; then
  cp -f "$TMP/$SCRIPT_NAME" "$INSTALL_DIR/changeish"
else
  ln -sf "$TMP/$SCRIPT_NAME" "$INSTALL_DIR/changeish"
  cp -f "$TMP/$SCRIPT_NAME" "$INSTALL_DIR/changeish"
fi

rm -rf "$TMP"

# 12. Final PATH check
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;; 
  *) printf 'Warning: %s is not in your PATH.\n' "$INSTALL_DIR" ;;
esac
printf 'Installation complete!\n'
