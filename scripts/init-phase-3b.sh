#!/usr/bin/env bash
# init-phase-3b.sh - Initialize all Phase 3B improvements

set -e

echo "🚀 Initializing Phase 3B Systems..."
echo

# 1. Multi-Objective Optimization
echo "1️⃣  Multi-Objective Optimization..."
~/.claude/scripts/multi-objective-optimization.sh init
echo

# 2. Workload Classification
echo "2️⃣  Workload Classification..."
~/.claude/scripts/workload-classifier.sh init
~/.claude/scripts/workload-classifier.sh auto-switch enable
echo

# 3. Config MAB
echo "3️⃣  Multi-Armed Bandit..."
~/.claude/scripts/config-mab.sh init
~/.claude/scripts/config-mab.sh enable
echo

# 4. A/B Testing
echo "4️⃣  A/B Testing Framework..."
~/.claude/scripts/ab-testing.sh init
echo

# 5. Smart Caching
echo "5️⃣  Smart Caching..."
~/.claude/scripts/smart-cache.sh init
~/.claude/scripts/smart-cache.sh enable
echo

echo "✅ All Phase 3B systems initialized!"
echo
echo "📋 Next steps:"
echo "  1. Let system collect baseline data (run normally for 1 hour)"
echo "  2. Run: ~/.claude/scripts/check-phase-3b-status.sh"
echo "  3. Review integration guide: ~/.claude/docs/PHASE-3B-INTEGRATION-EXAMPLES.md"
echo
echo "💡 Quick start commands:"
echo "  Check status:     ~/.claude/scripts/check-phase-3b-status.sh"
echo "  Dashboard:        ~/.claude/scripts/dashboard.sh"
echo "  Detect workload:  ~/.claude/scripts/workload-classifier.sh detect"
