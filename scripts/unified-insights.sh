#!/usr/bin/env bash
# unified-insights.sh - Enhanced insights combining user behavior + system performance
# Part of Adaptive Intelligence System v1.3.0

set -euo pipefail

# Data files
INTERACTION_DATA="$HOME/.claude/data/interaction-learning.json"
LEARNING_DATA="$HOME/.claude/data/learning-data.json"
LEARNING_CONFIG="$HOME/.claude/data/learning-config.json"
CACHE_CONFIG="$HOME/.claude/data/cache-config.json"
PARALLEL_CONFIG="$HOME/.claude/data/parallel-config.json"
USER_PROFILE="$HOME/.claude/data/user-profile.json"
OUTPUT_DIR="$HOME/.claude/data/insights"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Initialize files if missing
init_files() {
  if [[ ! -f "$INTERACTION_DATA" ]]; then
    echo "{\"version\": \"1.0.0\", \"learning_system\": {\"enabled\": true}, \"interaction_patterns\": {}, \"learned_preferences\": {}}" > "$INTERACTION_DATA"
  fi
  if [[ ! -f "$LEARNING_DATA" ]]; then
    echo "{\"version\": \"1.0.0\", \"cache_outcomes\": {\"hit_rate_history\": []}, \"parallel_outcomes\": {\"execution_history\": []}, \"learned_patterns\": {}}" > "$LEARNING_DATA"
  fi
}

# Generate ASCII progress bar
progress_bar() {
  local current=$1
  local target=$2
  local width=20
  local percentage=$(awk "BEGIN {printf \"%.0f\", ($current/$target)*100}")
  local filled=$(awk "BEGIN {printf \"%.0f\", ($current/$target)*$width}")

  printf "["
  for ((i=0; i<width; i++)); do
    if ((i < filled)); then
      printf "█"
    else
      printf "░"
    fi
  done
  printf "] %3d%%" "$percentage"
}

# Generate trend indicator
trend_indicator() {
  local trend=$1
  case $trend in
    "improving"|"up") echo "↑" ;;
    "declining"|"down") echo "↓" ;;
    "stable") echo "→" ;;
    *) echo "?" ;;
  esac
}

# Calculate confidence score
confidence_score() {
  local samples=$1
  local min_samples=${2:-10}

  if ((samples < min_samples)); then
    echo "LOW"
  elif ((samples < min_samples * 3)); then
    echo "MEDIUM"
  else
    echo "HIGH"
  fi
}

