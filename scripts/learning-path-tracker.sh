#!/usr/bin/env bash
# learning-path-tracker.sh - Track how knowledge evolved over time
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWLEDGE_DIR="${HOME}/.claude/knowledge"
GRAPH_FILE="${KNOWLEDGE_DIR}/knowledge-graph.json"
LEARNING_PATHS="${KNOWLEDGE_DIR}/learning-paths.json"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Initialize learning paths storage
initialize_paths() {
    if [[ ! -f "${LEARNING_PATHS}" ]]; then
        cat > "${LEARNING_PATHS}" <<'EOF'
{
  "version": "1.0.0",
  "paths": {},
  "milestones": [],
  "expertise_levels": {}
}
EOF
    fi
}

# Get learning path for a domain
get_learning_path() {
    local domain="$1"

    log_info "Generating learning path for: $domain"

    if [[ ! -f "${GRAPH_FILE}" ]]; then
        log_error "Knowledge graph not found."
        echo '{"error": "Graph not found"}'
        return 1
    fi

    # Find all nodes related to domain
    local nodes=$(jq --arg domain "$domain" -c \
        '.nodes[] | select(.tags[]? | contains($domain))' \
        "${GRAPH_FILE}" 2>/dev/null || echo "")

    if [[ -z "$nodes" ]]; then
        log_warn "No knowledge found for domain: $domain"
        echo "{\"domain\": \"$domain\", \"path\": []}"
        return 0
    fi

    # Collect nodes into array
    local node_array=()
    while IFS= read -r node; do
        [[ -n "$node" ]] && node_array+=("$node")
    done <<< "$nodes"

    # Sort by timestamp
    local sorted=$(printf '%s\n' "${node_array[@]}" | \
        jq -s 'sort_by(.created // .metadata.timestamp // "")')

    # Build path with relationships
    local path_entries=()
    local idx=0

    echo "$sorted" | jq -c '.[]' | while read -r node; do
        local node_id=$(echo "$node" | jq -r '.id')
        local created=$(echo "$node" | jq -r '.created // .metadata.timestamp // ""')
        local problem=$(echo "$node" | jq -r '.metadata.problem // "Unknown problem"')
        local solution=$(echo "$node" | jq -r '.metadata.solution // "Unknown solution"')
        local confidence=$(echo "$node" | jq -r '.confidence // 0.5')

        # Find relationships
        local builds_on=$(jq --arg id "$node_id" -r \
            '[.edges[] | select(.to == $id and .type == "builds-on") | .from] | join(", ")' \
            "${GRAPH_FILE}")

        local extended_by=$(jq --arg id "$node_id" -r \
            '[.edges[] | select(.from == $id and .type == "builds-on") | .to] | join(", ")' \
            "${GRAPH_FILE}")

        # Create entry
        jq -n \
            --argjson idx "$idx" \
            --arg id "$node_id" \
            --arg date "$created" \
            --arg problem "$problem" \
            --arg solution "$solution" \
            --argjson conf "$confidence" \
            --arg builds "$builds_on" \
            --arg extended "$extended_by" \
            '{
                step: $idx,
                knowledge_id: $id,
                date: $date,
                problem: $problem,
                solution: $solution,
                confidence: $conf,
                builds_on: (if $builds == "" then [] else [$builds] end),
                extended_by: (if $extended == "" then [] else [$extended] end)
            }'

        ((idx++))
    done | jq -s \
        --arg domain "$domain" \
        '{
            domain: $domain,
            path: .,
            total_steps: length,
            generated_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }'
}

