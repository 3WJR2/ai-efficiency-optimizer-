# Claude custom skills completion
# Source this in ~/.zshrc: source ~/.claude/scripts/completion.zsh

_claude_skills_completion() {
    local -a skills
    skills=(
        'adaptive-intelligence:Adaptive learning and critical thinking'
        'autonomous-orchestration:Autonomous workflow orchestration'
        'context-engineering:Context optimization and curation'
        'dependency-management:Dependency analysis and management'
        'master-orchestrator:Master workflow coordinator'
        'pattern-recognition:Pattern identification and documentation'
        'planning-methodology:Implementation planning'
        'quality-validation:Quality assurance and validation'
        'research-methodology:Documentation research'
        'self-healing:Self-healing systems'
        'test-generation:Test generation and coverage'
    )

    _describe 'claude skills' skills
}

# Register completion for common slash command patterns
compdef _claude_skills_completion claude
