# Installation

## Requirements

- Bash (or similiar shell)
- [curl](https://curl.se/)
- [Git](https://git-scm.com/)
- [jq](https://jqlang.org/)
- [Ollama](https://ollama.com/) (optional, for local AI changelog generation)

> NOTE
> jq can be installed using your systems package manager. 
> use `brew install jq` on MacOS
> use `sudo apt install jq` for Debian based Linux

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

To install the from a different branch (may be unstable):

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
- The main script (`changes.sh`) is installed as `changeish` in your chosen bin directory.
- The prompt template (`docs/prompt_template.md`) is downloaded to your current working directory.

## After Installation

- Make sure the install directory (e.g., `/usr/local/bin` or `$HOME/.local/bin`) is in your `PATH`.
- If it is not, you will see a warning. Add it to your shell profile (e.g., `.bashrc`, `.zshrc`) if needed:

  ```bash
  export PATH="$HOME/.local/bin:$PATH"
  ```

## Uninstall

To remove `changeish`:

```bash
rm $(which changeish)
```

## Troubleshooting

- If you see a "Permission denied" error, try running the install command with `sudo` (not usually needed for user-local installs).
- The installer requires `curl` and `jq` to be available on your system.
- If you have issues with the install location, you can manually move the `changeish` script to a directory in your `PATH`.
