#compdef claude

# Claude Code Auto-Completion
# Provides tab completion for Claude commands, agents, and skills

_claude() {
    local -a commands agents builtin_commands slash_commands

    # Built-in Claude commands
    builtin_commands=(
        '/help:Show help'
        '/clear:Clear screen'
        '/model:Switch model'
        '/logout:Logout'
        '/settings:Open settings'
    )

    # Custom slash commands from ~/.claude/commands/
    slash_commands=(
        '/autonomous:Autonomous workflow orchestration'
        '/context:Context engineering and analysis'
        '/implement:Implementation assistance'
        '/plan:Planning and design'
        '/research:Research methodology'
        '/workflow:Development workflow automation'
        '/skills:List all available skills'
    )

    # Agents from ~/.claude/agents/
    agents=(
        'brahma-analyzer:Code analysis and insights'
        'brahma-ci-runner:CI/CD pipeline execution'
        'brahma-dependency-resolver:Dependency management'
        'brahma-deployer:Deployment automation'
        'brahma-healer:Auto-fix and recovery'
        'brahma-investigator:Deep code investigation'
        'brahma-monitor:System monitoring'
        'brahma-optimizer:Performance optimization'
        'brahma-orchestrator:Multi-agent orchestration'
        'brahma-security-scanner:Security analysis'
        'brahma-test-generator:Test generation'
        'chief-architect:Architecture design'
        'code-implementer:Code implementation'
        'docs-researcher:Documentation research'
        'implementation-planner:Implementation planning'
    )

    # Main Claude commands
    commands=(
        'agent:Run an agent'
        'skill:Run a skill'
        'chat:Start chat session'
        'task:Execute a task'
    )

    local context state line
    typeset -A opt_args

    _arguments -C \
        '1: :->command' \
        '*:: :->args'

    case $state in
        command)
            _describe -t builtin-commands 'Built-in Commands' builtin_commands
            _describe -t slash-commands 'Slash Commands' slash_commands
            _describe -t commands 'Commands' commands
            _describe -t agents 'Agents' agents
            ;;
        args)
            case $line[1] in
                agent)
                    _describe 'Available Agents' agents
                    ;;
                skill)
                    _describe 'Available Skills' slash_commands
                    ;;
            esac
            ;;
    esac
}

_claude "$@"
