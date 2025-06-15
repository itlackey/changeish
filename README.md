# changesish

A Bash script to generate a changelog from your Git history, with optional AI-powered summarization using Ollama models.

## Features

- Generate a detailed Markdown changelog from your Git commit history
- Filter diffs for todos-related markdown files
- AI-powered changelog generation using Ollama models (optional)
- Customizable commit ranges, prompt, and changelog file paths
- Easy-to-use command-line interface with `--help`

## Usage

```sh
./changes.sh [OPTIONS]
```

### Options

- `--from REV`           Set the starting commit (default: HEAD)
- `--to REV`             Set the ending commit (default: HEAD^)
- `--short-diff`         Show only diffs for todos-related markdown files
- `--model MODEL`        Specify the Ollama model to use (default: devstral)
- `--changelog-file PATH`  Path to changelog file to update (default: ./static/help/changelog.md)
- `--prompt-file PATH`   Path to prompt file (default: ./docs/prompts/changelog_prompt.md)
- `--generate`           Generate changelog using Ollama
- `--all`                Include all history (from first commit to HEAD)
- `--help`               Show usage information and exit

### Example

Generate a changelog for all commits from `v1.0.0` to `HEAD` and use the `llama3` model for AI summarization:

```sh
./changes.sh --from v1.0.0 --to HEAD --generate --model llama3
```

## Requirements

- Bash
- Git
- [Ollama](https://ollama.com/) (optional, for AI changelog generation)

## How It Works

- The script collects commit history and diffs in the specified range.
- If `--generate` is used, it sends the history and a prompt to the specified Ollama model to generate a formatted changelog.
- The changelog is inserted into the specified changelog file.

## License

MIT
