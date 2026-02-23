#!/usr/bin/env bash
#
# key-point-extractor.sh - Extract important information from conversations
#
# Part of the Conversation Summarization System
# Extracts decisions, solutions, insights, and outcomes from conversation text
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$HOME/.claude/data"

# Token estimation (rough: 4 chars = 1 token)
estimate_tokens() {
    local text="$1"
    local chars=$(echo -n "$text" | wc -c | tr -d ' ')
    echo $((chars / 4))
}

# Extract text between line numbers (for context)
get_context_lines() {
    local text="$1"
    local start_line="$2"
    local num_lines="${3:-5}"

    echo "$text" | tail -n +$start_line | head -n $num_lines
}

# Extract decisions from conversation
extract_decisions() {
    local conversation="$1"
    local output=""

    # Decision patterns
    local patterns=(
        "decided to"
        "chose to"
        "going with"
        "let's use"
        "will use"
        "opted for"
        "selected"
        "picking"
    )

    for pattern in "${patterns[@]}"; do
        while IFS= read -r match; do
            if [ -z "$match" ]; then continue; fi

            # Get the decision statement
            local decision=$(echo "$match" | sed -E 's/.*'"$pattern"'//' | head -c 200)

            # Look for rationale in next few lines
            local line_num=$(echo "$conversation" | grep -n "$match" | head -1 | cut -d: -f1)
            local context=$(get_context_lines "$conversation" "$((line_num + 1))" 5)
            local rationale=$(echo "$context" | grep -E "because|since|reason|as it|this way" | head -1 | head -c 200)

            if [ -n "$decision" ]; then
                output+="**Decision:** ${decision}\n"
                if [ -n "$rationale" ]; then
                    output+="  **Rationale:** ${rationale}\n"
                fi
                output+="\n"
            fi
        done < <(echo "$conversation" | grep -i "$pattern")
    done

    echo -e "$output"
}

# Extract solutions and fixes
extract_solutions() {
    local conversation="$1"
    local output=""

    # Problem patterns
    local problem_patterns=(
        "problem:"
        "issue:"
        "error:"
        "bug:"
        "failing"
        "doesn't work"
        "not working"
    )

    # Solution patterns
    local solution_patterns=(
        "solution:"
        "fixed by"
        "resolved with"
        "solved by"
        "this works"
        "working now"
        "fix:"
    )

    # Find problem-solution pairs
    local in_problem=0
    local current_problem=""
    local line_num=0

    while IFS= read -r line; do
        ((line_num++))

        # Check if this is a problem statement
        for pattern in "${problem_patterns[@]}"; do
            if echo "$line" | grep -qi "$pattern"; then
                current_problem=$(echo "$line" | sed -E 's/.*'"$pattern"'//' | head -c 150)
                in_problem=1
                break
            fi
        done

        # Check if this is a solution (within 20 lines of problem)
        if [ $in_problem -eq 1 ]; then
            for pattern in "${solution_patterns[@]}"; do
                if echo "$line" | grep -qi "$pattern"; then
                    local solution=$(echo "$line" | sed -E 's/.*'"$pattern"'//' | head -c 200)

                    if [ -n "$current_problem" ] && [ -n "$solution" ]; then
                        output+="**Problem:** ${current_problem}\n"
                        output+="**Solution:** ${solution}\n\n"
                    fi

                    in_problem=0
                    current_problem=""
                    break
                fi
            done
        fi
    done <<< "$conversation"

    echo -e "$output"
}

