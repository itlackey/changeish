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

## Usage

```sh
./changes.sh [OPTIONS]
```

### Options

- `--from REV`              Set the starting commit (default: HEAD)
- `--to REV`                Set the ending commit (default: HEAD^)
- `--short-diff`            Show only diffs for todos-related markdown files
- `--model MODEL`           Specify the Ollama model to use (default: devstral)
- `--changelog-file PATH`   Path to changelog file to update (default: ./CHANGELOG.md)
- `--prompt-template PATH`  Path to prompt template file (default: ./changelog_prompt.md)
- `--prompt-only`           Generate prompt file only, do not generate or insert changelog
- `--version-file PATH`     File to check for version number changes in each commit (default: auto-detects common files)
- `--all`                   Include all history (from first commit to HEAD)
- `--help`                  Show usage information and exit
- `--version`               Show script version and exit

### Example

Generate a changelog for all commits from `v1.0.0` to `HEAD` and use the `llama3` model for AI summarization:

```sh
./changes.sh --from v1.0.0 --to HEAD --model llama3
```

Show version number changes in a specific file (e.g., `pyproject.toml`):

```sh
./changes.sh --from v1.0.0 --to HEAD --version-file pyproject.toml
```

Generate only the prompt file (no changelog generation):

```sh
./changes.sh --from v1.0.0 --to HEAD --prompt-only
```

## Requirements

- Bash
- Git
- [Ollama](https://ollama.com/) (optional, for AI changelog generation)

## How It Works

- The script collects commit history and diffs in the specified range.
- It detects version number changes in a user-specified file or common project files.
- It generates a prompt file (`prompt.md`) combining the git history and a prompt template.
- If not using `--prompt-only`, it sends the prompt to the specified Ollama model to generate a formatted changelog.
- The changelog is inserted into the specified changelog file.

## License

MIT
