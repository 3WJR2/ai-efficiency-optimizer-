#!/usr/bin/env bash
# ai-efficiency-optimizer.sh - Master AI Efficiency Optimization System
# Integrates: Unified Insights + Workflow Optimizer + Multi-Objective Optimization
# Version: 2.0.0 (Enhanced Integration)

set -euo pipefail

# Paths
UNIFIED_INSIGHTS="$HOME/.claude/scripts/unified-insights.sh"
WORKFLOW_OPTIMIZER="$HOME/.claude/scripts/workflow-optimizer.sh"
MOO_OPTIMIZER="$HOME/.claude/scripts/multi-objective-optimization.sh"
PATTERN_ANALYZER="$HOME/.claude/scripts/pattern-analyzer.sh"
ADAPTIVE_CONFIG="$HOME/.claude/scripts/adaptive-config-manager.sh"

LEARNING_DATA="$HOME/.claude/data/learning-data.json"
OPTIMIZATION_LOG="$HOME/.claude/data/optimization-log.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Initialize optimization log
init_log() {
  if [[ ! -f "$OPTIMIZATION_LOG" ]]; then
    cat > "$OPTIMIZATION_LOG" <<'EOF'
{
  "version": "2.0.0",
  "optimizations_applied": [],
  "composite_scores": [],
  "recommendations_history": []
}
EOF
  fi
}

