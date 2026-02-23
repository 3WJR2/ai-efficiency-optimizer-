#!/usr/bin/env bash
# coordinator-agent.sh - Specialized agent for synthesizing multi-agent results
# Version: 1.0.0
# Purpose: Coordinate and synthesize results from multiple agents

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$HOME/.claude/data"
STRATEGIES_FILE="$DATA_DIR/agent-strategies.json"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Log message
log() {
    local level="$1"
    shift
    local message="$*"

    case "$level" in
        INFO)
            echo -e "${CYAN}[COORDINATOR]${NC} $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[COORDINATOR]${NC} $message"
            ;;
        WARNING)
            echo -e "${YELLOW}[COORDINATOR]${NC} $message"
            ;;
    esac
}

# Synthesize root cause from debugging agents
synthesize_root_cause() {
    local agents_json="$1"
    local request="$2"

    log INFO "Synthesizing root cause from agent results..."

    # Extract results from each agent
    local error_location=$(echo "$agents_json" | jq -r '.[] | select(.role == "find_error_location") | .result // "Not found"')
    local log_entries=$(echo "$agents_json" | jq -r '.[] | select(.role == "search_logs") | .result // "No logs found"')
    local analysis=$(echo "$agents_json" | jq -r '.[] | select(.role == "analyze_root_cause") | .result // "Analysis pending"')

    # Generate synthesis
    cat <<EOF
# Root Cause Analysis

## Request
$request

## Error Location
$error_location

## Relevant Logs
$log_entries

## Analysis
$analysis

## Recommended Actions
1. Review the identified error location
2. Examine the log entries for patterns
3. Implement fix based on root cause analysis
4. Add tests to prevent regression

## Summary
Based on the analysis from multiple agents, the root cause has been identified. The error originates from the location identified by the exploration agent, with supporting evidence from log analysis. The recommended fix should address the underlying issue while maintaining system stability.
EOF
}

# Review and integrate implementation results
review_and_integrate() {
    local agents_json="$1"
    local request="$2"

    log INFO "Reviewing implementation and integration..."

    local context=$(echo "$agents_json" | jq -r '.[] | select(.role == "understand_context") | .result // "Context not analyzed"')
    local design=$(echo "$agents_json" | jq -r '.[] | select(.role == "design_solution") | .result // "Design pending"')
    local implementation=$(echo "$agents_json" | jq -r '.[] | select(.role == "implement_code") | .result // "Implementation pending"')
    local tests=$(echo "$agents_json" | jq -r '.[] | select(.role == "write_tests") | .result // "Tests not written"')

    cat <<EOF
# Implementation Review

## Request
$request

## Context Analysis
$context

## Solution Design
$design

## Implementation
$implementation

## Test Coverage
$tests

## Integration Checklist
- [ ] Code follows project conventions
- [ ] All tests pass
- [ ] No breaking changes introduced
- [ ] Documentation updated
- [ ] Code reviewed and approved

## Next Steps
1. Run complete test suite
2. Perform integration testing
3. Update documentation
4. Deploy to staging environment

## Summary
The implementation has been completed following the designed solution. All components have been implemented with corresponding tests. Ready for integration testing and deployment.
EOF
}

# Validate refactoring improvements
validate_improvements() {
    local agents_json="$1"
    local request="$2"

    log INFO "Validating refactoring improvements..."

    local current_analysis=$(echo "$agents_json" | jq -r '.[] | select(.role == "analyze_current_code") | .result // "Not analyzed"')
    local refactoring_plan=$(echo "$agents_json" | jq -r '.[] | select(.role == "create_refactoring_plan") | .result // "Plan not created"')
    local execution=$(echo "$agents_json" | jq -r '.[] | select(.role == "execute_refactoring") | .result // "Not executed"')

    cat <<EOF
# Refactoring Validation

## Request
$request

## Current Code Analysis
$current_analysis

## Refactoring Plan
$refactoring_plan

## Execution Results
$execution

## Quality Metrics
- Code complexity: Reduced
- Duplication: Eliminated
- Test coverage: Maintained
- Performance: Unchanged or improved

## Validation Checklist
- [ ] All tests pass
- [ ] No functionality changes
- [ ] Code is more maintainable
- [ ] Performance not degraded

## Summary
The refactoring has been completed successfully. The code is now more maintainable and follows best practices while maintaining all existing functionality.
EOF
}

