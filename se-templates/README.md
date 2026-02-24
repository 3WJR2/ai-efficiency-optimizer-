# Solutions Engineer Templates & Tools

Quick-access templates and tools for Qodo Solutions Engineers.

## 📁 Contents

### 1. Demo Preparation Checklist
**File**: `demo-prep-checklist.md`

**Use when**: Preparing for any product demo

**What it includes**:
- Pre-demo research guide (company context, pain points)
- Technical setup checklist (environment, examples, materials)
- Demo script with timing (25-minute flow)
- Objection handling responses
- Post-demo follow-up tasks

**How to use**:
```bash
cp ~/.claude/se-templates/demo-prep-checklist.md ~/demos/[company-name]-demo.md
# Edit with specific customer details
```

---

### 2. Feature Testing Checklist
**File**: `feature-testing-checklist.md`

**Use when**: New Qodo feature release

**What it includes**:
- Pre-testing setup and planning
- Functional testing (happy path + edge cases)
- Integration testing (Gen/Merge/Command/Aware)
- Performance and security testing
- Documentation validation
- Customer impact assessment
- Bug/improvement tracking

**How to use**:
```bash
cp ~/.claude/se-templates/feature-testing-checklist.md ~/testing/[feature-name]-test.md
# Work through checklist systematically
```

---

### 3. Customer Communication Templates
**File**: `customer-communications.md`

**Use when**: Any customer communication

**What it includes**:
- Demo follow-up email
- Feature announcement email
- Check-in/relationship email
- Trial/POC kick-off email
- Technical issue response
- Success story request
- Renewal discussion email
- Objection handling responses
- Executive summary email

**How to use**:
```bash
# View templates
cat ~/.claude/se-templates/customer-communications.md | less

# Or ask Claude:
"Use the demo follow-up template for [Company Name]"
"Create a feature announcement email for [Feature] to [Customer]"
```

---

### 4. ROI Calculator
**File**: `roi-calculator.sh`

**Use when**: Calculating customer ROI for demos, proposals, or renewals

**What it calculates**:
- Time savings (PR reviews, testing, bug fixing)
- Cost savings (labor + production bug costs)
- ROI percentage
- Payback period
- Projected metric improvements

**How to use**:
```bash
# Interactive calculator
~/.claude/se-templates/roi-calculator.sh

# Saves results to file for customer proposals
```

**Example output**:
```
ROI: 740%
Payback period: 1.6 months
Annual savings: $420,000
Test coverage: 45% → 70%
Production bugs: 20/mo → 14/mo
```

---

## 🚀 Quick Commands

### Prepare for Demo
```bash
# Create demo prep document
cp ~/.claude/se-templates/demo-prep-checklist.md ~/demos/$(date +%Y%m%d)-[company].md
code ~/demos/$(date +%Y%m%d)-[company].md
```

### Test New Feature
```bash
# Create feature test document
cp ~/.claude/se-templates/feature-testing-checklist.md ~/testing/[feature]-$(date +%Y%m%d).md
```

### Calculate ROI
```bash
# Run interactive ROI calculator
~/.claude/se-templates/roi-calculator.sh
```

### Send Follow-Up Email
Ask Claude:
```
"Use the demo follow-up email template for [Company Name] - we covered Gen and Merge"
```

---

## 🤖 Using with Claude

Claude has all these templates in context and can help you:

**Demo Preparation:**
- "Prepare demo for [Company Name] - they use Python/Django"
- "Create demo script for enterprise customer focused on security"
- "What should I show in a 15-minute Gen demo?"

**Feature Testing:**
- "Test [Feature Name] using the checklist"
- "What integration tests should I run for this feature?"
- "Generate bug report for issue I found"

**Customer Communications:**
- "Write demo follow-up email for [Company]"
- "Create feature announcement for [Feature] to [Customer]"
- "Draft renewal email for [Company] - contract ends in 60 days"

**ROI Calculations:**
- "Calculate ROI for 20 developers at $150k salary"
- "What's the payback period for this customer profile?"
- "Create executive summary with ROI for [Company]"

**Integration Solutions:**
- "Build GitHub Actions integration for Qodo Command"
- "Create custom agent for [specific use case]"
- "Set up multi-repo indexing for [customer]"

---

## 📚 Knowledge Base Integration

All templates integrate with `~/knowledge-core.md` which contains:
- Complete Qodo product documentation
- SE best practices and patterns
- Customer lifecycle workflows
- Competitive positioning
- Success metrics and benchmarks

Claude references this automatically when you use these templates.

---

## 🔄 Updating Templates

Templates are living documents. After successful demos, features tests, or customer wins:

1. **Document what worked**: Add to knowledge-core.md
2. **Update templates**: Incorporate learnings
3. **Share with team**: Successful patterns become best practices

Ask Claude:
```
"Update demo prep checklist based on today's successful demo"
"Add new objection handling response for [objection]"
```

---

## 💡 Best Practices

### Demo Preparation
- Customize 30+ minutes before call
- Test demo environment 15 minutes before
- Have backup plans ready
- Send follow-up within 2 hours

### Feature Testing
- Test within 24 hours of release
- Report findings immediately
- Identify customer opportunities
- Update documentation gaps

### Customer Communications
- Use customer's terminology
- Reference specific conversations
- Include clear next steps
- Proofread before sending

### ROI Calculations
- Use customer's real numbers
- Be conservative in estimates
- Show work and assumptions
- Offer to validate with trial data

---

## 🆘 Getting Help

**Ask Claude:**
- "How do I use the [template name]?"
- "Customize [template] for [situation]"
- "What template should I use for [task]?"

**Resources:**
- Product docs: qodo.ai/docs
- Knowledge base: ~/knowledge-core.md
- SE workflows: ~/.claude/CLAUDE.md
- Team Slack: #solutions-engineering

---

**Last Updated**: 2026-02-16
**Maintained By**: Claude Adaptive Learning System
