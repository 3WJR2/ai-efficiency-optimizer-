#!/bin/bash
# List available custom Claude skills
# Usage: ~/.claude/scripts/list-skills.sh [search_term]

SKILLS_DIR="$HOME/.claude/skills"
SEARCH_TERM="${1:-}"

echo "=================================================="
echo "Available Claude Skills"
echo "=================================================="
echo ""

# Function to extract description from skill.md
get_description() {
    local skill_file="$1"
    if [ -f "$skill_file" ]; then
        # Try to get first line with description
        grep -m 1 "^#\|Description:" "$skill_file" | sed 's/^#*\s*//' | sed 's/Description:\s*//' | head -c 80
    else
        echo "No description"
    fi
}

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

count=0

for skill_dir in "$SKILLS_DIR"/*; do
    if [ -d "$skill_dir" ]; then
        skill_name=$(basename "$skill_dir")

        # Filter by search term if provided
        if [ -n "$SEARCH_TERM" ] && [[ ! "$skill_name" =~ $SEARCH_TERM ]]; then
            continue
        fi

        skill_md="$skill_dir/skill.md"
        skill_sh="$skill_dir/skill.sh"

        description=$(get_description "$skill_md")

        echo -e "${GREEN}/$skill_name${NC}"
        echo -e "  ${BLUE}Description:${NC} $description"

        # Show available commands if skill.sh exists
        if [ -f "$skill_sh" ]; then
            echo -e "  ${YELLOW}Type:${NC} Shell-based skill"
            # Try to extract subcommands
            subcommands=$(grep -E "^\s*case.*in$" "$skill_sh" -A 20 | grep -E "^\s*[a-z-]+\)" | sed 's/)//' | tr -d ' ' | head -5)
            if [ -n "$subcommands" ]; then
                echo -e "  ${YELLOW}Subcommands:${NC} $(echo $subcommands | tr '\n' ', ' | sed 's/,$//')"
            fi
        fi

        echo ""
        ((count++))
    fi
done

echo "=================================================="
echo "Total skills found: $count"
echo "=================================================="
echo ""
echo "Usage examples:"
echo "  Type your request and mention the skill name"
echo "  Example: 'use adaptive-intelligence to analyze my code'"
echo ""
echo "To search: $0 <search_term>"
echo "  Example: $0 adaptive"
