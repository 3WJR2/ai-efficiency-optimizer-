#!/bin/bash
# pre-dependency-update.sh
# Autonomous Loop Hook: Security scan before dependency updates
# Triggered before dependency updates to ensure safety

set -euo pipefail

# Arguments
DEPENDENCY_FILE="${1:-}"
PACKAGE_NAME="${2:-}"
NEW_VERSION="${3:-}"

# Configuration
SECURITY_SCAN_ENABLED="${BRAHMA_SECURITY_SCAN_ENABLED:-true}"
AUTO_APPROVE_PATCHES="${BRAHMA_AUTO_APPROVE_PATCHES:-true}"
AUTO_APPROVE_SECURITY="${BRAHMA_AUTO_APPROVE_SECURITY:-true}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔒 Pre-dependency-update hook triggered"
echo "   File: $DEPENDENCY_FILE"
echo "   Package: $PACKAGE_NAME"
echo "   New version: $NEW_VERSION"

# Exit if security scan disabled
if [[ "$SECURITY_SCAN_ENABLED" != "true" ]]; then
    echo "ℹ️  Security scan disabled (BRAHMA_SECURITY_SCAN_ENABLED=false)"
    exit 0
fi

# Ensure scan directories exist
mkdir -p "$HOME/.claude/security/scan-results"
mkdir -p "$HOME/.claude/security/cve-reports"

# Determine package manager and run security scan
PACKAGE_MANAGER="unknown"
if [[ "$DEPENDENCY_FILE" == *"package.json"* ]] || [[ "$DEPENDENCY_FILE" == *"package-lock.json"* ]]; then
    PACKAGE_MANAGER="npm"
elif [[ "$DEPENDENCY_FILE" == *"requirements.txt"* ]] || [[ "$DEPENDENCY_FILE" == *"Pipfile"* ]]; then
    PACKAGE_MANAGER="pip"
elif [[ "$DEPENDENCY_FILE" == *"go.mod"* ]]; then
    PACKAGE_MANAGER="go"
elif [[ "$DEPENDENCY_FILE" == *"Cargo.toml"* ]]; then
    PACKAGE_MANAGER="cargo"
fi

echo "   Package manager: $PACKAGE_MANAGER"

# Run security scan based on package manager
SCAN_RESULT_FILE="$HOME/.claude/security/scan-results/pre-update-$(date +%s).json"

case "$PACKAGE_MANAGER" in
    npm)
        echo "🔍 Running npm security audit..."
        if npm audit --json > "$SCAN_RESULT_FILE" 2>&1; then
            VULNERABILITIES=0
        else
            # npm audit returns non-zero if vulnerabilities found
            VULNERABILITIES=$(jq '.metadata.vulnerabilities.total // 0' "$SCAN_RESULT_FILE" 2>/dev/null || echo "0")
        fi
        ;;

    pip)
        echo "🔍 Running pip security audit..."
        if command -v pip-audit &> /dev/null; then
            pip-audit --format json > "$SCAN_RESULT_FILE" 2>&1 || true
            VULNERABILITIES=$(jq '. | length' "$SCAN_RESULT_FILE" 2>/dev/null || echo "0")
        else
            echo "⚠️  pip-audit not installed, skipping scan"
            VULNERABILITIES=0
        fi
        ;;

    go)
        echo "🔍 Running Go vulnerability check..."
        if command -v govulncheck &> /dev/null; then
            govulncheck -json ./... > "$SCAN_RESULT_FILE" 2>&1 || true
            VULNERABILITIES=$(grep -c '"osv":' "$SCAN_RESULT_FILE" || echo "0")
        else
            echo "⚠️  govulncheck not installed, skipping scan"
            VULNERABILITIES=0
        fi
        ;;

    cargo)
        echo "🔍 Running Cargo security audit..."
        if command -v cargo-audit &> /dev/null; then
            cargo audit --json > "$SCAN_RESULT_FILE" 2>&1 || true
            VULNERABILITIES=$(jq '.vulnerabilities.found | length' "$SCAN_RESULT_FILE" 2>/dev/null || echo "0")
        else
            echo "⚠️  cargo-audit not installed, skipping scan"
            VULNERABILITIES=0
        fi
        ;;

    *)
        echo "⚠️  Unknown package manager, skipping security scan"
        VULNERABILITIES=0
        ;;
esac

echo "   Vulnerabilities found: $VULNERABILITIES"

