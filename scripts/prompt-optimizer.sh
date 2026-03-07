#!/usr/bin/env bash
# prompt-optimizer.sh v2.0 - Auto-generates optimal prompts based on Anthropic's best practices
# Enhanced with: project-aware context, few-shot learning, edit-based adaptation,
# task decomposition, codebase complexity detection, ambiguity detection,
# tailored output formats, and agent-lightning RL integration.
#
# Usage: prompt-optimizer.sh <command> [args]
#   generate "<user_request>" [cwd]  - Generate optimized prompt (cwd optional)
#   classify "<user_request>"        - Classify the task category
#   history                          - Show prompt generation history
#   status                           - Show optimizer status
#   record-edit "<category>" "<original>" "<edited>" - Record user's edit for learning
#   record-outcome "<category>" "<result>" - Record task outcome for RL

# Paths
DATA_DIR="$HOME/.claude/data/prompt-optimizer"
CONFIG_FILE="$DATA_DIR/config.json"
HISTORY_FILE="$DATA_DIR/history.json"
TEMPLATES_FILE="$DATA_DIR/templates.json"
EXAMPLES_FILE="$DATA_DIR/examples.json"
EDIT_PATTERNS_FILE="$DATA_DIR/edit-patterns.json"
USER_PROFILE="$HOME/.claude/data/user-profile.json"
INTERACTION_LEARNING="$HOME/.claude/data/interaction-learning.json"
RL_BRIDGE="$HOME/.claude/scripts/agent-lightning-bridge.sh"

# Ensure data directory exists
mkdir -p "$DATA_DIR"

# Initialize examples file if missing
if [ ! -f "$EXAMPLES_FILE" ]; then
    cat > "$EXAMPLES_FILE" <<'EXEOF'
{"version":"1.0.0","examples":{}}
EXEOF
fi

# Initialize edit patterns file if missing
if [ ! -f "$EDIT_PATTERNS_FILE" ]; then
    cat > "$EDIT_PATTERNS_FILE" <<'EPEOF'
{"version":"1.0.0","patterns":{},"section_removals":{},"section_additions":{},"common_additions":[]}
EPEOF
fi

# ─── Helper Functions ───────────────────────────────────────────────

json_read() {
    jq -r "$2" "$1" 2>/dev/null || echo ""
}

timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ─── IMPROVEMENT #1: Project-Aware Context Detection ───────────────

