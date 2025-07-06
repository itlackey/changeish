Write a structured, Keep a Changelog–style summary of the provided git diff. Do not include any version headings or other releases—just one section of grouped changes with type prefixes for each list item.

1. Overview  
   - Begin with a section summarizing all of the changes, and the purpose and scope of these changes.

2. Change Groups  
   For each group below (omit any with no entries), include the heading and list bullet points. Each bullet point should prefixed with the type tag:

   ### Added  
   - Describe each new feature: what changed, why it was added, and its impact.  
   - Mention affected files or components when relevant.

   ### Fixed  
   - Describe each bug fix: what was broken, how it’s now resolved, and any side-effects.  
   - Reference files or tests updated.

   ### Documentation  
   - Summarize documentation updates: what was clarified or added, and why.

   ### Style  
   - List formatting or lint changes; note any tooling/formatter updates.

   ### Refactored  
   - Explain code restructuring: what modules or components were reorganized and benefit gained.

   ### Performance  
   - Detail optimizations: what was improved and performance gains measured.

   ### Tests  
   - Outline new or updated tests: what scenarios now covered or fixed.

   ### Build  
   - Note changes to build scripts, dependencies, or CI configurations.

   ### CI/CD  
   - Summarize pipeline/job changes or additions.

   ### Chores  
   - Miscellaneous maintenance tasks not covered above.

   ### Security  
   - Describe any security patches or vulnerability fixes.

3. Formatting & Tone  
   - Use bullet points (`- `) under each heading.  
   - Keep each bullet under 120 characters.  
   - Write in natural, professional language—avoid raw diff syntax.  
   - Group related items together and maintain logical order.
   - Each list item should provide enough detail to understand the change.

4. Processing Instructions  
   - Parse the git diff to detect each change’s type.  
   - Assign changes to the appropriate group above.  
   - Extract file paths or components when pertinent.  
   - If possible, explain "what" changed, "why," and the "impact."  

Output only the completed summary—no additional commentary.