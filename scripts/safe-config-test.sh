#!/usr/bin/env bash
# safe-config-test.sh - Safe configuration testing with rollback

set -e

TEST_NAME="$1"
NEW_CACHE="$2"
NEW_CONCURRENT="$3"

if [[ -z "$TEST_NAME" ]] || [[ -z "$NEW_CACHE" ]] || [[ -z "$NEW_CONCURRENT" ]]; then
  echo "Usage: $0 <test_name> <new_cache_threshold> <new_concurrent>"
  echo
  echo "Example: $0 aggressive_test 0.65 8"
  echo
  echo "This script:"
  echo "  1. Creates rollback snapshot (safety)"
  echo "  2. Runs A/B test with new config"
  echo "  3. Monitors for anomalies"
  echo "  4. Applies if statistically significant"
  echo "  5. Rolls back if any issues"
  exit 1
fi

echo "🛡️  Safe Configuration Test: $TEST_NAME"
echo

# Step 1: Create rollback snapshot (Phase 3A)
echo "1. Creating rollback snapshot..."
~/.claude/scripts/automatic-rollback.sh snapshot cache "before $TEST_NAME"
echo

# Step 2: Get current config
current_cache=$(jq -r '.similarity_threshold' ~/.claude/data/cache-config.json)
current_concurrent=$(jq -r '.max_concurrent_processes' ~/.claude/data/parallel-config.json)

echo "2. Configuration comparison:"
echo "   Current: cache=$current_cache, concurrent=$current_concurrent"
echo "   New:     cache=$NEW_CACHE, concurrent=$NEW_CONCURRENT"
echo

# Step 3: Create A/B test
echo "3. Creating A/B test..."
test_output=$(~/.claude/scripts/ab-testing.sh create \
  "$TEST_NAME" \
  $current_cache $current_concurrent \
  $NEW_CACHE $NEW_CONCURRENT 2>&1)

test_id=$(echo "$test_output" | grep "Test created:" | awk '{print $3}')

if [[ -z "$test_id" ]]; then
  echo "Error: Failed to create A/B test"
  echo "$test_output"
  exit 1
fi

echo "   Test ID: $test_id"
echo

# Step 4: Apply new config
echo "4. Applying new configuration (Variant B)..."
~/.claude/scripts/ab-testing.sh apply-variant $test_id b
echo

echo "5. Collecting samples (6 samples over 30 minutes)..."
echo "   Each sample taken after 5 minutes of workload"
echo

samples=0
max_samples=6
interval=300  # 5 minutes

for i in $(seq 1 $max_samples); do
  echo "   📊 Sample $i/$max_samples..."
  echo "      Waiting $interval seconds for workload..."

  sleep $interval

  # Collect sample
  ~/.claude/scripts/ab-testing.sh collect-sample $test_id

  samples=$((samples + 1))
  echo "      ✓ Sample collected"

  # Check for anomalies after each sample (Phase 3A)
  echo "      Checking for anomalies..."
  if ~/.claude/scripts/anomaly-detection.sh detect 2>&1 | grep -q "ANOMALY DETECTED"; then
    echo
    echo "   ⚠️  ANOMALY DETECTED!"
    echo
    echo "6. Performing automatic rollback..."
    ~/.claude/scripts/automatic-rollback.sh rollback

    echo
    echo "   ❌ Test aborted due to anomalies"
    echo "   Check: ~/.claude/scripts/anomaly-detection.sh log"
    exit 1
  fi
  echo "      ✓ No anomalies"
  echo
done

echo "6. All samples collected successfully!"
echo

echo "7. Analyzing results..."
echo
analysis=$(~/.claude/scripts/ab-testing.sh analyze $test_id 2>&1)
echo "$analysis"
echo

# Check recommendation
recommendation=$(echo "$analysis" | grep "Recommendation:" | awk '{print $2}')
confidence=$(echo "$analysis" | grep "Confidence:" | awk '{print $2}')

echo "────────────────────────────────────────────────────────────"
echo

if [[ "$recommendation" == "ADOPT_B" ]]; then
  echo "✅ Test successful! New configuration performs better."
  echo "   Confidence: $confidence"
  echo
  echo "Apply changes permanently? (y/N): "
  read -r response

  if [[ "$response" =~ ^[Yy]$ ]]; then
    echo
    echo "8. Applying configuration permanently..."

    jq --argjson cache "$NEW_CACHE" \
       '.similarity_threshold = $cache' \
       ~/.claude/data/cache-config.json > ~/.claude/data/cache-config.json.tmp
    mv ~/.claude/data/cache-config.json.tmp ~/.claude/data/cache-config.json

    jq --argjson concurrent "$NEW_CONCURRENT" \
       '.max_concurrent_processes = $concurrent' \
       ~/.claude/data/parallel-config.json > ~/.claude/data/parallel-config.json.tmp
    mv ~/.claude/data/parallel-config.json.tmp ~/.claude/data/parallel-config.json

    echo "   ✓ Configuration applied"
    echo
    echo "✅ Test complete: Configuration updated successfully!"
  else
    echo
    echo "8. User declined. Rolling back..."
    ~/.claude/scripts/automatic-rollback.sh rollback
    echo "   ✓ Rolled back to previous configuration"
    echo
    echo "ℹ️  Test complete: Changes not applied (user choice)"
  fi
elif [[ "$recommendation" == "KEEP_A" ]]; then
  echo "❌ Test failed: New configuration performs worse"
  echo
  echo "8. Rolling back to previous configuration..."
  ~/.claude/scripts/automatic-rollback.sh rollback
  echo "   ✓ Rolled back successfully"
  echo
  echo "ℹ️  Test complete: Original configuration restored"
else
  echo "⚠️  Test inconclusive: No clear winner"
  echo
  echo "8. Rolling back to previous configuration (safety)..."
  ~/.claude/scripts/automatic-rollback.sh rollback
  echo "   ✓ Rolled back successfully"
  echo
  echo "ℹ️  Test complete: More samples needed for significance"
fi

# Complete the test
~/.claude/scripts/ab-testing.sh complete $test_id

echo
echo "────────────────────────────────────────────────────────────"
echo "Test completed: $TEST_NAME"
echo "Test ID: $test_id"
echo "Report saved in A/B test history"
