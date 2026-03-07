# Prompt Optimizer Skill

**Version**: 1.0.0
**Purpose**: Auto-generate optimal prompts based on Anthropic's prompting best practices, then present them to the user for review and editing before execution.

## Overview

The Prompt Optimizer analyzes the user's task intention and automatically generates a structured, high-quality prompt that follows Anthropic's official prompting best practices:

1. **Be clear and direct** - Explicit instructions, specific output format
2. **Add context** - Motivation and reasoning behind instructions
3. **Use XML tags** - Structured sections for unambiguous parsing
4. **Give a role** - Focused expertise for the task type
5. **Sequential steps** - Numbered instructions in logical order
6. **Quality validation** - Self-check criteria before finalizing
7. **Specify constraints** - Clear boundaries and limitations

## When This Skill Activates

This skill activates **automatically at the start of every new task** in a new Claude session. When a user provides their first message describing what they want to do, Claude:

1. Classifies the task category (code, debug, design, research, etc.)
2. Detects technologies and complexity level
3. Generates an optimized prompt using the appropriate template
4. Presents the prompt to the user in an editable format
5. Waits for user approval or edits before proceeding

## Supported Task Categories

- `code_implementation` - Building new features or functions
- `debugging` - Finding and fixing bugs
- `refactoring` - Improving code structure without changing behavior
- `code_review` - Evaluating code for quality and issues
- `system_design` - Architecting systems and components
- `research` - Investigating technologies or approaches
- `testing` - Writing tests and test strategies
- `frontend` - UI/UX component development
- `api_integration` - Connecting to APIs and services
- `performance_optimization` - Profiling and speeding up code
- `documentation` - Writing docs, guides, READMEs
- `security_audit` - Finding vulnerabilities
- `migration` - Moving between technologies
- `devops` - CI/CD, infrastructure, deployment
- `database` - Schema, queries, data modeling
- `data_analysis` - Analyzing datasets and extracting insights
- `general` - Catch-all for other tasks

## How to Use

### Automatic (Default)
Just describe your task naturally. The optimizer will:
1. Classify your intent
2. Generate the optimal prompt
3. Show it to you for review
4. Let you edit before execution

### Manual
```
/prompt-optimizer generate "your task description"
/prompt-optimizer status
```

## User Interaction Flow

```
User: "Fix the authentication bug in the login endpoint"
                    ↓
Claude: [Classifies as 'debugging', detects no specific tech]
                    ↓
Claude: "I've generated an optimized prompt for your task.
         Review and edit if needed:"

┌─────────────────────────────────────────────────────┐
│ GENERATED PROMPT (Editable)                         │
│                                                     │
│ You are an expert debugger and systems analyst who  │
│ methodically traces issues to their root cause.     │
│                                                     │
│ <task>                                              │
│ Fix the authentication bug in the login endpoint    │
│ </task>                                             │
│                                                     │
│ <instructions>                                      │
│ 1. Reproduce or understand the exact error...       │
│ 2. Read the relevant source files...                │
│ 3. Identify the root cause...                       │
│ 4. Propose and implement a targeted fix...          │
│ 5. Verify the fix resolves the issue...             │
│ </instructions>                                     │
│                                                     │
│ <debugging_approach>                                │
│ - Start with the error message or symptom...        │
│ - Check recent changes...                           │
│ - Examine inputs, state, and control flow...        │
│ - Validate assumptions...                           │
│ </debugging_approach>                               │
│                                                     │
│ <quality_validation>                                │
│ Before finalizing your response, verify:            │
│ - All requirements from the task are addressed...   │
│ </quality_validation>                               │
└─────────────────────────────────────────────────────┘

Options:
  [1] Accept and proceed with this prompt
  [2] Edit the prompt (provide your changes)
  [3] Skip optimization and use original request
```

## Learning

The optimizer learns from user edits:
- If users consistently remove certain sections, it adapts
- If users add similar instructions, it incorporates them
- Category frequency is tracked for prioritization
- Edit patterns inform future template improvements

## Files

- **Engine**: `~/.claude/scripts/prompt-optimizer.sh`
- **Config**: `~/.claude/data/prompt-optimizer/config.json`
- **History**: `~/.claude/data/prompt-optimizer/history.json`
- **Templates**: `~/.claude/data/prompt-optimizer/templates.json`

## Principles Applied (from Anthropic's Best Practices)

| Principle | How It's Applied |
|-----------|-----------------|
| Be clear and direct | Specific instructions with numbered steps |
| Add context | Motivation behind each instruction |
| Use XML tags | `<task>`, `<instructions>`, `<constraints>`, `<output_format>` |
| Give a role | Category-specific expert role |
| Use examples | Template-driven with category-specific patterns |
| Sequential steps | Numbered, ordered instructions |
| Quality validation | Self-check criteria for medium/high complexity tasks |
| Specify constraints | Clear boundaries per task type |
