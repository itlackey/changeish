# Integration with Git Hooks

```sh
mkdir -p .git/hooks
touch .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg
```

`.git/hooks/commit-msg`

```sh
#!/bin/bash

# Get the commit message file passed by Git
MESSAGE_FILE=$1

# Read original message
ORIGINAL_MESSAGE=$(cat "$MESSAGE_FILE")

# Overwrite original message
changeish message --cached > "$MESSAGE_FILE"

# Optionally: Append original message
# echo "$ORIGINAL_MESSAGE" >> "$MESSAGE_FILE"
```
