#!/usr/bin/env bash
#
# semantic-compressor.sh - Compress text while preserving semantic meaning
#
# Part of the Conversation Summarization System
# Uses multiple compression techniques to reduce token count while keeping key information
#

# Use bash 4+ if available, otherwise fallback to bash 3 compatible mode
if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
    set -euo pipefail
else
    set -eu
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Token estimation (rough: 4 chars = 1 token)
estimate_tokens() {
    local text="$1"
    local chars=$(echo -n "$text" | wc -c | tr -d ' ')
    echo $((chars / 4))
}

# Remove filler words and phrases
remove_filler() {
    local text="$1"

    # Filler words to remove
    local fillers=(
        "\bum\b"
        "\buh\b"
        "\blike\b"
        "\bbasically\b"
        "\bactually\b"
        "\bjust\b"
        "\breally\b"
        "\bkind of\b"
        "\bsort of\b"
        "\byou know\b"
        "\bI mean\b"
        "\bI think\b"
        "\bI guess\b"
        "\bprobably\b"
        "\bmaybe\b"
    )

    local result="$text"
    for filler in "${fillers[@]}"; do
        result=$(echo "$result" | sed -E "s/$filler//gi")
    done

    # Clean up multiple spaces
    result=$(echo "$result" | sed -E 's/  +/ /g')

    echo "$result"
}

# Condense common phrases to shorter equivalents
condense_phrases() {
    local text="$1"
    local result="$text"

    # Use sed for phrase replacements (bash 3 compatible)
    result=$(echo "$result" | sed 's/in order to/to/gi')
    result=$(echo "$result" | sed 's/at this point in time/now/gi')
    result=$(echo "$result" | sed 's/due to the fact that/because/gi')
    result=$(echo "$result" | sed 's/in the event that/if/gi')
    result=$(echo "$result" | sed 's/with regard to/regarding/gi')
    result=$(echo "$result" | sed 's/with reference to/about/gi')
    result=$(echo "$result" | sed 's/prior to/before/gi')
    result=$(echo "$result" | sed 's/subsequent to/after/gi')
    result=$(echo "$result" | sed 's/in spite of the fact that/although/gi')
    result=$(echo "$result" | sed 's/for the purpose of/for/gi')
    result=$(echo "$result" | sed 's/in the process of/while/gi')
    result=$(echo "$result" | sed 's/it is important to note that/note:/gi')
    result=$(echo "$result" | sed 's/as a matter of fact/in fact/gi')
    result=$(echo "$result" | sed 's/take into consideration/consider/gi')
    result=$(echo "$result" | sed 's/make a decision/decide/gi')
    result=$(echo "$result" | sed 's/come to a conclusion/conclude/gi')
    result=$(echo "$result" | sed 's/in a timely manner/promptly/gi')
    result=$(echo "$result" | sed 's/at the present time/currently/gi')
    result=$(echo "$result" | sed 's/on a regular basis/regularly/gi')
    result=$(echo "$result" | sed 's/in close proximity to/near/gi')

    echo "$result"
}

# Remove redundant information (repeated concepts)
remove_redundancy() {
    local text="$1"
    local output=""
    local prev_line=""

    # Track seen concepts to avoid repetition
    declare -A seen_concepts

    while IFS= read -r line; do
        if [ -z "$line" ]; then
            output+="\n"
            continue
        fi

        # Extract key terms (simple word extraction)
        local key_terms=$(echo "$line" | tr '[:upper:]' '[:lower:]' | grep -oE '\b[a-z]{4,}\b' | sort -u)

        # Check similarity with previous line
        local similarity=0
        if [ -n "$prev_line" ]; then
            local prev_terms=$(echo "$prev_line" | tr '[:upper:]' '[:lower:]' | grep -oE '\b[a-z]{4,}\b' | sort -u)
            local common=$(comm -12 <(echo "$key_terms") <(echo "$prev_terms") | wc -l | tr -d ' ')
            local total=$(echo "$key_terms" | wc -w | tr -d ' ')

            if [ $total -gt 0 ]; then
                similarity=$((common * 100 / total))
            fi
        fi

        # If similarity < 60%, include the line
        if [ $similarity -lt 60 ]; then
            output+="$line\n"
            prev_line="$line"
        fi
    done <<< "$text"

    echo -e "$output"
}

