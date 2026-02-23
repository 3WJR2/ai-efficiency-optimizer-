#!/bin/bash

set -e

TYPE="${type:-tests}"
TARGET="${target:-}"
COVERAGE="${coverage:-0.9}"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "  🤖 ${CYAN}Qodo Code Generation${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

case "$TYPE" in
    tests)
        echo -e "${CYAN}Generating unit tests...${NC}"
        if [ -n "$TARGET" ]; then
            qodo test-generator "Generate comprehensive unit tests for $TARGET with ${COVERAGE} coverage" --ci --yes
        else
            qodo test-generator --set coverage_threshold="$COVERAGE" --ci --yes
        fi
        ;;
    e2e-tests)
        echo -e "${CYAN}Generating E2E tests...${NC}"
        if [ -n "$TARGET" ]; then
            qodo e2e-test-generator "Generate E2E test scenarios for: $TARGET" --ci --yes
        else
            qodo e2e-test-generator --ci --yes
        fi
        ;;
    docs)
        echo -e "${CYAN}Generating documentation...${NC}"
        if [ -n "$TARGET" ]; then
            qodo doc-generator "Generate comprehensive documentation for $TARGET" --ci --yes
        else
            qodo doc-generator --ci --yes
        fi
        ;;
    api-docs)
        echo -e "${CYAN}Generating API documentation...${NC}"
        qodo doc-generator "Generate OpenAPI 3.0 specification for all API endpoints" --ci --yes
        ;;
    changelog)
        echo -e "${CYAN}Generating changelog...${NC}"
        qodo changelog-generator --ci --yes
        ;;
    *)
        echo "Unknown type: $TYPE"
        echo "Valid types: tests, e2e-tests, docs, api-docs, changelog"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}✅ Generation complete${NC}"
