# TODOs

- ADDED: Provide default version file for python and node
- ADDED: Provide a version file arg to override the defaults
- DONE: Refactor code to use functions
- ADDED: Add update function and argument to update script to latest version
- DONE: Add install instructions to README
- ADDED: Switch from --generate to --prompt-only to allow the script to generate the changelog by - default
- CHORE: Cleanup default output file names (ie. prompt.md, history.md)
- ENHANCEMENT: include a --include-pattern arg to replace the --short-diff arg to allow custom - patterns during diff
- ENHANCEMENT: add an --exclude-pattern arg
- DONE: Add "Managed by changeish" to change output
- FIXED: Script does not append to end of changelog if no existing sections are found
- ADDED: Add arg to only look at pending changes instead of previous commits
- FIXED: Parsing issue with --to and --from args
- FIXED: install.sh issue with getting latest version
- FIXED: bug with defaulting to --current if no other options are passed
- FIXED: POSIX sh compatibility bug in install.sh
- ENHANCEMENT: support remote API for generation
  ```bash
  curl -X POST "https://<workspace>.openai.azure.com/openai/deployments/<deployment>/chat/completions?api-version=<version>" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $AZURE_API_KEY" \
      -d '{
          "messages": [
              {
                  "role": "user",
                  "content": "I am going to Paris, what should I see?"
              },
              {
                  "role": "assistant",
                  "content": "Paris, the capital of France, is known for its stunning architecture, art museums, historical landmarks, and romantic atmosphere. Here are some of the top attractions to see in Paris:\n \n 1. The Eiffel Tower: The iconic Eiffel Tower is one of the most recognizable landmarks in the world and offers breathtaking views of the city.\n 2. The Louvre Museum: The Louvre is one of the world's largest and most famous museums, housing an impressive collection of art and artifacts, including the Mona Lisa.\n 3. Notre-Dame Cathedral: This beautiful cathedral is one of the most famous landmarks in Paris and is known for its Gothic architecture and stunning stained glass windows.\n \n These are just a few of the many attractions that Paris has to offer. With so much to see and do, it's no wonder that Paris is one of the most popular tourist destinations in the world."
              },
              {
                  "role": "user",
                  "content": "What is so great about #1?"
              }
          ],
          "max_completion_tokens": 800,
          "temperature": 1,
          "top_p": 1,
          "frequency_penalty": 0,
          "presence_penalty": 0,
          "model": "<model>"
      }'
  ```
- CHORE: write doc on using external APIs
- ENHANCEMENT: load .env file to get API settings
- DONE: move default prompt template into sh file.
- ENHANCEMENT: add option to create a prompt template based on the default
- ENHANCEMENT: use temp files for history and prompt. save them based on args
- ADDED: Help now shows the default version files the script will look for.
- CHORE: Add examples of using changeish with various workflows. ie. npm run changeish
- FIXED: Script should not fail if no todo files are found.
- ADDED: Better support for finding and parsing todo files in sub folders.
- DONE: Added descriptions to help examples
- ADDED: check to ensure we are in a git repository before running the script.
- ADDED: Better version management for install & update
- ADDED: Improve default prompt text
- ENHANCEMENT: Better git history formatted with more explict version and todo verbiage