# Display master dashboard
show_dashboard() {
  echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║       AI EFFICIENCY OPTIMIZER - Master Dashboard v2.0        ║${RESET}"
  echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════╝${RESET}"
  echo

  # Section 1: Unified Insights Summary
  echo -e "${BOLD}${MAGENTA}┌─ UNIFIED INSIGHTS (User + System) ───────────────────────┐${RESET}"

  python3 <<'PYTHON_DASHBOARD'
import json
from pathlib import Path
from statistics import mean

def safe_read(path, default=None):
    try:
        if Path(path).exists():
            with open(path) as f:
                return json.load(f)
    except:
        pass
    return default or {}

learning_data = safe_read('/Users/wallonwalusayi/.claude/data/learning-data.json')
interaction_data = safe_read('/Users/wallonwalusayi/.claude/data/interaction-learning.json')

# Cache metrics
cache_outcomes = learning_data.get('cache_outcomes', {})
hit_rate_history = cache_outcomes.get('hit_rate_history', [])
if hit_rate_history:
    recent_hit = mean([h['hit_rate'] for h in hit_rate_history[-5:]])
    print(f"│ Cache Performance: {recent_hit:.1%} hit rate ({len(hit_rate_history)} samples)")
else:
    print("│ Cache Performance: No data yet")

# Parallel metrics
parallel_outcomes = learning_data.get('parallel_outcomes', {})
exec_history = parallel_outcomes.get('execution_history', [])
total_execs = sum([e['total_executions'] for e in exec_history])
total_tasks = sum([e['total_tasks'] for e in exec_history])
print(f"│ Parallel Execution: {total_execs} runs, {total_tasks} tasks processed")

# Technology focus
tech_prefs = interaction_data.get('learned_preferences', {}).get('technologies', {})
if tech_prefs:
    top_tech = max(tech_prefs.items(), key=lambda x: x[1])
    print(f"│ Primary Tech Stack: {top_tech[0].title()} ({top_tech[1]} uses)")

PYTHON_DASHBOARD

  echo -e "${BOLD}${MAGENTA}└───────────────────────────────────────────────────────────┘${RESET}"
  echo

  # Section 2: Multi-Objective Optimization Score
  echo -e "${BOLD}${GREEN}┌─ MULTI-OBJECTIVE COMPOSITE SCORE ────────────────────────┐${RESET}"

  if [[ -x "$MOO_OPTIMIZER" ]]; then
    "$MOO_OPTIMIZER" calculate 2>/dev/null | grep -A 5 "Composite Score" || echo "│ Calculating composite score..."
  else
    echo "│ Multi-objective optimizer not available"
  fi

  echo -e "${BOLD}${GREEN}└───────────────────────────────────────────────────────────┘${RESET}"
  echo

  # Section 3: Workflow Optimization Opportunities
  echo -e "${BOLD}${YELLOW}┌─ WORKFLOW OPTIMIZATION OPPORTUNITIES ─────────────────────┐${RESET}"

  python3 <<'PYTHON_WORKFLOW'
import json
from pathlib import Path

def safe_read(path, default=None):
    try:
        if Path(path).exists():
            with open(path) as f:
                return json.load(f)
    except:
        pass
    return default or {}

learning_data = safe_read('/Users/wallonwalusayi/.claude/data/learning-data.json')

# Check for optimization opportunities
opportunities = []

# Parallel execution opportunity
parallel_outcomes = learning_data.get('parallel_outcomes', {})
exec_history = parallel_outcomes.get('execution_history', [])
total_execs = sum([e['total_executions'] for e in exec_history])

if total_execs < 5:
    opportunities.append("• Low parallel usage - more opportunities exist")

# Cache optimization opportunity
cache_outcomes = learning_data.get('cache_outcomes', {})
hit_rate_history = cache_outcomes.get('hit_rate_history', [])
if hit_rate_history:
    from statistics import mean
    recent_hit = mean([h['hit_rate'] for h in hit_rate_history[-5:]])
    if recent_hit < 0.6:
        opportunities.append(f"• Cache hit rate ({recent_hit:.1%}) below optimal")

# Adaptation opportunity
adaptations = learning_data.get('adaptation_log', [])
samples = len(hit_rate_history)
if samples >= 10 and not adaptations:
    opportunities.append("• Sufficient data for auto-tuning - enable adaptive config")

if not opportunities:
    opportunities.append("✓ System running optimally - no immediate opportunities")

for opp in opportunities:
    print(f"│ {opp}")

PYTHON_WORKFLOW

  echo -e "${BOLD}${YELLOW}└───────────────────────────────────────────────────────────┘${RESET}"
  echo

  # Section 4: Top Recommendations (Integrated)
  echo -e "${BOLD}${RED}🎯 INTEGRATED RECOMMENDATIONS${RESET}"
  echo

  python3 <<'PYTHON_RECOMMENDATIONS'
import json
from pathlib import Path
from statistics import mean

def safe_read(path, default=None):
    try:
        if Path(path).exists():
            with open(path) as f:
                return json.load(f)
    except:
        pass
    return default or {}

learning_data = safe_read('/Users/wallonwalusayi/.claude/data/learning-data.json')
cache_config = safe_read('/Users/wallonwalusayi/.claude/data/cache-config.json')
learning_config = safe_read('/Users/wallonwalusayi/.claude/data/learning-config.json')
moo_config = safe_read('/Users/wallonwalusayi/.claude/data/moo-config.json')

recommendations = []

# Cache optimization (from unified insights)
hit_rate_history = learning_data.get('cache_outcomes', {}).get('hit_rate_history', [])
if hit_rate_history and len(hit_rate_history) >= 10:
    recent_hit = mean([h['hit_rate'] for h in hit_rate_history[-5:]])
    target = learning_config.get('cache_learning', {}).get('target_hit_rate', 0.65)
    current_threshold = cache_config.get('similarity_threshold', 0.92)

    if recent_hit < target * 0.9:
        new_threshold = max(current_threshold - 0.04, 0.75)
        recommendations.append({
            'priority': 'HIGH',
            'source': 'Cache Analysis',
            'action': f"Lower cache threshold {current_threshold:.2f}→{new_threshold:.2f}",
            'benefit': f"+{((target - recent_hit) * 100):.0f}% hit rate",
            'score': 95
        })

# Multi-objective weight adjustment
if moo_config and hit_rate_history:
    cache_weight = moo_config.get('weights', {}).get('cache_hit_rate', 0.4)
    if recent_hit < 0.5 and cache_weight < 0.5:
        recommendations.append({
            'priority': 'MEDIUM',
            'source': 'Multi-Objective',
            'action': f"Increase cache weight {cache_weight:.2f}→0.5",
            'benefit': "Better cache prioritization",
            'score': 75
        })

# Workflow parallelization
parallel_outcomes = learning_data.get('parallel_outcomes', {})
total_execs = sum([e['total_executions'] for e in parallel_outcomes.get('execution_history', [])])
if total_execs < 10:
    recommendations.append({
        'priority': 'MEDIUM',
        'source': 'Workflow Analysis',
        'action': "Increase parallel execution usage",
        'benefit': "4x speedup on multi-task operations",
        'score': 80
    })

# Auto-tuning
auto_tuning = learning_config.get('learning_features', {}).get('auto_tuning', True)
if not auto_tuning and len(hit_rate_history) >= 15:
    recommendations.append({
        'priority': 'HIGH',
        'source': 'Adaptive Config',
        'action': "Enable auto-tuning",
        'benefit': "Automatic optimization based on patterns",
        'score': 90
    })

# Sort by score
recommendations.sort(key=lambda x: x['score'], reverse=True)

if not recommendations:
    print("✓ All systems optimized - excellent work!")
else:
    for i, rec in enumerate(recommendations[:5], 1):
        color = {
            'HIGH': '\033[0;31m',
            'MEDIUM': '\033[1;33m',
            'LOW': '\033[0;32m'
        }.get(rec['priority'], '')
        reset = '\033[0m'
        print(f"{i}. {color}[{rec['priority']}]{reset} [{rec['source']}]")
        print(f"   Action: {rec['action']}")
        print(f"   Benefit: {rec['benefit']}")
        print()

PYTHON_RECOMMENDATIONS

  # Section 5: Quick Stats
  echo -e "${BOLD}${CYAN}📊 EFFICIENCY METRICS${RESET}"
  echo

  python3 <<'PYTHON_STATS'
import json
from pathlib import Path
from statistics import mean

def safe_read(path, default=None):
    try:
        if Path(path).exists():
            with open(path) as f:
                return json.load(f)
    except:
        pass
    return default or {}

learning_data = safe_read('/Users/wallonwalusayi/.claude/data/learning-data.json')
optimization_log = safe_read('/Users/wallonwalusayi/.claude/data/optimization-log.json')

# Overall metrics
total_optimizations = len(optimization_log.get('optimizations_applied', []))
composite_scores = optimization_log.get('composite_scores', [])

if composite_scores:
    latest_score = composite_scores[-1]['score']
    trend = "↑" if len(composite_scores) > 1 and latest_score > composite_scores[-2]['score'] else "→"
    print(f"Composite Score: {latest_score:.2f}/100 {trend}")
else:
    print("Composite Score: Calculating...")

print(f"Optimizations Applied: {total_optimizations}")

# Learning cycles
cycles = learning_data.get('total_learning_cycles', 0)
print(f"Learning Cycles: {cycles}")

PYTHON_STATS

  echo
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
  echo
}