# Main insights generation
generate_insights() {
  local format=${1:-"terminal"}
  local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")

  echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║        UNIFIED INSIGHTS REPORT - Enhanced v1.3.0          ║${RESET}"
  echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${RESET}"
  echo
  echo -e "${BLUE}Generated:${RESET} $timestamp UTC"
  echo

  # Section 1: User Behavior Insights
  echo -e "${BOLD}${MAGENTA}┌─ USER BEHAVIOR INSIGHTS ─────────────────────────────────┐${RESET}"

  python3 <<'PYTHON_USER_INSIGHTS'
import json
import sys
from pathlib import Path

def safe_read_json(path, default=None):
    try:
        if Path(path).exists():
            with open(path) as f:
                return json.load(f)
    except:
        pass
    return default or {}

interaction_data = safe_read_json('/Users/wallonwalusayi/.claude/data/interaction-learning.json')
user_profile = safe_read_json('/Users/wallonwalusayi/.claude/data/user-profile.json')

# Get learning stage
learning_stage = user_profile.get('profile', {}).get('learning_stage', 'initialization')
interaction_count = user_profile.get('profile', {}).get('interaction_count', 0)

# Technology preferences
tech_prefs = interaction_data.get('learned_preferences', {}).get('technologies', {})
if tech_prefs:
    sorted_techs = sorted(tech_prefs.items(), key=lambda x: x[1], reverse=True)[:5]
    tech_summary = ", ".join([f"{k.title()} ({v})" for k, v in sorted_techs])
else:
    tech_summary = "No data yet"

# Communication style
comm_style = interaction_data.get('interaction_patterns', {}).get('communication_style', {})
detail_score = comm_style.get('brevity_vs_detail', {}).get('score', 0.5)
tech_depth = comm_style.get('technical_depth', {}).get('score', 0.5)

detail_level = "High" if detail_score > 0.7 else "Medium" if detail_score > 0.4 else "Low"
tech_level = "High" if tech_depth > 0.7 else "Medium" if tech_depth > 0.4 else "Low"

# Request categories
request_cats = interaction_data.get('interaction_patterns', {}).get('request_categories', {})
total_requests = sum(cat.get('count', 0) for cat in request_cats.values())

print(f"│ Learning Stage: {learning_stage.replace('_', ' ').title()} ({interaction_count} interactions)")
print(f"│ Technologies: {tech_summary}")
print(f"│ Communication: {detail_level} detail, {tech_level} technical depth")
print(f"│ Total Requests: {total_requests} categorized")
PYTHON_USER_INSIGHTS

  echo -e "${BOLD}${MAGENTA}└──────────────────────────────────────────────────────────┘${RESET}"
  echo

  # Section 2: System Performance Insights
  echo -e "${BOLD}${GREEN}┌─ SYSTEM PERFORMANCE INSIGHTS ────────────────────────────┐${RESET}"

  python3 <<'PYTHON_PERF_INSIGHTS'
import json
from pathlib import Path
from statistics import mean

def safe_read_json(path, default=None):
    try:
        if Path(path).exists():
            with open(path) as f:
                return json.load(f)
    except:
        pass
    return default or {}

learning_data = safe_read_json('/Users/wallonwalusayi/.claude/data/learning-data.json')
cache_config = safe_read_json('/Users/wallonwalusayi/.claude/data/cache-config.json')
learning_config = safe_read_json('/Users/wallonwalusayi/.claude/data/learning-config.json')

# Cache performance
cache_outcomes = learning_data.get('cache_outcomes', {})
hit_rate_history = cache_outcomes.get('hit_rate_history', [])
latency_history = cache_outcomes.get('latency_history', [])

if hit_rate_history:
    recent_hit_rate = mean([h['hit_rate'] for h in hit_rate_history[-5:]])
    avg_hit_rate = mean([h['hit_rate'] for h in hit_rate_history])
    trend = "↑" if recent_hit_rate > avg_hit_rate else "↓" if recent_hit_rate < avg_hit_rate else "→"

    # Visual progress bar
    target_hit_rate = learning_config.get('cache_learning', {}).get('target_hit_rate', 0.65)
    bar_width = 20
    filled = int((recent_hit_rate / 1.0) * bar_width)
    target_pos = int((target_hit_rate / 1.0) * bar_width)

    bar = ""
    for i in range(bar_width):
        if i == target_pos:
            bar += "|"
        elif i < filled:
            bar += "█"
        else:
            bar += "░"

    print(f"│ Cache Hit Rate:  [{bar}] {recent_hit_rate:.1%} {trend}")
    print(f"│ Target: {target_hit_rate:.1%} | Samples: {len(hit_rate_history)}")
else:
    print("│ Cache Hit Rate: No data yet")

if latency_history:
    avg_latency = mean([l['avg_latency_ms'] for l in latency_history[-5:]])
    avg_reduction = mean([l['reduction_pct'] for l in latency_history[-5:]])
    print(f"│ Latency: {avg_latency:.1f}ms avg ({avg_reduction:.1f}% reduction)")
else:
    print("│ Latency: No data yet")

# Parallel performance
parallel_outcomes = learning_data.get('parallel_outcomes', {})
exec_history = parallel_outcomes.get('execution_history', [])
success_history = parallel_outcomes.get('success_rate_history', [])

if exec_history:
    total_execs = sum([e['total_executions'] for e in exec_history])
    total_tasks = sum([e['total_tasks'] for e in exec_history])
    print(f"│ Parallel Executions: {total_execs} runs, {total_tasks} tasks")
else:
    print("│ Parallel Executions: Not used yet (opportunity!)")

if success_history:
    recent_success = mean([s['success_rate'] for s in success_history[-5:]])
    print(f"│ Success Rate: {recent_success:.1f}%")

# Learning cycles
total_cycles = learning_data.get('total_learning_cycles', 0)
print(f"│ Learning Cycles: {total_cycles} completed")

PYTHON_PERF_INSIGHTS

  echo -e "${BOLD}${GREEN}└──────────────────────────────────────────────────────────┘${RESET}"
  echo

  # Section 3: Cross-Domain Insights & Correlations
  echo -e "${BOLD}${YELLOW}┌─ CROSS-DOMAIN INSIGHTS & CORRELATIONS ───────────────────┐${RESET}"

  python3 <<'PYTHON_CROSS_INSIGHTS'
import json
from pathlib import Path
from statistics import mean

def safe_read_json(path, default=None):
    try:
        if Path(path).exists():
            with open(path) as f:
                return json.load(f)
    except:
        pass
    return default or {}

interaction_data = safe_read_json('/Users/wallonwalusayi/.claude/data/interaction-learning.json')
learning_data = safe_read_json('/Users/wallonwalusayi/.claude/data/learning-data.json')
learning_config = safe_read_json('/Users/wallonwalusayi/.claude/data/learning-config.json')

insights = []

# Cache analysis
hit_rate_history = learning_data.get('cache_outcomes', {}).get('hit_rate_history', [])
if hit_rate_history:
    recent_hit_rate = mean([h['hit_rate'] for h in hit_rate_history[-5:]])
    target = learning_config.get('cache_learning', {}).get('target_hit_rate', 0.65)

    if recent_hit_rate < target * 0.8:
        insights.append(f"• Cache hit rate low ({recent_hit_rate:.1%}) - queries may be diverse")
    elif recent_hit_rate >= target:
        insights.append(f"• Cache performing well ({recent_hit_rate:.1%}) - queries show patterns")

# Technology correlation
tech_prefs = interaction_data.get('learned_preferences', {}).get('technologies', {})
if tech_prefs:
    sorted_techs = sorted(tech_prefs.items(), key=lambda x: x[1], reverse=True)
    if len(sorted_techs) > 0:
        top_tech = sorted_techs[0]
        total = sum(tech_prefs.values())
        if top_tech[1] / total > 0.6:
            insights.append(f"• Heavy {top_tech[0].title()} focus ({top_tech[1]} uses) - optimize for this stack")

# Parallel usage
exec_history = learning_data.get('parallel_outcomes', {}).get('execution_history', [])
total_execs = sum([e['total_executions'] for e in exec_history]) if exec_history else 0
if total_execs == 0:
    insights.append("• Zero parallel execution usage - missing 4x speedup opportunity")
elif total_execs < 10:
    insights.append(f"• Low parallel usage ({total_execs} execs) - more opportunities exist")

# Learning stage correlation
user_profile = safe_read_json('/Users/wallonwalusayi/.claude/data/user-profile.json')
interaction_count = user_profile.get('profile', {}).get('interaction_count', 0)
sample_count = len(hit_rate_history)

if sample_count > 0 and interaction_count > 0:
    ratio = sample_count / interaction_count if interaction_count > 0 else 0
    if ratio < 0.5:
        insights.append(f"• Low sampling rate ({ratio:.1f}) - increase system usage for better learning")

# Adaptation status
adaptations = learning_data.get('adaptation_log', [])
if not adaptations and sample_count >= 10:
    insights.append("• No adaptations yet despite sufficient data - check auto-tuning config")
elif adaptations:
    recent_adaptations = [a for a in adaptations if 'timestamp' in a][-3:]
    if recent_adaptations:
        insights.append(f"• System adapting: {len(recent_adaptations)} recent optimizations applied")

if not insights:
    insights.append("• Insufficient data for cross-domain analysis (need 10+ samples)")

for insight in insights:
    print(f"│ {insight}")

PYTHON_CROSS_INSIGHTS

  echo -e "${BOLD}${YELLOW}└──────────────────────────────────────────────────────────┘${RESET}"
  echo

  # Section 4: Top Recommendations
  echo -e "${BOLD}${RED}🎯 TOP RECOMMENDATIONS${RESET}"
  echo

  python3 <<'PYTHON_RECOMMENDATIONS'
import json
from pathlib import Path
from statistics import mean

def safe_read_json(path, default=None):
    try:
        if Path(path).exists():
            with open(path) as f:
                return json.load(f)
    except:
        pass
    return default or {}

learning_data = safe_read_json('/Users/wallonwalusayi/.claude/data/learning-data.json')
cache_config = safe_read_json('/Users/wallonwalusayi/.claude/data/cache-config.json')
learning_config = safe_read_json('/Users/wallonwalusayi/.claude/data/learning-config.json')
interaction_data = safe_read_json('/Users/wallonwalusayi/.claude/data/interaction-learning.json')

recommendations = []

# Cache optimization
hit_rate_history = learning_data.get('cache_outcomes', {}).get('hit_rate_history', [])
if hit_rate_history and len(hit_rate_history) >= 10:
    recent_hit_rate = mean([h['hit_rate'] for h in hit_rate_history[-5:]])
    target = learning_config.get('cache_learning', {}).get('target_hit_rate', 0.65)
    current_threshold = cache_config.get('similarity_threshold', 0.92)

    if recent_hit_rate < target * 0.9:
        new_threshold = max(current_threshold - 0.06, 0.80)
        improvement = ((new_threshold - current_threshold) / current_threshold) * 100
        recommendations.append({
            'priority': 'HIGH',
            'category': 'PERFORMANCE',
            'text': f"Lower cache threshold {current_threshold:.2f}→{new_threshold:.2f} (est. +{abs(improvement):.0f}% hit rate)",
            'score': 90
        })
    elif recent_hit_rate > target * 1.2:
        new_threshold = min(current_threshold + 0.02, 0.98)
        recommendations.append({
            'priority': 'MEDIUM',
            'category': 'OPTIMIZATION',
            'text': f"Raise cache threshold {current_threshold:.2f}→{new_threshold:.2f} (more selective)",
            'score': 60
        })

# Parallel execution
exec_history = learning_data.get('parallel_outcomes', {}).get('execution_history', [])
total_execs = sum([e['total_executions'] for e in exec_history]) if exec_history else 0
if total_execs == 0:
    recommendations.append({
        'priority': 'MEDIUM',
        'category': 'USAGE',
        'text': "Enable parallel execution for multi-file operations (4x speedup)",
        'score': 75
    })

# Learning data
sample_count = len(hit_rate_history)
if sample_count < 30:
    recommendations.append({
        'priority': 'LOW',
        'category': 'LEARNING',
        'text': f"Continue diverse interactions ({sample_count}/50 for optimal learning)",
        'score': 40
    })

# Technology optimization
tech_prefs = interaction_data.get('learned_preferences', {}).get('technologies', {})
if tech_prefs:
    sorted_techs = sorted(tech_prefs.items(), key=lambda x: x[1], reverse=True)
    if len(sorted_techs) >= 2:
        top_two = sorted_techs[:2]
        total = sum(tech_prefs.values())
        if sum([t[1] for t in top_two]) / total > 0.8:
            tech_names = " & ".join([t[0].title() for t in top_two])
            recommendations.append({
                'priority': 'MEDIUM',
                'category': 'OPTIMIZATION',
                'text': f"Optimize workflows for {tech_names} (80% of activity)",
                'score': 65
            })

# Auto-tuning check
auto_tuning = learning_config.get('learning_features', {}).get('auto_tuning', True)
if not auto_tuning and sample_count >= 10:
    recommendations.append({
        'priority': 'HIGH',
        'category': 'CONFIG',
        'text': "Enable auto-tuning to apply learned optimizations automatically",
        'score': 85
    })

# Sort by priority score
recommendations.sort(key=lambda x: x['score'], reverse=True)

if not recommendations:
    print("✓ System optimized - no recommendations at this time")
else:
    for i, rec in enumerate(recommendations[:5], 1):
        priority_color = {
            'HIGH': '\033[0;31m',    # Red
            'MEDIUM': '\033[1;33m',  # Yellow
            'LOW': '\033[0;32m'      # Green
        }.get(rec['priority'], '')
        reset = '\033[0m'
        print(f"{i}. {priority_color}[{rec['priority']}]{reset} [{rec['category']}] {rec['text']}")

PYTHON_RECOMMENDATIONS

  echo

  # Section 5: Summary Stats
  echo -e "${BOLD}${CYAN}📊 SUMMARY STATISTICS${RESET}"
  echo

  python3 <<'PYTHON_SUMMARY'
import json
from pathlib import Path
from statistics import mean

def safe_read_json(path, default=None):
    try:
        if Path(path).exists():
            with open(path) as f:
                return json.load(f)
    except:
        pass
    return default or {}

learning_data = safe_read_json('/Users/wallonwalusayi/.claude/data/learning-data.json')
user_profile = safe_read_json('/Users/wallonwalusayi/.claude/data/user-profile.json')

# Calculate overall metrics
hit_rate_history = learning_data.get('cache_outcomes', {}).get('hit_rate_history', [])
sample_count = len(hit_rate_history)

interaction_count = user_profile.get('profile', {}).get('interaction_count', 0)

# Confidence calculation
min_samples = 10
if sample_count < min_samples:
    confidence = "LOW"
    confidence_pct = (sample_count / min_samples) * 100
elif sample_count < min_samples * 3:
    confidence = "MEDIUM"
    confidence_pct = 50 + ((sample_count - min_samples) / (min_samples * 2)) * 30
else:
    confidence = "HIGH"
    confidence_pct = min(80 + ((sample_count - min_samples * 3) / min_samples) * 5, 95)

# Trend
if hit_rate_history and len(hit_rate_history) >= 5:
    recent = mean([h['hit_rate'] for h in hit_rate_history[-5:]])
    older = mean([h['hit_rate'] for h in hit_rate_history[:5]])
    if recent > older * 1.05:
        trend = "IMPROVING"
    elif recent < older * 0.95:
        trend = "DECLINING"
    else:
        trend = "STABLE"
else:
    trend = "INSUFFICIENT DATA"

# Next milestone
if sample_count < 30:
    next_milestone = f"{sample_count}/30 samples to Medium confidence"
elif sample_count < 50:
    next_milestone = f"{sample_count}/50 samples to High confidence"
elif sample_count < 100:
    next_milestone = f"{sample_count}/100 samples to Optimal learning"
else:
    next_milestone = "Optimal learning achieved!"

print(f"Trend: {trend} | Confidence: {confidence} ({confidence_pct:.0f}%) | Next: {next_milestone}")

PYTHON_SUMMARY

  echo
  echo -e "${BOLD}${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo
  echo -e "${BLUE}💡 Tip:${RESET} Run '/adaptive-intelligence insights export' to save detailed report"
  echo
}

