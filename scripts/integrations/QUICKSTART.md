# Quick Start Guide - SE Demo Prep

Get from customer name to demo-ready in 15 minutes.

## 1. One-Time Setup (5 minutes)

### Install Dependencies

```bash
pip3 install requests
```

### Configure Credentials

Create files in `~/.claude/credentials/`:

```bash
# Create credentials directory
mkdir -p ~/.claude/credentials

# Add your API keys
cat > ~/.claude/credentials/gong.json << EOF
{
  "api_key": "your-gong-api-key"
}
EOF

cat > ~/.claude/credentials/hubspot.json << EOF
{
  "access_token": "your-hubspot-token"
}
EOF

cat > ~/.claude/credentials/github.json << EOF
{
  "api_key": "your-github-personal-access-token"
}
EOF

# Qodo is optional (uses embedded catalog)
cat > ~/.claude/credentials/qodo.json << EOF
{
  "api_key": "optional"
}
EOF

# Secure the files
chmod 600 ~/.claude/credentials/*.json
```

### Test Connections

```bash
~/.claude/scripts/se-demo-prep.sh test
```

Expected output:
```
═══════════════════════════════════════════════════════════
  Testing Connections
═══════════════════════════════════════════════════════════

ℹ Testing gong_client...
✅ Connected: True
✅ Message: Successfully connected to Gong API

ℹ Testing hubspot_client...
✅ Connected: True
✅ Message: Successfully connected to HubSpot API

ℹ Testing github_client...
✅ Connected: True
✅ Message: Successfully connected to GitHub as wallonwalusayi

ℹ Testing qodo_client...
✅ Connected: True
✅ Message: Using embedded Qodo product catalog
```

## 2. Gather Customer Context (2-3 minutes)

### Basic Usage

```bash
# Just company name (GitHub org derived from name)
~/.claude/scripts/se-demo-prep.sh gather "Acme Corp"
```

### With GitHub Organization

```bash
# Specify GitHub org explicitly
~/.claude/scripts/se-demo-prep.sh gather "TechCo" techco-org
```

### With Specific Repository

```bash
# Focus on specific repo
~/.claude/scripts/se-demo-prep.sh gather "StartupInc" startupinc-org backend-api
```

### What Happens

1. **Parallel data fetching** from all 4 sources (~2-3 seconds)
2. **Context unification** and enrichment
3. **Pain point extraction** from Gong calls
4. **Tech stack detection** from GitHub
5. **Deal analysis** from HubSpot
6. **Product recommendations** generated
7. **Demo script** automatically created
8. **Executive summary** prepared

### Example Output

```
═══════════════════════════════════════════════════════════
  Testing Connections
═══════════════════════════════════════════════════════════

4/4 integrations connected

═══════════════════════════════════════════════════════════
  Gathering Customer Context
═══════════════════════════════════════════════════════════

🔍 Gathering context for: TechCo
   GitHub org: techco-org
   Parallel fetching: true

✅ Gong: Success
✅ HubSpot: Success
✅ GitHub: Success
✅ Qodo: Success

═══════════════════════════════════════════════════════════
  Executive Summary
═══════════════════════════════════════════════════════════

Company: TechCo
Data Completeness: Complete (100%)
Demo Readiness: Ready (100%)

Key Insights:
  • Deal stage: demo
  • 5 pain points identified
  • Primary language: Python
  • 3 Qodo products recommended

✅ Context exported to: ~/.claude/data/customer-contexts/techco.json

═══════════════════════════════════════════════════════════
✅ COMPLETE
═══════════════════════════════════════════════════════════
```

## 3. Review Context & Recommendations (3-5 minutes)

### View All Saved Contexts

```bash
~/.claude/scripts/se-demo-prep.sh list
```

Output:
```
═══════════════════════════════════════════════════════════
  Saved Customer Contexts
═══════════════════════════════════════════════════════════

  • Acme Corp - Ready (100%) (7 insights)
  • TechCo - Ready (100%) (6 insights)
  • StartupInc - Almost Ready (80%) (5 insights)

✓ Total: 3 contexts
```

