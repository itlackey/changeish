# CHANGELOG

## v0.2.0

### Features

- Added `--include-pattern` and `--exclude-pattern` arguments:
   - These replace the old `--short-diff` argument for more flexible diff pattern matching.
- Added `--generation-mode` option to control the model generation process.
  - `none`: Skips changelog generation.
  - `local`: Forces local model for generation.
  - `remote`: Forces remote model for generation.
  - `auto`: Attempts to use a local model, falls back to remote if not found.
- Enhanced commit range handling:
   - Improved logic for determining commit ranges, especially when using `-
- Updated the script to automatically detect common version files if none is specified.
- Added functionality to write the default prompt template to a file using the `--make-prompt-template` flag.

### Fixes

- Fixed an issue where specifying a non-existent version file caused an error.
- Fixed issue where changelog file creation was skipped when the file did not exist.

### Chores

- Documentation updates:
   - Updated the todos.md file to reflect completed enhancements.
   - Added notes about newly added arguments and changes in behavior.

- Minor code cleanup and refactoring:
   - Some internal variable names were changed for clarity.
   - Improved commit message generation logic slightly.

## v0.1.10

### Enhancements

- Implemented a `generate_remote` function to interact with a remote API for generating changelogs.
- Added support for sourcing a `.env` file to provide `CHANGEISH_API_URL` and `CHANGEISH_API_KEY`.
- Introduced a `remote` flag in the script to switch between local and remote API generation.
- IN PROGRESS support remote API for generation
- Update changesish to source .env file

### Fixes

- Fixed the condition check in `generate_prompt` function to ensure the correct prompt template is used.
- Corrected the prompt file path in `install.sh`.

### Chores

- Updated `.gitignore` to include `.env` file.
- Cleaned up legacy API base URL variable.

## v0.1.9

### Enhancements

- Added support for `--available-releases` flag to list all GitHub release tags.
- Added logic to fetch and display the latest version number from GitHub API using `jq`.
- Added fallback behavior: if no `--from`, `--to`, `--all`, or `--staged` flags are provided, script defaults to showing current uncommitted changes.
- Improved diff output to show only added lines (`+`) in todos-related `.md` files and exclude diff headers.

### Chores

- Updated `install.sh` to fetch and install the latest tagged release if no version is provided.

## v0.1.0

### Enhancements

- Implemented a new prompt generation for changelog using AI models like Ollama.
- Added a new prompt file `changelog_prompt.md`.
- Provided the ability to specify both from and to revisions for git history.

### Chores

- Cleaned up default output file names (ie. prompt.md, history.md).
- Added the message "Managed by changeish" to the change output.

### Fixes

- Fixed an issue where the script does not append to the end of changelog if no existing sections are found.

[Managed by changeish](https://github.com/itlackey/changeish)