detect_project_context() {
    local cwd="${1:-.}"

    # If cwd doesn't exist or isn't a directory, return empty
    if [ ! -d "$cwd" ]; then
        return
    fi

    local context=""
    local lang=""
    local framework=""
    local tools=""
    local deps=""

    # -- Detect by manifest files --

    # Node.js / JavaScript / TypeScript
    if [ -f "$cwd/package.json" ]; then
        lang="JavaScript/TypeScript"
        local pkg_name pkg_deps
        pkg_name=$(jq -r '.name // ""' "$cwd/package.json" 2>/dev/null)
        # Detect frameworks from dependencies
        pkg_deps=$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' "$cwd/package.json" 2>/dev/null || echo "")
        echo "$pkg_deps" | grep -q '^react$' && framework="${framework}React, "
        echo "$pkg_deps" | grep -q '^next$' && framework="${framework}Next.js, "
        echo "$pkg_deps" | grep -q '^vue$' && framework="${framework}Vue, "
        echo "$pkg_deps" | grep -q '^nuxt$' && framework="${framework}Nuxt, "
        echo "$pkg_deps" | grep -q '^angular' && framework="${framework}Angular, "
        echo "$pkg_deps" | grep -q '^svelte$' && framework="${framework}Svelte, "
        echo "$pkg_deps" | grep -q '^express$' && framework="${framework}Express, "
        echo "$pkg_deps" | grep -q '^fastify$' && framework="${framework}Fastify, "
        echo "$pkg_deps" | grep -q '^prisma$\|^@prisma' && tools="${tools}Prisma, "
        echo "$pkg_deps" | grep -q '^mongoose$' && tools="${tools}Mongoose, "
        echo "$pkg_deps" | grep -q '^tailwindcss$' && tools="${tools}Tailwind CSS, "
        echo "$pkg_deps" | grep -q '^jest$' && tools="${tools}Jest, "
        echo "$pkg_deps" | grep -q '^vitest$' && tools="${tools}Vitest, "
        echo "$pkg_deps" | grep -q '^mocha$' && tools="${tools}Mocha, "
        echo "$pkg_deps" | grep -q '^typescript$' && lang="TypeScript"
        [ -f "$cwd/tsconfig.json" ] && lang="TypeScript"
    fi

    # Python
    if [ -f "$cwd/requirements.txt" ] || [ -f "$cwd/pyproject.toml" ] || [ -f "$cwd/setup.py" ] || [ -f "$cwd/Pipfile" ]; then
        lang="Python"
        local pyfiles=""
        [ -f "$cwd/requirements.txt" ] && pyfiles="$cwd/requirements.txt"
        [ -f "$cwd/pyproject.toml" ] && pyfiles="$cwd/pyproject.toml"
        if [ -n "$pyfiles" ]; then
            grep -qiE 'django' $pyfiles 2>/dev/null && framework="${framework}Django, "
            grep -qiE 'flask' $pyfiles 2>/dev/null && framework="${framework}Flask, "
            grep -qiE 'fastapi' $pyfiles 2>/dev/null && framework="${framework}FastAPI, "
            grep -qiE 'sqlalchemy' $pyfiles 2>/dev/null && tools="${tools}SQLAlchemy, "
            grep -qiE 'pytest' $pyfiles 2>/dev/null && tools="${tools}pytest, "
            grep -qiE 'pandas' $pyfiles 2>/dev/null && tools="${tools}pandas, "
            grep -qiE 'celery' $pyfiles 2>/dev/null && tools="${tools}Celery, "
        fi
    fi

    # Rust
    if [ -f "$cwd/Cargo.toml" ]; then
        lang="Rust"
        grep -qiE 'actix' "$cwd/Cargo.toml" 2>/dev/null && framework="${framework}Actix, "
        grep -qiE 'axum' "$cwd/Cargo.toml" 2>/dev/null && framework="${framework}Axum, "
        grep -qiE 'tokio' "$cwd/Cargo.toml" 2>/dev/null && tools="${tools}Tokio, "
    fi

    # Go
    if [ -f "$cwd/go.mod" ]; then
        lang="Go"
        grep -qiE 'gin-gonic' "$cwd/go.mod" 2>/dev/null && framework="${framework}Gin, "
        grep -qiE 'fiber' "$cwd/go.mod" 2>/dev/null && framework="${framework}Fiber, "
    fi

    # Java / Kotlin
    if [ -f "$cwd/pom.xml" ] || [ -f "$cwd/build.gradle" ] || [ -f "$cwd/build.gradle.kts" ]; then
        lang="Java"
        [ -f "$cwd/build.gradle.kts" ] && lang="Kotlin"
        grep -qiE 'spring' "$cwd/pom.xml" "$cwd/build.gradle" "$cwd/build.gradle.kts" 2>/dev/null && framework="${framework}Spring Boot, "
    fi

    # Ruby
    if [ -f "$cwd/Gemfile" ]; then
        lang="Ruby"
        grep -qiE 'rails' "$cwd/Gemfile" 2>/dev/null && framework="${framework}Rails, "
        grep -qiE 'sinatra' "$cwd/Gemfile" 2>/dev/null && framework="${framework}Sinatra, "
    fi

    # PHP
    if [ -f "$cwd/composer.json" ]; then
        lang="PHP"
        grep -qiE 'laravel' "$cwd/composer.json" 2>/dev/null && framework="${framework}Laravel, "
    fi

    # -- Detect infrastructure --
    [ -f "$cwd/Dockerfile" ] || [ -f "$cwd/docker-compose.yml" ] || [ -f "$cwd/docker-compose.yaml" ] && tools="${tools}Docker, "
    [ -f "$cwd/.github/workflows/"*.yml ] 2>/dev/null && tools="${tools}GitHub Actions, "
    [ -f "$cwd/.gitlab-ci.yml" ] && tools="${tools}GitLab CI, "
    [ -f "$cwd/Makefile" ] && tools="${tools}Make, "
    [ -d "$cwd/.git" ] && tools="${tools}Git, "

    # -- Detect database --
    local db=""
    if [ -f "$cwd/docker-compose.yml" ] || [ -f "$cwd/docker-compose.yaml" ]; then
        local composefile="$cwd/docker-compose.yml"
        [ -f "$cwd/docker-compose.yaml" ] && composefile="$cwd/docker-compose.yaml"
        grep -qiE 'postgres' "$composefile" 2>/dev/null && db="${db}PostgreSQL, "
        grep -qiE 'mysql|mariadb' "$composefile" 2>/dev/null && db="${db}MySQL, "
        grep -qiE 'mongo' "$composefile" 2>/dev/null && db="${db}MongoDB, "
        grep -qiE 'redis' "$composefile" 2>/dev/null && db="${db}Redis, "
    fi

    # -- Count project files for size estimation --
    local file_count=0
    if command -v find >/dev/null 2>&1; then
        file_count=$(find "$cwd" -maxdepth 4 -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.rb" -o -name "*.php" \) -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/venv/*" -not -path "*/__pycache__/*" 2>/dev/null | wc -l | tr -d ' ')
    fi

    local project_size="small"
    if [ "$file_count" -gt 100 ]; then
        project_size="large"
    elif [ "$file_count" -gt 30 ]; then
        project_size="medium"
    fi

    # -- Build context string --
    # Trim trailing ", " from collected values
    framework=$(echo "$framework" | sed 's/, $//')
    tools=$(echo "$tools" | sed 's/, $//')
    db=$(echo "$db" | sed 's/, $//')

    if [ -n "$lang" ]; then
        context="Language: $lang"
        [ -n "$framework" ] && context="$context | Framework: $framework"
        [ -n "$tools" ] && context="$context | Tools: $tools"
        [ -n "$db" ] && context="$context | Database: $db"
        context="$context | Project size: $project_size ($file_count source files)"
    fi

    echo "$context"
}

# ─── Task Classification ───────────────────────────────────────────

classify_task() {
    local request="$1"
    local request_lower
    request_lower=$(echo "$request" | tr '[:upper:]' '[:lower:]')

    if echo "$request_lower" | grep -qE '(security|vulnerabilit|audit|penetration|owasp|xss|sql.inject|csrf)'; then
        echo "security_audit"
    elif echo "$request_lower" | grep -qE '(migrat|upgrade|transition|convert.*(from|to)|move.*(from|to)|port.*(from|to))'; then
        echo "migration"
    elif echo "$request_lower" | grep -qE '(deploy|ci.?cd|pipeline|docker|kubernetes|k8s|terraform|ansible|helm|github.action|gitlab.ci|jenkins)'; then
        echo "devops"
    elif echo "$request_lower" | grep -qE '(schema|query|sql|database|table|index|join|postgres|mysql|mongo|redis|migration.*db)'; then
        echo "database"
    elif echo "$request_lower" | grep -qE '(analyz.*data|dataset|csv|pandas|dataframe|stats|statistic)'; then
        echo "data_analysis"
    elif echo "$request_lower" | grep -qE '(debug|fix.*bug|error|crash|exception|traceback|stack.trace|not.working|broken|issue|fails|failing)'; then
        echo "debugging"
    elif echo "$request_lower" | grep -qE '(refactor|clean.up|restructure|reorganiz|simplif|extract.*method|extract.*class|reduce.*complex)'; then
        echo "refactoring"
    elif echo "$request_lower" | grep -qE '(review.*code|code.*review|pr.*review|pull.*request|check.*code|look.*at.*code)'; then
        echo "code_review"
    elif echo "$request_lower" | grep -qE '(design.*system|architect|scale|distributed|microservice|monolith|system.*design|high.level)'; then
        echo "system_design"
    elif echo "$request_lower" | grep -qE '(test|spec|unit.test|integration.test|e2e|coverage|mock|stub|fixture|assert|jest|pytest|mocha)'; then
        echo "testing"
    elif echo "$request_lower" | grep -qE '(api|endpoint|rest|graphql|webhook|integrat|connect.*to|fetch.*from|call.*service)'; then
        echo "api_integration"
    elif echo "$request_lower" | grep -qE '(frontend|ui|ux|component|react|vue|angular|svelte|css|html|layout|responsive|animation|button|form|modal|page|dashboard|chart|graph|visualization)'; then
        echo "frontend"
    elif echo "$request_lower" | grep -qE '(performance|optimiz|slow|speed|latency|bottleneck|profil|benchmark|cach|memory.leak)'; then
        echo "performance_optimization"
    elif echo "$request_lower" | grep -qE '(document|readme|doc|wiki|guide|tutorial|how.to|explain|comment|jsdoc|docstring)'; then
        echo "documentation"
    elif echo "$request_lower" | grep -qE '(research|investigat|compar|evaluat|find.*out|what.*is|how.*does|look.*into|explore|survey)'; then
        echo "research"
    elif echo "$request_lower" | grep -qE '(implement|create|build|add|write|develop|make|code|function|class|module|script|feature|endpoint)'; then
        echo "code_implementation"
    else
        echo "general"
    fi
}

