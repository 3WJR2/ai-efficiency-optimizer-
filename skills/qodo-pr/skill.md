# Qodo PR Skill

Comprehensive Pull Request readiness validation using Qodo CLI.

## Description

This skill runs a complete PR review workflow including security, performance, quality checks, and PR readiness validation. Optionally posts results to Azure DevOps PR comments.

## Usage

### Basic PR Check

```
/qodo-pr
```

Runs comprehensive review locally.

### With PR Comment

```
/qodo-pr post_comment=true pr_id=123
```

Runs review and posts results to Azure DevOps PR #123.

## What It Checks

1. **Security Review** - OWASP vulnerabilities, secrets, injection
2. **Performance Review** - Algorithm complexity, N+1 queries
3. **Code Quality** - Maintainability, best practices, test coverage
4. **PR Requirements** - Tests passing, docs updated, formatting correct

## Output

Generates comprehensive report with:
- Summary of all findings
- Severity counts (Critical/High/Medium/Low)
- Specific recommendations
- PR approval recommendation

## Examples

### Example 1: Local PR Check

```
/qodo-pr
```

Output:
```
🤖 Qodo PR Review

✅ Security: PASSED (0 critical issues)
⚠️  Performance: 1 high priority issue
✅ Quality: Score 85/100
✅ PR Requirements: All checks passed

Recommendation: APPROVE with minor improvements
```

### Example 2: Post to Azure DevOps

```
/qodo-pr post_comment=true pr_id=123
```

Posts detailed review comment to PR #123 in Azure DevOps.

## Requirements

- Qodo CLI authenticated
- For PR comments: `AZURE_DEVOPS_PAT` and `AZURE_DEVOPS_ORG` env vars

## See Also

- `/qodo-review` - Individual review types
- `scripts/qodo-pr-review.sh` - Standalone PR review script
