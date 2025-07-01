# changeish

A powerful, open-source Bash tool to automatically generate beautiful, structured changelogs from your Git history locally with AI. Effortlessly keep your project documentation up to date, impress your users, and streamline your release process. Supports both local Ollama models and remote OpenAI-compatible APIs for maximum flexibility.

Contributions, stars, and feedback are welcome! If you find this project useful, please ⭐️ star it and consider submitting a pull request or opening an issue.

## Features

- ✨ **Automated, human-readable changelogs**: Summarize your Git commit history into clean, Markdown-formatted changelogs.
- 🤖 **AI-powered summarization**: Use local Ollama models or remote OpenAI-compatible endpoints for smart, context-aware changelog generation.
- 🔍 **Customizable commit ranges**: Generate changelogs for uncommitted, staged, or any commit range in your repository.
- 📝 **Version change detection**: Automatically highlight version number changes in common project files (or specify your own).
- 🗂️ **Diff filtering**: Focus on todos or specific markdown files with targeted diff options.
- 🛠️ **Flexible configuration**: Easily switch between local and remote AI, customize prompt templates, and set changelog file paths.
- 🧩 **Prompt-only mode**: Generate just the prompt for manual review or use with other tools.
- 🚀 **Easy installation & updates**: One-line install, self-updating, and minimal dependencies. **Now supports Linux, macOS, and Windows!**
- 💡 **Beginner-friendly**: Simple CLI, clear documentation, and example `.env` for quick setup.
- 🌍 **Open source & community-driven**: Contributions, issues, and feature requests are encouraged!
- 🐚 **POSIX shell compatible**: Tested with Bash, Zsh, Ash, and other POSIX-compliant shells.

## What's New in v0.2.0

- **Commit message and summary generation:** Use `--message` to generate an LLM-based commit message for your current or staged changes, and `--summary` for a human-readable summary. These can be combined or used independently.
- **Changelog section update modes:** Use `--update-mode` and `--section-name` to control how and where new changelog content is inserted or updated.
- **Flexible diff filtering:** Use `--include-pattern` and `--exclude-pattern` for advanced file selection in diffs (replaces `--short-diff`).
- **Config file support:** Load settings from a `.env` file with `--config-file`.
- **Improved temp file handling:** History and prompt files are now created as temporary files and only saved if `--save-history` or `--save-prompt` is used.
- **Changelog generation modes:**
  - `--model-provider` controls how changelogs are generated:
    - `none`: Skip changelog generation
    - `local`: Force local model
    - `remote`: Force remote API
    - `auto`: Try local, fallback to remote
- **Enhanced commit range logic:** Better handling of commit ranges, especially with `--all`.
- **Advanced TODO filtering:** Use regex patterns to filter TODOs in diffs.
- **Automatic version file detection:** If not specified, common version files are auto-detected.
- **Prompt template export:** Use `--make-prompt-template <file>` to write the default prompt template to a file for customization.
- **Improved error handling:** More informative errors for missing files, repos, or config.
- **Cross-platform install script:** The install script now works on Linux, macOS, and Windows (WSL, Git Bash, etc.).
- **POSIX shell compatibility:** The script is tested and works in Bash, Zsh, Ash, and other POSIX-compliant shells.

## How It Works

- The script collects commit history and diffs in the specified range.
- It detects version number changes in a user-specified file or common project files.
- It generates a prompt combining the git history and a prompt template.
- It sends the prompt to the specified Ollama model or remote API to generate a formatted changelog.
- The changelog is updated with the response from the LLM.

## Installation

Run this in your terminal to install the latest version (Linux, macOS, or Windows/WSL):

```bash
curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh
```

## Usage

```sh
changeish [OPTIONS]
```

### Examples

Generate a changelog with uncommitted changes using the local model:

```bash
changeish
```

Generate a changelog with staged changes only:

```bash
changeish --staged
```

Generate a changelog from a specific commit range using a local model:

```bash
changeish --from v1.0.0 --to HEAD --model llama3 --version-file custom_version.txt
```

Include all history since the start and write to a custom changelog file:

```bash
changeish --all --changelog-file ./docs/CHANGELOG.md
```

Use a remote API for changelog generation:

```bash
changeish --model-provider remote --api-model qwen3 --api-url https://api.example.com/v1/chat/completions
```

Write the default prompt template to a file for editing:

```bash
changeish --make-prompt-template my_prompt_template.md
```

Output a summary of the current changes (working tree):

```bash
changeish --summary
```

Output a commit message for staged changes:

```bash
changeish --staged --message
```

Output both a summary and commit message for current changes:

```bash
changeish --summary --message
```

### Options

- `--help`                   Show this help message and exit
- `--summary`                Output a summary of the changes to the console
- `--message`                Output a commit message for the changes to the console
- `--current`                Use uncommitted (working tree) changes for git history (default)
- `--staged`                 Use staged (index) changes for git history
- `--all`                    Include all history (from first commit to HEAD)
- `--from REV`               Set the starting commit (default: HEAD)
- `--to REV`                 Set the ending commit (default: HEAD^)
- `--include-pattern P`      Show diffs for files matching pattern P (and exclude them from full diff)
- `--exclude-pattern P`      Exclude files matching pattern P from full diff
- `--todo-pattern P`         Pattern for files to check for TODO changes (default: *todo*)
- `--model MODEL`            Specify the local Ollama model to use (default: qwen2.5-coder)
- `--model-provider MODE`    Control how changelog is generated: auto (default), local, remote, none
- `--api-model MODEL`        Specify remote API model (overrides --model for remote usage)
- `--api-url URL`            Specify remote API endpoint URL for changelog generation
- `--changelog-file PATH`    Path to changelog file to update (default: ./CHANGELOG.md)
- `--prompt-template PATH`   Path to prompt template file (default: ./changelog_prompt.md)
- `--update-mode MODE`       Section update mode: auto (default), prepend, append, update, none (disables writing changelog)
- `--section-name NAME`      Target section name (default: detected version or "Current Changes")
- `--version-file PATH`      File to check for version number changes in each commit
- `--config-file PATH`       Path to a shell config file to source before running (overrides .env)
- `--save-prompt`            Generate prompt file only and do not produce changelog
- `--save-history`           Do not delete the intermediate git history file
- `--make-prompt-template PATH`  Write the default prompt template to a file
- `--version`                Show script version and exit
- `--available-releases`     Show available script releases and exit
- `--update`                 Update this script to the latest version and exit
- `--debug`                  Enable debug output

You can also set the relevant environment variables in a `.env` formatted file or your shell environment. See the [Configuration](./docs/configuration.md) doc for details.

## Requirements

- POSIX-compliant shell (Bash, Zsh, Ash, etc.)
- [curl](https://curl.se/)
- [Git](https://git-scm.com/) **version 2.25 or newer**
- [Ollama](https://ollama.com/) (optional, for local AI changelog generation)

> **Note:** `jq` is no longer required. All JSON escaping is now handled internally in POSIX shell.

See the [Installation](./docs/installation.md) doc for more details.

## License

CC-BY

> If you use this with your project, leave a :star: and don't forget to tell your friends!