# ─── Detect Language/Framework from Request ─────────────────────────

detect_tech() {
    local request="$1"
    local request_lower
    request_lower=$(echo "$request" | tr '[:upper:]' '[:lower:]')
    local techs=""

    echo "$request_lower" | grep -qE '\bpython\b|\bpy\b|\.py\b' && techs="$techs Python"
    echo "$request_lower" | grep -qE '\btypescript\b|\bts\b|\.ts\b' && techs="$techs TypeScript"
    echo "$request_lower" | grep -qE '\bjavascript\b|\bjs\b|\.js\b' && techs="$techs JavaScript"
    echo "$request_lower" | grep -qE '\bjava\b|\.java\b' && techs="$techs Java"
    echo "$request_lower" | grep -qE '\brust\b|\.rs\b|cargo' && techs="$techs Rust"
    echo "$request_lower" | grep -qE '\bgo\b|golang|\.go\b' && techs="$techs Go"
    echo "$request_lower" | grep -qE '\bc\+\+\b|cpp|\.cpp\b|\.hpp\b' && techs="$techs C++"
    echo "$request_lower" | grep -qE '\bruby\b|\.rb\b|rails' && techs="$techs Ruby"
    echo "$request_lower" | grep -qE '\bswift\b|\.swift\b' && techs="$techs Swift"
    echo "$request_lower" | grep -qE '\bkotlin\b|\.kt\b' && techs="$techs Kotlin"
    echo "$request_lower" | grep -qE '\bphp\b|\.php\b|laravel' && techs="$techs PHP"
    echo "$request_lower" | grep -qE '\bbash\b|shell|\.sh\b|zsh' && techs="$techs Bash"
    echo "$request_lower" | grep -qE '\breact\b|next\.?js|jsx|tsx' && techs="$techs React"
    echo "$request_lower" | grep -qE '\bvue\b|nuxt' && techs="$techs Vue"
    echo "$request_lower" | grep -qE '\bangular\b' && techs="$techs Angular"
    echo "$request_lower" | grep -qE '\bdjango\b' && techs="$techs Django"
    echo "$request_lower" | grep -qE '\bflask\b|fastapi' && techs="$techs Flask/FastAPI"
    echo "$request_lower" | grep -qE '\bexpress\b|node\.?js|koa' && techs="$techs Node.js"
    echo "$request_lower" | grep -qE '\bspring\b' && techs="$techs Spring"
    echo "$request_lower" | grep -qE '\bdocker\b' && techs="$techs Docker"
    echo "$request_lower" | grep -qE '\bkubernetes\b|k8s' && techs="$techs Kubernetes"

    echo "$techs" | xargs
}

# ─── IMPROVEMENT #5: Dynamic Complexity Detection ──────────────────

detect_complexity() {
    local request="$1"
    local category="$2"
    local cwd="${3:-.}"
    local word_count
    word_count=$(echo "$request" | wc -w | tr -d ' ')
    local score=0

    # Word count scoring
    [ "$word_count" -gt 50 ] && score=$((score + 3))
    [ "$word_count" -gt 20 ] && score=$((score + 1))

    # Keyword complexity indicators
    echo "$request" | grep -qiE '(system.*design|architect|distributed|migrat|security.*audit|multi.*service)' && score=$((score + 3))
    echo "$request" | grep -qiE '(complex|advanced|enterprise|production|scale|comprehensive|multi.file|cross.module)' && score=$((score + 2))
    echo "$request" | grep -qiE '(implement|build|create|refactor|integrat|optimiz)' && score=$((score + 1))

    # Category complexity
    case "$category" in
        system_design|migration|security_audit) score=$((score + 2)) ;;
        refactoring|performance_optimization|api_integration) score=$((score + 1)) ;;
    esac

    # Codebase size factor (if in a project)
    if [ -d "$cwd" ]; then
        local file_count=0
        file_count=$(find "$cwd" -maxdepth 4 -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.rb" \) -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/venv/*" 2>/dev/null | wc -l | tr -d ' ')
        [ "$file_count" -gt 100 ] && score=$((score + 2))
        [ "$file_count" -gt 30 ] && score=$((score + 1))
    fi

    # Multiple action verbs suggest multi-step task
    local verb_count
    verb_count=$(echo "$request" | grep -oiE '(create|build|add|implement|fix|update|refactor|test|deploy|configure|migrate|integrate)' | wc -l | tr -d ' ')
    [ "$verb_count" -gt 2 ] && score=$((score + 2))

    if [ "$score" -ge 5 ]; then
        echo "high"
    elif [ "$score" -ge 2 ]; then
        echo "medium"
    else
        echo "low"
    fi
}

# ─── Extract Key Intent ─────────────────────────────────────────────

