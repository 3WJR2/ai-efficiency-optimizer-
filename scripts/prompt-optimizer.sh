#!/usr/bin/env bash
# prompt-optimizer.sh - Auto-generates optimal prompts based on Anthropic's best practices
# Analyzes user task intention and builds a structured, high-quality prompt
# Part of AI Efficiency Optimizer - Intelligence Layer
#
# Usage: prompt-optimizer.sh <command> [args]
#   generate "<user_request>"   - Generate optimized prompt from user's raw request
#   classify "<user_request>"   - Classify the task category
#   history                     - Show prompt generation history
#   status                      - Show optimizer status
#   record-edit "<original>" "<edited>" - Record user's edit for learning

set -euo pipefail

# Paths
DATA_DIR="$HOME/.claude/data/prompt-optimizer"
CONFIG_FILE="$DATA_DIR/config.json"
HISTORY_FILE="$DATA_DIR/history.json"
TEMPLATES_FILE="$DATA_DIR/templates.json"
USER_PROFILE="$HOME/.claude/data/user-profile.json"
INTERACTION_LEARNING="$HOME/.claude/data/interaction-learning.json"

# Ensure data directory exists
mkdir -p "$DATA_DIR"

# ─── Helper Functions ───────────────────────────────────────────────

json_read() {
    local file="$1" path="$2"
    jq -r "$path" "$file" 2>/dev/null || echo ""
}

timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ─── Task Classification ───────────────────────────────────────────

classify_task() {
    local request="$1"
    local request_lower
    request_lower=$(echo "$request" | tr '[:upper:]' '[:lower:]')

    # Pattern matching for task categories
    # Ordered by specificity (most specific first)

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

    # Languages
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

    # Frameworks
    echo "$request_lower" | grep -qE '\breact\b|next\.?js|jsx|tsx' && techs="$techs React"
    echo "$request_lower" | grep -qE '\bvue\b|nuxt' && techs="$techs Vue"
    echo "$request_lower" | grep -qE '\bangular\b' && techs="$techs Angular"
    echo "$request_lower" | grep -qE '\bdjango\b' && techs="$techs Django"
    echo "$request_lower" | grep -qE '\bflask\b|fastapi' && techs="$techs Flask/FastAPI"
    echo "$request_lower" | grep -qE '\bexpress\b|node\.?js|koa' && techs="$techs Node.js"
    echo "$request_lower" | grep -qE '\bspring\b' && techs="$techs Spring"
    echo "$request_lower" | grep -qE '\bdocker\b' && techs="$techs Docker"
    echo "$request_lower" | grep -qE '\bkubernetes\b|k8s' && techs="$techs Kubernetes"

    echo "$techs" | xargs  # trim whitespace
}

# ─── Detect Complexity ──────────────────────────────────────────────

detect_complexity() {
    local request="$1"
    local word_count
    word_count=$(echo "$request" | wc -w | xargs)
    local category="$2"

    # High complexity indicators
    if echo "$request" | grep -qE '(system.*design|architect|distributed|migrat|security.*audit|multi.*service)'; then
        echo "high"
    elif echo "$request" | grep -qE '(complex|advanced|enterprise|production|scale|comprehensive)'; then
        echo "high"
    elif [[ "$word_count" -gt 50 ]]; then
        echo "high"
    # Medium complexity
    elif echo "$request" | grep -qE '(implement|build|create|refactor|integrat|optimiz|debug.*complex)'; then
        echo "medium"
    elif [[ "$word_count" -gt 20 ]]; then
        echo "medium"
    # Low complexity
    else
        echo "low"
    fi
}

# ─── Extract Key Intent ─────────────────────────────────────────────

extract_intent() {
    local request="$1"

    # Extract the core action verb and object
    local action=""
    local object=""

    # Common action patterns
    if echo "$request" | grep -qoiE '(create|build|implement|add|write|develop|make|design|architect)'; then
        action="Create"
    elif echo "$request" | grep -qoiE '(fix|debug|resolve|repair|patch)'; then
        action="Fix"
    elif echo "$request" | grep -qoiE '(refactor|restructure|reorganize|clean)'; then
        action="Refactor"
    elif echo "$request" | grep -qoiE '(review|check|audit|inspect|analyze)'; then
        action="Review"
    elif echo "$request" | grep -qoiE '(test|verify|validate)'; then
        action="Test"
    elif echo "$request" | grep -qoiE '(deploy|release|ship|launch)'; then
        action="Deploy"
    elif echo "$request" | grep -qoiE '(optimize|improve|speed|enhance)'; then
        action="Optimize"
    elif echo "$request" | grep -qoiE '(research|investigate|explore|find)'; then
        action="Research"
    elif echo "$request" | grep -qoiE '(document|explain|describe)'; then
        action="Document"
    elif echo "$request" | grep -qoiE '(migrate|upgrade|convert|port)'; then
        action="Migrate"
    else
        action="Execute"
    fi

    echo "$action"
}

# ─── Load User Preferences from Learning Data ──────────────────────

