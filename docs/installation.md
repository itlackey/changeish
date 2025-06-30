# Installation

## Requirements

- POSIX-compatible shell (Bash, Zsh, Ash, etc.)
- [curl](https://curl.se/)
- [Git](https://git-scm.com/) (version 2.25 or newer)
- [Ollama](https://ollama.com/) (optional, for local AI changelog generation)

> **Note:** The installer works on Linux, macOS, and Windows/WSL.

## Quick Install (Latest Release)

Run this in your terminal to install the latest released version of `changeish`:

```bash
curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh
```

## Install a Specific Version

To install a specific version (e.g., `v0.1.9`):

```bash
curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh -s -- --version v0.1.9
```

## Install the Latest Changes from the `main` Branch

To install the very latest changes (may be unstable):

```bash
curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh -s -- --version main
```

## Install the Latest Changes from a specific Branch

To install from a different branch (may be unstable):

```bash
curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh -s -- --version <branch name>
```

## How the Installer Works

- The installer will **remove any existing `changeish` script** from your PATH before installing the new version.
- By default, it installs to:
  - `/usr/local/bin` (if writable)
  - Otherwise, `$HOME/.local/bin`
  - Otherwise, `$HOME/bin` (and creates the directory if needed)
- The script will **automatically detect the latest release** if you do not specify a version.
- The main script (`changes.sh`) is installed as `changeish` in your chosen bin directory (as a symlink or copy, depending on platform).
- The prompt templates are installed to an application data directory (not your current working directory):
  - Linux: `$XDG_DATA_HOME/changeish/prompts` or `$HOME/.local/share/changeish/prompts`
  - macOS: `$HOME/Library/Application Scripts/com.github.lackeyi/changeish/prompts`
  - Windows/WSL: `$LOCALAPPDATA/changeish/prompts` or `$HOME/AppData/Local/changeish/prompts`

## After Installation

- Ensure the install directory (e.g., `/usr/local/bin`, `$HOME/.local/bin`, or `$HOME/bin`) is in your `PATH`.
- If you see a warning that the directory is not in your `PATH`, add it to your shell profile:

  **For Bash/Zsh (Linux/macOS/WSL):**

  ```bash
  export PATH="$HOME/.local/bin:$PATH"
  # Add the above line to your ~/.bashrc, ~/.zshrc, or ~/.profile
  ```

  **For Fish shell:**

  ```fish
  set -U fish_user_paths $HOME/.local/bin $fish_user_paths
  ```

  **For Windows (WSL):**
  - Add the export line above to your `~/.bashrc` or `~/.zshrc` in your WSL home directory.
  - For native Windows, add the install directory to your system PATH via System Properties > Environment Variables.

- You can verify installation with:

  ```bash
  changeish --version
  ```

## Uninstall

To remove `changeish`, use the method appropriate for your OS:

**Linux/macOS/WSL:**

```bash
rm -f "$(command -v changeish)"
```

**Windows (WSL):**

```bash
rm -f "$(command -v changeish)"
```

- Optionally, you may also remove the prompt templates directory:
  - Linux: `$HOME/.local/share/changeish/prompts` or `$XDG_DATA_HOME/changeish/prompts`
  - macOS: `$HOME/Library/Application Scripts/com.github.lackeyi/changeish/prompts`
  - Windows/WSL: `$LOCALAPPDATA/changeish/prompts` or `$HOME/AppData/Local/changeish/prompts`

## Troubleshooting

- If you see a "Permission denied" error, try running the install command with `sudo` (not usually needed for user-local installs).
- The installer requires only `curl` and `git` to be available on your system.
- If you have issues with the install location, you can manually move or symlink the `changeish` script to a directory in your `PATH`.
- On Windows/WSL, the script is copied (not symlinked) for compatibility.
