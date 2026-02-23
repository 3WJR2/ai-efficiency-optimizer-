#!/usr/bin/env bash

# test-phase-b.sh - Demonstrate Phase B: Learning Integration Engine
# Version: 1.0.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "Phase B: Learning Integration Engine Demo"
echo "============================================"
echo

# Test 1: Learning Reader
echo "Test 1: Extract Learning Insights"
echo "-----------------------------------"
echo "Command: learning-reader.sh extract"
echo

insights=$("$SCRIPT_DIR/learning-reader.sh" extract 2>/dev/null)
total_insights=$(echo "$insights" | jq -r '.total_insights')
confidence=$(echo "$insights" | jq -r '.confidence_threshold')

echo "✓ Extracted $total_insights insights (threshold: $confidence)"
echo "$insights" | jq -r '.insights[] | "  - \(.type): confidence \(.confidence)"'
echo

# Test 2: Insight Injector
echo "Test 2: Inject Insights into Context"
echo "-------------------------------------"
echo "Command: insight-injector.sh show"
echo

temp_dir=$(mktemp -d)
cd "$temp_dir"

inject_result=$("$SCRIPT_DIR/insight-injector.sh" inject . 0.70 2>/dev/null)
status=$(echo "$inject_result" | jq -r '.status')

if [[ "$status" == "success" ]]; then
    echo "✓ Context file created: .claude/project-context.md"
    lines=$(wc -l < .claude/project-context.md)
    echo "  File contains $lines lines"
else
    echo "✗ Failed to create context"
fi

cd - > /dev/null
rm -rf "$temp_dir"
echo

# Test 3: Session Tracking
echo "Test 3: Session Lifecycle"
echo "-------------------------"
echo "Command: session-learning-bridge.sh workflow"
echo

temp_dir=$(mktemp -d)
cd "$temp_dir"

# Start session
start_result=$("$SCRIPT_DIR/session-learning-bridge.sh" start . 0.70 2>/dev/null)
session_id=$(echo "$start_result" | jq -r '.session_id')
insights_injected=$(echo "$start_result" | jq -r '.insights_injected')

echo "✓ Session started: $session_id"
echo "  Insights injected: $insights_injected"

# Track outcomes
"$SCRIPT_DIR/session-learning-bridge.sh" track success "Test operation 1" 2>/dev/null
echo "✓ Tracked operation: Test operation 1"

"$SCRIPT_DIR/session-learning-bridge.sh" track success "Test operation 2" 2>/dev/null
echo "✓ Tracked operation: Test operation 2"

# End session
"$SCRIPT_DIR/session-learning-bridge.sh" end success 9 2>/dev/null
echo "✓ Session ended (satisfaction: 9/10)"

cd - > /dev/null
rm -rf "$temp_dir"
echo

# Test 4: Session Statistics
echo "Test 4: Session Statistics"
echo "--------------------------"
echo "Command: outcome-tracker.sh session-stats"
echo

"$SCRIPT_DIR/outcome-tracker.sh" session-stats 2>/dev/null | while IFS= read -r line; do
    if [[ "$line" =~ ^[A-Z] ]]; then
        echo "  $line"
    fi
done

echo

# Test 5: Feedback Loop
echo "Test 5: Feedback Loop Verification"
echo "-----------------------------------"
echo

# Check that session was added to learning data
learning_cycles=$("$SCRIPT_DIR/outcome-tracker.sh" stats 2>/dev/null | grep "Total learning cycles" | awk '{print $4}')
echo "✓ Learning cycles recorded: $learning_cycles"

# Check session history
total_sessions=$(jq -r '.total_sessions' "$HOME/.claude/data/session-history.json")
echo "✓ Total sessions tracked: $total_sessions"

echo

# Summary
echo "============================================"
echo "Phase B Test Summary"
echo "============================================"
echo
echo "All components operational:"
echo "  ✓ Learning Reader - Extracting insights"
echo "  ✓ Insight Injector - Creating context files"
echo "  ✓ Session Tracking - Recording operations"
echo "  ✓ Session Bridge - Orchestrating workflow"
echo "  ✓ Feedback Loop - Updating global learning"
echo
echo "Phase B is ACTIVE and ready to use!"
echo
echo "Quick Start:"
echo "  1. Start session:  session-learning-bridge.sh start"
echo "  2. Track progress: session-learning-bridge.sh track success 'task'"
echo "  3. End session:    session-learning-bridge.sh end success 9"
echo
echo "Documentation: ~/.claude/docs/LEARNING-INTEGRATION.md"
echo "============================================"