### View Specific Context

```bash
~/.claude/scripts/se-demo-prep.sh view "TechCo"
```

Shows complete JSON with all data.

### View Product Recommendations

```bash
~/.claude/scripts/se-demo-prep.sh recommendations "TechCo"
```

Output:
```
═══════════════════════════════════════════════════════════
  Product Recommendations: TechCo
═══════════════════════════════════════════════════════════

Product: Qodo Gen
Reason: Addresses testing pain points
Tech Fit: excellent
Key Features:
  • Automated test generation
  • Code analysis and suggestions
  • Bug detection and fixing
────────────────────────────────────────────────────────

Product: Qodo Merge
Reason: Addresses code_quality pain points
Tech Fit: excellent
Key Features:
  • Automated PR reviews
  • Code quality analysis
  • Security vulnerability detection
────────────────────────────────────────────────────────

Product: Qodo Command
Reason: Addresses automation pain points
Tech Fit: good
Key Features:
  • Custom CLI agents
  • CI/CD integration
  • Scheduled code reviews
────────────────────────────────────────────────────────
```

## 4. Generate Demo Script (2 minutes)

```bash
~/.claude/scripts/se-demo-prep.sh script "TechCo"
```

Output:
```
═══════════════════════════════════════════════════════════
  Demo Script: TechCo
═══════════════════════════════════════════════════════════

INTRODUCTION (2 minutes)
─────────────────────────────────────────────────────────
  • Thanks for taking the time to meet with us, TechCo
  • I understand you're currently working with Python
  • Today I'll show you how Qodo can help address the challenges you mentioned

PAIN POINT REVIEW (3 minutes)
─────────────────────────────────────────────────────────
  • Based on our previous conversations, I heard:
  • 1. We're struggling with test coverage and manual testing takes too long...
  • 2. Code reviews are bottleneck, PRs sit for days waiting for review...
  • 3. We need better automation in our CI/CD pipeline...
  • Does that sound right? Anything else you'd like to add?

SOLUTION DEMO (15 minutes)
─────────────────────────────────────────────────────────
  Product: Qodo Gen
  Why: Addresses testing pain points
  Demo Flow:
    Open a file in VS Code
    Highlight a function that needs tests
    Run Qodo Gen to generate tests
    Show generated tests and explanations
    Demonstrate code improvement suggestions

  Product: Qodo Merge
  Why: Addresses code_quality pain points
  Demo Flow:
    Open a sample PR in GitHub
    Show Qodo Merge analysis in PR comments
    Walk through flagged issues (15+ agents)
    Demonstrate /implement command for auto-fix
    Show issue prioritization

  Product: Qodo Command
  Why: Addresses automation pain points
  Demo Flow:
    Show CLI agent configuration
    Run custom agent on repository
    Demonstrate CI/CD integration
    Show scheduled review results
    Explain custom agent creation

ROI DISCUSSION (5 minutes)
─────────────────────────────────────────────────────────
  • Let's talk about the impact Qodo can have on your team:
  • With Qodo Gen: 3-5 hours saved per developer per week
  • With Qodo Merge: 70% reduction in review time, 60% fewer production bugs
  • Typical customers see ROI in the first month
  • What metrics matter most to you in evaluating this?

NEXT STEPS (5 minutes)
─────────────────────────────────────────────────────────
  • Set up a trial environment
  • Schedule technical deep dive
  • Discuss integration requirements
  • Plan POC timeline

✓ Demo script ready
```

## 5. Prepare Demo Environment (5 minutes)

### Preparation Checklist

Based on context, prepare:

1. **Code Examples** (from tech stack)
   - Python examples if primary language
   - Framework-specific examples (Django, Flask, etc.)

2. **Demo PRs** (if recommending Qodo Merge)
   - Create sample PR with issues
   - Show real analysis results

3. **CI/CD Integration** (if recommending Qodo Command)
   - Prepare GitHub Actions example
   - Show scheduled review results

4. **Backup Environment**
   - Test all features in advance
   - Have offline demos ready

### Quick Demo Setup Script

