Write a git commit message following the Keep a Changelog standard:

1. Format Requirements:
   - First line (header): Brief overview of changes (50 characters or less)
   - Second line: Empty line separator
   - Third line onwards (body): Detailed changes with types (100 characters or less)

2. Content Requirements:
   - Header: Describe the overall purpose or impact
   - Body: List each change with its type prefix
     * feat: for new features
     * fix: for bug fixes
     * docs: for documentation changes
     * style: for code style changes
     * refactor: for code restructurings
     * test: for test additions/changes
     * chore: for other changes
     * build: for build system changes
     * ci: for CI/CD pipeline changes
     * perf: for performance improvements
     * security: for security fixes
     * deps: for dependency updates

3. Input Processing:
   - Analyze the git diff output provided
   - Identify the overall purpose of the changes
   - Extract individual changes and their types
   - Group related changes under appropriate types
   - Focus on what changed and why

4. Output Format:
```
[Overview under 50 chars]

[feat] Add user authentication
[fix] Resolve login timeout issues
[docs] Update API documentation
```

Example:
```
Improve user authentication system

[feat] Add JWT token handling
[fix] Resolve login timeout issues
[docs] Update API documentation
[perf] Optimize authentication queries
```