# Convert conversational text to dense format
densify_text() {
    local text="$1"

    # Replace conversational patterns with dense equivalents
    local result="$text"

    # "So we tried X but it didn't work" -> "X failed"
    result=$(echo "$result" | sed -E "s/[Ss]o (we|I) tried ([^,]+) but (it )?didn't work/\2 failed/g")

    # "Then we decided to use X" -> "→ X"
    result=$(echo "$result" | sed -E "s/[Tt]hen (we|I) decided to (use |go with )?/→ /g")

    # "The reason is that" -> "because"
    result=$(echo "$result" | sed -E "s/[Tt]he reason is that/because/g")

    # "We found that X works well" -> "X works"
    result=$(echo "$result" | sed -E "s/(We|I) found that ([^.]+) works? well/\2 works/g")

    # "This approach allows us to" -> "This enables"
    result=$(echo "$result" | sed -E "s/[Tt]his approach allows (us|you) to/This enables/g")

    echo "$result"
}

# Prioritize sentences by importance
prioritize_sentences() {
    local text="$1"
    local max_tokens="${2:-1000}"

    # Simple prioritization without associative arrays (bash 3 compatible)
    local output=""
    local current_tokens=0

    while IFS= read -r sentence; do
        if [ -z "$sentence" ]; then continue; fi

        # Calculate score based on keyword presence
        local score=1
        if echo "$sentence" | grep -Eqi "decided|chose|fixed|solved|critical"; then
            score=4
        elif echo "$sentence" | grep -Eqi "because|working|failed|error|key|important|main|primary|successfully|deployed|tested"; then
            score=3
        fi

        local sentence_tokens=$(estimate_tokens "$sentence")

        # Add high-priority sentences first
        if [ $score -ge 3 ] && [ $((current_tokens + sentence_tokens)) -le $max_tokens ]; then
            output+="$sentence. "
            current_tokens=$((current_tokens + sentence_tokens))
        fi
    done < <(echo "$text" | sed 's/\. /.\n/g')

    # If still under limit, add remaining sentences
    if [ $current_tokens -lt $max_tokens ]; then
        while IFS= read -r sentence; do
            if [ -z "$sentence" ]; then continue; fi

            # Skip if already added (simple check)
            if echo "$output" | grep -qF "$sentence"; then
                continue
            fi

            local sentence_tokens=$(estimate_tokens "$sentence")

            if [ $((current_tokens + sentence_tokens)) -le $max_tokens ]; then
                output+="$sentence. "
                current_tokens=$((current_tokens + sentence_tokens))
            else
                break
            fi
        done < <(echo "$text" | sed 's/\. /.\n/g')
    fi

    echo "$output"
}

# Compress text to target ratio
compress_to_ratio() {
    local text="$1"
    local target_ratio="${2:-0.1}"  # Default 10:1 compression

    local original_tokens=$(estimate_tokens "$text")
    local target_tokens=$(echo "scale=0; $original_tokens * $target_ratio" | bc)

    # Apply compression techniques in sequence
    local result="$text"

    # 1. Remove filler words (~5-10% reduction)
    result=$(remove_filler "$result")

    # 2. Condense phrases (~10-15% reduction)
    result=$(condense_phrases "$result")

    # 3. Densify conversational text (~15-20% reduction)
    result=$(densify_text "$result")

    # 4. Remove redundancy (~10-15% reduction)
    result=$(remove_redundancy "$result")

    # 5. If still too long, prioritize by importance
    local current_tokens=$(estimate_tokens "$result")
    if [ $current_tokens -gt $target_tokens ]; then
        result=$(prioritize_sentences "$result" "$target_tokens")
    fi

    echo "$result"
}