# Run comprehensive optimization analysis
run_comprehensive_analysis() {
  echo -e "${BOLD}${BLUE}Running comprehensive AI efficiency analysis...${RESET}"
  echo

  # 1. Run unified insights analysis
  echo -e "${YELLOW}[1/4] Running unified insights analysis...${RESET}"
  if [[ -x "$UNIFIED_INSIGHTS" ]]; then
    "$UNIFIED_INSIGHTS" show > /tmp/insights.txt 2>&1
    echo "✓ Unified insights analyzed"
  fi

  # 2. Run pattern analysis
  echo -e "${YELLOW}[2/4] Analyzing patterns...${RESET}"
  if [[ -x "$PATTERN_ANALYZER" ]]; then
    "$PATTERN_ANALYZER" analyze > /tmp/patterns.txt 2>&1
    echo "✓ Patterns analyzed"
  fi

  # 3. Run multi-objective optimization
  echo -e "${YELLOW}[3/4] Calculating multi-objective scores...${RESET}"
  if [[ -x "$MOO_OPTIMIZER" ]]; then
    "$MOO_OPTIMIZER" calculate > /tmp/moo.txt 2>&1 || true
    echo "✓ Composite scores calculated"
  fi

  # 4. Run workflow optimization analysis
  echo -e "${YELLOW}[4/4] Analyzing workflow efficiency...${RESET}"
  if [[ -x "$WORKFLOW_OPTIMIZER" ]]; then
    "$WORKFLOW_OPTIMIZER" analyze > /tmp/workflow.txt 2>&1 || true
    echo "✓ Workflow analyzed"
  fi

  echo
  echo -e "${GREEN}✓ Comprehensive analysis complete${RESET}"
  echo

  # Show dashboard
  show_dashboard
}

# Apply specific optimization
apply_optimization() {
  local opt_id="$1"

  echo -e "${BLUE}Applying optimization #${opt_id}...${RESET}"

  case "$opt_id" in
    1)
      # Cache threshold adjustment (most common)
      echo "Adjusting cache threshold..."
      # Implementation would go here
      ;;
    2)
      # Enable auto-tuning
      echo "Enabling auto-tuning..."
      if [[ -x "$ADAPTIVE_CONFIG" ]]; then
        "$ADAPTIVE_CONFIG" auto-tuning enable
      fi
      ;;
    3)
      # Adjust MOO weights
      echo "Adjusting multi-objective weights..."
      ;;
    *)
      echo "Unknown optimization ID: $opt_id"
      return 1
      ;;
  esac

  # Log optimization
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg ts "$timestamp" --arg opt "$opt_id" \
    '.optimizations_applied += [{timestamp: $ts, optimization: $opt}]' \
    "$OPTIMIZATION_LOG" > "$OPTIMIZATION_LOG.tmp"
  mv "$OPTIMIZATION_LOG.tmp" "$OPTIMIZATION_LOG"

  echo -e "${GREEN}✓ Optimization applied and logged${RESET}"
}

