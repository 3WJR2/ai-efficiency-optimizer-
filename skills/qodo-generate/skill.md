# Qodo Generate Skill

AI-powered generation of tests, documentation, and code using Qodo CLI.

## Description

Automate creation of tests, documentation, API specs, changelogs, and more using Qodo's AI agents.

## Usage

### Generate Tests

```
/qodo-generate type=tests target=src/auth/login.py
/qodo-generate type=tests target=src/auth/ coverage=0.95
```

### Generate Documentation

```
/qodo-generate type=docs target=src/api/
/qodo-generate type=api-docs
/qodo-generate type=changelog
```

### Generate E2E Tests

```
/qodo-generate type=e2e-tests target="user login flow"
```

## Generation Types

- **tests** - Unit and integration tests
- **e2e-tests** - End-to-end test scenarios
- **docs** - General documentation
- **api-docs** - API documentation
- **changelog** - Release notes from commits

## Examples

### Example 1: Generate Unit Tests

```
/qodo-generate type=tests target=src/auth/login.py coverage=0.9
```

Generates comprehensive unit tests with 90% coverage.

### Example 2: API Documentation

```
/qodo-generate type=api-docs
```

Generates OpenAPI/Swagger specification.

### Example 3: Changelog

```
/qodo-generate type=changelog
```

Analyzes commits and generates formatted changelog.