extract_intent() {
    local request="$1"

    if echo "$request" | grep -qoiE '(create|build|implement|add|write|develop|make|design|architect)'; then
        echo "Create"
    elif echo "$request" | grep -qoiE '(fix|debug|resolve|repair|patch)'; then
        echo "Fix"
    elif echo "$request" | grep -qoiE '(refactor|restructure|reorganize|clean)'; then
        echo "Refactor"
    elif echo "$request" | grep -qoiE '(review|check|audit|inspect|analyze)'; then
        echo "Review"
    elif echo "$request" | grep -qoiE '(test|verify|validate)'; then
        echo "Test"
    elif echo "$request" | grep -qoiE '(deploy|release|ship|launch)'; then
        echo "Deploy"
    elif echo "$request" | grep -qoiE '(optimize|improve|speed|enhance)'; then
        echo "Optimize"
    elif echo "$request" | grep -qoiE '(research|investigate|explore|find)'; then
        echo "Research"
    elif echo "$request" | grep -qoiE '(document|explain|describe)'; then
        echo "Document"
    elif echo "$request" | grep -qoiE '(migrate|upgrade|convert|port)'; then
        echo "Migrate"
    else
        echo "Execute"
    fi
}

# ─── IMPROVEMENT #6: Ambiguity Detection ───────────────────────────

detect_ambiguity() {
    local request="$1"
    local category="$2"
    local issues=""

    local word_count
    word_count=$(echo "$request" | wc -w | tr -d ' ')

    # Too short for the category
    if [ "$word_count" -lt 10 ]; then
        case "$category" in
            system_design) issues="${issues}|- What are the scale requirements and constraints?\n" ;;
            migration) issues="${issues}|- What is the source and target system/technology?\n" ;;
            api_integration) issues="${issues}|- Which API or service are you integrating with?\n" ;;
            security_audit) issues="${issues}|- What is the scope of the audit (specific files, full app, infrastructure)?\n" ;;
        esac
    fi

    # Missing tech specification for code tasks (only if project context also doesn't have it)
    local tech
    tech=$(detect_tech "$request")
    local has_project_tech=""
    # Check if we're in a detectable project (caller passes cwd via global)
    if [ -n "$CURRENT_CWD" ]; then
        has_project_tech=$(detect_project_context "$CURRENT_CWD")
    fi
    if [ -z "$tech" ] && [ -z "$has_project_tech" ]; then
        case "$category" in
            code_implementation|testing|frontend) issues="${issues}|- What language/framework should be used?\n" ;;
        esac
    fi

    # Vague action words
    echo "$request" | grep -qiE '(make.*better|improve|fix.*it|help.*with|work.*on|something)' && \
        issues="${issues}|- Can you be more specific about what outcome you expect?\n"

    # No error details for debugging
    if [ "$category" = "debugging" ]; then
        echo "$request" | grep -qiE '(error message|stack trace|log|traceback|output)' || \
            issues="${issues}|- What error message or unexpected behavior are you seeing?\n"
    fi

    echo -e "$issues"
}

# ─── IMPROVEMENT #2: Few-Shot Examples from History ────────────────

get_relevant_examples() {
    local category="$1"

    if [ ! -f "$EXAMPLES_FILE" ]; then
        return
    fi

    # Get up to 2 examples for this category
    local examples
    examples=$(jq -r --arg cat "$category" '
        .examples[$cat] // [] | .[0:2] | .[] |
        "<example>\nUser request: \(.request)\nOptimized approach: \(.approach)\n</example>"
    ' "$EXAMPLES_FILE" 2>/dev/null || echo "")

    if [ -n "$examples" ]; then
        echo "
<examples>
$examples
</examples>"
    fi
}

# ─── IMPROVEMENT #3: Apply Learned Edit Patterns ───────────────────

get_learned_adjustments() {
    local category="$1"

    if [ ! -f "$EDIT_PATTERNS_FILE" ]; then
        return
    fi

    local adjustments=""

    # Check if users consistently remove certain sections for this category
    local removals
    removals=$(jq -r --arg cat "$category" '
        .section_removals[$cat] // {} | to_entries[] |
        select(.value >= 3) | .key
    ' "$EDIT_PATTERNS_FILE" 2>/dev/null || echo "")

    # Check for common additions users make
    local additions
    additions=$(jq -r --arg cat "$category" '
        .section_additions[$cat] // [] | .[0:3] | .[]
    ' "$EDIT_PATTERNS_FILE" 2>/dev/null || echo "")

    # Check for globally common additions
    local global_additions
    global_additions=$(jq -r '
        .common_additions // [] | .[0:2] | .[]
    ' "$EDIT_PATTERNS_FILE" 2>/dev/null || echo "")

    if [ -n "$additions" ] || [ -n "$global_additions" ]; then
        adjustments="$additions"
        [ -n "$global_additions" ] && adjustments="${adjustments}${global_additions}"
    fi

    echo "$adjustments" "$removals"
}

# ─── Generate Optimized Prompt ──────────────────────────────────────

generate_prompt() {
    local user_request="$1"
    local cwd="${2:-.}"
    CURRENT_CWD="$cwd"  # Global for ambiguity detection

    # Step 1: Classify
    local category
    category=$(classify_task "$user_request")

    # Step 2: Detect tech from request AND project
    local tech
    tech=$(detect_tech "$user_request")
    local project_context
    project_context=$(detect_project_context "$cwd")

    # Merge: if request didn't mention tech but project has it, use project tech
    if [ -z "$tech" ] && [ -n "$project_context" ]; then
        tech=$(echo "$project_context" | sed -n 's/.*Language: \([^ |]*\).*/\1/p')
    fi

    # Step 3: Dynamic complexity detection
    local complexity
    complexity=$(detect_complexity "$user_request" "$category" "$cwd")

    # Step 4: Extract intent
    local intent
    intent=$(extract_intent "$user_request")

    # Step 5: Check for ambiguity
    local ambiguity
    ambiguity=$(detect_ambiguity "$user_request" "$category")

    # Step 6: Get learned adjustments
    local adjustments
    adjustments=$(get_learned_adjustments "$category")

    # Step 7: Build the optimized prompt

    # ── Role Assignment ──
    local role=""
    case "$category" in
        code_implementation)
            [ -n "$tech" ] && role="You are an expert software engineer specializing in $tech." || role="You are an expert software engineer."
            ;;
        debugging)
            role="You are an expert debugger and systems analyst who methodically traces issues to their root cause."
            ;;
        refactoring)
            role="You are an expert software architect focused on code quality, maintainability, and clean design patterns."
            ;;
        code_review)
            role="You are a senior code reviewer who evaluates code for correctness, security, performance, and best practices."
            ;;
        system_design)
            role="You are a senior systems architect with deep expertise in distributed systems, scalability, and resilient design."
            ;;
        research)
            [ -n "$tech" ] && role="You are a thorough technical researcher with expertise in $tech." || role="You are a thorough technical researcher who synthesizes information from multiple sources."
            ;;
        testing)
            [ -n "$tech" ] && role="You are a QA engineer and testing specialist experienced with $tech." || role="You are a QA engineer and testing specialist."
            ;;
        frontend)
            [ -n "$tech" ] && role="You are a frontend engineer specializing in $tech with strong UI/UX sensibility." || role="You are a frontend engineer with strong UI/UX sensibility and modern web expertise."
            ;;
        api_integration)
            role="You are a backend engineer specializing in API design, third-party integrations, and data flow architecture."
            ;;
        performance_optimization)
            role="You are a performance engineer specializing in profiling, bottleneck analysis, and systematic optimization."
            ;;
        documentation)
            role="You are a technical writer who creates clear, well-structured, and comprehensive documentation."
            ;;
        security_audit)
            role="You are a security engineer specializing in vulnerability assessment, threat modeling, and secure coding practices."
            ;;
        migration)
            role="You are a migration specialist experienced in safely transitioning systems between technologies with zero data loss."
            ;;
        devops)
            role="You are a DevOps engineer specializing in CI/CD pipelines, infrastructure as code, and deployment automation."
            ;;
        database)
            role="You are a database engineer specializing in schema design, query optimization, and data modeling."
            ;;
        data_analysis)
            role="You are a data analyst specializing in extracting actionable insights from complex datasets."
            ;;
        *)
            role="You are a helpful and thorough assistant."
            ;;
    esac

    local prompt="$role"

    # ── IMPROVEMENT #1: Project Context Section ──
    if [ -n "$project_context" ]; then
        prompt="$prompt

