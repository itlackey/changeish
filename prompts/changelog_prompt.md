Generate a comprehensive changelog in the Keep a Changelog format:

1. Format Requirements:
   - Use YAML front matter for metadata
   - Group changes by release version
   - Subgroup changes by type (Added, Changed, Deprecated, Removed, Fixed, Security)
   - Include dates and version numbers
   - Maintain consistent indentation

2. Structure Guidelines:
   - Start with version header
   - Include release date
   - Group changes by type
   - Use bullet points for individual changes
   - Maintain consistent formatting

3. Content Organization:
   - Process all provided summaries
   - Group related changes together
   - Maintain chronological order
   - Include all change types
   - Focus on technical accuracy

4. Information to Include:
   - Version numbers
   - Release dates
   - All change types
   - Detailed change descriptions
   - Breaking changes
   - Upgrade notes

5. Example Format:
```
---
title: Changelog
description: All notable changes to this project will be documented in this file.
template: changelog
---

## [1.2.3] - 2025-07-04

### Added
- JWT token handling for secure authentication
- New login and logout API endpoints
- Enhanced user model with additional security fields

### Changed
- Optimized authentication queries for better performance
- Updated API documentation with authentication examples
- Improved error messaging for authentication failures

### Fixed
- Resolved login timeout issues through connection pooling
- Fixed token expiration handling
- Improved error messaging for authentication failures

### Security
- Enhanced security with token-based authentication
- Added secure token storage
- Improved session management

## [1.2.2] - 2025-06-15
... previous release changes ...
```

6. Processing Instructions:
- Analyze all provided summaries
- Identify release boundaries
- Group changes by type
- Maintain chronological order
- Ensure consistent formatting
- Focus on technical accuracy