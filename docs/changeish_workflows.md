# How to Use `changeish` in Your Development Workflow

This guide provides a comprehensive overview of integrating `changeish` into your development workflow, including examples of using it with staged changes, working tree modifications, and automating version bumps and changelog updates during releases. It also references key files in the `#file:docs` folder and explains how to leverage the options in `#file:changes.sh`.

---

## 📌 Prerequisites

Before using `changeish`, ensure the following:

1. **Install Dependencies**:  
   `changeish` relies on tools like `git` and `bats` for testing. Ensure these are installed.

2. **Set Up .env File**:  
   Create a .env file in your project root to store API keys and URLs for remote operations (e.g., GitHub/GitLab). Example:
   ```bash
   # .env
   CHANGEISH_API_URL="https://api.github.com"
   CHANGEISH_API_KEY="your_github_token_here"
   ```

3. **Reference Existing Documentation**:  
   Review the changelog.md for examples of how `changeish` integrates with CI/CD pipelines and versioning.

---

## 🔄 Workflow Scenarios

### 1. **Working with Staged Changes**

Use `changeish` to generate changelogs based on **staged changes** (e.g., after running `git add`).

#### ✅ Example: Generate Changelog for Staged Changes
```bash
# Stage your changes
git add .

# Generate changelog based on staged files
changeish --staged
```

#### 📌 Notes:
- This is useful during **pre-commit hooks** or when preparing a PR.
- `changeish` analyzes diffs in the index and maps them to changelog entries (e.g., `feat`, `fix`, docs).

#### 📁 Reference:
- See `test_insert_changelog.bats` for how changes.sh is used in test scenarios.

---

### 2. **Working with Unstaged Changes (Working Tree)**

Use `changeish` to inspect **unstaged changes** in your working directory (e.g., for local experimentation).

#### ✅ Example: Generate Changelog for Unstaged Changes
```bash
# Generate changelog based on working tree changes
changeish --working-tree
```

#### 📌 Notes:
- This is ideal for **local development** before staging changes.
- Use `--dry-run` to preview changes without modifying the changelog.

---

### 3. **Release Cycle: Version Bump + Changelog Update**

Automate **version bumps** and **changelog updates** during releases using the `--to` argument.

#### ✅ Example: Bump Version and Update Changelog
```bash
# Bump version to 1.2.0 and update changelog
changeish --to 1.2.0
```

#### 📌 Notes:
- This command:
  1. Updates the version in your project's version file (e.g., `package.json`, `VERSION`).
  2. Appends a new changelog entry with the current date and a placeholder for the release notes.
- Use `--type` to specify the type of change (e.g., `--type feat`, `--type fix`).

#### 📁 Reference:
- The `test_Version-3a_auto-2ddetect_version_file.log` demonstrates how `changeish` auto-detects version files (e.g., `package.json`, `Cargo.toml`).

---

## 🛠️ Advanced Options in `#file:changes.sh`

The changes.sh script provides several flags and options. Here are key ones:

| Flag/Option         | Description                                                                 |
|---------------------|-----------------------------------------------------------------------------|
| `--staged`          | Analyze staged changes (index)                                              |
| `--working-tree`    | Analyze unstaged changes (working directory)                                |
| `--to <version>`    | Bump version and update changelog                                           |
| `--type <type>`     | Specify change type (e.g., `feat`, `fix`, docs)                           |
| `--auto-detect`     | Auto-detect version files (e.g., `package.json`, `VERSION`)                 |
| `--env <file>`      | Load environment variables from a .env file                             |
| `--dry-run`         | Preview changes without modifying files                                     |

#### ✅ Example: Auto-Detect Version File
```bash
# Auto-detect version file and bump to 2.0.0
changeish --to 2.0.0 --auto-detect
```

---

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
      - name: Bump version and update changelog
        run: changeish --to 1.1.0 --env .env
```

#### 📌 Notes:
- Ensure the .env file is securely stored in your CI/CD environment.
- Use `--dry-run` in CI/CD for validation before committing changes.

---

## 📚 Troubleshooting and Tips

- **Custom Changelog Templates**:  
  Modify the default changelog template in changes.sh to match your project's style.

- **Handling Merge Conflicts**:  
  Use `--force` to overwrite existing changelog entries if needed.

- **Debug Mode**:  
  Run `changeish --verbose` to see detailed logs for debugging.

---

## 📖 Further Reading

- changelog.md: Example of .env usage and CI/CD integration.
- test_insert_changelog.bats: How changes.sh is used in test scenarios.
- test_Version-3a_auto-2ddetect_version_file.log: Auto-detection of version files.

---

By following this guide, you can streamline your workflow with `changeish`, ensuring consistent changelogs and versioning across your projects.