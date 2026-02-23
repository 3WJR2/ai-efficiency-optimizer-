#!/bin/bash
# Show all available Claude commands with descriptions

cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                 AVAILABLE CLAUDE COMMANDS                     ║
╚══════════════════════════════════════════════════════════════╝

📋 WORKFLOW COMMANDS
  /workflow <description>  - Full development workflow automation
  /plan <feature>          - Create implementation plan
  /implement <task>        - Implement code changes
  /autonomous <goal>       - Autonomous multi-agent orchestration

🔍 ANALYSIS COMMANDS
  /context                 - Context engineering & analysis
  /research <topic>        - Research methodology

🤖 BRAHMA AGENTS (Use with: claude agent <name>)
  brahma-analyzer          - Code analysis and insights
  brahma-ci-runner         - CI/CD pipeline execution
  brahma-dependency-resolver - Dependency management
  brahma-deployer          - Deployment automation
  brahma-healer            - Auto-fix and recovery
  brahma-investigator      - Deep code investigation
  brahma-monitor           - System monitoring
  brahma-optimizer         - Performance optimization
  brahma-orchestrator      - Multi-agent orchestration
  brahma-security-scanner  - Security analysis
  brahma-test-generator    - Test generation

👨‍💼 ARCHITECT AGENTS
  chief-architect          - Architecture design
  code-implementer         - Code implementation
  docs-researcher          - Documentation research
  implementation-planner   - Implementation planning

⚙️  BUILT-IN COMMANDS
  /help                    - Show help
  /clear                   - Clear screen
  /model                   - Switch model
  /skills                  - Show this menu

╔══════════════════════════════════════════════════════════════╗
║ TIP: Type any command above to use it!                       ║
║ Example: /workflow add user authentication                   ║
╚══════════════════════════════════════════════════════════════╝
EOF
