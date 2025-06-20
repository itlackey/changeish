# TODOs

## Pending

- CHORE: Cleanup default output file names (ie. prompt.md, history.md)
- CHORE: write doc on using external APIs
- ENHANCEMENT: add option to create a prompt template based on the default
- CHORE: Add examples of using changeish with various workflows. ie. npm run changeish
- ENHANCEMENT: Better git history formatted with more explict version and todo verbiage


## Completed

- ADDED: Provide default version file for python and node
- ADDED: Provide a version file arg to override the defaults
- DONE: Refactor code to use functions
- ADDED: Add update function and argument to update script to latest version
- DONE: Add install instructions to README
- ADDED: Switch from --generate to --prompt-only to allow the script to generate the changelog by - default
- DONE: Add "Managed by changeish" to change output
- FIXED: Script does not append to end of changelog if no existing sections are found
- ADDED: Add arg to only look at pending changes instead of previous commits
- FIXED: Parsing issue with --to and --from args
- FIXED: install.sh issue with getting latest version
- FIXED: bug with defaulting to --current if no other options are passed
- FIXED: POSIX sh compatibility bug in install.sh
- DONE: move default prompt template into sh file.
- DONE: support remote API for generation
- FIXED: Script should not fail if no todo files are found.
- ADDED: Better support for finding and parsing todo files in sub folders.
- DONE: Added descriptions to help examples
- ADDED: Help now shows the default version files the script will look for.
- ADDED: check to ensure we are in a git repository before running the script.
- ADDED: Better version management for install & update
- ADDED: Improve default prompt text
- ADDED: use temp files for history and prompt. save them based on args
- DONE: replace --prompt-only with --save-prompt
- DONE: Add --save-history to Optionally save history file
- ADDED: add --config-file load .env file to get settings
- ADDED: include a --include-pattern arg to replace the --short-diff arg to allow custom patterns during diff
- ADDED: add an --exclude-pattern arg