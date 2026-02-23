#!/usr/bin/env bash

# knowledge-dashboard.sh
# Interactive terminal dashboard for knowledge system
# Part of Cross-Session Knowledge Synthesis Integration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${HOME}/.claude/data"
KNOWLEDGE_DIR="${HOME}/.claude/knowledge"
SESSIONS_DIR="${HOME}/Desktop/multi-claude-sessions/sessions"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# ============================================================================
# Data Collection
# ============================================================================

# Get knowledge base stats
get_kb_stats() {
    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    if [[ ! -f "$knowledge_base" ]] || [[ ! -s "$knowledge_base" ]]; then
        echo '{"total": 0, "by_type": [], "by_domain": [], "avg_confidence": 0}'
        return 0
    fi

    local total=$(wc -l < "$knowledge_base")
    local avg_confidence=$(jq -s 'map(.confidence) | add / length' "$knowledge_base" 2>/dev/null || echo "0")

    # By type
    local by_type=$(jq -s 'group_by(.type) | map({type: .[0].type, count: length}) | sort_by(.count) | reverse' "$knowledge_base" 2>/dev/null || echo "[]")

    # By domain
    local by_domain=$(jq -s 'group_by(.domain) | map({domain: .[0].domain, count: length}) | sort_by(.count) | reverse' "$knowledge_base" 2>/dev/null || echo "[]")

    cat <<EOF
{
  "total": $total,
  "by_type": $by_type,
  "by_domain": $by_domain,
  "avg_confidence": $avg_confidence
}
EOF
}

# Get pipeline stats
get_pipeline_stats() {
    local state_file="${DATA_DIR}/knowledge-pipeline-state.json"

    if [[ ! -f "$state_file" ]]; then
        echo '{"last_run": {"timestamp": null, "mode": null}, "statistics": {"total_runs": 0}}'
        return 0
    fi

    jq '{last_run, statistics}' "$state_file"
}

# Get injection stats
get_injection_stats() {
    local injection_log="${DATA_DIR}/knowledge-injection-log.json"

    if [[ ! -f "$injection_log" ]]; then
        echo '{"total": 0, "today": 0, "week": 0, "helpful": 0, "success_rate": 0}'
        return 0
    fi

    local total=$(jq '.injections | length' "$injection_log")
    local helpful=$(jq '[.injections[] | select(.was_helpful == true)] | length' "$injection_log")

    local success_rate=0
    if [[ $total -gt 0 ]] && [[ $helpful -gt 0 ]]; then
        success_rate=$(echo "scale=1; $helpful * 100 / $total" | bc)
    fi

    # Today
    local today=$(date +%Y-%m-%d)
    local today_count=$(jq --arg date "$today" '[.injections[] | select(.timestamp | startswith($date))] | length' "$injection_log")

    # Week
    local week_ago=$(date -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -v -7d +%Y-%m-%d 2>/dev/null)
    local week_count=$(jq --arg date "$week_ago" '[.injections[] | select(.timestamp >= $date)] | length' "$injection_log")

    cat <<EOF
{
  "total": $total,
  "today": $today_count,
  "week": $week_count,
  "helpful": $helpful,
  "success_rate": $success_rate
}
EOF
}

# Get growth data
get_growth_data() {
    local days="${1:-7}"
    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    if [[ ! -f "$knowledge_base" ]]; then
        echo "[]"
        return 0
    fi

    local growth_data="["

    for ((i = days - 1; i >= 0; i--)); do
        local date=$(date -d "$i days ago" +%Y-%m-%d 2>/dev/null || date -v -"${i}"d +%Y-%m-%d 2>/dev/null)
        local count=$(grep "\"$date" "$knowledge_base" 2>/dev/null | wc -l || echo "0")

        growth_data+="{\"date\": \"$date\", \"count\": $count}"
        if [[ $i -gt 0 ]]; then
            growth_data+=","
        fi
    done

    growth_data+="]"
    echo "$growth_data"
}

# ============================================================================
# Dashboard Sections
# ============================================================================

