# Qodo Refactor Skill

AI-powered code refactoring suggestions using Qodo CLI.

## Description

Get intelligent refactoring recommendations to improve code quality, maintainability, and adherence to best practices.

## Usage

### General Refactoring

```
/qodo-refactor
/qodo-refactor target=src/utils/data_processor.py
```

### Focused Refactoring

```
/qodo-refactor focus=complexity
/qodo-refactor focus=duplication
/qodo-refactor focus=patterns
/qodo-refactor focus=naming
```

### Specific Refactoring

```
/qodo-refactor target="the UserManager god class"
/qodo-refactor target="nested if statements in authentication"
```

## Refactoring Focus Areas

- **complexity** - Reduce cyclomatic complexity
- **duplication** - Remove duplicate code (DRY principle)
- **patterns** - Apply design patterns
- **naming** - Improve variable/function names
- **all** - Comprehensive refactoring analysis

## Examples

### Example 1: Reduce Complexity

```
/qodo-refactor target=src/auth/login.py focus=complexity
```

Suggests extracting methods, simplifying conditionals.

### Example 2: Remove Duplication

```
/qodo-refactor focus=duplication
```

Identifies duplicate code across codebase.

### Example 3: Apply Patterns

```
/qodo-refactor target="database access" focus=patterns
```

Suggests Repository pattern, Dependency Injection, etc.
