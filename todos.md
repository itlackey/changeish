# TODOs

ADDED: Provide default version file for python and node
ADDED: Provide a version file arg to override the defaults
DONE: Refactor code to use functions
ADDED: Add update function and argument to update script to latest version
DONE: Add install instructions to README
ADDED: Switch from --generate to --prompt-only to allow the script to generate the changelog by default
CHORE: Cleanup default output file names (ie. prompt.md, history.md)
ENHANCEMENT: include a --include-pattern arg to replace the --short-diff arg to allow custom patterns during diff
ENHANCEMENT: add an --exclude-pattern arg
DONE: Add "Managed by changeish" to change output
FIXED: Script does not append to end of changelog if no existing sections are found
ADDED: Add arg to only look at pending changes instead of previous commits
FIXED: Parsing issue with --to and --from args