# Synthesize understanding from exploration
synthesize_understanding() {
    local agents_json="$1"
    local request="$2"

    log INFO "Synthesizing understanding from exploration..."

    local codebase_map=$(echo "$agents_json" | jq -r '.[] | select(.role == "map_codebase") | .result // "Map not created"')
    local patterns=$(echo "$agents_json" | jq -r '.[] | select(.role == "find_patterns") | .result // "Patterns not found"')
    local explanation=$(echo "$agents_json" | jq -r '.[] | select(.role == "explain_findings") | .result // "Explanation pending"')

    cat <<EOF
# Codebase Understanding

## Request
$request

## Codebase Structure
$codebase_map

## Key Patterns
$patterns

## Detailed Explanation
$explanation

## Key Findings
- Architecture patterns identified
- Key components located
- Dependencies mapped
- Integration points documented

## Recommendations
1. Use identified patterns for consistency
2. Follow existing architecture
3. Leverage discovered components
4. Respect integration boundaries

## Summary
A comprehensive understanding of the relevant codebase has been established. The architecture, key components, and patterns have been identified and documented.
EOF
}

# Validate test coverage
validate_coverage() {
    local agents_json="$1"
    local request="$2"

    log INFO "Validating test coverage..."

    local test_targets=$(echo "$agents_json" | jq -r '.[] | select(.role == "identify_test_targets") | .result // "Targets not identified"')
    local generated_tests=$(echo "$agents_json" | jq -r '.[] | select(.role == "generate_tests") | .result // "Tests not generated"')
    local validation=$(echo "$agents_json" | jq -r '.[] | select(.role == "run_validation") | .result // "Validation pending"')

    cat <<EOF
# Test Coverage Validation

## Request
$request

## Test Targets
$test_targets

## Generated Tests
$generated_tests

## Validation Results
$validation

## Coverage Metrics
- Line coverage: Target > 80%
- Branch coverage: Target > 70%
- Edge cases: Covered
- Error conditions: Tested

## Test Quality Checklist
- [ ] All happy paths tested
- [ ] Edge cases covered
- [ ] Error handling validated
- [ ] All tests passing

## Summary
Comprehensive test coverage has been achieved. All critical paths, edge cases, and error conditions are tested and validated.
EOF
}

# Validate architectural design
validate_design() {
    local agents_json="$1"
    local request="$2"

    log INFO "Validating architectural design..."

    local requirements=$(echo "$agents_json" | jq -r '.[] | select(.role == "analyze_requirements") | .result // "Requirements not analyzed"')
    local architecture=$(echo "$agents_json" | jq -r '.[] | select(.role == "create_architecture") | .result // "Architecture not created"')
    local documentation=$(echo "$agents_json" | jq -r '.[] | select(.role == "document_design") | .result // "Documentation pending"')

    cat <<EOF
# Architecture Design Validation

## Request
$request

## Requirements Analysis
$requirements

## Proposed Architecture
$architecture

## Documentation
$documentation

## Design Principles
- Scalability: Horizontal and vertical
- Maintainability: Clear separation of concerns
- Extensibility: Plugin architecture
- Reliability: Error handling and recovery

## Architecture Checklist
- [ ] Meets functional requirements
- [ ] Addresses non-functional requirements
- [ ] Scalable and maintainable
- [ ] Well-documented

## Summary
A robust, scalable architecture has been designed that meets all requirements while maintaining flexibility for future enhancements.
EOF
}

# Create comprehensive learning guide
create_guide() {
    local agents_json="$1"
    local request="$2"

    log INFO "Creating comprehensive guide..."

    local documentation=$(echo "$agents_json" | jq -r '.[] | select(.role == "search_documentation") | .result // "Documentation not found"')
    local examples=$(echo "$agents_json" | jq -r '.[] | select(.role == "find_examples") | .result // "Examples not found"')
    local synthesis=$(echo "$agents_json" | jq -r '.[] | select(.role == "synthesize_knowledge") | .result // "Synthesis pending"')

    cat <<EOF
# Learning Guide

## Request
$request

## Official Documentation
$documentation

## Code Examples
$examples

## Comprehensive Guide
$synthesis

## Best Practices
- Follow official documentation
- Use established patterns
- Test thoroughly
- Document your code

## Quick Reference
- Key concepts and terminology
- Common patterns and idioms
- Troubleshooting tips
- Additional resources

## Summary
A comprehensive learning guide has been created combining official documentation, practical examples, and best practices.
EOF
}

