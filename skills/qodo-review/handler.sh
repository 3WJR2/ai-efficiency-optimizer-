#!/bin/bash

###############################################################################
# Qodo Review Skill Handler
#
# Integrates Qodo CLI code review into Claude Code workflow
###############################################################################

set -e

# Parse arguments
TYPE="${type:-security}"
FILES="${files:-}"
MODEL="${model:-}"
THRESHOLD="${threshold:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Emoji helpers
EMOJI_LOCK="🔒"
EMOJI_BOLT="⚡"
EMOJI_CHART="📊"
EMOJI_CHECK="✅"
EMOJI_CROSS="❌"
EMOJI_WARNING="⚠️"
EMOJI_CRITICAL="🔴"
EMOJI_ROBOT="🤖"

# Print header
print_header() {
    local review_name=$1
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${EMOJI_ROBOT} ${CYAN}Qodo AI Code Review${NC}                            ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  Review Type: ${YELLOW}${review_name}${NC}$(printf '%*s' $((39-${#review_name})) '')${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Check if Qodo is installed
if ! command -v qodo &> /dev/null; then
    echo -e "${RED}${EMOJI_CROSS} Error: Qodo CLI not installed${NC}"
    echo ""
    echo "Install with:"
    echo "  npm install -g @qodo/command"
    echo ""
    echo "Then authenticate:"
    echo "  qodo login"
    exit 1
fi

# Check if authenticated
if ! qodo --version &> /dev/null 2>&1; then
    if [ -z "$QODO_API_KEY" ] && [ ! -f "$HOME/.qodo/config" ]; then
        echo -e "${RED}${EMOJI_CROSS} Error: Not authenticated with Qodo${NC}"
        echo ""
        echo "Authenticate with:"
        echo "  qodo login"
        echo ""
        echo "Or set API key:"
        echo "  export QODO_API_KEY=your-key"
        exit 1
    fi
fi

# Build qodo command
QODO_CMD="qodo"

# Determine review type and emoji
case "$TYPE" in
    security|security-review)
        REVIEW_NAME="Security Review"
        EMOJI="${EMOJI_LOCK}"
        QODO_CMD="$QODO_CMD security-review"
        ;;
    performance|performance-review)
        REVIEW_NAME="Performance Review"
        EMOJI="${EMOJI_BOLT}"
        QODO_CMD="$QODO_CMD performance-review"
        ;;
    quality|code-quality-review)
        REVIEW_NAME="Code Quality Review"
        EMOJI="${EMOJI_CHART}"
        QODO_CMD="$QODO_CMD code-quality-review"
        ;;
    full|full-review)
        REVIEW_NAME="Comprehensive Review"
        EMOJI="${EMOJI_ROBOT}"
        QODO_CMD="$QODO_CMD chain \"security-review > performance-review > code-quality-review\""
        ;;
    *)
        # Custom agent name
        REVIEW_NAME="$TYPE"
        EMOJI="${EMOJI_ROBOT}"
        QODO_CMD="$QODO_CMD $TYPE"
        ;;
esac

# Print header
print_header "$REVIEW_NAME"

# Add model if specified
if [ -n "$MODEL" ]; then
    QODO_CMD="$QODO_CMD --model $MODEL"
    echo -e "${CYAN}Model:${NC} $MODEL"
fi

# Add threshold if specified
if [ -n "$THRESHOLD" ]; then
    QODO_CMD="$QODO_CMD --set $THRESHOLD"
    echo -e "${CYAN}Parameters:${NC} $THRESHOLD"
fi

# Add files if specified
if [ -n "$FILES" ]; then
    QODO_CMD="$QODO_CMD \"Review $FILES\""
    echo -e "${CYAN}Target:${NC} $FILES"
fi

# Add CI flags for cleaner output
QODO_CMD="$QODO_CMD --ci --yes"

echo ""
echo -e "${YELLOW}Running review...${NC}"
echo ""

