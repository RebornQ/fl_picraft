# Backend Development Guidelines

> Best practices for backend development in this project.

---

## Overview

**Status: Not Applicable**

This is a **pure local Flutter application** without a dedicated backend API layer. All data persistence is handled locally through:

- **Shared Preferences** - Simple key-value storage
- **Hive / Isar** (optional) - NoSQL local database
- **SQLite** (optional) - Relational local database

---

## Future Considerations

If backend API integration is needed in the future, this section should be updated to include:

| Guide | What to Document |
|-------|------------------|
| [Directory Structure](./directory-structure.md) | API client, interceptors, data sources |
| [Database Guidelines](./database-guidelines.md) | Local persistence patterns (Hive/SQLite) |
| [Error Handling](./error-handling.md) | Network errors, offline handling |
| [Quality Guidelines](./quality-guidelines.md) | API testing, mocking strategies |
| [Logging Guidelines](./logging-guidelines.md) | API request/response logging |

---

## Current Data Layer

For local data persistence patterns, refer to:

- `lib/core/storage/` - Local storage abstractions
- `lib/features/<feature>/data/datasources/` - Feature-specific data sources

---

**Language**: All documentation should be written in **English**.