# Section: Overview
show_overview() {
    local kb_stats=$(get_kb_stats)
    local pipeline_stats=$(get_pipeline_stats)

    local total=$(echo "$kb_stats" | jq -r '.total')
    local avg_confidence=$(echo "$kb_stats" | jq -r '.avg_confidence')
    local last_run=$(echo "$pipeline_stats" | jq -r '.last_run.timestamp // "Never"')
    local total_runs=$(echo "$pipeline_stats" | jq -r '.statistics.total_runs')

    # Format last run time
    if [[ "$last_run" != "Never" ]]; then
        last_run=$(date -d "$last_run" '+%Y-%m-%d %H:%M' 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_run" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$last_run")
    fi

    cat <<EOF
${CYAN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}
${CYAN}┃${NC}             ${WHITE}CLAUDE KNOWLEDGE SYNTHESIS DASHBOARD${NC}              ${CYAN}┃${NC}
${CYAN}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}
${CYAN}┃${NC} ${BLUE}Overview${NC}                                 Last Update: $(date '+%H:%M')  ${CYAN}┃${NC}
${CYAN}┃${NC} ────────────────────────────────────────────────────────────── ${CYAN}┃${NC}
${CYAN}┃${NC} Total Knowledge:        ${WHITE}$total${NC} entries     Pipeline Runs: ${WHITE}$total_runs${NC}     ${CYAN}┃${NC}
${CYAN}┃${NC} Avg Confidence:         ${WHITE}$(printf '%.2f' "$avg_confidence")${NC}          Last Run: ${WHITE}$last_run${NC}${CYAN}┃${NC}
${CYAN}┃${NC} ────────────────────────────────────────────────────────────── ${CYAN}┃${NC}
EOF
}

# Section: Growth Chart
show_growth_chart() {
    local days="${1:-7}"
    local growth_data=$(get_growth_data "$days")

    echo -e "${CYAN}┃${NC} ${BLUE}Knowledge Growth (Last $days Days)${NC}                                 ${CYAN}┃${NC}"
    echo -e "${CYAN}┃${NC}                                                                 ${CYAN}┃${NC}"

    # Find max for scaling
    local max=$(echo "$growth_data" | jq '[.[].count] | max')
    if [[ "$max" == "null" ]] || [[ $max -eq 0 ]]; then
        max=1
    fi

    # Chart height
    local chart_height=7
    local chart_width=50

    # Draw chart
    for ((row = chart_height; row >= 0; row--)); do
        local y_value=$(echo "scale=0; $max * $row / $chart_height" | bc)

        printf "${CYAN}┃${NC} %3d│" "$y_value"

        # Plot points
        for ((day = 0; day < days; day++)); do
            local count=$(echo "$growth_data" | jq -r ".[$day].count")
            local point_height=$(echo "scale=0; $count * $chart_height / $max" | bc)

            if [[ $row -le $point_height ]]; then
                printf "${GREEN}█${NC}"
            else
                printf " "
            fi
        done

        printf "                                              ${CYAN}┃${NC}\n"
    done

    # X-axis
    printf "${CYAN}┃${NC}    └"
    for ((i = 0; i < days; i++)); do
        printf "─"
    done
    printf "────────────────────────────────────────────────── ${CYAN}┃${NC}\n"

    # Date labels
    printf "${CYAN}┃${NC}     "
    for ((i = days - 1; i >= 0; i--)); do
        if [[ $((i % 2)) -eq 0 ]]; then
            local date=$(date -d "$i days ago" +%d 2>/dev/null || date -v -"${i}"d +%d 2>/dev/null)
            printf " %s" "$date"
        fi
    done
    printf "                                                 ${CYAN}┃${NC}\n"
    echo -e "${CYAN}┃${NC} ────────────────────────────────────────────────────────────── ${CYAN}┃${NC}"
}

# Section: Top Domains and Recommendations
show_domains_and_recommendations() {
    local kb_stats=$(get_kb_stats)
    local injection_stats=$(get_injection_stats)

    local domains=$(echo "$kb_stats" | jq -r '.by_domain | .[:4] | .[] | "\(.domain):\(.count)"')
    local inj_today=$(echo "$injection_stats" | jq -r '.today')
    local inj_helpful=$(echo "$injection_stats" | jq -r '.helpful')
    local inj_total=$(echo "$injection_stats" | jq -r '.total')
    local success_rate=$(echo "$injection_stats" | jq -r '.success_rate')

    cat <<EOF
${CYAN}┃${NC} ${BLUE}Top Domains${NC}                    | ${BLUE}Recommendations Today${NC}         ${CYAN}┃${NC}
EOF

    local domain_lines=()
    while IFS= read -r line; do
        domain_lines+=("$line")
    done <<< "$domains"

    local max_lines=4
    for ((i = 0; i < max_lines; i++)); do
        local domain_line=""
        if [[ $i -lt ${#domain_lines[@]} ]]; then
            local domain=$(echo "${domain_lines[$i]}" | cut -d: -f1)
            local count=$(echo "${domain_lines[$i]}" | cut -d: -f2)
            domain_line=$(printf "  %-15s %3d entries" "$domain:" "$count")
        else
            domain_line="                             "
        fi

        local rec_line=""
        case $i in
            0) rec_line=$(printf "  Made:       %3d" "$inj_today") ;;
            1) rec_line=$(printf "  Helpful:    %3d (%s%%)" "$inj_helpful" "$success_rate") ;;
            2) rec_line=$(printf "  Total:      %3d" "$inj_total") ;;
            3) rec_line="                     " ;;
        esac

        printf "${CYAN}┃${NC} %-30s | %-30s${CYAN}┃${NC}\n" "$domain_line" "$rec_line"
    done

    echo -e "${CYAN}┃${NC} ────────────────────────────────────────────────────────────── ${CYAN}┃${NC}"
}

