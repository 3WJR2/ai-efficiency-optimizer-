#!/usr/bin/env bash
# request-classifier.sh - Intelligent request classification for proactive agent orchestration
# Version: 1.0.0
# Purpose: Analyze user requests and classify into task types for optimal agent spawning

set -eo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$HOME/.claude/data"
CLASSIFICATION_HISTORY="$DATA_DIR/classification-history.json"
LEARNING_DATA="$DATA_DIR/interaction-learning.json"

# Initialize classification history if not exists
init_classification_history() {
    if [[ ! -f "$CLASSIFICATION_HISTORY" ]]; then
        mkdir -p "$DATA_DIR"
        cat > "$CLASSIFICATION_HISTORY" <<'EOF'
{
  "version": "1.0.0",
  "classifications": [],
  "pattern_accuracy": {},
  "total_classifications": 0,
  "last_updated": ""
}
EOF
    fi
}

# Get pattern for task type
get_pattern() {
    local task_type="$1"

    case "$task_type" in
        debug)
            echo "debug|debugging|error|issue|problem|failing|fails|broken|crash|exception|stacktrace|trace|bug|defect"
            ;;
        implement)
            echo "implement|create|build|develop|add|feature|new|functionality|function|method|class|component|module"
            ;;
        refactor)
            echo "refactor|refactoring|restructure|reorganize|improve|clean|cleanup|optimize code|simplify|modernize"
            ;;
        explore)
            echo "explore|understand|analyze|investigate|examine|find|search|locate|where|what|how|codebase|structure"
            ;;
        test)
            echo "test|testing|unit test|integration test|e2e|validate|verification|coverage|spec|tdd"
            ;;
        design)
            echo "design|architecture|architect|plan|planning|structure|pattern|approach|strategy|blueprint"
            ;;
        research)
            echo "research|documentation|docs|learn|study|api|library|framework|examples|tutorial|guide"
            ;;
        fix)
            echo "fix|fixing|repair|resolve|solution|patch|correct|address"
            ;;
        optimize)
            echo "optimize|optimization|performance|speed|faster|efficiency|improve performance|bottleneck|slow"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Extract keywords from request
