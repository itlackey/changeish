# changeish

A Bash script to generate a changelog from your Git history, with optional AI-powered summarization using Ollama models.

## Features

- Generate a detailed Markdown changelog from your Git commit history
- Filter diffs for todos-related markdown files
- Detect and show version number changes in common project files (or specify your own)
- AI-powered changelog generation using Ollama models (optional)
- Customizable commit ranges, prompt template, and changelog file paths
- Generate only the prompt file for manual or external use
- Easy-to-use command-line interface with `--help`

## Installation

Run this in your terminal to install the latest version:

```bash
curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh
```

To install a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/itlackey/changeish/main/install.sh | sh -s -- --version v0.1.8
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
- `--model MODEL`           Specify the Ollama model to use (default: devstral)
- `--changelog-file PATH`   Path to changelog file to update (default: ./CHANGELOG.md)
- `--prompt-template PATH`  Path to prompt template file (default: ./changelog_prompt.md)
- `--prompt-only`           Generate prompt file only, do not generate or update changelog
- `--version-file PATH`     File to check for version number changes in each commit (default: auto-detects common files)
- `--help`                  Show usage information and exit
- `--version`               Show script version and exit

### Example

Generate a changelog for all uncommitted changes:

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

## Requirements

- Bash
- Git
- jq
- [Ollama](https://ollama.com/) (optional, for AI changelog generation)

## How It Works

- The script collects commit history and diffs in the specified range.
- It detects version number changes in a user-specified file or common project files.
- It generates a prompt file (`prompt.md`) combining the git history and a prompt template.
- If not using `--prompt-only`, it sends the prompt to the specified Ollama model to generate a formatted changelog.
- The changelog is inserted into the specified changelog file.

## Uninstall

```bash
 rm $(which changeish )
```

## License

CC-BY

> If you use this with you project, leave a :star: and don't forget to tell your friends!
