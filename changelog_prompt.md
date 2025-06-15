
=== INSTRUCTIONS ===

Please generate a change log based on the provided Git History above. The change log should be grouped by version (descending), then by Enhancements, Fixes, and Chores. Enhancements are considered completed when they are marked as ADDED in the todos file. Fixes are considered completed when they are marked as FIXED in the todos file. Chores are considered completed when they are marked as DONE in the todos file. The change log should be sorted by version number, then by category (Enhancements, Fixes, Chores), then by task description. It there are no tasks for a given category, do not include that category for the section.

Also review any code changes provided in the Git History above and include them in the change log as well. Do your best to summarize the changes in a concise manner and list them in the proper category. If you are unsure of the proper category, place the item in the Enhancements category. If you cannot find a version number in the Git History, use the date range of the commits provided in the Git History as a fallback.

It is VERY IMPORTANT that you follow this format exactly and DO NOT include additional comments. DO NOT INCLUDE FIRST LEVEL HEADING. DO NOT INCLUDE THE EXAMPLE OR INFORMATION FROM IT. Only include information contained within the provided Git History above.

Here is an example of the desired changelog format:

===EXAMPLE===

## v2.0.123-1 (2025-01-23)

### Enhancements

* Added example feature.

### Fixes

* Fixed example issues.

### Chores

* Updated example documentation.

===END EXAMPLE===