get_user_preferences() {
    local prefs=""

    if [[ -f "$USER_PROFILE" ]]; then
        local style
        style=$(json_read "$USER_PROFILE" '.profile.preferences.communication_style // "adaptive"')
        local detail
        detail=$(json_read "$USER_PROFILE" '.profile.preferences.detail_level // "comprehensive"')
        prefs="communication_style=$style detail_level=$detail"
    fi

    if [[ -f "$INTERACTION_LEARNING" ]]; then
        local brevity
        brevity=$(json_read "$INTERACTION_LEARNING" '.interaction_patterns.communication_style.brevity_vs_detail.score // 0.5')
        local tech_depth
        tech_depth=$(json_read "$INTERACTION_LEARNING" '.interaction_patterns.communication_style.technical_depth.score // 0.5')
        prefs="$prefs brevity=$brevity tech_depth=$tech_depth"
    fi

    echo "$prefs"
}

# ─── Generate Optimized Prompt ──────────────────────────────────────

generate_prompt() {
    local user_request="$1"

    # Step 1: Classify the task
    local category
    category=$(classify_task "$user_request")

    # Step 2: Detect technology
    local tech
    tech=$(detect_tech "$user_request")

    # Step 3: Detect complexity
    local complexity
    complexity=$(detect_complexity "$user_request" "$category")

    # Step 4: Extract intent
    local intent
    intent=$(extract_intent "$user_request")

    # Step 5: Get user preferences
    local prefs
    prefs=$(get_user_preferences)

    # Step 6: Build the optimized prompt using Anthropic's principles
    local prompt=""

    # ── Role Assignment (Anthropic: "Give Claude a role") ──
    local role=""
    case "$category" in
        code_implementation)
            if [[ -n "$tech" ]]; then
                role="You are an expert software engineer specializing in $tech."
            else
                role="You are an expert software engineer."
            fi
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
            if [[ -n "$tech" ]]; then
                role="You are a thorough technical researcher with expertise in $tech."
            else
                role="You are a thorough technical researcher who synthesizes information from multiple sources."
            fi
            ;;
        testing)
            if [[ -n "$tech" ]]; then
                role="You are a QA engineer and testing specialist experienced with $tech."
            else
                role="You are a QA engineer and testing specialist."
            fi
            ;;
        frontend)
            if [[ -n "$tech" ]]; then
                role="You are a frontend engineer specializing in $tech with strong UI/UX sensibility."
            else
                role="You are a frontend engineer with strong UI/UX sensibility and modern web expertise."
            fi
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

    # ── Build Structured Prompt (Anthropic: "Structure prompts with XML tags") ──

    prompt="$role

<task>
$user_request
</task>"

    # ── Add Context Section (Anthropic: "Add context to improve performance") ──
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
</instructions>

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

<instructions>
1. Clarify requirements and constraints before proposing a design.
2. Consider multiple architectural approaches and their trade-offs.
3. Address scalability, reliability, maintainability, and cost.
4. Provide clear diagrams or structured descriptions of the architecture.
5. Identify risks and mitigation strategies.
</instructions>

<output_format>
Structure your response with:
- Requirements summary
- Proposed architecture with rationale
- Component breakdown
- Data flow description
- Trade-offs and alternatives considered
- Risks and mitigations
</output_format>"
            ;;
        research)
            prompt="$prompt

<instructions>
1. Define the scope of the research clearly.
2. Investigate multiple sources and perspectives.
3. Compare and contrast options objectively.
4. Provide evidence-based recommendations.
5. Clearly distinguish facts from opinions.
</instructions>

<output_format>
Structure findings with:
- Summary of findings
- Detailed analysis with evidence
- Comparison matrix (if comparing options)
- Recommendation with rationale
- Sources and references
</output_format>"
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
</instructions>

<output_format>
For each finding:
- Severity (Critical/High/Medium/Low)
- Vulnerability type (OWASP category)
- Location and description
- Proof of concept or exploitation scenario
- Recommended fix with code example
</output_format>"
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
</instructions>

<output_format>
Structure your analysis with:
- Data overview and quality assessment
- Methodology used
- Key findings with supporting evidence
- Visualizations or summary tables
- Conclusions and recommendations
</output_format>"
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

    # ── Add quality validation (Anthropic: "Ask Claude to self-check") ──
    if [[ "$complexity" == "high" ]] || [[ "$complexity" == "medium" ]]; then
        prompt="$prompt

<quality_validation>
Before finalizing your response, verify:
- All requirements from the task are addressed.
- Edge cases and error scenarios are handled.
- The solution follows established patterns in the codebase.
- No security vulnerabilities have been introduced.
</quality_validation>"
    fi

    echo "$prompt"
}

# ─── Record Prompt in History ───────────────────────────────────────

