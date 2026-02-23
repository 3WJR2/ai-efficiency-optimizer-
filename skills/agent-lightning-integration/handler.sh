#!/usr/bin/env bash
#
# Agent-Lightning Integration Skill Handler
#

set -euo pipefail

readonly SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BRIDGE_SCRIPT="${HOME}/.claude/scripts/agent-lightning-bridge.sh"
readonly CONFIG_PATH="${HOME}/.claude/data/agent-lightning/config.json"

# Source the bridge script
source "${BRIDGE_SCRIPT}"

# Parse command
COMMAND="${1:-help}"
shift || true

case "${COMMAND}" in
    init)
        echo "Initializing agent-lightning integration..."
        agl_bridge_init
        echo ""
        echo "✓ Integration initialized successfully!"
        echo ""
        echo "Next steps:"
        echo "  1. Run: /agent-lightning sync"
        echo "  2. Monitor: /agent-lightning status"
        echo "  3. Train: /agent-lightning train (after 100+ samples)"
        ;;

    sync)
        echo "Syncing learning data to agent-lightning..."
        agl_bridge_sync
        echo ""
        echo "✓ Sync completed!"
        echo ""
        echo "View status: /agent-lightning status"
        ;;

    train)
        echo "Running agent-lightning training..."
        agl_bridge_train
        echo ""
        echo "✓ Training completed!"
        echo ""
        if [[ -f "${HOME}/.claude/data/agent-lightning/recommendations.json" ]]; then
            echo "Recommendations available:"
            jq -r '.recommendations[] | "  - \(.component): \(.recommended_action) (current: \(.current_value))"' \
                "${HOME}/.claude/data/agent-lightning/recommendations.json"
            echo ""
            echo "Apply recommendations: /agent-lightning apply"
        fi
        ;;

    status)
        agl_bridge_status
        ;;

    config)
        echo "Agent-Lightning Configuration"
        echo "=============================="
        echo ""
        echo "1. Enable/disable training"
        echo "2. Change algorithm (APO/VERL)"
        echo "3. Adjust reward shaping"
        echo "4. Set sync interval"
        echo "5. Training thresholds"
        echo "6. View current config"
        echo "7. Back"
        echo ""
        read -p "Enter choice: " choice

        case "${choice}" in
            1)
                current=$(jq -r '.training_enabled' "${CONFIG_PATH}")
                echo "Current: ${current}"
                read -p "Enable training? (true/false): " enable
                jq --argjson enable "${enable}" '.training_enabled = $enable' \
                    "${CONFIG_PATH}" | sponge "${CONFIG_PATH}"
                echo "✓ Training $([ "${enable}" = "true" ] && echo "enabled" || echo "disabled")"
                ;;
            2)
                current=$(jq -r '.algorithm' "${CONFIG_PATH}")
                echo "Current: ${current}"
                echo "Available: apo, verl"
                read -p "Algorithm: " algo
                jq --arg algo "${algo}" '.algorithm = $algo' \
                    "${CONFIG_PATH}" | sponge "${CONFIG_PATH}"
                echo "✓ Algorithm set to ${algo}"
                ;;
            3)
                echo "Reward Shaping Configuration"
                jq -r '.reward_shaping | to_entries[] | "\(.key): \(.value)"' "${CONFIG_PATH}"
                echo ""
                read -p "Reward to adjust: " reward_key
                read -p "New value: " reward_value
                jq --arg key "${reward_key}" --argjson val "${reward_value}" \
                    '.reward_shaping[$key] = $val' \
                    "${CONFIG_PATH}" | sponge "${CONFIG_PATH}"
                echo "✓ ${reward_key} set to ${reward_value}"
                ;;
            4)
                current=$(jq -r '.integration.sync_interval_seconds' "${CONFIG_PATH}")
                echo "Current: ${current}s"
                read -p "New interval (seconds): " interval
                jq --argjson interval "${interval}" \
                    '.integration.sync_interval_seconds = $interval' \
                    "${CONFIG_PATH}" | sponge "${CONFIG_PATH}"
                echo "✓ Sync interval set to ${interval}s"
                ;;
            5)
                current=$(jq -r '.integration.min_samples_for_training' "${CONFIG_PATH}")
                echo "Current: ${current} samples"
                read -p "Minimum samples for training: " samples
                jq --argjson samples "${samples}" \
                    '.integration.min_samples_for_training = $samples' \
                    "${CONFIG_PATH}" | sponge "${CONFIG_PATH}"
                echo "✓ Min samples set to ${samples}"
                ;;
            6)
                echo "Current Configuration:"
                jq . "${CONFIG_PATH}"
                ;;
        esac
        ;;

    apply)
        echo "Applying learned optimizations..."

        if [[ ! -f "${HOME}/.claude/data/agent-lightning/recommendations.json" ]]; then
            echo "No recommendations available. Run /agent-lightning train first."
            exit 1
        fi

        # Read recommendations
        recommendations=$(cat "${HOME}/.claude/data/agent-lightning/recommendations.json")

        # Apply cache recommendations
        cache_rec=$(echo "${recommendations}" | jq -r '.recommendations[] | select(.component == "cache")')
        if [[ -n "${cache_rec}" ]]; then
            action=$(echo "${cache_rec}" | jq -r '.recommended_action')
            if [[ "${action}" == "adjust_threshold" ]]; then
                current=$(echo "${cache_rec}" | jq -r '.current_value')
                target=0.65
                # Calculate new threshold to improve hit rate
                new_threshold=$(echo "${current} ${target}" | awk '{
                    if ($1 < $2) print 0.78
                    else print 0.85
                }')

                # Update cache config
                if [[ -f "${HOME}/.claude/data/cache-config.json" ]]; then
                    jq --argjson threshold "${new_threshold}" \
                        '.similarity_threshold = $threshold' \
                        "${HOME}/.claude/data/cache-config.json" | \
                        sponge "${HOME}/.claude/data/cache-config.json"
                    echo "✓ Cache threshold: ${new_threshold}"
                fi
            fi
        fi

        # Apply parallel recommendations
        parallel_rec=$(echo "${recommendations}" | jq -r '.recommendations[] | select(.component == "parallel")')
        if [[ -n "${parallel_rec}" ]]; then
            action=$(echo "${parallel_rec}" | jq -r '.recommended_action')
            if [[ "${action}" == "adjust_concurrency" ]]; then
                current=$(echo "${parallel_rec}" | jq -r '.current_value')
                # Increase concurrency if success rate is high
                if (( $(echo "${current} > 0.9" | bc -l) )); then
                    new_concurrent=6
                else
                    new_concurrent=4
                fi

                # Update parallel config
                if [[ -f "${HOME}/.claude/data/parallel-config.json" ]]; then
                    jq --argjson concurrent "${new_concurrent}" \
                        '.max_concurrent_processes = $concurrent' \
                        "${HOME}/.claude/data/parallel-config.json" | \
                        sponge "${HOME}/.claude/data/parallel-config.json"
                    echo "✓ Max concurrent processes: ${new_concurrent}"
                fi
            fi
        fi

        echo ""
        echo "✓ Optimizations applied successfully!"
        ;;

    dashboard)
        echo "Starting agent-lightning dashboard..."

        source "${HOME}/.claude/venv/bin/activate"

        # Check if dashboard is available
        if ! python3 -c "import agentlightning" 2>/dev/null; then
            echo "Error: agent-lightning not installed in venv"
            echo "Run: pip install agentlightning"
            exit 1
        fi

        echo "Note: Dashboard feature requires agent-lightning UI components"
        echo "This is a placeholder - implement full dashboard integration"
        echo ""
        echo "For now, view metrics at:"
        echo "  ~/.claude/data/agent-lightning/metrics.json"
        echo "  ~/.claude/data/agent-lightning/recommendations.json"

        deactivate
        ;;

    help|*)
        cat <<EOF
Agent-Lightning Integration

Usage: /agent-lightning <command>

Commands:
  init      - Initialize agent-lightning integration
  sync      - Sync learning data to agent-lightning
  train     - Run RL training on collected spans
  status    - View integration status and metrics
  config    - Configure integration settings
  apply     - Apply learned optimizations
  dashboard - Launch web dashboard (coming soon)
  help      - Show this help message

Examples:
  /agent-lightning init
  /agent-lightning sync
  /agent-lightning train
  /agent-lightning status

Documentation:
  ~/.claude/skills/agent-lightning-integration/skill.md

Resources:
  https://microsoft.github.io/agent-lightning/
EOF
        ;;
esac