# Section: Recent Knowledge
show_recent_knowledge() {
    local limit="${1:-5}"
    local knowledge_base="${KNOWLEDGE_DIR}/knowledge-base.jsonl"

    echo -e "${CYAN}┃${NC} ${BLUE}Recent Knowledge (Last $limit)${NC}                                      ${CYAN}┃${NC}"

    if [[ ! -f "$knowledge_base" ]] || [[ ! -s "$knowledge_base" ]]; then
        echo -e "${CYAN}┃${NC}  ${YELLOW}No knowledge found${NC}                                              ${CYAN}┃${NC}"
        echo -e "${CYAN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
        return 0
    fi

    # Get last N entries
    local recent=$(tail -n "$limit" "$knowledge_base")

    local index=1
    echo "$recent" | while IFS= read -r entry; do
        local problem=$(echo "$entry" | jq -r '.problem' | head -c 40)
        local type=$(echo "$entry" | jq -r '.type')
        local tags=$(echo "$entry" | jq -r '.tags | .[:3] | join(", ")')
        local confidence=$(echo "$entry" | jq -r '.confidence')

        printf "${CYAN}┃${NC}  ${GREEN}%d.${NC} %-40s  ${CYAN}┃${NC}\n" "$index" "$problem..."
        printf "${CYAN}┃${NC}     ${BLUE}[$type]${NC}  Tags: %-30s Conf: %.2f  ${CYAN}┃${NC}\n" "$tags" "$confidence"

        ((index++))
    done

    echo -e "${CYAN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

# Section: Key Controls
show_controls() {
    cat <<EOF

${CYAN}[R]${NC}efresh  ${CYAN}[S]${NC}earch  ${CYAN}[G]${NC}raph  ${CYAN}[T]${NC}op  ${CYAN}[E]${NC}xport  ${CYAN}[Q]${NC}uit
EOF
}

# ============================================================================
# Full Dashboard
# ============================================================================

# Show complete dashboard
show_dashboard() {
    clear

    show_overview
    show_growth_chart 7
    show_domains_and_recommendations
    show_recent_knowledge 5
    show_controls
}

# Show specific section
show_section() {
    local section="$1"

    case "$section" in
        overview)
            show_overview
            ;;

        growth)
            show_growth_chart 7
            ;;

        domains)
            show_domains_and_recommendations
            ;;

        recent)
            show_recent_knowledge 5
            ;;

        *)
            echo "Unknown section: $section"
            return 1
            ;;
    esac
}

# Refresh dashboard (live updates)
refresh_dashboard() {
    local interval="${1:-5}" # seconds

    while true; do
        show_dashboard
        sleep "$interval"
    done
}