<project_context>
$project_context
</project_context>"
    fi

    prompt="$prompt

<task>
$user_request
</task>"

    # ── IMPROVEMENT #6: Ambiguity Clarifications ──
    if [ -n "$ambiguity" ]; then
        prompt="$prompt

<clarifying_questions>
Before proceeding, consider asking the user about these underspecified aspects:
$(echo -e "$ambiguity")
If you can reasonably infer the answers from the project context, proceed with your best judgment and state your assumptions.
</clarifying_questions>"
    fi

    # ── Category-specific instructions ──
    case "$category" in
        code_implementation)
            prompt="$prompt

<instructions>
1. Read and understand any existing code in the relevant files before making changes.
2. Implement the solution following established patterns and conventions in the codebase.
3. Keep the implementation minimal and focused - only what is directly needed.
4. Ensure the code is correct, secure, and handles edge cases appropriately.
5. Verify the implementation works by checking for syntax errors and logical correctness.
</instructions>

<constraints>
- Follow existing code style and conventions in the project.
- Do not introduce unnecessary dependencies.
- Handle errors at system boundaries (user input, external APIs).
- Avoid over-engineering: no premature abstractions or speculative features.
</constraints>"
            ;;
        debugging)
            prompt="$prompt

<instructions>
1. Reproduce or understand the exact error/symptom described.
2. Read the relevant source files to understand the code flow.
3. Identify the root cause - not just the symptom.
4. Propose and implement a targeted fix.
5. Verify the fix resolves the issue without introducing regressions.
</instructions>

<debugging_approach>
- Start with the error message or symptom and trace backwards.
- Check recent changes that may have introduced the issue.
- Examine inputs, state, and control flow at the failure point.
- Validate assumptions about data types, null values, and edge cases.
</debugging_approach>"
            ;;
        refactoring)
            prompt="$prompt

<instructions>
1. Read and fully understand the current code before suggesting changes.
2. Identify specific code smells or issues to address.
3. Apply refactoring in small, verifiable steps.
4. Preserve all existing behavior - refactoring must not change functionality.
5. Verify the refactored code maintains correctness.
</instructions>

<constraints>
- Do not change behavior or add features during refactoring.
- Keep changes minimal and focused on the stated goal.
- Preserve existing tests and ensure they still pass.
- Each refactoring step should leave the code in a working state.
</constraints>"
            ;;
        code_review)
            prompt="$prompt

<instructions>
1. Read the code thoroughly before providing feedback.
2. Focus on: correctness, security vulnerabilities, performance, and maintainability.
3. Prioritize issues by severity (critical > major > minor > style).
4. Provide specific, actionable suggestions with code examples.
5. Acknowledge what is done well, not just what needs improvement.
</instructions>"
            ;;
        system_design)
            prompt="$prompt

<instructions>
1. Clarify requirements and constraints before proposing a design.
2. Consider multiple architectural approaches and their trade-offs.
3. Address scalability, reliability, maintainability, and cost.
4. Provide clear diagrams or structured descriptions of the architecture.
5. Identify risks and mitigation strategies.
</instructions>"
            ;;
        research)
            prompt="$prompt

<instructions>
1. Define the scope of the research clearly.
2. Investigate multiple sources and perspectives.
3. Compare and contrast options objectively.
4. Provide evidence-based recommendations.
5. Clearly distinguish facts from opinions.
</instructions>"
            ;;
        testing)
            prompt="$prompt

<instructions>
1. Understand the code under test and its expected behavior.
2. Write tests that cover: happy path, edge cases, error cases, and boundary conditions.
3. Use descriptive test names that explain the expected behavior.
4. Keep tests independent, deterministic, and fast.
5. Aim for meaningful coverage, not just line count.
</instructions>

<constraints>
- Follow existing test patterns and framework conventions in the project.
- Tests should be readable as documentation of expected behavior.
- Do not test implementation details - test behavior and contracts.
- Mock external dependencies, not internal logic.
</constraints>"
            ;;
        frontend)
            prompt="$prompt

<instructions>
1. Understand the component requirements and user interactions.
2. Build with accessibility (ARIA, keyboard navigation, screen readers) in mind.
3. Ensure responsive design across device sizes.
4. Follow existing component patterns and design system if one exists.
5. Keep components focused - single responsibility.
</instructions>

<constraints>
- Follow the project's existing design system and component patterns.
- Ensure semantic HTML and proper accessibility attributes.
- Handle loading, error, and empty states.
- Keep styling consistent with the rest of the application.
</constraints>"
            ;;
        api_integration)
            prompt="$prompt

