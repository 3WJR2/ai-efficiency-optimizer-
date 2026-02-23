#!/usr/bin/env bash
# solution-recommender.sh - Recommend relevant past solutions
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DATA_DIR="${HOME}/.claude/data"
KNOWLEDGE_DIR="${HOME}/.claude/knowledge"
GRAPH_FILE="${KNOWLEDGE_DIR}/knowledge-graph.json"
EMBEDDINGS_FILE="${CLAUDE_DATA_DIR}/knowledge-embeddings.json"
RECOMMENDATION_CACHE="${KNOWLEDGE_DIR}/recommendation-cache.json"

# Weights for ranking algorithm
WEIGHT_SEMANTIC=0.40
WEIGHT_TAG_OVERLAP=0.20
WEIGHT_RECENCY=0.15
WEIGHT_CONFIDENCE=0.15
WEIGHT_SUCCESS_RATE=0.10

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Initialize recommendation cache
initialize_cache() {
    if [[ ! -f "${RECOMMENDATION_CACHE}" ]]; then
        cat > "${RECOMMENDATION_CACHE}" <<'EOF'
{
  "version": "1.0.0",
  "recommendations": {},
  "usage_stats": {}
}
EOF
    fi
}

# Calculate semantic similarity (simplified)
calculate_semantic_similarity() {
    local query="$1"
    local target="$2"

    # Convert to lowercase and split into words
    local query_words=($(echo "$query" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u | grep -v '^$'))
    local target_words=($(echo "$target" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u | grep -v '^$'))

    # Handle empty arrays
    if [[ ${#query_words[@]} -eq 0 || ${#target_words[@]} -eq 0 ]]; then
        echo "0.0"
        return
    fi

    # Calculate intersection
    local intersection=0
    for word in "${query_words[@]}"; do
        if [[ " ${target_words[*]} " =~ " ${word} " ]]; then
            ((intersection++)) || true
        fi
    done

    # Calculate union
    local union=$((${#query_words[@]} + ${#target_words[@]} - intersection))

    if [[ $union -eq 0 ]]; then
        echo "0.0"
    else
        echo "scale=3; $intersection / $union" | bc
    fi
}

# Calculate tag overlap
calculate_tag_overlap() {
    local query_tags="$1"
    local target_tags="$2"

    # Parse JSON arrays
    local query_array=($(echo "$query_tags" | jq -r '.[]' 2>/dev/null || echo ""))
    local target_array=($(echo "$target_tags" | jq -r '.[]' 2>/dev/null || echo ""))

    if [[ ${#query_array[@]} -eq 0 || ${#target_array[@]} -eq 0 ]]; then
        echo "0.0"
        return
    fi

    # Calculate intersection
    local intersection=0
    for tag in "${query_array[@]}"; do
        if [[ " ${target_array[@]} " =~ " ${tag} " ]]; then
            ((intersection++)) || true
        fi
    done

    # Calculate union
    local union=$((${#query_array[@]} + ${#target_array[@]} - intersection))

    if [[ $union -eq 0 ]]; then
        echo "0.0"
    else
        echo "scale=3; $intersection / $union" | bc
    fi
}

# Calculate recency score (exponential decay)
calculate_recency_score() {
    local timestamp="$1"
    local now=$(date +%s)

    # Parse timestamp (handle various formats)
    local ts_epoch
    if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        ts_epoch=$timestamp
    else
        ts_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s 2>/dev/null || echo "$now")
    fi

    # Calculate days ago
    local days_ago=$(( (now - ts_epoch) / 86400 ))

    # Exponential decay: score = e^(-days/30)
    # Recent (0 days) = 1.0, 30 days = 0.37, 60 days = 0.14
    echo "scale=3; e(-$days_ago/30)" | bc -l
}

# Get success rate for a knowledge entry
get_success_rate() {
    local knowledge_id="$1"

    # Check usage stats
    local used_count=$(jq -r --arg id "$knowledge_id" \
        '.usage_stats[$id].used_count // 0' "${RECOMMENDATION_CACHE}" 2>/dev/null || echo "0")

    local success_count=$(jq -r --arg id "$knowledge_id" \
        '.usage_stats[$id].success_count // 0' "${RECOMMENDATION_CACHE}" 2>/dev/null || echo "0")

    if [[ $used_count -eq 0 ]]; then
        echo "0.5"  # Neutral score for unused knowledge
    else
        echo "scale=3; $success_count / $used_count" | bc
    fi
}

# Recommend solutions based on problem description
recommend_solutions() {
    local problem_desc="$1"
    local top_k="${2:-10}"

    log_info "Searching for solutions to: $problem_desc"

    initialize_cache

    # Check if graph exists
    if [[ ! -f "${GRAPH_FILE}" ]]; then
        log_error "Knowledge graph not found. Run knowledge-graph-builder.sh first."
        echo '{"error": "Graph not found", "recommendations": []}'
        return 1
    fi

    # Get all nodes
    local nodes=$(jq -c '.nodes[]' "${GRAPH_FILE}")

    # Score each node
    local recommendations=()

    while IFS= read -r node; do
        local node_id=$(echo "$node" | jq -r '.id')
        local node_tags=$(echo "$node" | jq -c '.tags // []')
        local node_confidence=$(echo "$node" | jq -r '.confidence // 0.5')
        local node_created=$(echo "$node" | jq -r '.created // .metadata.timestamp // ""')

        # Get problem and solution from metadata
        local problem=$(echo "$node" | jq -r '.metadata.problem // ""')
        local solution=$(echo "$node" | jq -r '.metadata.solution // ""')
        local content="$problem $solution"

        # Calculate scores
        local semantic_sim=$(calculate_semantic_similarity "$problem_desc" "$content")
        local tag_overlap=0.0  # Would extract tags from problem_desc in production
        local recency_score=$(calculate_recency_score "$node_created")
        local success_rate=$(get_success_rate "$node_id")

        # Calculate weighted score
        local total_score=$(echo "scale=3; \
            $semantic_sim * $WEIGHT_SEMANTIC + \
            $tag_overlap * $WEIGHT_TAG_OVERLAP + \
            $recency_score * $WEIGHT_RECENCY + \
            $node_confidence * $WEIGHT_CONFIDENCE + \
            $success_rate * $WEIGHT_SUCCESS_RATE" | bc)

        # Create recommendation entry
        local rec=$(jq -n \
            --arg id "$node_id" \
            --arg problem "$problem" \
            --arg solution "$solution" \
            --argjson score "$total_score" \
            --argjson semantic "$semantic_sim" \
            --argjson tags "$tag_overlap" \
            --argjson recency "$recency_score" \
            --argjson conf "$node_confidence" \
            --argjson success "$success_rate" \
            '{
                knowledge_id: $id,
                score: $score,
                problem: $problem,
                solution: $solution,
                why_relevant: {
                    semantic_similarity: $semantic,
                    tag_overlap: $tags,
                    recency_score: $recency,
                    confidence: $conf,
                    success_rate: $success
                }
            }')

        recommendations+=("$rec")
    done <<< "$nodes"

    # Sort by score and take top K
    local sorted=$(printf '%s\n' "${recommendations[@]}" | \
        jq -s 'sort_by(-.score) | .[0:'"$top_k"'] |
        to_entries | map(.value + {rank: (.key + 1)})')

    # Format final output
    jq -n \
        --arg query "$problem_desc" \
        --argjson recs "$sorted" \
        --argjson total "$(echo ${#recommendations[@]})" \
        '{
            query: $query,
            recommendations: $recs,
            total: $total,
            timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }'
}

# Recommend by context (domain, language, tags)
recommend_by_context() {
    local domain="${1:-}"
    local language="${2:-}"
    local tags="${3:-[]}"
    local top_k="${4:-10}"

    log_info "Searching by context: domain=$domain, language=$language"

    initialize_cache

    if [[ ! -f "${GRAPH_FILE}" ]]; then
        log_error "Knowledge graph not found."
        echo '{"error": "Graph not found", "recommendations": []}'
        return 1
    fi

    # Build context tags
    local context_tags="$tags"
    if [[ -n "$domain" ]]; then
        context_tags=$(echo "$context_tags" | jq --arg d "$domain" '. += [$d]')
    fi
    if [[ -n "$language" ]]; then
        context_tags=$(echo "$context_tags" | jq --arg l "$language" '. += [$l]')
    fi

    # Get all nodes
    local nodes=$(jq -c '.nodes[]' "${GRAPH_FILE}")
    local recommendations=()

    while IFS= read -r node; do
        local node_id=$(echo "$node" | jq -r '.id')
        local node_tags=$(echo "$node" | jq -c '.tags // []')
        local node_confidence=$(echo "$node" | jq -r '.confidence // 0.5')

        # Calculate tag overlap
        local tag_overlap=$(calculate_tag_overlap "$context_tags" "$node_tags")

        # Only include if there's some overlap
        if (( $(echo "$tag_overlap > 0.0" | bc -l) )); then
            local rec=$(jq -n \
                --arg id "$node_id" \
                --argjson overlap "$tag_overlap" \
                --argjson conf "$node_confidence" \
                '{
                    knowledge_id: $id,
                    score: ($overlap + $conf) / 2,
                    tag_overlap: $overlap,
                    confidence: $conf
                }')
            recommendations+=("$rec")
        fi
    done <<< "$nodes"

    # Sort and take top K
    local sorted=$(printf '%s\n' "${recommendations[@]}" | \
        jq -s 'sort_by(-.score) | .[0:'"$top_k"']')

    jq -n \
        --arg domain "$domain" \
        --arg language "$language" \
        --argjson tags "$context_tags" \
        --argjson recs "$sorted" \
        '{
            context: {domain: $domain, language: $language, tags: $tags},
            recommendations: $recs,
            timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }'
}

# Find solutions similar to a given knowledge entry
recommend_similar_to() {
    local knowledge_id="$1"
    local top_k="${2:-5}"

    log_info "Finding solutions similar to: $knowledge_id"

    if [[ ! -f "${GRAPH_FILE}" ]]; then
        log_error "Knowledge graph not found."
        echo '{"error": "Graph not found"}'
        return 1
    fi

    # Get source node
    local source_node=$(jq --arg id "$knowledge_id" '.nodes[] | select(.id == $id)' "${GRAPH_FILE}")

    if [[ -z "$source_node" ]]; then
        log_error "Node not found: $knowledge_id"
        echo '{"error": "Node not found"}'
        return 1
    fi

    # Get source content and tags
    local source_content=$(echo "$source_node" | jq -r '.metadata.problem + " " + .metadata.solution // ""')
    local source_tags=$(echo "$source_node" | jq -c '.tags // []')

    # Find similar nodes
    local nodes=$(jq -c --arg id "$knowledge_id" '.nodes[] | select(.id != $id)' "${GRAPH_FILE}")
    local recommendations=()

    while IFS= read -r node; do
        local node_id=$(echo "$node" | jq -r '.id')
        local node_content=$(echo "$node" | jq -r '.metadata.problem + " " + .metadata.solution // ""')
        local node_tags=$(echo "$node" | jq -c '.tags // []')

        # Calculate similarity
        local semantic_sim=$(calculate_semantic_similarity "$source_content" "$node_content")
        local tag_overlap=$(calculate_tag_overlap "$source_tags" "$node_tags")

        # Combined score
        local score=$(echo "scale=3; ($semantic_sim + $tag_overlap) / 2" | bc)

        if (( $(echo "$score > 0.3" | bc -l) )); then
            local rec=$(jq -n \
                --arg id "$node_id" \
                --argjson score "$score" \
                --argjson semantic "$semantic_sim" \
                --argjson tags "$tag_overlap" \
                '{
                    knowledge_id: $id,
                    score: $score,
                    semantic_similarity: $semantic,
                    tag_overlap: $tags
                }')
            recommendations+=("$rec")
        fi
    done <<< "$nodes"

    # Sort and take top K
    local sorted=$(printf '%s\n' "${recommendations[@]}" | \
        jq -s 'sort_by(-.score) | .[0:'"$top_k"']')

    jq -n \
        --arg source "$knowledge_id" \
        --argjson similar "$sorted" \
        '{
            source_knowledge_id: $source,
            similar_solutions: $similar,
            timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }'
}

# Explain why a recommendation was made
explain_recommendation() {
    local knowledge_id="$1"
    local query="$2"

    log_info "Explaining recommendation: $knowledge_id"

    if [[ ! -f "${GRAPH_FILE}" ]]; then
        log_error "Knowledge graph not found."
        echo '{"error": "Graph not found"}'
        return 1
    fi

    # Get node
    local node=$(jq --arg id "$knowledge_id" '.nodes[] | select(.id == $id)' "${GRAPH_FILE}")

    if [[ -z "$node" ]]; then
        log_error "Node not found: $knowledge_id"
        echo '{"error": "Node not found"}'
        return 1
    fi

    # Calculate all relevance factors
    local content=$(echo "$node" | jq -r '.metadata.problem + " " + .metadata.solution // ""')
    local tags=$(echo "$node" | jq -c '.tags // []')
    local confidence=$(echo "$node" | jq -r '.confidence // 0.5')
    local created=$(echo "$node" | jq -r '.created // ""')

    local semantic_sim=$(calculate_semantic_similarity "$query" "$content")
    local recency_score=$(calculate_recency_score "$created")
    local success_rate=$(get_success_rate "$knowledge_id")

    # Get related knowledge
    local related=$(jq --arg id "$knowledge_id" \
        '[.edges[] | select(.from == $id or .to == $id) |
         if .from == $id then .to else .from end] | unique' \
        "${GRAPH_FILE}")

    # Build explanation
    jq -n \
        --arg id "$knowledge_id" \
        --arg query "$query" \
        --argjson node "$node" \
        --argjson semantic "$semantic_sim" \
        --argjson recency "$recency_score" \
        --argjson conf "$confidence" \
        --argjson success "$success_rate" \
        --argjson related "$related" \
        '{
            knowledge_id: $id,
            query: $query,
            explanation: {
                semantic_match: {
                    score: $semantic,
                    interpretation: (if ($semantic > 0.8) then "Very high match"
                                    elif ($semantic > 0.6) then "Good match"
                                    elif ($semantic > 0.4) then "Moderate match"
                                    else "Low match" end)
                },
                recency: {
                    score: $recency,
                    interpretation: (if ($recency > 0.9) then "Very recent"
                                    elif ($recency > 0.7) then "Recent"
                                    elif ($recency > 0.4) then "Moderately old"
                                    else "Old" end)
                },
                confidence: {
                    score: $conf,
                    interpretation: (if ($conf > 0.85) then "High confidence"
                                    elif ($conf > 0.70) then "Good confidence"
                                    elif ($conf > 0.50) then "Moderate confidence"
                                    else "Low confidence" end)
                },
                success_rate: {
                    score: $success,
                    interpretation: (if ($success > 0.8) then "Highly successful"
                                    elif ($success > 0.6) then "Successful"
                                    elif ($success > 0.4) then "Moderately successful"
                                    else "Unproven" end)
                },
                related_solutions: $related
            },
            node: $node
        }'
}

# Get recommendation path (lineage)
get_recommendation_path() {
    local knowledge_id="$1"

    log_info "Getting knowledge lineage for: $knowledge_id"

    if [[ ! -f "${GRAPH_FILE}" ]]; then
        log_error "Knowledge graph not found."
        echo '{"error": "Graph not found"}'
        return 1
    fi

    # Find all "builds-on" relationships leading to this node
    local predecessors=$(jq --arg id "$knowledge_id" \
        '[.edges[] | select(.to == $id and .type == "builds-on") | .from]' \
        "${GRAPH_FILE}")

    # Find all nodes that build on this one
    local successors=$(jq --arg id "$knowledge_id" \
        '[.edges[] | select(.from == $id and .type == "builds-on") | .to]' \
        "${GRAPH_FILE}")

    jq -n \
        --arg id "$knowledge_id" \
        --argjson pred "$predecessors" \
        --argjson succ "$successors" \
        '{
            knowledge_id: $id,
            predecessors: $pred,
            successors: $succ,
            lineage: {
                builds_on: $pred,
                extended_by: $succ
            }
        }'
}

# Track recommendation usage
track_usage() {
    local knowledge_id="$1"
    local outcome="${2:-used}"  # used|success|failure

    initialize_cache

    log_info "Tracking usage: $knowledge_id ($outcome)"

    # Update usage stats
    jq --arg id "$knowledge_id" \
       --arg outcome "$outcome" \
       '
       .usage_stats[$id] = (.usage_stats[$id] // {used_count: 0, success_count: 0, failure_count: 0}) |
       .usage_stats[$id].used_count += 1 |
       if $outcome == "success" then
           .usage_stats[$id].success_count += 1
       elif $outcome == "failure" then
           .usage_stats[$id].failure_count += 1
       else . end |
       .usage_stats[$id].last_used = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
       ' "${RECOMMENDATION_CACHE}" > "${RECOMMENDATION_CACHE}.tmp"

    mv "${RECOMMENDATION_CACHE}.tmp" "${RECOMMENDATION_CACHE}"

    log_success "Usage tracked"
}

# Get recommendation statistics
get_recommendation_stats() {
    initialize_cache

    log_info "Recommendation Statistics:"
    echo ""

    jq -r '
    .usage_stats | to_entries |
    map({
        id: .key,
        used: .value.used_count,
        success: .value.success_count,
        failure: .value.failure_count,
        rate: (if .value.used_count > 0 then
                (.value.success_count / .value.used_count * 100 | floor)
               else 0 end)
    }) |
    sort_by(-.used) |
    map("  " + .id + ": " + (.used | tostring) + " uses, " +
        (.rate | tostring) + "% success") |
    join("\n")
    ' "${RECOMMENDATION_CACHE}"

    echo ""
}

# Main command dispatcher
main() {
    case "${1:-help}" in
        recommend)
            recommend_solutions "${2:-}" "${3:-10}"
            ;;
        by-context)
            recommend_by_context "${2:-}" "${3:-}" "${4:-[]}" "${5:-10}"
            ;;
        similar)
            recommend_similar_to "${2:-}" "${3:-5}"
            ;;
        explain)
            explain_recommendation "${2:-}" "${3:-}"
            ;;
        path)
            get_recommendation_path "${2:-}"
            ;;
        track)
            track_usage "${2:-}" "${3:-used}"
            ;;
        stats)
            get_recommendation_stats
            ;;
        *)
            cat <<EOF
Usage: $0 {recommend|by-context|similar|explain|path|track|stats}

Commands:
  recommend <problem_desc> [top_k]
      Find solutions for a problem description

  by-context <domain> <language> [tags_json] [top_k]
      Find solutions by context

  similar <knowledge_id> [top_k]
      Find solutions similar to a given entry

  explain <knowledge_id> <query>
      Explain why a recommendation was made

  path <knowledge_id>
      Show knowledge lineage (predecessors/successors)

  track <knowledge_id> <outcome>
      Track usage (outcome: used|success|failure)

  stats
      Show recommendation statistics

Examples:
  $0 recommend "implement authentication" 5
  $0 by-context "backend" "nodejs" '["auth","security"]' 10
  $0 similar "k_auth_basic_20260115" 5
  $0 explain "k_auth_oauth_20260201" "need social login"
  $0 track "k_websocket_realtime_20260205" success
EOF
            exit 1
            ;;
    esac
}

# Run main
main "$@"
