# How to Use `changeish` in Your Development Workflow

This guide provides a comprehensive overview of integrating `changeish` into your development workflow, including examples of using it with staged changes, working tree modifications, and automating version bumps and changelog updates during releases.

## 📌 Prerequisites

Before using `changeish`, ensure the following:

1. **Install Dependencies**:  
   `changeish` requires `git` (version 2.25 or newer) and optionally `bats` for testing. Ensure these are installed.

2. **Set Up .env File**:  
   Create a .env file in your project root to store API keys and URLs for remote LLM operations. Example:

   ```bash
   # .env
   CHANGEISH_API_URL="https://api.example.com/v1/chat/completions"
   CHANGEISH_API_KEY="your_api_key_here"
   CHANGEISH_API_MODEL="gpt-4"
   ```

3. **Reference Existing Documentation**:  
   Review the `CHANGELOG.md` for examples of how `changeish` integrates with CI/CD pipelines and versioning.

## 🔄 Workflow Scenarios

### 1. **Working with Staged Changes**

Use `changeish` to generate changelogs, summaries, or commit messages based on **staged changes** (after running `git add`).

#### ✅ Example: Generate Changelog for Staged Changes

```bash
# Stage your changes
git add .

# Generate changelog based on staged files
changeish --staged
```

#### ✅ Example: Output a Commit Message for Staged Changes

```bash
changeish --staged --message
```

#### ✅ Example: Output a Summary and Commit Message for Staged Changes

```bash
changeish --staged --summary --message
```

#### 📌 Notes

- `--staged` analyzes diffs in the index (staged files).
- `--summary` outputs a concise summary of the changes (does not update the changelog).
- `--message` outputs an LLM-generated commit message for the changes.
- You can combine `--summary` and `--message`.

#### 📁 Reference

- See `test_insert_changelog.bats` for how `changes.sh` is used in test scenarios.

### 2. **Working with Unstaged Changes (Working Tree)**

Use `changeish` to inspect **unstaged changes** in your working directory (default behavior, or with `--current`).

#### ✅ Example: Generate Changelog for Unstaged Changes

```bash
# Generate changelog based on working tree changes (default)
changeish
# Or explicitly:
changeish --current
```

#### ✅ Example: Output a Summary or Commit Message for Unstaged Changes

```bash
changeish --summary
changeish --message
changeish --summary --message
```

#### 📌 Notes

- This is ideal for local development before staging changes.
- `--current` is the default if neither `--staged` nor `--all` nor `--from`/`--to` are specified.
- `--summary` and `--message` can be used independently or together.

### 3. **Release Cycle: Changelog Update for a Commit Range**

Automate changelog updates for a specific commit range using `--from` and `--to`.

#### ✅ Example: Generate Changelog for a Commit Range

```bash
# Generate changelog for all changes from v1.0.0 to HEAD
changeish --from v1.0.0 --to HEAD
```

#### 📌 Notes

- Use `--all` to include all history from the first commit to HEAD.
- Use `--changelog-file` to specify a custom changelog file.
- Use `--model-provider remote --api-model gpt-4 --api-url ...` to use a remote LLM API.

#### 📁 Reference

- The `test_Version-3a_auto-2ddetect_version_file.log` demonstrates how `changeish` auto-detects version files (e.g., `package.json`, `Cargo.toml`).

## 🛠️ Key Options in `changes.sh`

The `changes.sh` script provides several flags and options. Here are key ones:

| Flag/Option             | Description                                                                 |
|-|--|
| `--current`             | Analyze unstaged (working tree) changes (default)                           |
| `--staged`              | Analyze staged changes (index)                                              |
| `--all`                 | Include all history (from first commit to HEAD)                             |
| `--from <rev>`          | Set the starting commit (default: HEAD)                                     |
| `--to <rev>`            | Set the ending commit (default: HEAD^)                                      |
| `--summary`             | Output a summary of the changes to the console                              |
| `--message`             | Output a commit message for the changes to the console                      |
| `--changelog-file <f>`  | Path to changelog file to update (default: ./CHANGELOG.md)                  |
| `--model <model>`       | Specify the local Ollama model to use (default: qwen2.5-coder)              |
| `--model-provider <m>`  | Control how changelog is generated: auto (default), local, remote, none      |
| `--api-model <model>`   | Specify remote API model (overrides --model for remote usage)                |
| `--api-url <url>`       | Specify remote API endpoint URL for changelog generation                    |
| `--prompt-template <f>` | Path to prompt template file (default: ./changelog_prompt.md)               |
| `--update-mode <mode>`  | Section update mode: auto (default), prepend, append, update, none          |
| `--section-name <name>` | Target section name (default: detected version or "Current Changes")        |
| `--version-file <f>`    | File to check for version number changes in each commit                     |
| `--save-prompt`         | Generate prompt file only and do not produce changelog                      |
| `--save-history`        | Do not delete the intermediate git history file                             |
| `--make-prompt-template <f>` | Write the default prompt template to a file                        |
| `--debug`               | Enable debug output                                                         |
| `--help`                | Show help message and exit                                                  |
| `--version`             | Show script version and exit                                                |

## 🧪 Integration with CI/CD

Use `changeish` in CI/CD pipelines to automate changelog generation and versioning.

#### ✅ Example: GitHub Actions Workflow

```yaml
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '16'
      - name: Install dependencies
        run: npm install
      - name: Update changelog for release
        run: changeish --from v1.1.0 --to HEAD --changelog-file ./CHANGELOG.md --model-provider remote --api-model gpt-4 --api-url ${{ secrets.CHANGEISH_API_URL }}
        env:
          CHANGEISH_API_KEY: ${{ secrets.CHANGEISH_API_KEY }}
```

#### 📌 Notes

- Ensure the .env file or environment variables are securely stored in your CI/CD environment.
- Use `--summary` or `--message` for previewing changes in CI/CD without modifying files.

## 📚 Troubleshooting and Tips

- **Custom Changelog Templates**:  
  Use `--prompt-template` to specify a custom changelog prompt template.

- **Handling Merge Conflicts**:  
  Manually resolve changelog conflicts if they occur during merges.

- **Debug Mode**:  
  Run `changeish --debug` to see detailed logs for debugging.

## 📖 Further Reading

- CHANGELOG.md: Example of .env usage and CI/CD integration.
- test_insert_changelog.bats: How changes.sh is used in test scenarios.
- test_Version-3a_auto-2ddetect_version_file.log: Auto-detection of version files.

By following this guide, you can streamline your workflow with `changeish`, ensuring consistent changelogs and versioning across your projects.