<instructions>
1. Understand the API specification and authentication requirements.
2. Implement robust error handling for network failures and API errors.
3. Handle rate limiting, retries, and timeouts appropriately.
4. Validate request/response data at system boundaries.
5. Document the integration points and data flow.
</instructions>

<constraints>
- Never hardcode credentials or API keys.
- Implement proper error handling for all API response codes.
- Add request/response logging for debugging.
- Handle pagination if the API uses it.
</constraints>"
            ;;
        performance_optimization)
            prompt="$prompt

<instructions>
1. Profile and measure current performance to establish a baseline.
2. Identify the actual bottleneck - do not optimize speculatively.
3. Apply targeted optimizations to the bottleneck.
4. Measure the improvement against the baseline.
5. Document the optimization and its impact.
</instructions>

<constraints>
- Always measure before and after optimization.
- Focus on the actual bottleneck, not premature optimization.
- Do not sacrifice readability without significant measurable gain.
- Validate that the optimization does not change behavior.
</constraints>"
            ;;
        security_audit)
            prompt="$prompt

<instructions>
1. Review the code/system for OWASP Top 10 vulnerabilities.
2. Check for: injection, authentication flaws, sensitive data exposure, XSS, misconfigurations.
3. Assess input validation and output encoding.
4. Review access controls and authorization logic.
5. Check dependency versions for known vulnerabilities.
</instructions>"
            ;;
        migration)
            prompt="$prompt

<instructions>
1. Document the current state of the system being migrated.
2. Create a detailed migration plan with clear steps.
3. Identify and mitigate risks of data loss or downtime.
4. Build and test the migration in a safe environment first.
5. Include a rollback plan for every step.
</instructions>

<constraints>
- Zero data loss is the top priority.
- Each migration step must be reversible.
- Test the migration with realistic data before production.
- Document every change for auditability.
</constraints>"
            ;;
        devops)
            prompt="$prompt

<instructions>
1. Understand the current infrastructure and deployment setup.
2. Implement changes following infrastructure-as-code principles.
3. Ensure idempotency - running the same operation twice should be safe.
4. Include health checks, monitoring, and alerting.
5. Document the setup and any manual steps required.
</instructions>

<constraints>
- Follow the principle of least privilege for all permissions.
- Ensure all secrets are managed securely (not in code or logs).
- Make deployments reproducible and rollback-safe.
- Test in a staging environment before production.
</constraints>"
            ;;
        database)
            prompt="$prompt

<instructions>
1. Understand the current schema and data model.
2. Design changes that are backwards-compatible when possible.
3. Consider query performance and add appropriate indexes.
4. Write migration scripts that are safe and reversible.
5. Validate data integrity after any schema changes.
</instructions>

<constraints>
- Schema migrations must be reversible.
- Consider the impact on existing queries and application code.
- Test with realistic data volumes.
- Ensure data integrity constraints are maintained.
</constraints>"
            ;;
        data_analysis)
            prompt="$prompt

<instructions>
1. Understand the data source, format, and quality.
2. Clean and validate the data before analysis.
3. Apply appropriate analytical methods for the question being asked.
4. Present findings with clear visualizations or structured summaries.
5. Distinguish correlation from causation in conclusions.
</instructions>"
            ;;
        *)
            prompt="$prompt

<instructions>
1. Understand the complete requirement before starting.
2. Break the task into clear, sequential steps.
3. Execute each step thoroughly.
4. Validate the result against the original requirement.
</instructions>"
            ;;
    esac

    # ── IMPROVEMENT #4: Task Decomposition for High Complexity ──
    if [ "$complexity" = "high" ]; then
        prompt="$prompt

<task_decomposition>
This is a complex task. Before implementing, create a structured plan:
1. Break the task into independent, ordered subtasks.
2. Identify dependencies between subtasks.
3. For each subtask, define: what it does, what files it touches, and how to verify it works.
4. Execute subtasks in order, verifying each before moving to the next.
5. After all subtasks complete, run an integration check across the full change.
Present your plan to the user before starting implementation.
</task_decomposition>"
    fi

    # ── IMPROVEMENT #7: Tailored Output Format ──
    case "$category" in
        code_review)
            prompt="$prompt

<output_format>
Organize your review by severity level. For each issue:
- Location (file:line)
- Severity (critical/major/minor/style)
- Description of the issue
- Suggested fix with code example
</output_format>"
            ;;
        system_design)
            prompt="$prompt

<output_format>
Structure your response with:
- Requirements summary
- Proposed architecture with rationale
- Component breakdown with responsibilities
- Data flow description
- Trade-offs and alternatives considered
- Risks and mitigations
</output_format>"
            ;;
        research)
            prompt="$prompt

<output_format>
Structure findings with:
- Summary of findings (2-3 sentences)
- Detailed analysis with evidence
- Comparison matrix (if comparing options)
- Recommendation with rationale
- Sources and references
</output_format>"
            ;;
        security_audit)
            prompt="$prompt

<output_format>
For each finding:
- Severity (Critical/High/Medium/Low)
- Vulnerability type (OWASP category)
- Location and description
- Proof of concept or exploitation scenario
- Recommended fix with code example
</output_format>"
            ;;
        data_analysis)
            prompt="$prompt

<output_format>
Structure your analysis with:
- Data overview and quality assessment
- Methodology used
- Key findings with supporting evidence
- Visualizations or summary tables
- Conclusions and recommendations
</output_format>"
            ;;
    esac

    # For simple code tasks, keep output instructions minimal
    if [ "$complexity" = "low" ]; then
        case "$category" in
            code_implementation|debugging|refactoring)
                prompt="$prompt

<output_format>
Implement the change directly. Keep explanations brief - focus on the code.
</output_format>"
                ;;
        esac
    fi

    # ── IMPROVEMENT #2: Few-Shot Examples ──
    local examples
    examples=$(get_relevant_examples "$category")
    if [ -n "$examples" ]; then
        prompt="$prompt
$examples"
    fi

    # ── Quality Validation (medium/high only) ──
    if [ "$complexity" = "high" ] || [ "$complexity" = "medium" ]; then
        prompt="$prompt