# Compress but preserve code blocks
compress_with_code() {
    local text="$1"
    local target_ratio="${2:-0.1}"

    # Extract code blocks
    local code_blocks=()
    local text_parts=()
    local in_code=0
    local current_block=""
    local current_text=""

    while IFS= read -r line; do
        if echo "$line" | grep -q '^```'; then
            if [ $in_code -eq 0 ]; then
                # Start of code block - save accumulated text
                if [ -n "$current_text" ]; then
                    text_parts+=("$current_text")
                    current_text=""
                fi
                in_code=1
                current_block="$line\n"
            else
                # End of code block
                current_block+="$line\n"
                code_blocks+=("$current_block")
                current_block=""
                in_code=0
            fi
        elif [ $in_code -eq 1 ]; then
            current_block+="$line\n"
        else
            current_text+="$line\n"
        fi
    done <<< "$text"

    # Save final text part
    if [ -n "$current_text" ]; then
        text_parts+=("$current_text")
    fi

    # Compress text parts
    local compressed_parts=()
    for part in "${text_parts[@]}"; do
        compressed_parts+=("$(compress_to_ratio "$part" "$target_ratio")")
    done

    # Reconstruct with code blocks preserved
    local output=""
    local text_idx=0
    local code_idx=0

    for ((i=0; i<${#text_parts[@]}; i++)); do
        output+="${compressed_parts[$i]}\n"
        if [ $code_idx -lt ${#code_blocks[@]} ]; then
            output+="${code_blocks[$code_idx]}\n"
            ((code_idx++))
        fi
    done

    echo -e "$output"
}

# Get compression statistics
compression_stats() {
    local original="$1"
    local compressed="$2"

    local original_tokens=$(estimate_tokens "$original")
    local compressed_tokens=$(estimate_tokens "$compressed")
    local saved_tokens=$((original_tokens - compressed_tokens))
    local ratio=$(echo "scale=2; $original_tokens / $compressed_tokens" | bc)
    local percent=$(echo "scale=1; ($saved_tokens * 100) / $original_tokens" | bc)

    cat <<EOF
{
    "original_tokens": $original_tokens,
    "compressed_tokens": $compressed_tokens,
    "saved_tokens": $saved_tokens,
    "compression_ratio": $ratio,
    "percent_reduction": $percent
}
EOF
}

# CLI interface
main() {
    local command="${1:-compress}"
    local input_file="${2:-}"
    local target_ratio="${3:-0.1}"

    case "$command" in
        compress)
            if [ -z "$input_file" ]; then
                echo "Usage: $0 compress <input_file> [target_ratio]" >&2
                exit 1
            fi
            compress_to_ratio "$(cat "$input_file")" "$target_ratio"
            ;;
        compress-with-code)
            if [ -z "$input_file" ]; then
                echo "Usage: $0 compress-with-code <input_file> [target_ratio]" >&2
                exit 1
            fi
            compress_with_code "$(cat "$input_file")" "$target_ratio"
            ;;
        stats)
            if [ -z "$input_file" ]; then
                echo "Usage: $0 stats <original_file> <compressed_file>" >&2
                exit 1
            fi
            local compressed_file="$target_ratio"
            compression_stats "$(cat "$input_file")" "$(cat "$compressed_file")"
            ;;
        *)
            echo "Usage: $0 {compress|compress-with-code|stats} <input_file> [params]" >&2
            echo "" >&2
            echo "Commands:" >&2
            echo "  compress             - Compress text to target ratio (default 0.1 = 10:1)" >&2
            echo "  compress-with-code   - Compress but preserve code blocks" >&2
            echo "  stats                - Show compression statistics" >&2
            exit 1
            ;;
    esac
}

# Run if called directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
