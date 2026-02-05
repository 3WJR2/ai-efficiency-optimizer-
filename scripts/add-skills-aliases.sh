#!/bin/bash
# Add convenient aliases for Claude skills to ~/.zshrc

ZSHRC="$HOME/.zshrc"
MARKER="# Claude Skills Aliases"

# Check if aliases already exist
if grep -q "$MARKER" "$ZSHRC" 2>/dev/null; then
    echo "Skills aliases already exist in ~/.zshrc"
    echo "Remove them manually if you want to regenerate"
    exit 0
fi

cat << 'EOF' >> "$ZSHRC"

# Claude Skills Aliases
alias skills='~/.claude/scripts/skills-quickref.sh'
alias skills-help='~/.claude/scripts/skills-quickref.sh'
alias skills-list='~/.claude/scripts/list-skills.sh'
alias skills-search='~/.claude/scripts/list-skills.sh'

EOF

echo "✓ Added skills aliases to ~/.zshrc"
echo ""
echo "Run: source ~/.zshrc"
echo "Then try: skills"