# Get knowledge timeline (all domains)
get_knowledge_timeline() {
    log_info "Generating knowledge timeline..."

    if [[ ! -f "${GRAPH_FILE}" ]]; then
        log_error "Knowledge graph not found."
        echo '{"error": "Graph not found"}'
        return 1
    fi

    # Get all nodes sorted by timestamp
    jq '.nodes | sort_by(.created // .metadata.timestamp // "") |
        map({
            id: .id,
            date: (.created // .metadata.timestamp // ""),
            type: .type,
            tags: .tags,
            confidence: (.confidence // 0.5),
            problem: (.metadata.problem // ""),
            solution: (.metadata.solution // "")
        }) |
        {
            timeline: .,
            total_entries: length,
            date_range: {
                earliest: .[0].date,
                latest: .[-1].date
            },
            generated_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }' "${GRAPH_FILE}"
}

# Track expertise growth in a domain
track_expertise_growth() {
    local domain="$1"

    log_info "Tracking expertise growth: $domain"

    if [[ ! -f "${GRAPH_FILE}" ]]; then
        log_error "Knowledge graph not found."
        echo '{"error": "Graph not found"}'
        return 1
    fi

    # Get all nodes for domain
    local nodes=$(jq --arg domain "$domain" \
        '[.nodes[] | select(.tags[]? | contains($domain))] |
         sort_by(.created // .metadata.timestamp // "")' \
        "${GRAPH_FILE}" 2>/dev/null || echo "[]")

    local count=$(echo "$nodes" | jq 'length')

    if [[ $count -eq 0 ]]; then
        log_warn "No knowledge found for domain: $domain"
        echo "{\"domain\": \"$domain\", \"expertise_level\": \"none\", \"count\": 0}"
        return 0
    fi

    # Calculate average confidence
    local avg_confidence=$(echo "$nodes" | jq '[.[].confidence // 0.5] | add / length')

    # Count relationships
    local total_relationships=$(jq --arg domain "$domain" \
        '[.nodes[] | select(.tags[]? | contains($domain)) | .id] as $ids |
         [.edges[] | select(.from as $f | $ids | index($f))] | length' \
        "${GRAPH_FILE}")

    # Determine expertise level
    # Novice: 1-5 entries, <0.60 confidence
    # Beginner: 5-10 entries, 0.60-0.70 confidence
    # Intermediate: 10-20 entries, 0.70-0.80 confidence
    # Advanced: 20-50 entries, 0.80-0.90 confidence
    # Expert: 50+ entries, 0.90+ confidence

    local expertise_level="novice"
    local expertise_score=1

    if [[ $count -ge 50 ]] && (( $(echo "$avg_confidence >= 0.90" | bc -l) )); then
        expertise_level="expert"
        expertise_score=5
    elif [[ $count -ge 20 ]] && (( $(echo "$avg_confidence >= 0.80" | bc -l) )); then
        expertise_level="advanced"
        expertise_score=4
    elif [[ $count -ge 10 ]] && (( $(echo "$avg_confidence >= 0.70" | bc -l) )); then
        expertise_level="intermediate"
        expertise_score=3
    elif [[ $count -ge 5 ]] && (( $(echo "$avg_confidence >= 0.60" | bc -l) )); then
        expertise_level="beginner"
        expertise_score=2
    fi

    jq -n \
        --arg domain "$domain" \
        --argjson count "$count" \
        --argjson conf "$avg_confidence" \
        --argjson rels "$total_relationships" \
        --arg level "$expertise_level" \
        --argjson score "$expertise_score" \
        '{
            domain: $domain,
            expertise_level: $level,
            expertise_score: $score,
            metrics: {
                knowledge_entries: $count,
                average_confidence: $conf,
                total_relationships: $rels,
                knowledge_density: ($rels / $count)
            },
            interpretation: (
                if $level == "expert" then "Deep expertise, comprehensive knowledge"
                elif $level == "advanced" then "Strong understanding, can solve complex problems"
                elif $level == "intermediate" then "Good foundation, can handle common scenarios"
                elif $level == "beginner" then "Basic understanding, learning in progress"
                else "Limited experience, just starting" end
            )
        }'
}

# Identify learning milestones
identify_milestones() {
    log_info "Identifying learning milestones..."

    if [[ ! -f "${GRAPH_FILE}" ]]; then
        log_error "Knowledge graph not found."
        echo '{"error": "Graph not found"}'
        return 1
    fi

    # Milestones are:
    # 1. First knowledge entry in a domain
    # 2. High-confidence solutions (>0.90)
    # 3. Knowledge that many others build upon
    # 4. Major paradigm shifts (replaces relationships)

    local milestones=()

    # Find first entry in each domain
    local domains=$(jq -r '[.nodes[].tags[]] | unique[]' "${GRAPH_FILE}" 2>/dev/null || echo "")

    while IFS= read -r domain; do
        [[ -z "$domain" ]] && continue

        local first_entry=$(jq --arg d "$domain" -c \
            '[.nodes[] | select(.tags[]? == $d)] |
             sort_by(.created // .metadata.timestamp // "") | .[0]' \
            "${GRAPH_FILE}")

        if [[ "$first_entry" != "null" && -n "$first_entry" ]]; then
            local entry_id=$(echo "$first_entry" | jq -r '.id')
            local entry_date=$(echo "$first_entry" | jq -r '.created // .metadata.timestamp // ""')

            milestones+=($(jq -n \
                --arg id "$entry_id" \
                --arg type "first_in_domain" \
                --arg domain "$domain" \
                --arg date "$entry_date" \
                '{
                    type: $type,
                    knowledge_id: $id,
                    domain: $domain,
                    date: $date,
                    description: "First learning in " + $domain
                }'))
        fi
    done <<< "$domains"

    # Find high-confidence solutions
    jq -c '.nodes[] | select(.confidence >= 0.90)' "${GRAPH_FILE}" | while read -r node; do
        local node_id=$(echo "$node" | jq -r '.id')
        local node_date=$(echo "$node" | jq -r '.created // .metadata.timestamp // ""')
        local problem=$(echo "$node" | jq -r '.metadata.problem // "Unknown"')

        milestones+=($(jq -n \
            --arg id "$node_id" \
            --arg type "high_confidence" \
            --arg date "$node_date" \
            --arg problem "$problem" \
            '{
                type: $type,
                knowledge_id: $id,
                date: $date,
                description: "High-confidence solution: " + $problem
            }'))
    done

    # Find highly-referenced knowledge (foundation nodes)
    jq -r '.nodes[].id' "${GRAPH_FILE}" | while read -r node_id; do
        local ref_count=$(jq --arg id "$node_id" \
            '[.edges[] | select(.from == $id and .type == "builds-on")] | length' \
            "${GRAPH_FILE}")

        if [[ $ref_count -ge 3 ]]; then
            local node=$(jq --arg id "$node_id" '.nodes[] | select(.id == $id)' "${GRAPH_FILE}")
            local node_date=$(echo "$node" | jq -r '.created // .metadata.timestamp // ""')
            local problem=$(echo "$node" | jq -r '.metadata.problem // "Unknown"')

            milestones+=($(jq -n \
                --arg id "$node_id" \
                --arg type "foundation" \
                --arg date "$node_date" \
                --arg problem "$problem" \
                --argjson refs "$ref_count" \
                '{
                    type: $type,
                    knowledge_id: $id,
                    date: $date,
                    description: "Foundation knowledge (" + ($refs|tostring) + " solutions built on this): " + $problem
                }'))
        fi
    done

    # Sort milestones by date
    printf '%s\n' "${milestones[@]}" | jq -s 'sort_by(.date) |
        {
            milestones: .,
            total_count: length,
            generated_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }'
}

# Generate learning report
generate_learning_report() {
    log_info "Generating comprehensive learning report..."

    local timeline=$(get_knowledge_timeline)
    local milestones=$(identify_milestones)

    # Get all domains
    local domains=$(jq -r '[.nodes[].tags[]] | unique[]' "${GRAPH_FILE}" 2>/dev/null || echo "")

    local domain_expertise=()
    while IFS= read -r domain; do
        [[ -z "$domain" ]] && continue
        local expertise=$(track_expertise_growth "$domain")
        domain_expertise+=("$expertise")
    done <<< "$domains"

    # Combine into report
    jq -n \
        --argjson timeline "$timeline" \
        --argjson milestones "$milestones" \
        --argjson expertise "$(printf '%s\n' "${domain_expertise[@]}" | jq -s .)" \
        '{
            report_type: "comprehensive_learning",
            generated_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
            timeline: $timeline,
            milestones: $milestones,
            expertise_by_domain: $expertise,
            summary: {
                total_knowledge_entries: $timeline.total_entries,
                total_milestones: $milestones.total_count,
                domains_covered: ($expertise | length),
                date_range: $timeline.date_range
            }
        }'
}

# Visualize learning path (ASCII art)
visualize_learning_path() {
    local domain="$1"

    log_info "Visualizing learning path: $domain"

    local path=$(get_learning_path "$domain")

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Learning Path: $domain${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local count=$(echo "$path" | jq -r '.path | length')

    if [[ $count -eq 0 ]]; then
        echo "No learning path found for: $domain"
        return
    fi

    echo "$path" | jq -r '.path[] |
        .date[:10] + ": " + .problem,
        "  ├─ Confidence: " + (.confidence * 100 | floor | tostring) + "%",
        "  └─ Solution: " + .solution,
        ""'

    # Show expertise level
    local expertise=$(track_expertise_growth "$domain")
    local level=$(echo "$expertise" | jq -r '.expertise_level')
    local score=$(echo "$expertise" | jq -r '.expertise_score')

    echo ""
    echo -e "${GREEN}Expertise Level: $level ($score/5)${NC}"
    echo "Total Learning Steps: $count"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Main command dispatcher
main() {
    initialize_paths

    case "${1:-help}" in
        path)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 path <domain>"
                exit 1
            fi
            get_learning_path "$2"
            ;;
        timeline)
            get_knowledge_timeline
            ;;
        expertise)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 expertise <domain>"
                exit 1
            fi
            track_expertise_growth "$2"
            ;;
        milestones)
            identify_milestones
            ;;
        report)
            generate_learning_report
            ;;
        visualize)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 visualize <domain>"
                exit 1
            fi
            visualize_learning_path "$2"
            ;;
        *)
            cat <<EOF
Usage: $0 {path|timeline|expertise|milestones|report|visualize}

Commands:
  path <domain>
      Get learning path for a specific domain

  timeline
      Get chronological timeline of all knowledge

  expertise <domain>
      Track expertise growth in a domain

  milestones
      Identify key learning milestones

  report
      Generate comprehensive learning report

  visualize <domain>
      Visualize learning path (ASCII art)

Examples:
  $0 path "authentication"
  $0 timeline
  $0 expertise "nodejs"
  $0 milestones
  $0 report
  $0 visualize "authentication"
EOF
            exit 1
            ;;
    esac
}

# Run main
main "$@"
