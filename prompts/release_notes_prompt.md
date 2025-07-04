Generate a comprehensive release notes document from the provided change summaries:

1. Document Structure:
   - Start with a brief overview paragraph
   - Organize changes by type (features, fixes, improvements)
   - Include version information
   - Group related changes logically
   - End with upgrade instructions if needed

2. Content Requirements:
   - Process all provided change summaries
   - Group similar changes together
   - Maintain chronological order where relevant
   - Include all major changes and their types
   - Focus on user-impactful changes

3. Format Guidelines:
   - Use clear section headers
   - Employ consistent bullet point formatting
   - Include version numbers
   - Add upgrade instructions if needed
   - Maintain professional tone

4. Information to Include:
   - Version number
   - Release date
   - Major features and improvements
   - Bug fixes and resolutions
   - Breaking changes (if any)
   - Upgrade instructions
   - Known issues or limitations

5. Example Format:
```
# Release Notes - v1.2.3 (2025-07-04)

## Overview
This release focuses on improving the user authentication system with several security enhancements and performance optimizations.

## New Features
- JWT token handling implementation for secure authentication
- New login and logout API endpoints
- Enhanced user model with additional security fields

## Bug Fixes
- Resolved login timeout issues through connection pooling
- Fixed token expiration handling
- Improved error messaging for authentication failures

## Improvements
- Optimized authentication queries for better performance
- Updated API documentation with authentication examples
- Added comprehensive test coverage for authentication flows

## Upgrade Instructions
To upgrade from the previous version:
1. Update dependencies to the latest versions
2. Run database migrations if prompted
3. Clear any cached authentication tokens
4. Restart the application

## Known Issues
- Some users may need to re-authenticate after upgrade
- Token expiration warnings may appear during transition period
```

6. Processing Instructions:
- Read and analyze all provided change summaries
- Identify the overall scope and impact of changes
- Group related changes by type and functionality
- Extract version information if provided
- Focus on providing clear, actionable information