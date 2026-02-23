#!/bin/bash
# Quick reference card for Claude skills
# Usage: skills or skills-help

cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║                    CLAUDE SKILLS QUICK REFERENCE               ║
╚════════════════════════════════════════════════════════════════╝

📚 Available Custom Skills:
────────────────────────────────────────────────────────────────
  /adaptive-intelligence    Self-learning & critical thinking
  /autonomous-orchestration Autonomous workflow execution
  /context-engineering     Context optimization (39% improvement)
  /dependency-management   Dependency analysis & management
  /master-orchestrator     Master workflow coordinator
  /pattern-recognition     Pattern capture & documentation
  /planning-methodology    Implementation planning
  /quality-validation      Quality gates & validation
  /research-methodology    Documentation research
  /self-healing           Self-healing systems
  /test-generation        Test generation & coverage

🎯 Official Plugin Skills (from system):
────────────────────────────────────────────────────────────────
  /keybindings-help       Customize keyboard shortcuts
  /context               Analyze context configuration
  /workflow              Complete Research→Plan→Implement
  /research              Quick docs research
  /plan                  Create implementation plans
  /implement             Execute with self-correction
  /autonomous            Autonomous mode control

💡 Usage:
────────────────────────────────────────────────────────────────
  In conversation: Just mention the skill naturally
    ✓ "use adaptive-intelligence to analyze this"
    ✓ "help me with context-engineering"
    ✓ "run quality-validation on my code"

  For detailed info on any skill:
    $ cat ~/.claude/skills/<skill-name>/skill.md

  To search skills:
    $ ~/.claude/scripts/list-skills.sh <search_term>

🔍 Why no auto-complete?
────────────────────────────────────────────────────────────────
  Claude Code 2.1.29 only auto-completes built-in commands.
  Custom skills work but don't show in auto-complete.
  This is a platform limitation, not a configuration issue.

⚡ Quick Commands:
────────────────────────────────────────────────────────────────
  skills              Show this reference
  skills-list         List all skills with details
  skills-search <term> Search for specific skills

EOF