```bash
# Based on context, run relevant setup
cd ~/demo-environments

# For TechCo (Python + GitHub)
mkdir -p techco-demo
cd techco-demo

# Clone demo repo or create sample
# ... prepare Python examples ...
# ... create sample PRs ...
```

## Common Workflows

### New Customer (Zero History)

```bash
# 1. Gather context
~/.claude/scripts/se-demo-prep.sh gather "NewCo Inc" newco

# 2. Review recommendations (might be generic)
~/.claude/scripts/se-demo-prep.sh recommendations "NewCo Inc"

# 3. Prepare generic demo script
~/.claude/scripts/se-demo-prep.sh script "NewCo Inc"
```

Result: Basic demo ready based on tech stack alone.

### Active Deal (Multiple Interactions)

```bash
# 1. Gather context (pulls Gong + HubSpot data)
~/.claude/scripts/se-demo-prep.sh gather "ActiveCorp"

# 2. Review pain points and recommendations
~/.claude/scripts/se-demo-prep.sh recommendations "ActiveCorp"

# 3. Generate customized script
~/.claude/scripts/se-demo-prep.sh script "ActiveCorp"
```

Result: Highly customized demo with specific pain point focus.

### Technical Deep Dive

```bash
# 1. Gather with specific repo
~/.claude/scripts/se-demo-prep.sh gather "TechCorp" techcorp backend-api

# 2. View code style (for matching demo style)
~/.claude/scripts/se-demo-prep.sh view "TechCorp" | jq '.code_style'

# 3. Prepare demo matching their patterns
# ... create demos using their code style ...
```

Result: Demo that feels native to their codebase.

## Tips & Tricks

### Caching

First query: 8-12 seconds
Subsequent queries: 2-3 seconds (85% cache hit rate)

```bash
# Clear cache if data is stale
rm -rf ~/.claude/cache/integrations/*

# Re-gather with fresh data
~/.claude/scripts/se-demo-prep.sh gather "Company"
```

### Partial Data

System works with partial data:

- **No Gong data?** → Generic pain point assumptions
- **No HubSpot data?** → Focus on tech stack fit
- **No GitHub data?** → Use language from config
- **Qodo always available** → Embedded catalog

### Quick Reference

```bash
# Add alias for convenience
echo 'alias demo-prep="~/.claude/scripts/se-demo-prep.sh"' >> ~/.zshrc
source ~/.zshrc

# Now use shorter commands
demo-prep gather "Acme Corp"
demo-prep script "Acme Corp"
demo-prep list
```

### JSON Queries

```bash
# Extract specific data with jq
cat ~/.claude/data/customer-contexts/techco.json | jq '
  .pain_points | map(.context) | .[]
'

cat ~/.claude/data/customer-contexts/techco.json | jq '
  .tech_stack.frameworks
'

cat ~/.claude/data/customer-contexts/techco.json | jq '
  .qodo_recommendations.recommendations | map(.product_name)
'
```

## Troubleshooting

### "No credentials found"

```bash
# Check credentials exist
ls -la ~/.claude/credentials/

# Should see:
# gong.json
# hubspot.json
# github.json
# qodo.json
```

### "Connection failed"

```bash
# Test individual client
cd ~/.claude/scripts/integrations
python3 gong_client.py config.json
```

### "jq not found"

```bash
# Install jq
brew install jq

# Or view raw JSON
cat ~/.claude/data/customer-contexts/company.json
```

### Rate Limiting

Wait messages like:
```
Rate limit: sleeping 45.2s
```

This is normal - system auto-throttles to stay within API limits.

## Next Steps

1. ✅ Test all connections
2. ✅ Gather context for first customer
3. ✅ Review demo script
4. ✅ Prepare demo environment
5. ⏭️ Integrate with Skills Router
6. ⏭️ Add MCP for real Qodo interaction
7. ⏭️ Automate PR creation
8. ⏭️ Add pattern recognition

---

**Goal**: From customer name to demo-ready in **15 minutes**

**Current Status**: Foundational data layer ✅ complete and ready for testing