record_prompt() {
    local user_request="$1"
    local category="$2"
    local generated_prompt="$3"

    if [[ -f "$HISTORY_FILE" ]]; then
        local count
        count=$(json_read "$HISTORY_FILE" '.prompts_generated // 0')
        count=$((count + 1))

        # Update counters
        local tmp_file
        tmp_file=$(mktemp)
        jq --arg ts "$(timestamp)" \
           --argjson count "$count" \
           --arg cat "$category" \
           '.prompts_generated = $count | .last_generated = $ts | .category_frequency[$cat] = ((.category_frequency[$cat] // 0) + 1)' \
           "$HISTORY_FILE" > "$tmp_file" && mv "$tmp_file" "$HISTORY_FILE"
    fi
}

# ─── Record User Edit (Learning) ───────────────────────────────────

record_edit() {
    local original="$1"
    local edited="$2"

    if [[ "$original" == "$edited" ]]; then
        # User accepted as-is
        if [[ -f "$HISTORY_FILE" ]]; then
            local tmp_file
            tmp_file=$(mktemp)
            jq '.prompts_accepted_as_is = ((.prompts_accepted_as_is // 0) + 1)' \
               "$HISTORY_FILE" > "$tmp_file" && mv "$tmp_file" "$HISTORY_FILE"
        fi
    else
        # User made edits - record for learning
        if [[ -f "$HISTORY_FILE" ]]; then
            local tmp_file
            tmp_file=$(mktemp)
            jq --arg ts "$(timestamp)" \
               '.prompts_edited = ((.prompts_edited // 0) + 1) | .edit_patterns += [{"timestamp": $ts, "action": "edited"}]' \
               "$HISTORY_FILE" > "$tmp_file" && mv "$tmp_file" "$HISTORY_FILE"
        fi
    fi
}

# ─── Status ─────────────────────────────────────────────────────────

show_status() {
    echo "=== Prompt Optimizer Status ==="
    echo ""

    if [[ -f "$CONFIG_FILE" ]]; then
        local enabled
        enabled=$(json_read "$CONFIG_FILE" '.enabled')
        echo "Enabled: $enabled"
        echo "Auto-trigger: $(json_read "$CONFIG_FILE" '.auto_trigger_on_new_task')"
        echo "Show to user: $(json_read "$CONFIG_FILE" '.show_prompt_to_user')"
        echo "Editable: $(json_read "$CONFIG_FILE" '.editable_before_execution')"
        echo "Learn from edits: $(json_read "$CONFIG_FILE" '.learn_from_edits')"
    fi

    echo ""

    if [[ -f "$HISTORY_FILE" ]]; then
        echo "--- Generation Stats ---"
        echo "Total generated: $(json_read "$HISTORY_FILE" '.prompts_generated')"
        echo "Accepted as-is: $(json_read "$HISTORY_FILE" '.prompts_accepted_as_is')"
        echo "Edited by user: $(json_read "$HISTORY_FILE" '.prompts_edited')"
        echo "Last generated: $(json_read "$HISTORY_FILE" '.last_generated')"
        echo ""
        echo "--- Category Frequency ---"
        jq -r '.category_frequency | to_entries | sort_by(-.value) | .[] | "  \(.key): \(.value)"' "$HISTORY_FILE" 2>/dev/null || echo "  No data yet"
    fi
}

# ─── Main ───────────────────────────────────────────────────────────

main() {
    local command="${1:-help}"

    case "$command" in
        generate)
            local request="${2:-}"
            if [[ -z "$request" ]]; then
                echo "Error: No request provided"
                echo "Usage: prompt-optimizer.sh generate \"your task description\""
                exit 1
            fi

            local category
            category=$(classify_task "$request")
            local prompt
            prompt=$(generate_prompt "$request")

            # Record in history
            record_prompt "$request" "$category" "$prompt"

            # Output classification metadata as comment, then the prompt
            echo "# Task Category: $category"
            echo "# Detected Tech: $(detect_tech "$request")"
            echo "# Complexity: $(detect_complexity "$request" "$category")"
            echo "# Intent: $(extract_intent "$request")"
            echo "---"
            echo "$prompt"
            ;;

        classify)
            local request="${2:-}"
            if [[ -z "$request" ]]; then
                echo "Error: No request provided"
                exit 1
            fi
            classify_task "$request"
            ;;

        record-edit)
            local original="${2:-}"
            local edited="${3:-}"
            record_edit "$original" "$edited"
            ;;

        history)
            if [[ -f "$HISTORY_FILE" ]]; then
                jq '.' "$HISTORY_FILE"
            else
                echo "No history yet"
            fi
            ;;

        status)
            show_status
            ;;

        help|*)
            echo "Prompt Optimizer - Auto-generate optimal prompts based on Anthropic's best practices"
            echo ""
            echo "Usage: prompt-optimizer.sh <command> [args]"
            echo ""
            echo "Commands:"
            echo "  generate \"<request>\"            Generate optimized prompt"
            echo "  classify \"<request>\"            Classify task category"
            echo "  record-edit \"<orig>\" \"<edit>\"   Record user's edit for learning"
            echo "  history                          Show generation history"
            echo "  status                           Show optimizer status"
            echo "  help                             Show this help"
            ;;
    esac
}

main "$@"