<quality_validation>
Before finalizing your response, verify:
- All requirements from the task are addressed.
- Edge cases and error scenarios are handled.
- The solution follows established patterns in the codebase.
- No security vulnerabilities have been introduced.
</quality_validation>"
    fi

    # ── IMPROVEMENT #3: Apply learned user adjustments ──
    if [ -n "$adjustments" ]; then
        local trimmed
        trimmed=$(echo "$adjustments" | xargs)
        if [ -n "$trimmed" ]; then
            prompt="$prompt

<learned_preferences>
Based on your previous feedback and edits:
$trimmed
</learned_preferences>"
        fi
    fi

    echo "$prompt"
}

# ─── Record Prompt in History ───────────────────────────────────────

record_prompt() {
    local user_request="$1"
    local category="$2"

    if [ -f "$HISTORY_FILE" ]; then
        local count
        count=$(json_read "$HISTORY_FILE" '.prompts_generated // 0')
        count=$((count + 1))

        local tmp_file
        tmp_file=$(mktemp)
        jq --arg ts "$(timestamp)" \
           --argjson count "$count" \
           --arg cat "$category" \
           '.prompts_generated = $count | .last_generated = $ts | .category_frequency[$cat] = ((.category_frequency[$cat] // 0) + 1)' \
           "$HISTORY_FILE" > "$tmp_file" && mv "$tmp_file" "$HISTORY_FILE"
    fi
}

# ─── IMPROVEMENT #3: Record User Edit with Pattern Analysis ────────

record_edit() {
    local category="$1"
    local original="$2"
    local edited="$3"

    if [ "$original" = "$edited" ]; then
        # User accepted as-is
        if [ -f "$HISTORY_FILE" ]; then
            local tmp_file
            tmp_file=$(mktemp)
            jq '.prompts_accepted_as_is = ((.prompts_accepted_as_is // 0) + 1)' \
               "$HISTORY_FILE" > "$tmp_file" && mv "$tmp_file" "$HISTORY_FILE"
        fi
        # Record as a good example for few-shot learning
        record_example "$category" "$edited"
    else
        # User edited - analyze what changed
        if [ -f "$HISTORY_FILE" ]; then
            local tmp_file
            tmp_file=$(mktemp)
            jq --arg ts "$(timestamp)" \
               '.prompts_edited = ((.prompts_edited // 0) + 1)' \
               "$HISTORY_FILE" > "$tmp_file" && mv "$tmp_file" "$HISTORY_FILE"
        fi

        # Detect which sections were removed
        local sections="instructions constraints output_format debugging_approach quality_validation task_decomposition clarifying_questions"
        for section in $sections; do
            if echo "$original" | grep -q "<$section>" && ! echo "$edited" | grep -q "<$section>"; then
                # Section was removed - track it
                if [ -f "$EDIT_PATTERNS_FILE" ]; then
                    local tmp_file
                    tmp_file=$(mktemp)
                    jq --arg cat "$category" --arg sec "$section" \
                       '.section_removals[$cat][$sec] = ((.section_removals[$cat][$sec] // 0) + 1)' \
                       "$EDIT_PATTERNS_FILE" > "$tmp_file" && mv "$tmp_file" "$EDIT_PATTERNS_FILE"
                fi
            fi
        done

        # Detect lines that were added (not in original, in edited)
        local added_lines
        added_lines=$(diff <(echo "$original") <(echo "$edited") 2>/dev/null | grep '^>' | sed 's/^> //' | head -5)
        if [ -n "$added_lines" ]; then
            if [ -f "$EDIT_PATTERNS_FILE" ]; then
                local tmp_file
                tmp_file=$(mktemp)
                jq --arg cat "$category" --arg lines "$added_lines" \
                   '.section_additions[$cat] = ((.section_additions[$cat] // []) + [$lines]) | .section_additions[$cat] = .section_additions[$cat][-10:]' \
                   "$EDIT_PATTERNS_FILE" > "$tmp_file" && mv "$tmp_file" "$EDIT_PATTERNS_FILE"
            fi
        fi
    fi
}

# ─── IMPROVEMENT #2: Store Good Examples ───────────────────────────

record_example() {
    local category="$1"
    local prompt="$2"

    if [ -f "$EXAMPLES_FILE" ]; then
        # Extract the task line from the prompt
        local task_line
        task_line=$(echo "$prompt" | sed -n '/<task>/,/<\/task>/p' | grep -v '<\/*task>' | head -1 | xargs)

        if [ -n "$task_line" ]; then
            # Extract the approach (first 2 instruction lines)
            local approach
            approach=$(echo "$prompt" | sed -n '/<instructions>/,/<\/instructions>/p' | grep '^[0-9]' | head -2 | tr '\n' ' ')

            local tmp_file
            tmp_file=$(mktemp)
            jq --arg cat "$category" --arg req "$task_line" --arg app "$approach" \
               '.examples[$cat] = ((.examples[$cat] // []) + [{"request": $req, "approach": $app}]) | .examples[$cat] = .examples[$cat][-5:]' \
               "$EXAMPLES_FILE" > "$tmp_file" && mv "$tmp_file" "$EXAMPLES_FILE"
        fi
    fi
}

# ─── IMPROVEMENT #8: Record Outcome for RL ─────────────────────────

record_outcome() {
    local category="$1"
    local result="$2"  # "success", "partial", "failure"

    # Log to history
    if [ -f "$HISTORY_FILE" ]; then
        local tmp_file
        tmp_file=$(mktemp)
        jq --arg cat "$category" --arg res "$result" --arg ts "$(timestamp)" \
           '.outcomes = ((.outcomes // []) + [{"category": $cat, "result": $res, "timestamp": $ts}]) | .outcomes = .outcomes[-100:]' \
           "$HISTORY_FILE" > "$tmp_file" && mv "$tmp_file" "$HISTORY_FILE"
    fi

    # Feed to agent-lightning RL bridge if available
    if [ -x "$RL_BRIDGE" ]; then
        local reward=0
        case "$result" in
            success) reward=1 ;;
            partial) reward=0 ;;
            failure) reward=-1 ;;
        esac

        "$RL_BRIDGE" emit-span \
            --type "prompt_optimization" \
            --category "$category" \
            --reward "$reward" \
            --timestamp "$(timestamp)" 2>/dev/null || true
    fi
}

