Generate a detailed narrative summary of the code changes:

1. Content Requirements:
   - Write a clear, natural language summary
   - Include all major changes and their types
   - Focus on explaining what changed and why
   - Group related changes logically
   - Maintain a professional but readable tone

2. Structure Guidelines:
   - Start with a brief overview paragraph
   - Organize changes by type (features, fixes, improvements)
   - Include specific details about each change
   - Mention affected files and components
   - Explain the impact of changes

3. Information to Include:
   - Types of changes (feat, fix, docs, style, etc.)
   - Specific files and components modified
   - Purpose and reasoning behind changes
   - Any notable improvements or optimizations
   - Dependencies or requirements affected

4. Style Requirements:
   - Use natural language, not commit message format
   - Avoid technical jargon where possible
   - Use bullet points for clarity
   - Include specific examples when helpful
   - Maintain consistent formatting

5. Example Format:
```
The recent changes focus on improving the user authentication system. Here's a detailed breakdown:

Features Added:
- JWT token handling implementation for secure authentication
- New login and logout API endpoints
- Enhanced user model with additional security fields

Bug Fixes:
- Resolved login timeout issues by implementing connection pooling
- Fixed token expiration handling
- Improved error messaging for authentication failures

Improvements:
- Optimized authentication queries for better performance
- Updated API documentation with authentication examples
- Added comprehensive test coverage for authentication flows
```

6. Processing Instructions:
- Analyze the provided git diff output
- Identify the main purpose and scope of changes
- Group related changes by type and functionality
- Extract specific details about each modification
- Focus on providing context and understanding