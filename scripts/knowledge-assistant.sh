#!/usr/bin/env bash

# knowledge-assistant.sh
# Unified CLI for all knowledge operations
# Part of Cross-Session Knowledge Synthesis Integration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"
KNOWLEDGE_DIR="${HOME}/.claude/knowledge"
SESSIONS_DIR="${HOME}/Desktop/multi-claude-sessions/sessions"
CONFIG_FILE="${DATA_DIR}/knowledge-assistant-config.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Configuration Management
# ============================================================================

# Initialize configuration
init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<EOF
{
  "auto_extract": true,
  "min_confidence": 0.5,
  "max_injected": 5,
  "realtime_capture": true,
  "pipeline_enabled": true
}
EOF
    fi
}

# Get config value
get_config() {
    local key="$1"
    jq -r ".$key" "$CONFIG_FILE" 2>/dev/null || echo ""
}

# Set config value
set_config() {
    local key="$1"
    local value="$2"

    local tmp_file=$(mktemp)
    jq --arg key "$key" --arg value "$value" '.[$key] = $value' "$CONFIG_FILE" > "$tmp_file" && mv "$tmp_file" "$CONFIG_FILE"

    echo -e "${GREEN}✓${NC} Configuration updated: $key = $value"
}

# ============================================================================
# Search & Discovery
# ============================================================================

# Search knowledge base
search_knowledge() {
    local query="$1"
    local limit="${2:-10}"

    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    if [[ ! -f "$knowledge_base" ]] || [[ ! -s "$knowledge_base" ]]; then
        echo -e "${YELLOW}No knowledge base found. Run 'knowledge-assistant pipeline full' first.${NC}"
        return 1
    fi

    echo -e "${BLUE}Searching for: \"$query\"${NC}\n"

    # Simple grep-based search
    local results=$(grep -i "$query" "$knowledge_base" 2>/dev/null || echo "")

    if [[ -z "$results" ]]; then
        echo -e "${YELLOW}No results found${NC}"
        return 0
    fi

    # Display results
    local count=0
    echo "$results" | while IFS= read -r entry && [[ $count -lt $limit ]]; do
        local id=$(echo "$entry" | jq -r '.id')
        local type=$(echo "$entry" | jq -r '.type')
        local problem=$(echo "$entry" | jq -r '.problem' | head -c 100)
        local confidence=$(echo "$entry" | jq -r '.confidence')
        local tags=$(echo "$entry" | jq -r '.tags | join(", ")')

        echo -e "${GREEN}[$type]${NC} $id"
        echo "  Problem: $problem..."
        echo "  Confidence: $confidence | Tags: $tags"
        echo ""

        ((count++))
    done

    echo -e "Showing $count results (limit: $limit)"
}

# Find solutions to a specific problem
solve_problem() {
    local problem="$1"
    local limit="${2:-5}"

    echo -e "${BLUE}Finding solutions for: \"$problem\"${NC}\n"

    # Use session-startup-hook search logic
    local context='{"technologies": [], "task_type": "general", "key_terms": []}'
    local results=$(bash "${SCRIPT_DIR}/session-startup-hook.sh" test "$problem" 2>/dev/null | jq -c '.[]' | head -n "$limit")

    if [[ -z "$results" ]]; then
        echo -e "${YELLOW}No solutions found${NC}"
        return 0
    fi

    # Display results
    local count=1
    echo "$results" | while IFS= read -r entry; do
        local id=$(echo "$entry" | jq -r '.id')
        local problem_text=$(echo "$entry" | jq -r '.problem' | head -c 150)
        local solution=$(echo "$entry" | jq -r '.solution' | head -c 200)
        local confidence=$(echo "$entry" | jq -r '.confidence')
        local relevance=$(echo "$entry" | jq -r '.relevance_score // 0')

        echo -e "${GREEN}$count. Solution (Confidence: $confidence, Relevance: $relevance)${NC}"
        echo "   Problem: $problem_text"
        echo "   Solution: $solution..."
        echo ""

        ((count++))
    done
}

