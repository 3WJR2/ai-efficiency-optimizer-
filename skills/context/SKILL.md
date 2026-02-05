---
name: context
description: Analyze and optimize context configuration. Reviews CLAUDE.md, knowledge-core.md, and active context for optimization opportunities.
argument-hint: Optional analysis target (analyze|optimize|reset)
disable-model-invocation: true
---

# /context - Context Analysis & Optimization

Analyze and optimize your Claude Code context configuration using Anthropic's context engineering principles.

## Usage

```bash
/context                # Analyze mode (default)
/context analyze        # Same as default
/context optimize       # Actively optimize context
/context reset          # Reset to templates
```

## What This Does

### Analyze Mode (Default)

When you run `/context` or `/context analyze`:

1. **Read context files**
   - CLAUDE.md (project configuration)
   - knowledge-core.md (accumulated learnings)
   - Imported files (via `@` syntax)

2. **Analyze token count and relevance**
   - Count total tokens in context
   - Identify stale/redundant information
   - Check for context rot indicators

3. **Identify optimization opportunities**
   - Sections that should be archived
   - Redundant content that can be consolidated
   - Missing imports that could improve modularity

4. **Report findings**
   - Current token usage
   - Stale information detected
   - Potential token savings
   - Recommended actions

### Optimize Mode

When you run `/context optimize`:

1. **Run analysis** (as above)

2. **Archive stale information**
   - Move outdated patterns to knowledge-core.md historical section
   - Add timestamps to archived content
   - Preserve information for future retrieval

3. **Prune redundant context**
   - Remove duplicate information
   - Consolidate similar sections
   - Replace verbose explanations with concise bullet points

4. **Update CLAUDE.md**
   - Keep only high-signal, project-specific content
   - Use imports for modular organization
   - Ensure clear structure with markdown headings

5. **Report token savings**
   - Before/after token counts
   - Percentage reduction
   - Expected performance improvement

### Reset Mode

When you run `/context reset`:

1. **Confirmation prompt**
   - Warns that this will discard current context
   - Asks for explicit confirmation

2. **Restore templates** (if confirmed)
   - CLAUDE.md → `.claude/templates/CLAUDE.md.template`
   - knowledge-core.md → Fresh template
   - Clear project-specific customizations

3. **Fresh start**
   - Ideal for switching to new project
   - Removes accumulated context rot
   - Begins with clean slate

## When to Use

### Run `/context analyze` when:
- ✅ Conversation feels sluggish (context rot suspected)
- ✅ Starting new project in same repo
- ✅ After major refactoring (old patterns obsolete)
- ✅ Monthly maintenance (context hygiene)
- ✅ Every 50 messages in long conversations

### Run `/context optimize` when:
- ✅ Analysis shows 15%+ potential savings
- ✅ Switching major tasks (e.g., API work → UI work)
- ✅ Context rot indicators detected
- ✅ Performance feels degraded

### Run `/context reset` when:
- ✅ Starting completely new project
- ✅ Context is severely corrupted or misaligned
- ✅ Want fresh start after major project pivot

## Integration with Context Engineering

This command implements Anthropic's context engineering principles:

**Context Engineering Definition**:
> "The art and science of curating what goes into the limited context window from
> the constantly evolving universe of possible information."

**Key Principles**:
1. **Context Rot is Real**: Information degrades over time
2. **Finite Attention Budget**: Optimize for signal-to-noise ratio
3. **Active Curation**: Editing context improves performance
4. **Structure as Context**: Organization encodes information

**Performance Results** (Anthropic Research):
- 39% improvement in agent-based search
- 84% token reduction in 100-round web search
- Higher quality decisions due to focused context

## Best Practices

1. **Regular Analysis**: Don't wait for problems - proactive context hygiene
2. **Archive, Don't Delete**: Move to knowledge-core.md for future retrieval
3. **Project-Specific Only**: Remove generic advice Claude already knows
4. **Use Imports**: Modular organization beats monolithic CLAUDE.md
5. **Clear Structure**: Headings and sections improve navigability

---

**Executing command...**

Analyze and optimize your Claude Code context files. The system will:
1. Read all context files (CLAUDE.md, knowledge-core.md, imports)
2. Count tokens and identify stale/redundant content
3. Report optimization opportunities
4. Optionally apply optimizations (if optimize mode)
5. Provide token savings report

**Context engineering is not optional - it's the foundation of sustainable, high-performance agent interactions.**