extract_keywords() {
    local request="$1"
    local keywords=()

    # Convert to lowercase for matching
    local request_lower=$(echo "$request" | tr '[:upper:]' '[:lower:]')

    # Extract technical terms (camelCase, snake_case, kebab-case)
    local tech_terms=$(echo "$request_lower" | grep -oE '[a-z]+[A-Z][a-zA-Z]+|[a-z]+_[a-z]+|[a-z]+-[a-z]+' || echo "")

    # Extract quoted strings (skip on macOS as -P not supported)
    local quoted=""

    # Combine all keywords
    for word in $tech_terms $quoted; do
        keywords+=("$word")
    done

    # Return as JSON array
    if [[ ${#keywords[@]} -gt 0 ]]; then
        printf '%s\n' "${keywords[@]}" | jq -R . | jq -s .
    else
        echo '[]'
    fi
}

# Calculate confidence score based on keyword matches
calculate_confidence() {
    local request="$1"
    local pattern="$2"
    local match_count=0
    local total_words=0

    # Convert to lowercase
    local request_lower=$(echo "$request" | tr '[:upper:]' '[:lower:]')

    # Count total words
    total_words=$(echo "$request_lower" | wc -w | tr -d ' ')

    # Count pattern matches
    IFS='|' read -ra PATTERNS <<< "$pattern"
    for p in "${PATTERNS[@]}"; do
        if echo "$request_lower" | grep -qE "\b$p\b"; then
            match_count=$((match_count + 1))
        fi
    done

    # Calculate confidence (0.0 - 1.0)
    if [[ $total_words -gt 0 ]]; then
        # Weight: pattern matches contribute 70%, keyword density 30%
        local pattern_score=$(echo "scale=2; $match_count * 0.35" | bc)
        local density_score=$(echo "scale=2; ($match_count / $total_words) * 0.65" | bc)
        local confidence=$(echo "scale=2; $pattern_score + $density_score" | bc)

        # Cap at 0.95 (never 100% certain)
        if (( $(echo "$confidence > 0.95" | bc -l) )); then
            confidence="0.95"
        fi

        echo "$confidence"
    else
        echo "0.0"
    fi
}

# Detect intent (action vs inquiry)
detect_intent() {
    local request="$1"
    local request_lower=$(echo "$request" | tr '[:upper:]' '[:lower:]')

    local action_score=0
    local inquiry_score=0

    # Check action patterns
    local action_pattern="need to|want to|can you|please|help me|show me how|implement|create|build|fix|add"
    IFS='|' read -ra PATTERNS <<< "$action_pattern"
    for p in "${PATTERNS[@]}"; do
        if echo "$request_lower" | grep -qE "\b$p\b"; then
            action_score=$((action_score + 1))
        fi
    done

    # Check inquiry patterns
    local inquiry_pattern="what is|why|how does|explain|tell me about|difference between"
    IFS='|' read -ra PATTERNS <<< "$inquiry_pattern"
    for p in "${PATTERNS[@]}"; do
        if echo "$request_lower" | grep -qE "\b$p\b"; then
            inquiry_score=$((inquiry_score + 1))
        fi
    done

    # Check for question marks
    if echo "$request" | grep -q "?"; then
        inquiry_score=$((inquiry_score + 1))
    fi

    # Determine intent
    if [[ $action_score -gt $inquiry_score ]]; then
        echo "action"
    elif [[ $inquiry_score -gt $action_score ]]; then
        echo "inquiry"
    else
        echo "mixed"
    fi
}

# Detect domain/technology area
detect_domain() {
    local request="$1"
    local request_lower=$(echo "$request" | tr '[:upper:]' '[:lower:]')
    local domains=()

    # Check backend
    if echo "$request_lower" | grep -qE "api|server|backend|database|db|sql|postgres|mysql|mongodb|redis|rest|graphql|endpoint"; then
        domains+=("backend")
    fi

    # Check frontend
    if echo "$request_lower" | grep -qE "ui|frontend|react|vue|angular|css|html|dom|component|button|form|page"; then
        domains+=("frontend")
    fi

    # Check devops
    if echo "$request_lower" | grep -qE "docker|kubernetes|deploy|deployment|ci|cd|pipeline|container|orchestration"; then
        domains+=("devops")
    fi

    # Check security
    if echo "$request_lower" | grep -qE "security|auth|authentication|authorization|jwt|oauth|encrypt|decrypt|vulnerability|xss|sql injection"; then
        domains+=("security")
    fi

    # Check testing
    if echo "$request_lower" | grep -qE "test|testing|jest|mocha|pytest|junit|coverage|assertion|mock"; then
        domains+=("testing")
    fi

    # Check data
    if echo "$request_lower" | grep -qE "data|dataset|csv|json|xml|parse|transform|etl|analytics"; then
        domains+=("data")
    fi

    # Check cli
    if echo "$request_lower" | grep -qE "cli|command|terminal|shell|script|bash|zsh"; then
        domains+=("cli")
    fi

    # Check ml
    if echo "$request_lower" | grep -qE "machine learning|ml|ai|neural|model|training|prediction|tensorflow|pytorch"; then
        domains+=("ml")
    fi

    # Return as JSON array
    if [[ ${#domains[@]} -gt 0 ]]; then
        printf '%s\n' "${domains[@]}" | jq -R . | jq -s .
    else
        echo '[]'
    fi
}

# Classify request into task type
classify_request() {
    local request="$1"
    local request_lower=$(echo "$request" | tr '[:upper:]' '[:lower:]')

    # Task types to check
    local task_types=("debug" "implement" "refactor" "explore" "test" "design" "research" "fix" "optimize")

    # Calculate scores for each task type
    local max_score=0
    local best_type=""
    local all_scores='{'

    for task_type in "${task_types[@]}"; do
        local pattern=$(get_pattern "$task_type")
        local confidence=$(calculate_confidence "$request" "$pattern")

        all_scores="${all_scores}\"${task_type}\": ${confidence}, "

        if (( $(echo "$confidence > $max_score" | bc -l) )); then
            max_score=$confidence
            best_type=$task_type
        fi
    done

    all_scores="${all_scores%%, }}"

    # If no clear match (confidence < 0.3), try heuristics
    if (( $(echo "$max_score < 0.3" | bc -l) )); then
        # Check for question words -> likely explore
        if echo "$request_lower" | grep -qE "^(what|where|how|why|when|which)"; then
            best_type="explore"
            max_score="0.6"
        # Check for imperative verbs -> likely implement
        elif echo "$request_lower" | grep -qE "^(create|build|make|add|write)"; then
            best_type="implement"
            max_score="0.6"
        else
            best_type="explore"
            max_score="0.4"
        fi
    fi

    # Extract additional metadata
    local keywords=$(extract_keywords "$request")
    local intent=$(detect_intent "$request")
    local domains=$(detect_domain "$request")

    # Get secondary types (within 20% of top score)
    local secondary_types=()
    local threshold=$(echo "scale=2; $max_score * 0.8" | bc)

    for task_type in "${task_types[@]}"; do
        if [[ "$task_type" != "$best_type" ]]; then
            local pattern=$(get_pattern "$task_type")
            local score=$(calculate_confidence "$request" "$pattern")
            if (( $(echo "$score >= $threshold" | bc -l) )); then
                secondary_types+=("$task_type")
            fi
        fi
    done

    # Build secondary_json
    local secondary_json
    if [[ ${#secondary_types[@]} -gt 0 ]]; then
        secondary_json=$(printf '%s\n' "${secondary_types[@]}" | jq -R . | jq -s .)
    else
        secondary_json="[]"
    fi

    # Generate complexity estimate
    local complexity="medium"
    local word_count=$(echo "$request" | wc -w | tr -d ' ')
    if [[ $word_count -lt 10 ]]; then
        complexity="low"
    elif [[ $word_count -gt 30 ]]; then
        complexity="high"
    fi

    # Check for complexity indicators
    if echo "$request_lower" | grep -qE "multiple|several|all|every|entire|system|architecture"; then
        complexity="high"
    fi

    # Output classification result
    cat <<EOF
{
  "type": "$best_type",
  "confidence": $max_score,
  "intent": "$intent",
  "complexity": "$complexity",
  "keywords": $keywords,
  "domains": $domains,
  "secondary_types": $secondary_json,
  "all_scores": $all_scores,
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

# Record classification for learning
record_classification() {
    local request="$1"
    local classification="$2"
    local outcome="${3:-pending}"

    init_classification_history

    # Escape quotes in request
    local escaped_request=$(echo "$request" | sed 's/"/\\"/g')

    # Add to history
    local entry=$(cat <<EOF
{
  "request": "$escaped_request",
  "classification": $classification,
  "outcome": "$outcome",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
)

    # Update history file
    local temp_file="$CLASSIFICATION_HISTORY.tmp"
    jq --argjson entry "$entry" '
        .classifications += [$entry] |
        .total_classifications += 1 |
        .last_updated = $entry.timestamp
    ' "$CLASSIFICATION_HISTORY" > "$temp_file" 2>/dev/null || echo '{}' > "$temp_file"

    mv "$temp_file" "$CLASSIFICATION_HISTORY"
}

# Update classification accuracy based on outcome
update_accuracy() {
    local task_type="$1"
    local outcome="$2"

    init_classification_history

    # Update pattern accuracy
    local temp_file="$CLASSIFICATION_HISTORY.tmp"
    jq --arg type "$task_type" --arg outcome "$outcome" '
        .pattern_accuracy[$type] //= {"total": 0, "successful": 0} |
        .pattern_accuracy[$type].total += 1 |
        if $outcome == "success" then
            .pattern_accuracy[$type].successful += 1
        else
            .
        end |
        .pattern_accuracy[$type].accuracy = (
            .pattern_accuracy[$type].successful / .pattern_accuracy[$type].total
        )
    ' "$CLASSIFICATION_HISTORY" > "$temp_file" 2>/dev/null || echo '{}' > "$temp_file"

    mv "$temp_file" "$CLASSIFICATION_HISTORY"
}

# Get classification statistics
get_stats() {
    init_classification_history

    jq '{
        total_classifications: .total_classifications,
        pattern_accuracy: .pattern_accuracy,
        recent_classifications: (.classifications | sort_by(.timestamp) | reverse | .[0:10])
    }' "$CLASSIFICATION_HISTORY" 2>/dev/null || echo '{}'
}

# Improve classification using learning data
enhance_with_learning() {
    local classification="$1"

    if [[ ! -f "$LEARNING_DATA" ]]; then
        echo "$classification"
        return
    fi

    # Get learned preferences from interaction learning
    local learned_techs=$(jq -r '.learned_preferences.technologies | to_entries | sort_by(.value) | reverse | .[0:3] | .[].key' "$LEARNING_DATA" 2>/dev/null || echo "")

    # Enhance domains with learned technologies
    if [[ -n "$learned_techs" ]]; then
        local tech_array=$(echo "$learned_techs" | jq -R . | jq -s .)
        classification=$(echo "$classification" | jq --argjson techs "$tech_array" '
            .learned_technologies = $techs
        ')
    fi

    echo "$classification"
}

# Main CLI interface
main() {
    local command="${1:-classify}"
    shift || true

    case "$command" in
        classify)
            local request="$*"
            if [[ -z "$request" ]]; then
                echo "Error: Request text required" >&2
                echo "Usage: $0 classify <request text>" >&2
                exit 1
            fi

            local result=$(classify_request "$request")
            # result=$(enhance_with_learning "$result")
            echo "$result" | jq .

            # Record classification (disabled for debugging)
            # record_classification "$request" "$result" "pending"
            ;;

        record-outcome)
            local task_type="$1"
            local outcome="$2"

            if [[ -z "$task_type" ]] || [[ -z "$outcome" ]]; then
                echo "Error: Task type and outcome required" >&2
                echo "Usage: $0 record-outcome <task_type> <success|failure>" >&2
                exit 1
            fi

            update_accuracy "$task_type" "$outcome"
            echo "Recorded outcome: $task_type -> $outcome"
            ;;

        stats)
            get_stats
            ;;

        test)
            echo "=== Request Classifier Test Suite ==="
            echo

            # Test cases
            echo "Request: Debug why authentication is failing"
            classify_request "Debug why authentication is failing" | jq -r '
                "  Type: \(.type) (confidence: \(.confidence))",
                "  Intent: \(.intent)",
                "  Complexity: \(.complexity)",
                "  Domains: \(.domains | join(", "))"
            '
            echo

            echo "Request: Implement user profile feature"
            classify_request "Implement user profile feature" | jq -r '
                "  Type: \(.type) (confidence: \(.confidence))",
                "  Intent: \(.intent)",
                "  Complexity: \(.complexity)"
            '
            echo

            echo "Request: Refactor the payment processing code"
            classify_request "Refactor the payment processing code" | jq -r '
                "  Type: \(.type) (confidence: \(.confidence))",
                "  Intent: \(.intent)"
            '
            echo

            echo "Request: Where is the API endpoint defined?"
            classify_request "Where is the API endpoint defined?" | jq -r '
                "  Type: \(.type) (confidence: \(.confidence))",
                "  Intent: \(.intent)"
            '
            echo
            ;;

        help|--help|-h)
            cat <<EOF
Request Classifier - Intelligent request classification for agent orchestration

USAGE:
    $0 <command> [args]

COMMANDS:
    classify <request>              Classify a request into task type
    record-outcome <type> <outcome> Record classification outcome for learning
    stats                           Show classification statistics
    test                            Run test suite with example requests
    help                            Show this help message

EXAMPLES:
    # Classify a request
    $0 classify "Debug why the API is failing"

    # Record successful classification
    $0 record-outcome debug success

    # View statistics
    $0 stats

OUTPUT FORMAT:
    {
        "type": "debug|implement|refactor|explore|test|design|research|fix|optimize",
        "confidence": 0.0-1.0,
        "intent": "action|inquiry|mixed",
        "complexity": "low|medium|high",
        "keywords": ["keyword1", "keyword2"],
        "domains": ["backend", "frontend"],
        "secondary_types": ["type1", "type2"],
        "learned_technologies": ["python", "shell"]
    }

EOF
            ;;

        *)
            echo "Error: Unknown command: $command" >&2
            echo "Run '$0 help' for usage information" >&2
            exit 1
            ;;
    esac
}

# Run main
main "$@"
