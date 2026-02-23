# Qodo Review Skill

AI-powered code review integration for Claude Code using Qodo CLI.

## Description

This skill integrates Qodo CLI's comprehensive code review capabilities directly into your Claude Code workflow. Run security scans, performance analysis, and code quality reviews without leaving your development environment.

## Usage

### Basic Usage

```
/qodo-review
```

Runs default security review on current directory.

### Review Types

```
/qodo-review type=security
/qodo-review type=performance
/qodo-review type=quality
/qodo-review type=full
```

### Specific Files/Directories

```
/qodo-review type=security files=src/auth/
/qodo-review type=performance files=src/utils/data_processor.py
```

### Custom Agent

```
/qodo-review type=database-review
/qodo-review type=api-design-review
/qodo-review type=refactor
```

### Model Selection

```
/qodo-review type=security model=claude-haiku-4-5
/qodo-review type=quality model=claude-opus-4-6
```

### Custom Parameters

```
/qodo-review type=test-generator threshold="coverage_threshold=0.9"
/qodo-review type=code-quality-review threshold="max_complexity=10"
```

## Examples

### Example 1: Quick Security Check

```
/qodo-review
```

Output:
```
🔒 Running Qodo Security Review...

🔴 CRITICAL: Hardcoded credentials detected
  File: src/auth/login.py:15
  Issue: Database password in source code
  Fix: Use environment variables

⚠️ HIGH: SQL injection vulnerability
  File: src/database/user_repository.py:42
  Fix: Use parameterized queries
```

### Example 2: Performance Analysis

```
/qodo-review type=performance files=src/utils/
```

Output:
```
⚡ Running Qodo Performance Review...

🔴 CRITICAL: O(n²) nested loop
  File: src/utils/data_processor.py:78
  Impact: 100x slower with 100 records
  Fix: Use hash map for O(n) complexity
```

### Example 3: Comprehensive Review

```
/qodo-review type=full
```

Runs security → performance → quality review chain.

### Example 4: Generate Tests

```
/qodo-review type=test-generator files=src/auth/login.py threshold="coverage_threshold=0.9"
```

Generates unit tests with 90% coverage target.

## Review Types

### Built-in Reviews

- **security** - OWASP Top 10, hardcoded secrets, injection vulnerabilities
- **performance** - Algorithm complexity, N+1 queries, memory leaks
- **quality** - Maintainability, best practices, code smells
- **full** - Comprehensive security + performance + quality

### Specialized Reviews

- **accessibility-review** - WCAG compliance, ARIA labels
- **api-design-review** - RESTful API design validation
- **database-review** - Schema optimization, query performance
- **ci-cd-review** - Pipeline configuration best practices

### Code Improvement

- **refactor** - Refactoring suggestions
- **test-generator** - Generate unit/integration tests
- **e2e-test-generator** - Generate E2E test scenarios
- **doc-generator** - Generate documentation

### Advanced

- **dependency-updater** - Security updates and CVE scanning
- **pr-ready-check** - Pre-PR verification checklist
- **changelog-generator** - Generate changelogs from commits

## Integration with Claude Workflow

This skill seamlessly integrates Qodo reviews into your Claude Code workflow:

1. **Before Commit**: Run `/qodo-review` to catch issues early
2. **During Development**: Use `/qodo-review type=performance` for optimization
3. **Before PR**: Run `/qodo-review type=full` for comprehensive check
4. **Code Review**: Use specific agents for targeted analysis

## Requirements

- Qodo CLI installed: `npm install -g @qodo/command`
- Authenticated: `qodo login`
- Agent configuration: `agent.toml` in project root

## Output Format

Reviews return structured findings with:
- **Severity**: Critical, High, Medium, Low
- **Location**: File path and line number
- **Issue**: Clear description of the problem
- **Impact**: Explanation of consequences
- **Fix**: Specific remediation steps with code examples

## Tips

1. **Fast Reviews**: Use `model=claude-haiku-4-5` for quicker results
2. **Targeted**: Specify `files=` to review only changed code
3. **Chain Reviews**: Run multiple reviews sequentially
4. **Custom Agents**: Create custom agents in `agent.toml`

## Troubleshooting

**"Qodo API key not found"**
- Run: `qodo login`
- Or set: `export QODO_API_KEY=your-key`

**"No agent configuration file"**
- Ensure `agent.toml` exists in project root
- Or specify path: `--agent-file=path/to/agent.toml`

**Slow performance**
- Use faster model: `model=claude-haiku-4-5`
- Review specific files only

## See Also

- [Qodo CLI Guide](https://docs.qodo.ai/qodo-documentation/qodo-command)
- Project `agent.toml` for available agents
- Project `docs/QODO_CLI_GUIDE.md` for detailed documentation