# Show related knowledge
show_related() {
    local knowledge_id="$1"
    local limit="${2:-10}"

    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    if [[ ! -f "$knowledge_base" ]]; then
        echo -e "${YELLOW}No knowledge base found${NC}"
        return 1
    fi

    # Get the entry
    local entry=$(grep "$knowledge_id" "$knowledge_base" | head -1)

    if [[ -z "$entry" ]]; then
        echo -e "${YELLOW}Knowledge entry not found: $knowledge_id${NC}"
        return 1
    fi

    local tags=$(echo "$entry" | jq -r '.tags[]')
    local type=$(echo "$entry" | jq -r '.type')

    echo -e "${BLUE}Related knowledge for: $knowledge_id${NC}\n"

    # Find entries with similar tags
    local related=""
    for tag in $tags; do
        related+=$(grep -i "$tag" "$knowledge_base" | grep -v "$knowledge_id" || echo "")
        related+=$'\n'
    done

    # Display unique results
    local count=0
    echo "$related" | sort -u | while IFS= read -r rel_entry && [[ $count -lt $limit ]]; do
        [[ -z "$rel_entry" ]] && continue

        local rel_id=$(echo "$rel_entry" | jq -r '.id')
        local rel_type=$(echo "$rel_entry" | jq -r '.type')
        local rel_problem=$(echo "$rel_entry" | jq -r '.problem' | head -c 100)
        local rel_tags=$(echo "$rel_entry" | jq -r '.tags | join(", ")')

        echo -e "${GREEN}[$rel_type]${NC} $rel_id"
        echo "  $rel_problem..."
        echo "  Tags: $rel_tags"
        echo ""

        ((count++))
    done
}

# Show knowledge graph
show_graph() {
    local topic="${1:-all}"

    local graph_file="${KNOWLEDGE_DIR}/knowledge-graph.json"

    if [[ ! -f "$graph_file" ]]; then
        echo -e "${YELLOW}Knowledge graph not found. Run 'knowledge-assistant pipeline full' first.${NC}"
        return 1
    fi

    echo -e "${BLUE}Knowledge Graph${NC}"
    echo -e "${BLUE}===============${NC}\n"

    # Show nodes and edges
    local nodes=$(jq -r '.nodes | length' "$graph_file")
    local edges=$(jq -r '.edges | length' "$graph_file")

    echo "Nodes: $nodes"
    echo "Edges: $edges"
    echo ""

    if [[ "$topic" != "all" ]]; then
        echo "Filtering by topic: $topic"
        # Show nodes related to topic
        jq -r ".nodes[] | select(.tags[] | contains(\"$topic\")) | .id" "$graph_file"
    fi
}

# ============================================================================
# Management Operations
# ============================================================================

# Extract knowledge from session
extract_session() {
    local session_dir="$1"

    echo -e "${BLUE}Extracting knowledge from session: $(basename "$session_dir")${NC}\n"

    bash "${SCRIPT_DIR}/knowledge-extractor.sh" extract "$session_dir"

    echo -e "\n${GREEN}✓${NC} Extraction complete"
}

# Run pipeline
run_pipeline() {
    local mode="${1:-incremental}"

    echo -e "${BLUE}Running knowledge pipeline (mode: $mode)${NC}\n"

    bash "${SCRIPT_DIR}/knowledge-pipeline.sh" "$mode"

    echo -e "\n${GREEN}✓${NC} Pipeline complete"
}

# Show statistics
show_stats() {
    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    if [[ ! -f "$knowledge_base" ]]; then
        echo -e "${YELLOW}No knowledge base found${NC}"
        return 1
    fi

    echo -e "${BLUE}Knowledge Base Statistics${NC}"
    echo -e "${BLUE}=========================${NC}\n"

    bash "${SCRIPT_DIR}/knowledge-extractor.sh" stats "$knowledge_base"
}