# Export insights to file
export_insights() {
  local format=${1:-"markdown"}
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  local output_file="$OUTPUT_DIR/insights_${timestamp}.${format}"

  case $format in
    "markdown"|"md")
      generate_insights "markdown" > "${output_file%.${format}}.md"
      echo "Insights exported to: ${output_file%.${format}}.md"
      ;;
    "json")
      python3 <<'PYTHON_JSON_EXPORT'
import json
from pathlib import Path
from statistics import mean
from datetime import datetime

def safe_read_json(path, default=None):
    try:
        if Path(path).exists():
            with open(path) as f:
                return json.load(f)
    except:
        pass
    return default or {}

interaction_data = safe_read_json('/Users/wallonwalusayi/.claude/data/interaction-learning.json')
learning_data = safe_read_json('/Users/wallonwalusayi/.claude/data/learning-data.json')
user_profile = safe_read_json('/Users/wallonwalusayi/.claude/data/user-profile.json')

report = {
    'generated_at': datetime.utcnow().isoformat() + 'Z',
    'version': '1.3.0',
    'user_behavior': {
        'learning_stage': user_profile.get('profile', {}).get('learning_stage', 'unknown'),
        'interaction_count': user_profile.get('profile', {}).get('interaction_count', 0),
        'technologies': interaction_data.get('learned_preferences', {}).get('technologies', {}),
        'communication_style': interaction_data.get('interaction_patterns', {}).get('communication_style', {})
    },
    'system_performance': {
        'cache': {
            'samples': len(learning_data.get('cache_outcomes', {}).get('hit_rate_history', [])),
            'recent_hit_rate': mean([h['hit_rate'] for h in learning_data.get('cache_outcomes', {}).get('hit_rate_history', [])[-5:]]) if learning_data.get('cache_outcomes', {}).get('hit_rate_history', []) else 0,
            'avg_latency_ms': mean([l['avg_latency_ms'] for l in learning_data.get('cache_outcomes', {}).get('latency_history', [])[-5:]]) if learning_data.get('cache_outcomes', {}).get('latency_history', []) else 0
        },
        'parallel': {
            'total_executions': sum([e['total_executions'] for e in learning_data.get('parallel_outcomes', {}).get('execution_history', [])]),
            'total_tasks': sum([e['total_tasks'] for e in learning_data.get('parallel_outcomes', {}).get('execution_history', [])])
        }
    },
    'learned_patterns': learning_data.get('learned_patterns', {}),
    'total_learning_cycles': learning_data.get('total_learning_cycles', 0)
}

print(json.dumps(report, indent=2))
PYTHON_JSON_EXPORT
      echo "Insights exported to: $output_file"
      ;;
    *)
      echo "Unsupported format: $format"
      exit 1
      ;;
  esac
}

# Main execution
main() {
  init_files

  case ${1:-"show"} in
    "show"|"")
      generate_insights "terminal"
      ;;
    "export")
      format=${2:-"markdown"}
      export_insights "$format"
      ;;
    *)
      echo "Usage: $0 [show|export] [format]"
      echo "  show          - Display insights in terminal (default)"
      echo "  export md     - Export to markdown"
      echo "  export json   - Export to JSON"
      exit 1
      ;;
  esac
}

main "$@"
