#!/usr/bin/env sh
set -eu

# Repository and filenames
REPO="itlackey/changeish"
SCRIPT_NAME="changes.sh"
PROMPT_DIR="prompts"
#PROMPT_NAME="${PROMPT_DIR}/prompt_template.md"
INSTALL_DIR=""
APP_DIR=""
VERSION=""

# 1. Remove existing changeish binary (does not remove configs or related files)
if CHANGEISH_PATH="$(command -v changeish)"; then
  if [ -f "${CHANGEISH_PATH}" ] && [ "${CHANGEISH_PATH}" != "/usr/bin/changeish" ]; then
    rm -f "${CHANGEISH_PATH}"
  fi
fi

# 2. Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

# 3. Determine INSTALL_DIR for script
if [ -w /usr/local/bin ]; then
  INSTALL_DIR="/usr/local/bin"
elif [ -d "${HOME}/.local/bin" ]; then
  INSTALL_DIR="${HOME}/.local/bin"
else
  INSTALL_DIR="${HOME}/bin"
fi

# 4. Before creating directories, display planned locations
printf 'Script will be installed to: %s/changeish\n' "${INSTALL_DIR}"

# 5. OS and WSL detection
get_app_dir() {
  OS_NAME=$(uname -s)
  case "${OS_NAME}" in
    Linux*)
      if [ -f /etc/wsl.conf ] || grep -qi microsoft /proc/version 2>/dev/null; then
        PLATFORM=windows
      else
        PLATFORM=linux
      fi
      ;;
    Darwin*) PLATFORM=macos ;;
    CYGWIN*|MINGW*|MSYS*) PLATFORM=windows ;;
    *)
      printf 'Error: Unsupported OS: %s\n' "${OS_NAME}" >&2
      exit 1
      ;;
  esac

  case "${PLATFORM}" in
    linux)
      printf '%s/changeish' "${XDG_DATA_HOME:-"${HOME}/.local/share"}"
      ;;
    windows)
      printf '%s/changeish' "${LOCALAPPDATA:-"${HOME:-USERPROFILE}/AppData/Local"}"
      ;;
    macos)
      printf '%s/Library/Application Scripts/com.example.changeish' "${HOME}"
      ;;
    *)
      printf 'Error: Unsupported platform: %s\n' "${PLATFORM}" >&2
      exit 1
      ;;
  esac
}

# 6. Set APP_DIR for storing prompt templates (not the main binary)
APP_DIR="$(get_app_dir)"

# 7. Before creating directories, display prompt folder location
printf 'Prompt templates will be stored in: %s/%s\n' "${APP_DIR}" "${PROMPT_DIR}"

# 8. Create directories
mkdir -p "${INSTALL_DIR}" "${APP_DIR}/${PROMPT_DIR}"

# 9. Fetch prompts folder via git sparse-checkout
fetch_prompts_sparse() {
  TMP=$(mktemp -d) || exit 1
  git clone --depth 1 --branch "${VERSION:-main}" --filter=blob:none --sparse \
    "https://github.com/${REPO}.git" "${TMP}"
  cd "${TMP}" || exit 1
  git sparse-checkout init --cone
  git sparse-checkout set "${PROMPT_DIR}"
  cp -R "${PROMPT_DIR}"/* "${APP_DIR}/${PROMPT_DIR}/"
  cd - >/dev/null 2>&1
  rm -rf "${TMP}"
}

if command -v git >/dev/null 2>&1; then
  fetch_prompts_sparse
else
  printf 'Error: git is required for installation of prompt templates.\n' >&2
  exit 1
fi

# 10. Determine latest version if not provided (using awk instead of jq)
if [ -z "${VERSION:-}" ]; then
  VERSION=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" |
    awk -F '"' '/"tag_name"/ {print $4; exit}')
fi

# 11. Download changeish script via curl
printf 'Installing changeish version %s\n' "${VERSION}"
curl -fsSL -o "${INSTALL_DIR}/changeish" "https://raw.githubusercontent.com/${REPO}/${VERSION}/${SCRIPT_NAME}"
chmod +x "${INSTALL_DIR}/changeish"
printf 'Installed changeish to %s/changeish\n' "${INSTALL_DIR}"

# # 12. Copy prompt_template.md locally
# mkdir -p "$(dirname "${PROMPT_NAME}")"
# cp "${APP_DIR}/${PROMPT_NAME}" "${PROMPT_NAME}"
# printf 'Copied %s to %s\n' "${PROMPT_NAME}" "$(pwd || true)/${PROMPT_NAME}"

# 13. PATH warning
printf '\n'
case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ;;
  *)
    printf 'Warning: %s is not in your PATH.\n' "${INSTALL_DIR}"
    ;;
esac

printf 'Installation complete!\n'