# ─── Status ─────────────────────────────────────────────────────────

show_status() {
    echo "=== Prompt Optimizer v2.0 Status ==="
    echo ""

    if [ -f "$CONFIG_FILE" ]; then
        echo "Enabled: $(json_read "$CONFIG_FILE" '.enabled')"
        echo "Auto-trigger: $(json_read "$CONFIG_FILE" '.auto_trigger_on_new_task')"
        echo "Editable: $(json_read "$CONFIG_FILE" '.editable_before_execution')"
        echo "Learn from edits: $(json_read "$CONFIG_FILE" '.learn_from_edits')"
    fi

    echo ""

    if [ -f "$HISTORY_FILE" ]; then
        local generated accepted edited
        generated=$(json_read "$HISTORY_FILE" '.prompts_generated // 0')
        accepted=$(json_read "$HISTORY_FILE" '.prompts_accepted_as_is // 0')
        edited=$(json_read "$HISTORY_FILE" '.prompts_edited // 0')

        echo "--- Generation Stats ---"
        echo "Total generated: $generated"
        echo "Accepted as-is: $accepted"
        echo "Edited by user: $edited"
        if [ "$generated" -gt 0 ] 2>/dev/null; then
            local accept_rate=$((accepted * 100 / generated))
            echo "Accept rate: ${accept_rate}%"
        fi
        echo "Last generated: $(json_read "$HISTORY_FILE" '.last_generated')"
        echo ""
        echo "--- Category Frequency ---"
        jq -r '.category_frequency | to_entries | sort_by(-.value) | .[] | "  \(.key): \(.value)"' "$HISTORY_FILE" 2>/dev/null || echo "  No data yet"

        # Show outcome stats if available
        local outcomes
        outcomes=$(jq -r '.outcomes // [] | length' "$HISTORY_FILE" 2>/dev/null || echo "0")
        if [ "$outcomes" -gt 0 ] 2>/dev/null; then
            echo ""
            echo "--- Outcome Stats ---"
            echo "  Total outcomes tracked: $outcomes"
            jq -r '.outcomes | group_by(.result) | .[] | "  \(.[0].result): \(length)"' "$HISTORY_FILE" 2>/dev/null || true
        fi
    fi

    echo ""
    echo "--- Learned Patterns ---"
    if [ -f "$EDIT_PATTERNS_FILE" ]; then
        local removals
        removals=$(jq -r '.section_removals | to_entries[] | select(.value | to_entries | any(.value >= 3)) | "  \(.key): commonly removes \(.value | to_entries[] | select(.value >= 3) | .key)"' "$EDIT_PATTERNS_FILE" 2>/dev/null || echo "")
        if [ -n "$removals" ]; then
            echo "$removals"
        else
            echo "  No strong patterns yet (need 3+ consistent edits)"
        fi
    fi

    if [ -f "$EXAMPLES_FILE" ]; then
        local example_count
        example_count=$(jq '[.examples[] | length] | add // 0' "$EXAMPLES_FILE" 2>/dev/null || echo "0")
        echo "  Stored examples: $example_count"
    fi

    echo ""
    echo "--- Features ---"
    echo "  [v2.0] Project-aware context: ON"
    echo "  [v2.0] Few-shot examples: ON (from accepted prompts)"
    echo "  [v2.0] Edit pattern learning: ON"
    echo "  [v2.0] Task decomposition: ON (high complexity)"
    echo "  [v2.0] Dynamic complexity: ON (codebase-aware)"
    echo "  [v2.0] Ambiguity detection: ON"
    echo "  [v2.0] Tailored output format: ON"
    echo "  [v2.0] Agent-lightning RL: $([ -x "$RL_BRIDGE" ] && echo "ON" || echo "OFF (bridge not found)")"
}

# ─── Main ───────────────────────────────────────────────────────────

main() {
    local command="${1:-help}"

    case "$command" in
        generate)
            local request="${2:-}"
            local cwd="${3:-.}"
            if [ -z "$request" ]; then
                echo "Error: No request provided"
                echo "Usage: prompt-optimizer.sh generate \"your task description\" [cwd]"
                exit 1
            fi

            local category
            category=$(classify_task "$request")
            local prompt
            prompt=$(generate_prompt "$request" "$cwd")

            record_prompt "$request" "$category"

            local project_ctx
            project_ctx=$(detect_project_context "$cwd")

            echo "# Task Category: $category"
            echo "# Detected Tech: $(detect_tech "$request")"
            echo "# Project Context: ${project_ctx:-none detected}"
            echo "# Complexity: $(detect_complexity "$request" "$category" "$cwd")"
            echo "# Intent: $(extract_intent "$request")"
            echo "---"
            echo "$prompt"
            ;;

        classify)
            local request="${2:-}"
            [ -z "$request" ] && { echo "Error: No request provided"; exit 1; }
            classify_task "$request"
            ;;

        detect-project)
            local cwd="${2:-.}"
            detect_project_context "$cwd"
            ;;

        record-edit)
            local category="${2:-}"
            local original="${3:-}"
            local edited="${4:-}"
            record_edit "$category" "$original" "$edited"
            ;;

        record-outcome)
            local category="${2:-}"
            local result="${3:-}"
            record_outcome "$category" "$result"
            ;;

        history)
            [ -f "$HISTORY_FILE" ] && jq '.' "$HISTORY_FILE" || echo "No history yet"
            ;;

        status)
            show_status
            ;;

        help|*)
            echo "Prompt Optimizer v2.0 - Auto-generate optimal prompts (Anthropic best practices)"
            echo ""
            echo "Commands:"
            echo "  generate \"<request>\" [cwd]               Generate optimized prompt"
            echo "  classify \"<request>\"                     Classify task category"
            echo "  detect-project [cwd]                      Detect project context"
            echo "  record-edit \"<cat>\" \"<orig>\" \"<edit>\"    Record user's edit for learning"
            echo "  record-outcome \"<cat>\" \"<result>\"        Record outcome (success/partial/failure)"
            echo "  history                                   Show generation history"
            echo "  status                                    Show optimizer status"
            ;;
    esac
}

main "$@"
