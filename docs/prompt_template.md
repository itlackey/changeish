<<<INSTRUCTIONS>>>
Task: Generate a changelog from the Git history that follows the structure below.

Output rules

1. Output **ONLY** valid Markdown.
2. Use this exact hierarchy:

   ## {version} ({date})

   ### Enhancements

   - ...

   ### Fixes

   - ...

   ### Chores

   - ...
3. Omit any section that would be empty.

Version ordering: newest => oldest (descending).

### Example Output (for reference only)

## v2.0.213-3 (2025-02-13)

### Enhancements

- Example enhancement A

### Fixes

- Example fix A

### Chores

- Example chore A
<<<END>>>
