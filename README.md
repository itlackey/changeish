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
- 🚀 **Easy installation & updates**: One-line install, self-updating, and minimal dependencies.
- 💡 **Beginner-friendly**: Simple CLI, clear documentation, and example `.env` for quick setup.
- 🌍 **Open source & community-driven**: Contributions, issues, and feature requests are encouraged!

## Installation

Run this in your terminal to install the latest version:

```bash
curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh
```

To install a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh -s -- --version v0.1.9
```

To install the latest changes from the `main` branch:

```bash
curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh -s -- --version main
```

## Usage

```sh
changeish [OPTIONS]
```

### Options

- `--current`               Only use current (uncommitted) changes in the prompt
- `--staged`                Only use staged changes in the prompt
- `--from REV`              Set the starting commit (default: HEAD)
- `--to REV`                Set the ending commit (default: HEAD^)
- `--all`                   Include all history (from first commit to HEAD)
- `--short-diff`            Show only diffs for todos-related markdown files
- `--model MODEL`           Specify the Ollama/local model to use (default: qwen2.5-coder)
- `--changelog-file PATH`   Path to changelog file to update (default: ./CHANGELOG.md)
- `--prompt-template PATH`  Path to prompt template file (default: ./changelog_prompt.md)
- `--prompt-only`           Generate prompt file only, do not generate or update changelog
- `--version-file PATH`     File to check for version number changes in each commit (default: auto-detects common files)
- `--remote`                Use a remote OpenAI-compatible API for changelog generation
- `--api-model MODEL`       Specify the remote API model to use (overrides --model for remote)
- `--api-url URL`           Specify the remote API URL for changelog generation
- `--help`                  Show usage information and exit
- `--available-releases`    Show releases available on GitHub
- `--update`                Update `changeish` to the latest release
- `--version`               Show script version and exit

### Environment Variables

- `CHANGEISH_MODEL`         Model to use for local generation (same as --model)
- `CHANGEISH_API_KEY`       API key for remote changelog generation (required if --remote is used)
- `CHANGEISH_API_URL`       API URL for remote changelog generation (same as --api-url)
- `CHANGEISH_API_MODEL`     API model for remote changelog generation (same as --api-model)

See `.env.example` for configuration examples for Ollama, OpenAI, and Azure OpenAI.

### Examples

Generate a changelog for all uncommitted changes using the local model:

```bash
changeish
```

Generate a changelog for all commits from `v1.0.0` to `HEAD` and use the `llama3` model for AI summarization:

```sh
changeish --from v1.0.0 --to HEAD --model llama3
```

Show version number changes in a specific file (e.g., `pyproject.toml`):

```sh
changeish --from v1.0.0 --to HEAD --version-file pyproject.toml
```

Generate only the prompt file (no changelog generation):

```sh
changeish --from v1.0.0 --to HEAD --prompt-only
```

Use a remote OpenAI-compatible API for changelog generation (with custom model and URL):

```sh
changeish --remote --api-model gpt-4o-mini --api-url https://api.openai.com/v1/chat/completions
```

You can also set the relevant environment variables in a `.env` file or your shell environment. See `.env.example` for details.

## How It Works

- The script collects commit history and diffs in the specified range.
- It detects version number changes in a user-specified file or common project files.
- It generates a prompt combining the git history and a prompt template.
- If not using `--prompt-only`, it sends the prompt to the specified Ollama model or remote API to generate a formatted changelog.
- The changelog is inserted into the specified changelog file.

## Configuration

You can configure models and API endpoints using environment variables or a `.env` file. See `.env.example` for detailed examples for Ollama, OpenAI, and Azure OpenAI.

- For local Ollama: set `CHANGEISH_MODEL` or use `--model`
- For remote API: set `CHANGEISH_API_KEY`, `CHANGEISH_API_URL`, and `CHANGEISH_API_MODEL` or use the corresponding CLI flags

> Note: For remote API usage, you must have a valid API key set in your environment variables or in a `.env` file. See `.env.example` for configuration.

## Requirements

- Bash (or similiar shell)
- [Git](https://git-scm.com/)
- [jq](https://jqlang.org/)
- [Ollama](https://ollama.com/) (optional, for local AI changelog generation)

> NOTE
> jq can be installed using your systems package manager. 
> use `brew install jq` on MacOS
> use `sudo apt install jq` for Debian based Linux

## Uninstall

```bash
 rm $(which changeish )
```

## License

CC-BY

> If you use this with you project, leave a :star: and don't forget to tell your friends!