# Extract code snippets that were marked as working
extract_code_snippets() {
    local conversation="$1"
    local max_snippets="${2:-5}"
    local output=""
    local count=0

    # Convert conversation to array to look ahead/behind
    local lines=()
    while IFS= read -r line; do
        lines+=("$line")
    done <<< "$conversation"

    # Find code blocks
    local i=0
    while [ $i -lt ${#lines[@]} ]; do
        local line="${lines[$i]}"

        # Check if this is start of code block
        if echo "$line" | grep -q '^```'; then
            local code_lang=$(echo "$line" | sed 's/```//' | tr -d ' ')
            local code_block=""
            local start_idx=$i

            # Find matching end
            ((i++))
            while [ $i -lt ${#lines[@]} ]; do
                line="${lines[$i]}"
                if echo "$line" | grep -q '^```'; then
                    # Found end of code block

                    # Check context before and after
                    local context_before=""
                    local context_after=""

                    if [ $start_idx -gt 0 ]; then
                        context_before="${lines[$((start_idx - 1))]}"
                    fi

                    if [ $((i + 1)) -lt ${#lines[@]} ]; then
                        context_after="${lines[$((i + 1))]}"
                    fi
                    if [ $((i + 2)) -lt ${#lines[@]} ]; then
                        context_after="$context_after ${lines[$((i + 2))]}"
                    fi

                    # Check if code was marked as working
                    if echo "$context_before $context_after" | grep -Eqi "this works|working|successful|use this|final|perfectly|implementation"; then
                        if [ $count -lt $max_snippets ]; then
                            # Trim code block to reasonable size
                            local line_count=$(echo -e "$code_block" | wc -l | tr -d ' ')
                            local trimmed=$(echo -e "$code_block" | head -n 20)

                            output+="\`\`\`${code_lang}\n${trimmed}\n\`\`\`\n"

                            if [ "$line_count" -gt 20 ]; then
                                output+="*(${line_count} lines total, showing first 20)*\n"
                            fi
                            output+="\n"

                            ((count++))
                        fi
                    fi

                    break
                else
                    code_block+="$line\n"
                fi
                ((i++))
            done
        fi

        ((i++))
    done

    echo -e "$output"
}

# Extract insights and learnings
extract_insights() {
    local conversation="$1"
    local output=""

    # Insight patterns
    local patterns=(
        "learned that"
        "discovered"
        "realized"
        "turns out"
        "important to note"
        "keep in mind"
        "key insight"
        "found that"
    )

    for pattern in "${patterns[@]}"; do
        while IFS= read -r match; do
            if [ -z "$match" ]; then continue; fi

            # Get the insight
            local insight=$(echo "$match" | sed -E 's/.*'"$pattern"'//' | head -c 250)

            if [ -n "$insight" ]; then
                output+="- ${insight}\n"
            fi
        done < <(echo "$conversation" | grep -i "$pattern")
    done

    echo -e "$output"
}

# Extract outcomes and results
extract_outcomes() {
    local conversation="$1"
    local output=""

    # Success patterns
    local success_patterns=(
        "working"
        "successful"
        "deployed"
        "merged"
        "completed"
        "finished"
        "passed tests"
        "verified"
    )

    # Failure patterns
    local failure_patterns=(
        "didn't work"
        "failed"
        "error"
        "blocked"
        "couldn't"
        "unable to"
    )

    # Partial success patterns
    local partial_patterns=(
        "works but"
        "almost"
        "needs improvement"
        "mostly working"
        "partial"
    )

    # Scan for outcomes
    while IFS= read -r line; do
        local marked=0

        # Check success
        for pattern in "${success_patterns[@]}"; do
            if echo "$line" | grep -qi "$pattern"; then
                output+="✅ $(echo "$line" | head -c 150)\n"
                marked=1
                break
            fi
        done

        # Check failure (if not already marked success)
        if [ $marked -eq 0 ]; then
            for pattern in "${failure_patterns[@]}"; do
                if echo "$line" | grep -qi "$pattern"; then
                    output+="❌ $(echo "$line" | head -c 150)\n"
                    marked=1
                    break
                fi
            done
        fi

        # Check partial (if not already marked)
        if [ $marked -eq 0 ]; then
            for pattern in "${partial_patterns[@]}"; do
                if echo "$line" | grep -qi "$pattern"; then
                    output+="⚠️  $(echo "$line" | head -c 150)\n"
                    marked=1
                    break
                fi
            done
        fi
    done <<< "$conversation"

    echo -e "$output"
}

# Extract all key points from conversation
extract_all_key_points() {
    local conversation="$1"
    local output=""

    # Decisions
    local decisions=$(extract_decisions "$conversation")
    if [ -n "$decisions" ]; then
        output+="### Decisions\n\n${decisions}\n"
    fi

    # Solutions
    local solutions=$(extract_solutions "$conversation")
    if [ -n "$solutions" ]; then
        output+="### Solutions\n\n${solutions}\n"
    fi

    # Insights
    local insights=$(extract_insights "$conversation")
    if [ -n "$insights" ]; then
        output+="### Insights\n\n${insights}\n"
    fi

    # Code snippets
    local code=$(extract_code_snippets "$conversation" 3)
    if [ -n "$code" ]; then
        output+="### Code Highlights\n\n${code}\n"
    fi

    # Outcomes
    local outcomes=$(extract_outcomes "$conversation")
    if [ -n "$outcomes" ]; then
        output+="### Outcomes\n\n${outcomes}\n"
    fi

    echo -e "$output"
}

# Extract structured key points (JSON output)
extract_structured_key_points() {
    local conversation="$1"

    local decisions=$(extract_decisions "$conversation" | jq -Rs .)
    local solutions=$(extract_solutions "$conversation" | jq -Rs .)
    local insights=$(extract_insights "$conversation" | jq -Rs .)
    local outcomes=$(extract_outcomes "$conversation" | jq -Rs .)

    jq -n \
        --arg decisions "$decisions" \
        --arg solutions "$solutions" \
        --arg insights "$insights" \
        --arg outcomes "$outcomes" \
        '{
            decisions: $decisions,
            solutions: $solutions,
            insights: $insights,
            outcomes: $outcomes
        }'
}

# CLI interface
main() {
    local command="${1:-}"
    local input_file="${2:-}"

    case "$command" in
        decisions)
            if [ -z "$input_file" ]; then
                echo "Usage: $0 decisions <conversation_file>" >&2
                exit 1
            fi
            extract_decisions "$(cat "$input_file")"
            ;;
        solutions)
            if [ -z "$input_file" ]; then
                echo "Usage: $0 solutions <conversation_file>" >&2
                exit 1
            fi
            extract_solutions "$(cat "$input_file")"
            ;;
        insights)
            if [ -z "$input_file" ]; then
                echo "Usage: $0 insights <conversation_file>" >&2
                exit 1
            fi
            extract_insights "$(cat "$input_file")"
            ;;
        code)
            if [ -z "$input_file" ]; then
                echo "Usage: $0 code <conversation_file>" >&2
                exit 1
            fi
            extract_code_snippets "$(cat "$input_file")"
            ;;
        outcomes)
            if [ -z "$input_file" ]; then
                echo "Usage: $0 outcomes <conversation_file>" >&2
                exit 1
            fi
            extract_outcomes "$(cat "$input_file")"
            ;;
        all)
            if [ -z "$input_file" ]; then
                echo "Usage: $0 all <conversation_file>" >&2
                exit 1
            fi
            extract_all_key_points "$(cat "$input_file")"
            ;;
        structured)
            if [ -z "$input_file" ]; then
                echo "Usage: $0 structured <conversation_file>" >&2
                exit 1
            fi
            extract_structured_key_points "$(cat "$input_file")"
            ;;
        *)
            echo "Usage: $0 {decisions|solutions|insights|code|outcomes|all|structured} <conversation_file>" >&2
            echo "" >&2
            echo "Commands:" >&2
            echo "  decisions   - Extract decision points and rationale" >&2
            echo "  solutions   - Extract problem-solution pairs" >&2
            echo "  insights    - Extract learnings and insights" >&2
            echo "  code        - Extract important code snippets" >&2
            echo "  outcomes    - Extract success/failure outcomes" >&2
            echo "  all         - Extract all key points (markdown)" >&2
            echo "  structured  - Extract all key points (JSON)" >&2
            exit 1
            ;;
    esac
}

# Run if called directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
