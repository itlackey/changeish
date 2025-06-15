# CHANGELOG

## v0.1.0

### Enhancements

* Implemented a new prompt generation for changelog using AI models like Ollama.
* Introduced changes in the script logic to ensure accurate and consistent insertion into the CHANGELOG.md file.

### Fixes

* Resolved issues with appending fresh changelog at the end if no second-level heading was found previously.
* Ensured that the "Managed by changeish" message is added correctly within the generated output for enhanced clarity and understanding of changes made by scripts or models used.

### Chores

* Updated logic to include `prompt.md` as the new source file instead of `.prompt`.
* Revised CHANGELOG.md insertion logic to ensure compatibility with model-generated content.
* Adjusted script functions and paths within `changes.sh` to support better maintenance practices.

Generated my changeish

## v0.1.0 (2025-01-23)

### Enhancements

* Added a new prompt file `changelog_prompt.md`.
* Provided the ability to specify both from and to revisions for git history.

### Chores

* Cleaned up default output file names (ie. prompt.md, history.md).
* Added the message "Managed by changeish" to the change output.

### Fixes

* Fixed an issue where the script does not append to the end of changelog if no existing sections are found.
