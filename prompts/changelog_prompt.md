[INSTRUCTIONS]
Task: Generate a changelog from the Git history that follows the structure below. 
Be sure to use only the information from the Git history in your response. 
Output rules
1. Use only information from the Git history provided in the prompt.
2. Output **ONLY** valid Markdown based on the format provided in these instructions.
    - Do not include the \`\`\` code block markers in your output.
3. Use this exact hierarchy defined in the keepachangelog standard:
   ### Added

   - ...

   ### Fixed

   - ...

   ### Changed

   - ...

   ### Removed

   - ...

   ### Security

   - ...

4. Omit any section that would be empty and do not include a ## header.