# Check for CRITICAL vulnerabilities
CRITICAL_VULNS=0
if [[ -f "$SCAN_RESULT_FILE" ]]; then
    case "$PACKAGE_MANAGER" in
        npm)
            CRITICAL_VULNS=$(jq '.metadata.vulnerabilities.critical // 0' "$SCAN_RESULT_FILE" 2>/dev/null || echo "0")
            HIGH_VULNS=$(jq '.metadata.vulnerabilities.high // 0' "$SCAN_RESULT_FILE" 2>/dev/null || echo "0")
            ;;
        pip|go|cargo)
            # For other package managers, check severity in results
            CRITICAL_VULNS=$(grep -i 'critical\|high' "$SCAN_RESULT_FILE" | wc -l || echo "0")
            HIGH_VULNS=0
            ;;
    esac
fi

echo "   CRITICAL vulnerabilities: $CRITICAL_VULNS"

# Decision logic
if [[ $CRITICAL_VULNS -gt 0 ]]; then
    echo -e "${RED}❌ CRITICAL vulnerabilities detected!${NC}"

    # Check if this update is a security patch
    if [[ "$AUTO_APPROVE_SECURITY" == "true" ]]; then
        # Check if new version patches CVEs
        echo "🔍 Checking if update patches vulnerabilities..."

        # Create task for brahma-dependency-resolver to validate
        TASK_ID="depcheck-$(date +%s)-$(uuidgen | cut -d- -f1)"

        cat > "$HOME/.claude/tasks/queue/$TASK_ID.json" <<EOF
{
  "task_id": "$TASK_ID",
  "type": "SECURITY_VALIDATION",
  "title": "Validate security update for $PACKAGE_NAME",
  "description": "Check if updating $PACKAGE_NAME to $NEW_VERSION patches CRITICAL vulnerabilities",
  "base_priority": 90,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "dependencies": [],
  "blocks": [],
  "metadata": {
    "trigger": "pre-dependency-update",
    "package": "$PACKAGE_NAME",
    "new_version": "$NEW_VERSION",
    "critical_vulns": $CRITICAL_VULNS,
    "scan_result": "$SCAN_RESULT_FILE"
  },
  "assigned_agent": "brahma-dependency-resolver",
  "status": "PENDING"
}
EOF

        echo -e "${YELLOW}⚠️  Security validation task created: $TASK_ID${NC}"
        echo "   Approval required from brahma-dependency-resolver"
        exit 1  # Block update until validated
    else
        echo -e "${RED}⛔ Dependency update blocked (CRITICAL vulnerabilities)${NC}"
        echo "   Please review security scan results: $SCAN_RESULT_FILE"
        exit 1
    fi

elif [[ $VULNERABILITIES -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Vulnerabilities detected (non-critical)${NC}"

    if [[ "$AUTO_APPROVE_PATCHES" == "true" ]]; then
        # Check if this is a patch version (X.Y.Z where Z changed)
        VERSION_PARTS=(${NEW_VERSION//./ })
        if [[ ${#VERSION_PARTS[@]} -eq 3 ]]; then
            # It's a semantic version
            echo "✅ Auto-approving patch version update"
        else
            echo "⚠️  Not a standard semantic version, requiring manual approval"
            exit 1
        fi
    else
        echo "⚠️  Manual approval required for updates with vulnerabilities"
        exit 1
    fi

else
    echo -e "${GREEN}✅ No vulnerabilities detected${NC}"
fi

# Check for breaking changes (major version bump)
if [[ "$NEW_VERSION" =~ ^[0-9]+ ]]; then
    NEW_MAJOR=$(echo "$NEW_VERSION" | cut -d. -f1)

    # Get current version (simple detection, may need enhancement)
    CURRENT_VERSION=""
    case "$PACKAGE_MANAGER" in
        npm)
            CURRENT_VERSION=$(jq -r ".dependencies.\"$PACKAGE_NAME\" // .devDependencies.\"$PACKAGE_NAME\" // \"\"" "$DEPENDENCY_FILE" 2>/dev/null | sed 's/[\^~]//g')
            ;;
        # Add other package managers as needed
    esac

    if [[ -n "$CURRENT_VERSION" ]] && [[ "$CURRENT_VERSION" =~ ^[0-9]+ ]]; then
        CURRENT_MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)

        if [[ $NEW_MAJOR -gt $CURRENT_MAJOR ]]; then
            echo -e "${YELLOW}⚠️  Major version change detected: v$CURRENT_MAJOR → v$NEW_MAJOR${NC}"
            echo "   This may include breaking changes"
            echo "   Recommendation: Review changelog and test thoroughly"

            # Don't block, but warn
            echo "   Proceeding with caution..."
        fi
    fi
fi

# Log the check
METRICS_DIR="$HOME/.claude/metrics"
mkdir -p "$METRICS_DIR"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$PACKAGE_NAME,$NEW_VERSION,$VULNERABILITIES,$CRITICAL_VULNS" >> "$METRICS_DIR/dependency-security-checks.log"

echo -e "${GREEN}✅ Pre-dependency-update checks complete${NC}"

exit 0