# Export knowledge base
export_knowledge() {
    local output_file="${1:-${KNOWLEDGE_DIR}/knowledge-export-$(date +%Y%m%d-%H%M%S).json}"

    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    if [[ ! -f "$knowledge_base" ]]; then
        echo -e "${YELLOW}No knowledge base found${NC}"
        return 1
    fi

    echo -e "${BLUE}Exporting knowledge base...${NC}\n"

    # Convert JSONL to JSON array
    jq -s '.' "$knowledge_base" > "$output_file"

    echo -e "${GREEN}✓${NC} Exported to: $output_file"
}

# ============================================================================
# Analytics
# ============================================================================

# Show top knowledge entries
show_top_knowledge() {
    local limit="${1:-10}"

    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    if [[ ! -f "$knowledge_base" ]]; then
        echo -e "${YELLOW}No knowledge base found${NC}"
        return 1
    fi

    echo -e "${BLUE}Top $limit Knowledge Entries${NC}"
    echo -e "${BLUE}===========================${NC}\n"

    # Sort by confidence
    jq -s 'sort_by(.confidence) | reverse | .[:'"$limit"'] | .[] | "\(.confidence) - \(.type) - \(.id) - \(.problem[:80])"' "$knowledge_base" | while read -r line; do
        echo "  $line"
    done
}

# Show knowledge growth chart
show_growth_chart() {
    local days="${1:-7}"

    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    if [[ ! -f "$knowledge_base" ]]; then
        echo -e "${YELLOW}No knowledge base found${NC}"
        return 1
    fi

    echo -e "${BLUE}Knowledge Growth (Last $days Days)${NC}"
    echo -e "${BLUE}===================================${NC}\n"

    # Group by date
    for ((i = days - 1; i >= 0; i--)); do
        local date=$(date -d "$i days ago" +%Y-%m-%d 2>/dev/null || date -v -"${i}"d +%Y-%m-%d 2>/dev/null)
        local count=$(grep "\"$date" "$knowledge_base" | wc -l)

        # Simple bar chart
        local bar=""
        for ((j = 0; j < count; j++)); do
            bar+="█"
        done

        printf "%-12s %3d %s\n" "$date" "$count" "$bar"
    done
}

# Show recommendation effectiveness
show_recommendation_stats() {
    local injection_log="${DATA_DIR}/knowledge-injection-log.json"

    if [[ ! -f "$injection_log" ]]; then
        echo -e "${YELLOW}No injection log found${NC}"
        return 1
    fi

    echo -e "${BLUE}Recommendation Effectiveness${NC}"
    echo -e "${BLUE}============================${NC}\n"

    local total=$(jq '.injections | length' "$injection_log")
    local helpful=$(jq '[.injections[] | select(.was_helpful == true)] | length' "$injection_log")
    local not_helpful=$(jq '[.injections[] | select(.was_helpful == false)] | length' "$injection_log")
    local unknown=$(jq '[.injections[] | select(.was_helpful == null)] | length' "$injection_log")

    echo "Total recommendations: $total"
    echo "Helpful: $helpful"
    echo "Not helpful: $not_helpful"
    echo "Unknown: $unknown"

    if [[ $total -gt 0 ]] && [[ $helpful -gt 0 ]]; then
        local success_rate=$(echo "scale=1; $helpful * 100 / $total" | bc)
        echo ""
        echo "Success rate: ${success_rate}%"
    fi
}

