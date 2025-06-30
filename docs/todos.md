# TODOs

## Pending

- CHORE: write doc on using external APIs
- CHORE: Add examples of using changeish with various workflows. ie. npm run changeish
- ADDED: --summary option to provide summary of changes
- ENHANCEMENT: --type "annoucement" option to generate a release announcement
- ADDED: --type "commit" option to generate commit message `git commit -m "$(changeish -t commit)"
- ENHANCEMENT: add git config user.name to output

- CHORE: Add more "real-world" tests with more detailed output validation
- ENHANCEMENT: allow user to specify (regex?) patterns for matching sections, headers, versions, todos
- ENHANCEMENT: improve prompt with more specific todo rules. ie. BUG->FIXED changes go in ### Fixed sub section

## In Progress

- Improve installer to support copying default templates to APP_DIR
- Pending updating script to look for templates in APP_DIR if not specified and APP_DIR exists. Otherwise throw an error saying template is required

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
- DONE: Cleanup default output file names (ie. prompt.md, history.md)
- FIXED: Always generates changelog, should be able only generate prompts
- ADDED: Add --debug arg to enable debug more
- ADDED: Add --todo-pattern to use in addition to the include/exclude args. The diffs found in this pattern should be used in the todos history section instead of the --include-pattern files
- ADDED: Better git history formatted with more explict version and todo verbiage
- ADDED: If no version changes are found, grep for existing/current verison info in the version file
- DONE: Refactor the handling of --include/exclude so it handles the general diff and not the todos section
- FIXED: Bug with pager displaying on long git diff output
- ADDED: Add --generation-mode with allowed values of "auto", "local", "remote", and "none"
- ADDED: add option to create a prompt template based on the default
- ADDED: Add --update-mode with allowed values of "auto", "prepend", "append", and "update"
- ADDED: Add --section-name to specify which section to when updating the changelog.
  - If not specified it should be generated based on the new or current version information in that priority order. 
  - If not specified and no verison info can be found, then set section name to "Current Changes"
  - If a matching section is found and it contains the current verison and the update-mode is either auto or update, that section should be sent to LLM with instructions to update the section with information about the git history.
  - If matching section is found and the update mode is "prepend" then insert the changelog content before the matching section
  - If no matching section is found and the update mode is "auto" or "prepend" then insert the changelog content after the first # header and before the first ## heading
  - If matching section is found and the update mode is "appened" then insert the changelog content after the matching section and before the next section or at the end of the file.
  - If no matching section is found and the update mode is "append" then insert the changelog content at the end of the file.
- ADDED: use existing section from existing change log in prompt instead of examples items when possible
- FIXED: fix debug flag handling, should default to "" so checks work correctly
- DONE: improve prompt to handle updating existing sections