# Export dashboard to HTML
export_dashboard_html() {
    local output_file="${1:-${KNOWLEDGE_DIR}/dashboard-$(date +%Y%m%d-%H%M%S).html}"

    local kb_stats=$(get_kb_stats)
    local pipeline_stats=$(get_pipeline_stats)
    local injection_stats=$(get_injection_stats)
    local growth_data=$(get_growth_data 30)

    cat > "$output_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Claude Knowledge Dashboard</title>
    <style>
        body {
            font-family: 'Monaco', 'Courier New', monospace;
            background: #1e1e1e;
            color: #d4d4d4;
            padding: 20px;
        }
        .dashboard {
            max-width: 1200px;
            margin: 0 auto;
        }
        .section {
            background: #252526;
            border: 1px solid #3e3e42;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
        }
        h1 {
            color: #4ec9b0;
            text-align: center;
        }
        h2 {
            color: #569cd6;
            border-bottom: 2px solid #3e3e42;
            padding-bottom: 10px;
        }
        .stat {
            display: inline-block;
            margin: 10px 20px;
        }
        .stat-label {
            color: #9cdcfe;
        }
        .stat-value {
            color: #ce9178;
            font-size: 1.5em;
            font-weight: bold;
        }
        .chart {
            margin: 20px 0;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th, td {
            padding: 10px;
            text-align: left;
            border-bottom: 1px solid #3e3e42;
        }
        th {
            color: #4ec9b0;
        }
    </style>
</head>
<body>
    <div class="dashboard">
        <h1>Claude Knowledge Synthesis Dashboard</h1>

        <div class="section">
            <h2>Overview</h2>
            <div class="stat">
                <div class="stat-label">Total Knowledge</div>
                <div class="stat-value">$(echo "$kb_stats" | jq -r '.total')</div>
            </div>
            <div class="stat">
                <div class="stat-label">Avg Confidence</div>
                <div class="stat-value">$(echo "$kb_stats" | jq -r '.avg_confidence')</div>
            </div>
            <div class="stat">
                <div class="stat-label">Pipeline Runs</div>
                <div class="stat-value">$(echo "$pipeline_stats" | jq -r '.statistics.total_runs')</div>
            </div>
            <div class="stat">
                <div class="stat-label">Success Rate</div>
                <div class="stat-value">$(echo "$injection_stats" | jq -r '.success_rate')%</div>
            </div>
        </div>

        <div class="section">
            <h2>Knowledge by Domain</h2>
            <table>
                <tr><th>Domain</th><th>Count</th></tr>
$(echo "$kb_stats" | jq -r '.by_domain[] | "<tr><td>\(.domain)</td><td>\(.count)</td></tr>"')
            </table>
        </div>

        <div class="section">
            <h2>Growth (Last 30 Days)</h2>
            <canvas id="growthChart" width="800" height="400"></canvas>
        </div>

        <div class="section">
            <p>Generated: $(date)</p>
        </div>
    </div>

    <script>
        // Simple chart rendering (placeholder)
        const growthData = $growth_data;
        console.log('Growth data:', growthData);
    </script>
</body>
</html>
EOF

    echo -e "${GREEN}✓${NC} Dashboard exported to: $output_file"
}

# ============================================================================
# Interactive Mode
# ============================================================================

# Interactive dashboard with key handling
interactive_dashboard() {
    show_dashboard

    while true; do
        read -n 1 -s key

        case "$key" in
            r|R)
                show_dashboard
                ;;

            s|S)
                clear
                echo -e "${BLUE}Search Knowledge${NC}"
                echo -n "Query: "
                read query
                bash "${SCRIPT_DIR}/knowledge-assistant.sh" search "$query"
                echo ""
                echo "Press any key to return to dashboard..."
                read -n 1 -s
                show_dashboard
                ;;

            g|G)
                clear
                bash "${SCRIPT_DIR}/knowledge-assistant.sh" graph
                echo ""
                echo "Press any key to return to dashboard..."
                read -n 1 -s
                show_dashboard
                ;;

            t|T)
                clear
                bash "${SCRIPT_DIR}/knowledge-assistant.sh" top-knowledge 20
                echo ""
                echo "Press any key to return to dashboard..."
                read -n 1 -s
                show_dashboard
                ;;

            e|E)
                clear
                export_dashboard_html
                echo ""
                echo "Press any key to return to dashboard..."
                read -n 1 -s
                show_dashboard
                ;;

            q|Q)
                clear
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
        esac
    done
}

# ============================================================================
# CLI Interface
# ============================================================================

show_usage() {
    cat <<EOF
Knowledge Dashboard - Interactive terminal dashboard

Usage: $(basename "$0") <command>

Commands:
  show                Show dashboard once
  interactive         Interactive mode with key controls
  refresh [interval]  Auto-refresh mode (default: 5s)
  section <name>      Show specific section
  export [file]       Export to HTML
  help                Show this help

Sections:
  overview            Overview statistics
  growth              Growth chart
  domains             Domains and recommendations
  recent              Recent knowledge

Examples:
  $(basename "$0") show
  $(basename "$0") interactive
  $(basename "$0") refresh 10
  $(basename "$0") export dashboard.html
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    local command="${1:-show}"
    shift || true

    case "$command" in
        show)
            show_dashboard
            ;;

        interactive)
            interactive_dashboard
            ;;

        refresh)
            refresh_dashboard "$@"
            ;;

        section)
            show_section "$@"
            ;;

        export)
            export_dashboard_html "$@"
            ;;

        help|--help|-h)
            show_usage
            ;;

        *)
            echo "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