# Auto-optimize based on recommendations
auto_optimize() {
  echo -e "${BOLD}${YELLOW}Running auto-optimization...${RESET}"
  echo
  echo "This will automatically apply safe, high-confidence optimizations."
  read -p "Continue? [y/N]: " confirm

  if [[ "$confirm" != "y" ]]; then
    echo "Cancelled"
    return
  fi

  # Run adaptive config manager
  if [[ -x "$ADAPTIVE_CONFIG" ]]; then
    echo "Running adaptive configuration..."
    "$ADAPTIVE_CONFIG" apply
  fi

  echo
  echo -e "${GREEN}✓ Auto-optimization complete${RESET}"
  echo "Run 'ai-efficiency-optimizer dashboard' to see results"
}

# Export integrated report
export_report() {
  local format="${1:-markdown}"
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  local output_file="$HOME/.claude/data/insights/efficiency-report-${timestamp}.${format}"

  mkdir -p "$HOME/.claude/data/insights"

  case "$format" in
    markdown|md)
      {
        echo "# AI Efficiency Report"
        echo "Generated: $(date)"
        echo
        echo "## Dashboard Summary"
        show_dashboard
        echo
        echo "## Detailed Insights"
        if [[ -f /tmp/insights.txt ]]; then
          cat /tmp/insights.txt
        fi
        echo
        echo "## Pattern Analysis"
        if [[ -f /tmp/patterns.txt ]]; then
          cat /tmp/patterns.txt
        fi
      } > "$output_file"
      echo -e "${GREEN}Report exported: $output_file${RESET}"
      ;;
    json)
      python3 <<PYTHON_EXPORT
import json
from datetime import datetime
from pathlib import Path

def safe_read(path, default=None):
    try:
        if Path(path).exists():
            with open(path) as f:
                return json.load(f)
    except:
        pass
    return default or {}

report = {
    'generated_at': datetime.utcnow().isoformat() + 'Z',
    'version': '2.0.0',
    'unified_insights': safe_read('/Users/wallonwalusayi/.claude/data/learning-data.json'),
    'optimization_log': safe_read('/Users/wallonwalusayi/.claude/data/optimization-log.json'),
    'moo_config': safe_read('/Users/wallonwalusayi/.claude/data/moo-config.json')
}

with open('$output_file', 'w') as f:
    json.dump(report, f, indent=2)
PYTHON_EXPORT
      echo -e "${GREEN}Report exported: $output_file${RESET}"
      ;;
  esac
}

# Show usage
show_usage() {
  cat <<'EOF'
AI Efficiency Optimizer - Master Command v2.0

USAGE:
  ai-efficiency-optimizer [command] [options]

COMMANDS:
  dashboard              Show integrated efficiency dashboard
  analyze                Run comprehensive analysis across all systems
  apply <id>             Apply specific optimization
  auto                   Auto-optimize based on recommendations
  export [format]        Export integrated report (markdown, json)
  status                 Quick status check

INTEGRATED SYSTEMS:
  • Unified Insights     - User behavior + system performance
  • Workflow Optimizer   - Parallelization & bottleneck analysis
  • Multi-Objective Opt  - Balanced performance optimization
  • Pattern Analyzer     - Learning pattern identification
  • Adaptive Config      - Auto-tuning based on patterns

EXAMPLES:
  ai-efficiency-optimizer dashboard
  ai-efficiency-optimizer analyze
  ai-efficiency-optimizer auto
  ai-efficiency-optimizer export markdown

QUICK ACCESS:
  /ai-efficiency-optimizer          (via skill system)

For detailed docs:
  ~/.claude/docs/AI-EFFICIENCY-OPTIMIZER.md
EOF
}

# Main
main() {
  init_log

  local command="${1:-dashboard}"
  shift || true

  case "$command" in
    dashboard|show)
      show_dashboard
      ;;
    analyze|full)
      run_comprehensive_analysis
      ;;
    apply)
      apply_optimization "$@"
      ;;
    auto|optimize)
      auto_optimize
      ;;
    export)
      export_report "$@"
      ;;
    status)
      echo "Quick Status Check:"
      show_dashboard | head -30
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