# Create temp file for output
TEMP_OUTPUT=$(mktemp)

# Run qodo review
if eval "$QODO_CMD" > "$TEMP_OUTPUT" 2>&1; then
    REVIEW_EXIT_CODE=0
else
    REVIEW_EXIT_CODE=$?
fi

# Display output with formatting
if [ -s "$TEMP_OUTPUT" ]; then
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Review Results:${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""

    # Colorize output
    while IFS= read -r line; do
        if echo "$line" | grep -qi "critical"; then
            echo -e "${RED}${EMOJI_CRITICAL} $line${NC}"
        elif echo "$line" | grep -qi "high"; then
            echo -e "${YELLOW}${EMOJI_WARNING} $line${NC}"
        elif echo "$line" | grep -qi "medium\|moderate"; then
            echo -e "${YELLOW}$line${NC}"
        elif echo "$line" | grep -qi "low"; then
            echo -e "${CYAN}$line${NC}"
        elif echo "$line" | grep -qi "passed\|success\|✓"; then
            echo -e "${GREEN}${EMOJI_CHECK} $line${NC}"
        else
            echo "$line"
        fi
    done < "$TEMP_OUTPUT"

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
fi

# Check for critical issues
CRITICAL_COUNT=$(grep -ic "critical" "$TEMP_OUTPUT" 2>/dev/null || echo 0)
HIGH_COUNT=$(grep -ic "high" "$TEMP_OUTPUT" 2>/dev/null || echo 0)

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${CYAN}Summary${NC}                                              ${BLUE}║${NC}"
echo -e "${BLUE}╠════════════════════════════════════════════════════════╣${NC}"

if [ "$CRITICAL_COUNT" -gt 0 ]; then
    echo -e "${BLUE}║${NC}  ${RED}${EMOJI_CRITICAL} Critical Issues: ${CRITICAL_COUNT}${NC}$(printf '%*s' $((35-${#CRITICAL_COUNT})) '')${BLUE}║${NC}"
fi

if [ "$HIGH_COUNT" -gt 0 ]; then
    echo -e "${BLUE}║${NC}  ${YELLOW}${EMOJI_WARNING} High Priority: ${HIGH_COUNT}${NC}$(printf '%*s' $((37-${#HIGH_COUNT})) '')${BLUE}║${NC}"
fi

if [ "$CRITICAL_COUNT" -eq 0 ] && [ "$HIGH_COUNT" -eq 0 ]; then
    echo -e "${BLUE}║${NC}  ${GREEN}${EMOJI_CHECK} No critical or high issues found${NC}               ${BLUE}║${NC}"
fi

echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Next steps
if [ "$CRITICAL_COUNT" -gt 0 ] || [ "$HIGH_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}${EMOJI_WARNING} Action Required:${NC}"
    echo "  • Review and fix critical/high priority issues"
    echo "  • Run specific review: /qodo-review type=<review-type>"
    echo "  • View full details in output above"
    echo ""
fi

# Save full output to file
OUTPUT_FILE="qodo-review-$(date +%Y%m%d-%H%M%S).txt"
cp "$TEMP_OUTPUT" "$OUTPUT_FILE"
echo -e "${CYAN}Full review saved to:${NC} $OUTPUT_FILE"
echo ""

# Cleanup
rm -f "$TEMP_OUTPUT"

# Exit with appropriate code
if [ "$CRITICAL_COUNT" -gt 0 ]; then
    echo -e "${RED}${EMOJI_CROSS} Review completed with critical issues${NC}"
    exit 1
elif [ "$REVIEW_EXIT_CODE" -ne 0 ]; then
    echo -e "${YELLOW}${EMOJI_WARNING} Review completed with warnings${NC}"
    exit 0
else
    echo -e "${GREEN}${EMOJI_CHECK} Review completed successfully${NC}"
    exit 0
fi