# Show learning path for a domain
show_learning_path() {
    local domain="$1"

    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    if [[ ! -f "$knowledge_base" ]]; then
        echo -e "${YELLOW}No knowledge base found${NC}"
        return 1
    fi

    echo -e "${BLUE}Learning Path: $domain${NC}"
    echo -e "${BLUE}=======================${NC}\n"

    # Find all entries for domain, sorted by timestamp
    jq -s "sort_by(.timestamp) | .[] | select(.domain == \"$domain\" or (.tags | contains([\"$domain\"]))) | \"\(.timestamp[:10]) - \(.type) - \(.problem[:80])\"" "$knowledge_base" | while read -r line; do
        echo "  $line"
    done
}

# ============================================================================
# Configuration
# ============================================================================

# Show/update configuration
manage_config() {
    local action="${1:-show}"
    local key="${2:-}"
    local value="${3:-}"

    init_config

    case "$action" in
        show)
            echo -e "${BLUE}Knowledge Assistant Configuration${NC}"
            echo -e "${BLUE}===================================${NC}\n"
            jq . "$CONFIG_FILE"
            ;;

        set)
            if [[ -z "$key" ]] || [[ -z "$value" ]]; then
                echo "Usage: knowledge-assistant config set <key> <value>"
                return 1
            fi
            set_config "$key" "$value"
            ;;

        get)
            if [[ -z "$key" ]]; then
                echo "Usage: knowledge-assistant config get <key>"
                return 1
            fi
            get_config "$key"
            ;;

        *)
            echo "Unknown config action: $action"
            return 1
            ;;
    esac
}

# ============================================================================
# CLI Interface
# ============================================================================

show_usage() {
    cat <<EOF
${CYAN}Knowledge Assistant${NC} - Unified CLI for knowledge operations

${BLUE}SEARCH & DISCOVERY:${NC}
  search <query> [limit]              Search knowledge base
  solve <problem> [limit]             Find solutions to problem
  related <knowledge_id> [limit]      Show related knowledge
  graph [topic]                       Show knowledge graph

${BLUE}MANAGEMENT:${NC}
  extract <session_dir>               Extract from session
  pipeline <full|incremental>         Run knowledge pipeline
  stats                               Show statistics
  export [output_file]                Export knowledge base

${BLUE}ANALYTICS:${NC}
  top-knowledge [limit]               Most useful knowledge
  growth-chart [days]                 Knowledge growth over time
  recommendation-stats                Recommendation effectiveness
  learning-path <domain>              Learning paths

${BLUE}CONFIGURATION:${NC}
  config show                         Show configuration
  config set <key> <value>            Set config value
  config get <key>                    Get config value

${BLUE}EXAMPLES:${NC}
  knowledge-assistant search "authentication"
  knowledge-assistant solve "session timeout"
  knowledge-assistant pipeline incremental
  knowledge-assistant top-knowledge 10
  knowledge-assistant config set auto_extract true

${BLUE}CONFIG OPTIONS:${NC}
  auto_extract       Auto-extract from sessions (true/false)
  min_confidence     Minimum confidence threshold (0.0-1.0)
  max_injected       Max recommendations to inject (number)
  realtime_capture   Enable real-time capture (true/false)
  pipeline_enabled   Enable pipeline (true/false)
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        # Search & Discovery
        search)
            search_knowledge "$@"
            ;;

        solve)
            solve_problem "$@"
            ;;

        related)
            show_related "$@"
            ;;

        graph)
            show_graph "$@"
            ;;

        # Management
        extract)
            extract_session "$@"
            ;;

        pipeline)
            run_pipeline "$@"
            ;;

        stats)
            show_stats
            ;;

        export)
            export_knowledge "$@"
            ;;

        # Analytics
        top-knowledge)
            show_top_knowledge "$@"
            ;;

        growth-chart)
            show_growth_chart "$@"
            ;;

        recommendation-stats)
            show_recommendation_stats
            ;;

        learning-path)
            show_learning_path "$@"
            ;;

        # Configuration
        config)
            manage_config "$@"
            ;;

        # Help
        help|--help|-h)
            show_usage
            ;;

        *)
            echo -e "${RED}Unknown command: $command${NC}"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