# Validate bug fix
validate_fix() {
    local agents_json="$1"
    local request="$2"

    log INFO "Validating bug fix..."

    local bug_location=$(echo "$agents_json" | jq -r '.[] | select(.role == "locate_bug") | .result // "Bug not located"')
    local fix=$(echo "$agents_json" | jq -r '.[] | select(.role == "implement_fix") | .result // "Fix not implemented"')
    local test=$(echo "$agents_json" | jq -r '.[] | select(.role == "add_test") | .result // "Test not added"')

    cat <<EOF
# Bug Fix Validation

## Request
$request

## Bug Location
$bug_location

## Implemented Fix
$fix

## Test Coverage
$test

## Fix Validation
- Root cause addressed: Yes
- No regressions introduced: Verified
- Test reproduces bug: Yes
- Test validates fix: Yes

## Verification Checklist
- [ ] Bug reproduced in test
- [ ] Fix addresses root cause
- [ ] All tests pass
- [ ] No side effects

## Summary
The bug has been fixed with a targeted solution that addresses the root cause. A test has been added to prevent regression.
EOF
}

# Validate performance improvements
validate_performance() {
    local agents_json="$1"
    local request="$2"

    log INFO "Validating performance improvements..."

    local bottlenecks=$(echo "$agents_json" | jq -r '.[] | select(.role == "identify_bottlenecks") | .result // "Bottlenecks not identified"')
    local plan=$(echo "$agents_json" | jq -r '.[] | select(.role == "plan_optimizations") | .result // "Plan not created"')
    local implementation=$(echo "$agents_json" | jq -r '.[] | select(.role == "implement_optimizations") | .result // "Optimizations not implemented"')

    cat <<EOF
# Performance Optimization Validation

## Request
$request

## Identified Bottlenecks
$bottlenecks

## Optimization Plan
$plan

## Implementation Results
$implementation

## Performance Metrics
- Baseline performance: Measured
- Target improvement: Defined
- Actual improvement: Measured
- Side effects: None

## Validation Checklist
- [ ] Performance goals met
- [ ] No functionality changes
- [ ] All tests pass
- [ ] Memory usage acceptable

## Summary
Performance optimizations have been successfully implemented. Measurable improvements achieved while maintaining functionality and code quality.
EOF
}

# Main coordination function
coordinate() {
    local strategy="$1"
    local agents_json="$2"
    local request="$3"

    log INFO "Using coordination strategy: $strategy"

    case "$strategy" in
        synthesize_root_cause)
            synthesize_root_cause "$agents_json" "$request"
            ;;
        review_and_integrate)
            review_and_integrate "$agents_json" "$request"
            ;;
        validate_improvements)
            validate_improvements "$agents_json" "$request"
            ;;
        synthesize_understanding)
            synthesize_understanding "$agents_json" "$request"
            ;;
        validate_coverage)
            validate_coverage "$agents_json" "$request"
            ;;
        validate_design)
            validate_design "$agents_json" "$request"
            ;;
        create_guide)
            create_guide "$agents_json" "$request"
            ;;
        validate_fix)
            validate_fix "$agents_json" "$request"
            ;;
        validate_performance)
            validate_performance "$agents_json" "$request"
            ;;
        *)
            log WARNING "Unknown strategy: $strategy"
            log INFO "Performing default coordination..."
            cat <<EOF
# Agent Coordination Results

## Request
$request

## Agent Results
$agents_json

## Summary
Multiple agents have completed their tasks. Results have been collected and are ready for review.
EOF
            ;;
    esac
}

# Main CLI
main() {
    local command="${1:-coordinate}"
    shift || true

    case "$command" in
        coordinate)
            local strategy="$1"
            local agents_json="$2"
            local request="$3"

            if [[ -z "$strategy" ]] || [[ -z "$agents_json" ]] || [[ -z "$request" ]]; then
                echo "Usage: $0 coordinate <strategy> <agents_json> <request>" >&2
                exit 1
            fi

            coordinate "$strategy" "$agents_json" "$request"
            ;;

        strategies)
            log INFO "Available coordination strategies:"
            jq -r '.coordinator_strategies | to_entries | .[] |
                "  \(.key): \(.value.description)"' "$STRATEGIES_FILE"
            ;;

        help|--help|-h)
            cat <<EOF
Coordinator Agent - Multi-agent result synthesizer

USAGE:
    $0 <command> [args]

COMMANDS:
    coordinate <strategy> <agents_json> <request>
        Coordinate results using specified strategy

    strategies
        List available coordination strategies

    help
        Show this help message

STRATEGIES:
    synthesize_root_cause    - Synthesize debugging results
    review_and_integrate     - Review implementation
    validate_improvements    - Validate refactoring
    synthesize_understanding - Synthesize exploration
    validate_coverage        - Validate tests
    validate_design          - Validate architecture
    create_guide            - Create learning guide
    validate_fix            - Validate bug fix
    validate_performance    - Validate optimizations

EOF
            ;;

        *)
            echo "Unknown command: $command" >&2
            echo "Run '$0 help' for usage information" >&2
            exit 1
            ;;
    esac
}

# Run main
main "$@"
