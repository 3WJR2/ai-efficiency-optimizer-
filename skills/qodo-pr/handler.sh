#!/bin/bash

set -e

POST_COMMENT="${post_comment:-false}"
PR_ID="${pr_id:-}"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  🤖 ${CYAN}Qodo Comprehensive PR Review${NC}                     ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Run comprehensive review
echo -e "${YELLOW}Running comprehensive review...${NC}"
echo ""

TEMP_OUTPUT=$(mktemp)
qodo chain "security-review > performance-review > code-quality-review" \
    --ci --yes > "$TEMP_OUTPUT" 2>&1 || true

# Analyze results
CRITICAL=$(grep -ic "critical" "$TEMP_OUTPUT" 2>/dev/null || echo 0)
HIGH=$(grep -ic "high" "$TEMP_OUTPUT" 2>/dev/null || echo 0)
MEDIUM=$(grep -ic "medium" "$TEMP_OUTPUT" 2>/dev/null || echo 0)

echo -e "${CYAN}Review Results:${NC}"
echo ""
cat "$TEMP_OUTPUT"
echo ""

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${CYAN}Summary${NC}                                              ${BLUE}║${NC}"
echo -e "${BLUE}╠════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC}  🔴 Critical: $CRITICAL                                      ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  ⚠️  High: $HIGH                                           ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  🟡 Medium: $MEDIUM                                        ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Recommendation
if [ "$CRITICAL" -gt 0 ]; then
    echo -e "${RED}❌ Recommendation: DO NOT MERGE - Critical issues found${NC}"
    RECOMMENDATION="REJECT"
elif [ "$HIGH" -gt 3 ]; then
    echo -e "${YELLOW}⚠️  Recommendation: REQUEST CHANGES - Multiple high priority issues${NC}"
    RECOMMENDATION="REQUEST_CHANGES"
elif [ "$HIGH" -gt 0 ]; then
    echo -e "${YELLOW}✓ Recommendation: APPROVE WITH COMMENTS - Minor improvements needed${NC}"
    RECOMMENDATION="APPROVE_WITH_COMMENTS"
else
    echo -e "${GREEN}✅ Recommendation: APPROVE - No significant issues${NC}"
    RECOMMENDATION="APPROVE"
fi

# Post to PR if requested
if [ "$POST_COMMENT" = "true" ] && [ -n "$PR_ID" ]; then
    echo ""
    echo -e "${CYAN}Posting review to Azure DevOps PR #${PR_ID}...${NC}"

    if [ -f "/Users/wallonwalusayi/qodo-demo-repo/scripts/qodo-pr-review.sh" ]; then
        bash /Users/wallonwalusayi/qodo-demo-repo/scripts/qodo-pr-review.sh "$PR_ID" full
        echo -e "${GREEN}✅ Review posted to PR${NC}"
    else
        echo -e "${YELLOW}⚠️  PR review script not found${NC}"
    fi
fi

rm -f "$TEMP_OUTPUT"

[ "$RECOMMENDATION" = "REJECT" ] && exit 1 || exit 0
