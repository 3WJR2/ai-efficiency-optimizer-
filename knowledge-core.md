# Solutions Engineer Knowledge Core - Qodo

**Version**: 1.0.0
**Role**: Solutions Engineer at Qodo
**Purpose**: Institutional knowledge for SE workflows, product expertise, and customer patterns
**Last Updated**: 2026-02-16

---

## 🎯 Role Context: Solutions Engineer at Qodo

### Primary Responsibilities
1. **Product Demonstrations** - Showcase Qodo's value to prospects and customers
2. **Feature Testing** - Validate new releases, identify issues, provide feedback
3. **Custom Solutions** - Build integrations and custom workflows for enterprise customers
4. **Relationship Management** - Deepen and maintain customer relationships
5. **Technical Evangelism** - Present at events, create content, educate users

### Success Metrics
- Demo conversion rates
- Feature adoption post-release
- Customer satisfaction scores
- Time-to-value for new customers
- Renewal and expansion rates

---

## 🛠️ Qodo Product Suite (2026) - Complete Official Documentation

**Documentation Sources**:
- Main Docs: https://docs.qodo.ai/
- Qodo Merge: https://qodo-merge-docs.qodo.ai/
- GitHub: https://github.com/qodo-ai

---

### 1. Qodo Merge (Git/PR-Agent) 🔀

**What**: Open-source PR review and management tool with hosted enterprise version
**Where**: GitHub, GitLab, Bitbucket, Azure DevOps, Gitea
**Status**: Open-source (PR-Agent) + Hosted (Qodo Merge) + Self-hosted options

#### Core Features

**Available Tools** (20+ total):
- `/describe` - Generates PR summaries, types, walkthroughs, diagrams
- `/review` - Performs code analysis and identifies issues
- `/improve` - Suggests code enhancements and refactoring
- `/ask` - Enables Q&A about code changes
- `/help` - Provides documentation search
- `/update_changelog` - Automates changelog generation

**Premium Features** (💎 Qodo Merge only):
- Documentation generation
- Compliance checking
- Test generation
- Custom prompts
- PR chat functionality (browser extension)
- Auto-approval workflows
- Impact evaluation
- Self-review requirements

#### `/describe` Command (Complete Documentation)

**Purpose**: Generates automated PR descriptions with title, type, summary, walkthrough, and labels

**Invocation**:
- **Manual**: Comment `/describe` on any PR
- **Automatic**: Configure `pr_commands = ["/describe", ...]` in settings

**Key Configuration Options**:
| Option | Default | Purpose |
|--------|---------|---------|
| `publish_labels` | false | Publishes labels to PR |
| `publish_description_as_comment` | false | Posts as comment vs overwriting |
| `generate_ai_title` | false | Creates AI-generated title |
| `enable_pr_diagram` | true | Generates Mermaid sequence diagram |
| `enable_semantic_files_types` | true | Generates "Changes walkthrough" |
| `add_original_user_description` | true | Preserves original description |
| `enable_large_pr_handling` | true | Handles large PRs with chunking |

**Generated Content**:
- **PR Type**: Classification (feature, bug fix, refactor, etc.)
- **Summary**: High-level overview of changes
- **Walkthrough**: File-by-file breakdown with change descriptions
- **Diagram**: Mermaid sequence diagram showing component interactions
- **Labels**: Auto-assigned categorizations

**Advanced Features**:
- **Markers Template**: Use placeholders like `pr_agent:type`, `pr_agent:summary`, `pr_agent:walkthrough`
- **Custom Labels**: Define repo-specific labels with `pr_agent:` prefix
- **Inline File Summaries** (Premium): Change tables in "Files changed" tab or collapsible comments

**SE Demo Points**:
- Show auto-generated PR description on real customer code
- Demonstrate Mermaid diagram visualization
- Highlight time saved (5 min manual → 30 seconds automatic)
- Show custom label configuration

---

#### `/review` Command (Complete Documentation)

**Purpose**: Analyzes PR code changes and generates reviewer feedback (~30 seconds)

**Invocation**:
- **Manual**: Comment `/review` on any PR
- **Automatic**: Configure `pr_commands = ["/review", ...]`

**Key Configuration Options**:
| Setting | Default | Purpose |
|---------|---------|---------|
| `persistent_comment` | true | Edits previous review vs new comment |
| `extra_instructions` | — | Custom guidance for analysis |
| `num_max_findings` | 3 | Maximum returned findings |
| `require_score_review` | false | Add PR scoring section |
| `require_tests_review` | true | Check for test coverage |
| `require_security_review` | true | Scan for vulnerabilities |
| `require_ticket_analysis_review` | true | Validate against linked tickets |

**Review Sections** (Optional):
- **Effort Estimation**: Review effort scale 1-5
- **Time-to-Implement**: Cost analysis for changes
- **Split-ability Assessment**: Can PR be split?
- **TODO Comment Scanning**: Identifies incomplete work
- **Security Vulnerability Detection**: Flags potential issues

**Auto-Generated Labels**:
- `possible security issue` - Triggered by vulnerability detection
- `review effort [x/5]` - Effort scale from 1-5
- `ticket compliance` - Fully/Partially/Not compliant, or No ticket found

**Best Practices**:
1. Customize configuration to match project needs
2. Enable useful disabled-by-default features like `require_score_review`
3. Provide specific, detailed `extra_instructions`
4. Use multi-line instructions with bullet points
5. Block merges on security labels via CI/CD integration

**SE Demo Points**:
- Live review on customer PR showing findings in ~30 seconds
- Demonstrate security vulnerability detection with label
- Show effort estimation and ticket compliance validation
- Configure custom `extra_instructions` for customer standards

---

#### `/improve` Command (Complete Documentation)

**Purpose**: Generates meaningful code improvement suggestions with direct and indirect implementation tracking

**Invocation**:
- **Manual**: `/improve` or `/improve --pr_code_suggestions.commitable_code_suggestions=true`
- **Automatic**: Configure `pr_commands = ["/improve", ...]`
- **Extended**: `/improve --more_suggestions=true` for additional suggestions

**Suggestion Modes**:
- **Table Format** (default, recommended): Cleaner PR experience, high-level suggestions, interactive features
- **Committable Code Comments**: Inline editable suggestions

**Key Configuration Options**:
| Parameter | Default | Purpose |
|-----------|---------|---------|
| `suggestions_depth` | regular | Controls depth: selective/regular/exhaustive |
| `num_code_suggestions_per_chunk` | 3 | Suggestions per chunk |
| `num_best_practice_suggestions` | 1 | Best practice-specific suggestions |
| `focus_only_on_problems` | true | Prioritize bugs vs style |
| `commitable_code_suggestions` | false | Display as editable comments |
| `persistent_comment` | true | Edit previous vs new comment |
| `suggestions_score_threshold` | 0 | Minimum importance score |
| `dual_publishing_score_threshold` | -1 | Score for dual publishing |

**Advanced Features**:

**Extended Mode** (Auto Chunking):
- Divides large PRs into chunks (up to 32,000 tokens each)
- Generates up to 3 suggestions per chunk
- Maximum 3 chunks per PR
- Scales with PR size

**Best Practices System** (3-tier):
- **Local**: Project-specific patterns
- **Global Hierarchical**: Organization-wide standards
- **Auto-Generated** (Qodo Merge): Learns from accepted suggestions

**Self-Review Feature** (Qodo Merge):
- Requires PR author acknowledgment
- Auto-folds suggestions after review
- Optional PR approval upon completion

**Depth Control** (Qodo Merge):
- `selective`: High-threshold filtering for critical issues
- `regular`: Balanced suggestions
- `exhaustive`: Maximum coverage with enhanced bug detection

**Dual Publishing**: Highlights critical suggestions both in tables and PR comments when exceeding score threshold

**SE Demo Points**:
- Show 3 suggestions generated on customer code
- Demonstrate committable suggestions feature
- Show best practices auto-learning (accepted suggestions → patterns)
- Highlight self-review checkbox workflow
- Configure `exhaustive` mode for comprehensive analysis

---

#### Installation & Setup

**Qodo Merge** (Hosted - Easiest):
1. Visit Qodo Merge app page for your platform
2. Add app to relevant repositories
3. Configure via `.qodo_merge.toml` in repo root (optional)

**PR-Agent** (Self-Hosted - Full Control):
- **Locally**: CLI for local repository operations
- **GitHub Actions**: Workflow automation
- **Webhooks**: Azure DevOps, GitLab, Bitbucket
- **Docker**: Container deployment

**Configuration File** (`.pr_agent.toml`):
```toml
[github_app]
pr_commands = ["/describe", "/review", "/improve"]

[pr_description]
generate_ai_title = true
enable_pr_diagram = true

[pr_code_suggestions]
suggestions_depth = "exhaustive"
num_code_suggestions_per_chunk = 4

[pr_reviewer]
require_security_review = true
extra_instructions = """
Focus on:
- Memory leaks
- SQL injection vulnerabilities
- Performance bottlenecks
"""
```

**Environment Variables**:
```bash
# For Anthropic Claude
export ANTHROPIC_API_KEY=your-key

# For OpenAI
export OPENAI_API_KEY=your-key
```

---

#### Usage Patterns & Automation

**Automatic PR Processing**:
```toml
[github_app]
pr_commands = ["/describe", "/review", "/improve"]
auto_review = true
auto_describe = true
auto_improve = true
```

**Selective Automation**:
```toml
# Only on specific branches
[pr_reviewer]
require_focused_review = true
num_code_suggestions = 6

# Only for large PRs
[pr_description]
enable_large_pr_handling = true
```

**CI/CD Integration**:
```yaml
# GitHub Actions example
name: Qodo Review
on: [pull_request]
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: qodo-ai/pr-agent-action@v1
        with:
          command: /review
```

---

### 2. Qodo Gen (IDE Plugin) 💻

**What**: Automated, context-aware code review directly in your IDE
**Where**: Visual Studio Code, JetBrains IDEs, Visual Studio Professional
**Language Support**: All programming languages

#### Core Features

- **Local Code Review**: Analyzes diffs and test logic in real-time
- **AI-Powered Suggestions**: Issue resolution with single-click application
- **Automated Test Identification**: Finds relevant tests for code modifications
- **Customizable Review Agents**: Adapts to team-specific standards and rules
- **Critical Issue Detection**: Breaking changes, security vulnerabilities, compliance violations

#### Installation

**Visual Studio Code**:
1. Open Extensions menu (Extensions icon in Activity Bar)
2. Search "Qodo Gen"
3. Click Install
4. Restart extensions to activate
5. Icon appears in Activity Bar

**Alternative**: Visit [VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=Codium.codium)

**JetBrains IDEs**:
1. Open Settings → Plugins (cog wheel → Plugins)
2. Search "Qodo Gen"
3. Click Install
4. Restart IDE
5. Icon appears in sidebar

**Alternative**: Visit [JetBrains Marketplace](https://plugins.jetbrains.com/plugin/21206-qodo-gen)

**Requirements**:
- JCEF (Java Chromium Embedded Framework) required for JetBrains
- Most IntelliJ-based IDEs include JCEF by default
- Android Studio and some versions lack JCEF (plugin won't load)

**Visual Studio Professional**:
Similar installation process via Visual Studio Marketplace

#### Configuration

**Enterprise Users**:
- Log in with work email from registered domain
- Automatically connects to organization workspace
- Choose login method (SSO supported)

**Settings**:
- Access settings menu in IDE
- Configure features like Code Completion
- Enable/disable specific review agents
- Customize review rules

**Custom Review Agents**:
Define organization-specific rules and standards in configuration files

#### Usage Patterns

**Real-Time Review**:
- Makes code changes in IDE
- Qodo Gen analyzes diffs automatically
- Surfaces issues inline with suggestions
- Apply fixes with single click

**Test Discovery**:
- Modify code
- Qodo Gen identifies affected tests
- Shows test coverage gaps
- Suggests new test cases

**SE Demo Points**:
- Show real-time code review as you type
- Demonstrate single-click fix application
- Show security vulnerability detection inline
- Configure custom rules for customer's standards
- Highlight test identification and coverage analysis

---

### 3. Qodo Command (CLI) ⌨️

**What**: Command-line interface for running and managing AI agents
**Where**: Terminal, CI/CD pipelines, automation scripts
**Status**: Beta release

#### Core Capabilities

- **Execute AI Agents**: Run agents through terminal commands
- **Custom Workflows**: Configure personalized automation
- **External Tool Integration**: Custom schemas for tool connections
- **HTTP Services**: Deploy agents as callable web services
- **Model Selection**: Choose between Claude, GPT-4, and other LLMs
- **MCP Integration**: Convert agents to Model Context Protocol format

#### Available Modes

**1. Interactive Chat** (`qodo chat`):
- Direct natural language conversation with agents
- Terminal-based interaction
- Real-time responses

**2. Custom Commands** (`qodo <command-name>`):
- Run configured agents
- Pass arguments and flags
- Automated execution

**3. Web UI Mode** (`qodo <command> --ui`):
- Interactive web interface
- Visual agent interaction
- Browser-based access

**4. HTTP/Webhook Mode** (`qodo <command> --mcp`):
- Expose agents as web services
- Webhook integration
- API-style access

**5. MCP Integration**:
- Convert agents to MCP format
- Tool server compatibility
- Protocol standardization

#### CLI Commands

**Authentication**:
```bash
qodo login  # Authenticate and receive API key
```

**Agent Management**:
```bash
qodo <command-name>           # Run configured agent
qodo <command-name> --mcp     # Run agent as MCP service
qodo <command-name> --ui      # Run with web UI
```

**Tool Management**:
```bash
qodo list-mcp                 # List available local and remote tools
```

**Model Management**:
```bash
qodo models                   # List available AI models
qodo <command> --model=<name> # Use specific model
```

**API Key Management**:
```bash
qodo key list                 # List API keys
qodo key create <name>        # Create new API key
qodo key revoke <name>        # Revoke API key
```

**Tool Selection**:
```bash
qodo <command> --tools=<tool1>,<tool2>  # Use specific tools
```

#### Agent Configuration

**File Structure**:
```
project/
└── agents/
    ├── code-reviewer.toml
    ├── test-generator.toml
    └── bug-analyzer.toml
```

**Basic Agent Configuration** (`agent.toml`):
```toml
version = "1.0"

[commands.my_agent]
description = "Brief description of what this agent does"

instructions = """
Specify the agent's behavior and expected outcomes:
1. Analyze the input code
2. Identify potential issues
3. Generate suggestions
4. Format output as markdown
"""

# Optional: Arguments
[[commands.my_agent.arguments]]
name = "input_file"
type = "string"
description = "Path to the file to analyze"
required = true

[[commands.my_agent.arguments]]
name = "threshold"
type = "number"
description = "Severity threshold (0.0-1.0)"
required = false
default = 0.8

# Optional: MCP Servers
[commands.my_agent.mcpServers]
shell = { command = "npx", args = ["-y", "@modelcontextprotocol/server-shell"] }
github = { command = "npx", args = ["-y", "@modelcontextprotocol/server-github"] }

# Optional: Tools
[commands.my_agent.tools]
tools = ["filesystem", "git", "shell", "github"]
```

**Advanced Configuration Example**:
```toml
version = "1.0"

[commands.security_scanner]
description = "Scans code for security vulnerabilities"

instructions = """
Security Analysis Protocol:
- Scan for SQL injection vulnerabilities
- Check for XSS attack vectors
- Identify hardcoded credentials
- Verify input sanitization
- Review authentication logic

Output Format:
- Severity: Critical/High/Medium/Low
- Location: File and line number
- Description: Issue explanation
- Recommendation: Fix suggestion
"""

[[commands.security_scanner.arguments]]
name = "directory"
type = "string"
description = "Directory to scan"
required = true

[[commands.security_scanner.arguments]]
name = "output_format"
type = "string"
description = "Output format: json, markdown, or html"
required = false
default = "markdown"

[commands.security_scanner.mcpServers]
filesystem = { command = "npx", args = ["-y", "@modelcontextprotocol/server-filesystem", "."] }

[commands.security_scanner.tools]
tools = ["filesystem"]
```

#### Usage Examples

**Simple Agent Execution**:
```bash
# Run code reviewer
qodo code-reviewer --input_file=src/main.py

# Run with specific model
qodo code-reviewer --model=claude-4-opus --input_file=src/main.py

# Run with specific tools
qodo code-reviewer --tools=filesystem,git --input_file=src/main.py
```

**Interactive Chat**:
```bash
qodo chat
# Then interact naturally:
# > Review the authentication logic in auth.py
# > Generate tests for the User class
# > Explain the caching strategy
```

**Web UI Mode**:
```bash
qodo security_scanner --ui --directory=./src
# Opens browser interface at http://localhost:3000
```

**HTTP Service Mode**:
```bash
qodo test_generator --mcp
# Exposes agent as HTTP endpoint
# POST requests trigger agent execution
```

**CI/CD Integration**:
```yaml
# GitHub Actions example
name: Code Review
on: [push]
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install Qodo CLI
        run: npm install -g @qodo/cli
      - name: Run Code Review
        run: qodo code-reviewer --directory=./src
        env:
          QODO_API_KEY: ${{ secrets.QODO_API_KEY }}
```

#### Multi-Agent Workflows

**Sequential Execution**:
```bash
# Step 1: Analyze code
qodo analyzer --input=src/ > analysis.json

# Step 2: Generate tests based on analysis
qodo test-generator --analysis=analysis.json

# Step 3: Review generated tests
qodo reviewer --tests=tests/
```

**Parallel Execution** (in CI):
```yaml
jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - run: qodo analyzer --input=src/

  lint:
    runs-on: ubuntu-latest
    steps:
      - run: qodo linter --input=src/

  security:
    runs-on: ubuntu-latest
    steps:
      - run: qodo security-scanner --input=src/
```

#### TypeScript SDK

**For programmatic access**:
```typescript
import { QodoClient } from '@qodo/cli-sdk';

const client = new QodoClient({ apiKey: process.env.QODO_API_KEY });

const result = await client.runAgent('code-reviewer', {
  input_file: 'src/main.ts',
  threshold: 0.8
});

console.log(result.suggestions);
```

#### SE Demo Points

- Show custom agent creation for customer-specific workflow
- Demonstrate CLI integration in existing CI/CD pipeline
- Run multi-agent workflow (analyze → fix → review)
- Show web UI mode for interactive demos
- Expose agent as HTTP service for webhook integration
- Configure model selection (Claude vs GPT-4)

---

### 4. Qodo Aware (Context Engine) 🧠

**What**: Deep research agent purpose-built for large codebases
**Purpose**: Turn your codebase into a living knowledge engine
**Where**: Integrated across Qodo platform (Gen, Merge, Command)

#### Core Purpose

Qodo Context Engine provides foundational intelligence for all Qodo products, enabling deep codebase understanding across multiple repositories.

#### Primary Capabilities

- **Remote Codebase Querying**: Access across multiple repositories simultaneously
- **Organizational Knowledge**: Access insights without switching tools
- **Development Best Practices**: Explore patterns and standards
- **Architectural Understanding**: Similar to senior engineer consultation
- **Multi-Repo Analysis**: Cross-service dependency tracking

#### Available Agents

**1. Ask Agent**:
- **Purpose**: Rapid responses from indexed code
- **Speed**: Fast, immediate answers
- **Use When**: Quick questions about specific functionality
- **Example**: "Where is user authentication implemented?"

**2. Deep Research Agent** (Principal Engineer):
- **Purpose**: Multi-step analysis across services
- **Depth**: Comprehensive investigation
- **Use When**: Complex architectural questions
- **Example**: "How does authentication flow across our microservices architecture?"

#### Technical Architecture

**Indexing**:
- Creates structured, multi-layered codebase understanding
- Connects to Git providers
- Daily updates for popular open-source libraries
- Supports thousands of repositories

**Retrieval**:
- Advanced retrieval beyond "nearby code"
- Gathers relevant functions, documentation, commit patterns
- Identifies architectural elements
- Contextual relevance ranking

**Agentic Reasoning**:
- Analyzes relationships and dependencies
- Understands intent beyond syntax
- Multi-step decomposition for complex queries

**Generation**:
- Produces grounded, accurate responses
- Evidence-based from actual code
- Architectural insights and recommendations

#### Key Differentiators

**vs Traditional AI Tools**:
1. **Advanced Retrieval**: Identifies "the *right* context, not just nearby code"
2. **Multi-Agent Reasoning**: Complex decomposition and analysis
3. **Enterprise Scale**: Thousands of repositories indexed

#### Notable Use Cases

**Feature Understanding**:
- How feature X works across system layers
- Dependencies and integration points
- Historical context from commits

**Architectural Planning**:
- Impact analysis before changes
- Design pattern identification
- Best approach recommendations

**Best Practice Discovery**:
- Organizational standards and patterns
- Proven solutions to common problems
- Historical decisions and rationale

**Impact Analysis**:
- What will break if I change X?
- Which services depend on this module?
- Test coverage and risk assessment

#### Usage Patterns

**Simple Queries**:
```
Ask: "Where is the payment processing logic?"
Response: Points to specific files, functions, and explains flow
```

**Complex Analysis**:
```
Ask: "How should I implement feature flags across our microservices?"
Deep Research: Analyzes existing patterns, suggests architecture,
provides examples from codebase
```

**Architectural Questions**:
```
Ask: "What's our caching strategy and where is it implemented?"
Response: Explains strategy, shows implementations, identifies gaps
```

#### Integration Points

**Qodo Gen** (IDE):
- Context-aware code suggestions
- Relevant test identification
- Impact analysis for changes

**Qodo Merge** (PR Review):
- Deeper code understanding for reviews
- Architectural compliance checking
- Historical pattern matching

**Qodo Command** (CLI):
- Agent access to codebase knowledge
- Multi-repo workflow automation
- Documentation generation

#### MCP Integration

**Model Context Protocol**:
- Exposes code intelligence as callable tools
- Compatible with Claude and other AI systems
- Real-time codebase access

**Endpoint**: `https://open-aware.qodo.ai/mcp`

**Tools Available**:
- `get_context`: Semantic search with language filtering
- `deep_research`: Multi-step analysis across repos
- `ask`: Q&A about indexed repositories

#### Configuration

**Repository Indexing**:
```bash
# Index repositories
qodo aware index --repos "org/repo1,org/repo2,org/repo3"

# Update schedule
qodo aware index --update-schedule daily

# Language filtering
qodo aware index --languages python,typescript
```

**Query Examples**:
```bash
# Simple query
qodo aware query "authentication implementation"

# Cross-repo query
qodo aware query "service communication patterns" \
  --repos service-a,service-b --format markdown

# Deep research
qodo aware research "optimal caching strategy" \
  --scope multi-repo --depth comprehensive
```

#### SE Demo Points

- Show multi-repo query answering complex architectural question
- Demonstrate speed difference: Ask Agent (2 sec) vs Deep Research (30 sec)
- Query customer's actual codebase (with permission)
- Show how Context Engine powers Qodo Gen suggestions
- Demonstrate MCP integration with Claude
- Compare accuracy vs traditional code search (keyword matching)

---

### Key Features (All Products)

**Universal Capabilities**:
- **20+ Tools**: Describe, Review, Improve, Ask, Help, Documentation, Analyze, CI Feedback, Compliance, Test Generation, and more
- **Multi-Platform**: GitHub, GitLab, Bitbucket, Azure DevOps, Gitea, VS Code, JetBrains, Visual Studio
- **Multi-LLM**: Anthropic Claude, OpenAI GPT-4, and others
- **Context Engine**: Deep codebase understanding powered by Qodo Aware
- **Enterprise Security**: SOC 2 Type II, on-premises, VPC, air-gapped deployment
- **Data Privacy**: Auto-purge within 48 hours for Teams/Enterprise
- **Customization**: Extra instructions, custom prompts, best practices, review agents

**Integration Options**:
- IDE plugins (real-time)
- Git platform webhooks (automated)
- CLI tools (scripted)
- CI/CD pipelines (integrated)
- HTTP/MCP services (exposed)

**Deployment Models**:
- Hosted (Qodo Merge) - Zero setup
- Self-hosted (PR-Agent) - Full control
- Hybrid - Mix and match
- On-premises - Enterprise security

---

## 📊 Market Position & Competitive Advantage

### Rankings & Recognition
- **Gartner**: #1 in AI Code Assistants category (2026)
- **Users**: 1M+ developers, Fortune 100 early adopters
- **Funding**: $40M Series A (September 2024)

### Competitive Differentiators
1. **Multi-Agent Architecture** - Specialized agents vs single AI assistant
2. **Deep Context Engine** - Multi-repo understanding vs file-level analysis
3. **Enterprise-Grade Security** - On-premises/air-gapped vs cloud-only
4. **15+ Review Workflows** - Comprehensive vs basic review
5. **Open Source Components** - Qodo Merge PR agent is open source

### Common Competitor Comparisons
- **vs GitHub Copilot**: More comprehensive (testing + review + generation), enterprise security
- **vs Cursor**: Specialized agents, deeper code review capabilities
- **vs Tabnine**: Better context engine, multi-agent workflows
- **vs CodeWhisperer**: Superior PR review, open-source options

---

## 🎪 Demo Preparation Patterns

### Pre-Demo Checklist
- [ ] Understand prospect's tech stack (language, frameworks, tools)
- [ ] Identify pain points (testing time, PR review bottlenecks, quality issues)
- [ ] Prepare relevant demo repo (matching their stack if possible)
- [ ] Test all features in demo environment
- [ ] Have backup plans for common demo issues
- [ ] Prepare customer-specific examples

### Demo Structure (20-30 min)
1. **Context** (2 min): Understand their current workflow
2. **Problem** (3 min): Identify specific pain points
3. **Solution** (15 min): Show Qodo addressing those pain points
4. **Value** (5 min): Quantify time/cost savings
5. **Next Steps** (5 min): Trial, POC, or implementation plan

### Demo Best Practices
- Start with their code, not generic examples
- Show ROI early (time saved, bugs caught)
- Use their terminology and workflows
- Address objections proactively
- Leave time for questions
- Have technical depth ready but don't overwhelm

---

## 🧪 Feature Testing Workflows

### New Feature Testing Process
1. **Understand Feature**: Read release notes, internal docs, design specs
2. **Test Environment**: Set up isolated environment matching production
3. **Happy Path**: Test intended use cases
4. **Edge Cases**: Test boundary conditions, errors, failures
5. **Integration**: Test with existing features and workflows
6. **Performance**: Measure speed, resource usage, scalability
7. **Documentation**: Verify docs match implementation
8. **Feedback**: Report issues, suggest improvements

### Testing Checklist Template
```markdown
## Feature: [Feature Name]

### Setup
- [ ] Environment configured
- [ ] Dependencies installed
- [ ] Test data prepared

### Functional Testing
- [ ] Happy path works
- [ ] Edge cases handled
- [ ] Error messages clear
- [ ] Performance acceptable

### Integration Testing
- [ ] Works with Qodo Gen
- [ ] Works with Qodo Merge
- [ ] Works with Qodo Command
- [ ] Context engine integration

### Documentation
- [ ] Docs accurate
- [ ] Examples work
- [ ] API docs complete

### Findings
- Bugs: [List]
- Improvements: [List]
- Questions: [List]
```

---

## 🤝 Relationship Management Patterns

### Customer Lifecycle Stages

#### 1. Prospecting
**Goal**: Understand needs, build trust, demonstrate value
**Activities**:
- Discovery calls
- Technical deep dives
- Demo customization
- POC planning

**Success Indicators**:
- Technical champion identified
- Pain points documented
- POC scope agreed

#### 2. POC/Trial
**Goal**: Prove value, address objections, secure buy-in
**Activities**:
- Hands-on implementation
- Regular check-ins
- Success metrics tracking
- Executive summaries

**Success Indicators**:
- Measurable ROI demonstrated
- User adoption growing
- Technical validation complete

#### 3. Onboarding
**Goal**: Fast time-to-value, establish best practices
**Activities**:
- Team training
- Integration setup
- Workflow optimization
- Success criteria definition

**Success Indicators**:
- Team using daily
- Integrated into workflows
- Success stories emerging

#### 4. Expansion
**Goal**: Deepen usage, expand to more teams
**Activities**:
- Advanced feature training
- New use case identification
- Additional team onboarding
- Executive business reviews

**Success Indicators**:
- Usage growing month-over-month
- Multiple teams/products using
- Advocates emerging

#### 5. Renewal
**Goal**: Demonstrate ongoing value, expand contract
**Activities**:
- ROI quantification
- Success story documentation
- Future roadmap alignment
- Upsell opportunities

**Success Indicators**:
- Renewal secured
- Contract expanded
- Reference customer potential

---

## 💼 Customer Communication Templates

### Demo Follow-Up Email
```
Subject: Thanks for the Qodo demo - [Company Name]

Hi [Name],

Great connecting today! Here's a quick recap:

**What we covered:**
- [Feature 1] reducing PR review time by [X]%
- [Feature 2] catching [Y] types of bugs automatically
- [Feature 3] integrating with your [tech stack]

**Next steps:**
1. [Specific action item 1]
2. [Specific action item 2]

**Resources:**
- Demo recording: [link]
- Trial signup: [link]
- Documentation: [link]

Questions? Reply here or schedule time: [calendar link]

Best,
[Your name]
```

### Feature Announcement Template
```
Subject: New Qodo feature: [Feature Name]

Hi [Name],

Quick update - we just released [feature name] that I think will help with [specific pain point you discussed].

**What it does:**
[1-2 sentence description]

**Why it matters for you:**
[Specific benefit for this customer]

**Try it:**
[Quick start instructions]

Want a walkthrough? [Calendar link]

Best,
[Your name]
```

---

## 🔧 Technical Integration Patterns

### Common Integration Scenarios

#### 1. Enterprise CI/CD Integration
**Stack**: Jenkins, GitHub Actions, GitLab CI, Azure Pipelines
**Pattern**: Qodo Command in pipeline stages
**Template**:
```yaml
# .github/workflows/qodo-review.yml
name: Qodo Code Review
on: [pull_request]
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Qodo Review
        run: qodo review --pr ${{ github.event.pull_request.number }}
```

#### 2. Multi-Repo Context Setup
**Challenge**: Customer has microservices across many repos
**Pattern**: Qodo Aware multi-repo indexing
**Solution**:
```bash
# Index all repos for context
qodo aware index --repos "org/repo1,org/repo2,org/repo3"

# Query across repos
qodo aware query "How does service A call service B?"
```

#### 3. Custom Review Agents
**Challenge**: Customer has specific compliance/security rules
**Pattern**: Custom agent workflows
**Solution**:
```python
# custom_agent.py
from qodo import Agent, Rule

agent = Agent("compliance-checker")
agent.add_rule(Rule("no-hardcoded-secrets"))
agent.add_rule(Rule("pii-detection"))
agent.add_rule(Rule("hipaa-compliance"))
```

---

## 📈 Success Metrics & ROI Calculation

### Quantifiable Metrics

#### Time Savings
- **PR Review Time**: Before vs After (e.g., 2 hours → 15 minutes)
- **Test Writing Time**: Manual vs Qodo Gen (e.g., 1 hour → 5 minutes)
- **Bug Detection**: Caught in review vs production (e.g., 80% vs 20%)

#### Quality Improvements
- **Test Coverage**: Before vs After (e.g., 45% → 85%)
- **Code Quality Score**: Measured improvement
- **Production Bugs**: Reduction over time

#### Developer Productivity
- **PRs Merged/Week**: Increase in throughput
- **Context Switching**: Reduction in time lost
- **Developer Satisfaction**: Survey scores

### ROI Calculation Template
```
Annual Developer Cost: $150,000
Time Spent on Code Review: 20%
Time Saved with Qodo: 70%

Annual Savings per Developer:
$150,000 × 0.20 × 0.70 = $21,000

Team of 20 Developers:
$21,000 × 20 = $420,000/year

ROI = (Savings - Cost) / Cost
ROI = ($420,000 - $50,000) / $50,000 = 740%
```

---

## 🎓 Continuous Learning

### Stay Current
- Weekly Qodo release notes review
- Monthly competitive analysis updates
- Quarterly customer feedback synthesis
- Annual SE best practices review

### Knowledge Capture
- Document successful demos
- Save customer objection responses
- Catalog integration patterns
- Record ROI calculations

### Skills Development
- Product deep dives
- Industry trends monitoring
- Technical skills expansion
- Presentation skills practice

---

## 🚀 Quick Reference: SE Daily Workflows

### Morning Routine
1. Check customer Slack channels
2. Review overnight demo recordings/feedback
3. Test any new feature releases
4. Prepare for scheduled demos/calls

### Demo Day
1. Test demo environment 30 min before
2. Review prospect context
3. Customize demo repo/examples
4. Run demo, take notes
5. Send follow-up within 2 hours

### Feature Release Day
1. Read release notes
2. Set up test environment
3. Run through testing checklist
4. Document findings
5. Identify customer opportunities

### Customer Check-In
1. Review usage metrics
2. Identify potential issues
3. Prepare discussion points
4. Schedule call/meeting
5. Document outcomes

---

## 🔓 Open Source Projects & GitHub Repositories

Qodo maintains significant open-source presence across two GitHub organizations:
- **qodo-ai**: Current branding and active development
- **Codium-ai**: Legacy name, still hosting key research projects

### Major Open Source Projects

#### 1. PR-Agent (Qodo Merge) ⭐ 10,191 stars
**Repository**: https://github.com/qodo-ai/pr-agent
**License**: AGPL-3.0
**Language**: Python

**What it is**: The original open-source PR reviewer - core engine behind Qodo Merge

**Key Features**:
- `/describe` - Auto-generates PR descriptions
- `/review` - Comprehensive code review with inline suggestions
- `/improve` - Code quality enhancements and refactoring
- `/ask` - Interactive Q&A about code changes (line-specific on GitHub/GitLab)

**Supported Platforms**:
- GitHub, GitLab, Bitbucket, Azure DevOps, Gitea

**Deployment Options**:
- CLI (local development)
- GitHub Actions (recommended for automation)
- Docker containers
- Webhook-based integrations
- Self-hosted servers

**Architecture Highlights**:
- PR Compression strategy for large changesets
- Token-aware patch fitting
- Dynamic context enrichment (includes related files + tickets)
- RAG-based context retrieval (GitHub/Bitbucket)
- Each tool runs in single LLM call (~30s latency)

**Configuration**:
- JSON-based prompting with TOML configuration
- Customizable review categories and severity levels
- Model selection (OpenAI GPT, Claude, Deepseek, others)
- `/pr_agent/settings/configuration.toml` for customization

**SE Demo Points**:
- Show `/review` on real customer PR
- Demonstrate `/improve` finding refactoring opportunities
- Use `/ask` for interactive code Q&A
- Highlight self-hosted option for enterprise security

---

#### 2. Qodo-Cover (Test Generation) ⭐ 5,280 stars
**Repository**: https://github.com/qodo-ai/qodo-cover
**License**: AGPL-3.0
**Language**: Python

**What it is**: AI-powered automated test generation and code coverage enhancement

**Core Components**:
1. **Test Runner** - Executes test suites and generates coverage reports
2. **Coverage Parser** - Validates coverage improvements from new tests
3. **Prompt Builder** - Assembles contextual data for LLM
4. **AI Caller** - Interfaces with language models to generate tests

**Supported Languages**:
- **Python** (pytest/coverage)
- **Go** (gocov)
- **Java** (Gradle/JaCoCo)

**Installation**:
```bash
# Via pip
pip install git+https://github.com/qodo-ai/qodo-cover.git

# Binary executables (no Python required)
# Download from releases page
```

**CLI Usage**:
```bash
cover-agent \
  --source-file-path "src/calculator.py" \
  --test-file-path "tests/test_calculator.py" \
  --project-root "." \
  --test-command "pytest" \
  --coverage-type "cobertura" \
  --desired-coverage 90
```

**Key Features**:
- **Record & Replay**: Caches LLM responses to reduce API costs
- **Repository Scanning**: Auto-identifies test files across codebase
- **Weights & Biases**: Optional logging integration
- **HTML Reports**: Detailed results documentation
- **Docker Support**: Containerized execution

**LLM Integration**:
- Uses LiteLLM supporting 100+ models
- Works with Vertex AI, Azure OpenAI, custom endpoints
- Environment variables configure API credentials

**CI/CD Integration**:
- Companion "Qodo CI" provides GitHub Actions workflows
- Automated test generation within CI pipelines
- Currently in preview for Python projects

**SE Demo Points**:
- Show test generation increasing coverage from 45% → 85%
- Demonstrate time savings vs manual test writing
- Highlight multi-language support
- Show CI/CD integration example

**⚠️ Status Note**: Repository maintenance paused as of June 2025 - now integrated into Qodo Gen platform

---

#### 3. Open Aware (Deep Code Research) ⭐ 438 stars
**Repository**: https://github.com/qodo-ai/open-aware
**Language**: Python/MCP

**What it is**: AI-powered code intelligence system performing semantic analysis across multiple repositories

**Core Capabilities**:
1. **Context Retrieval** (`get_context`)
   - Semantic search with language filtering
   - Relevance ranking across repos

2. **Deep Research** (`deep_research`)
   - Analyzes code structure and design patterns
   - Cross-repository relationships
   - Architecture pattern identification

3. **Context Ask** (`ask`)
   - Answers coding questions about indexed repos
   - Evidence-based implementation guidance

**Architecture**:
- Operates through **Model Context Protocol (MCP)**
- Exposes code intelligence as callable tools for AI assistants
- Daily-updated indexes of popular open-source libraries
- Vector embeddings for semantic understanding (not keyword matching)

**Key Features**:
- **Multi-repository analysis**: Examines code across different projects simultaneously
- **Pattern recognition**: Identifies design patterns, error handling, architecture
- **Implementation planning**: Generates feasibility assessments
- **Language-specific filtering**: Narrows results by programming language

**Query Examples**:
- "How does authentication flow across microservices?"
- "Where should caching improve performance?"
- "What error handling patterns are used in this repo?"

**Integration**:
- MCP endpoint: `https://open-aware.qodo.ai/mcp`
- Connects directly with Claude and compatible AI systems
- Available in Qodo Aware product

**SE Demo Points**:
- Show complex codebase query (multi-repo)
- Demonstrate pattern identification
- Highlight vs traditional search (semantic vs keyword)
- Show implementation planning capability

---

#### 4. AlphaCodium (Research) ⭐ 3,920 stars
**Repository**: https://github.com/Codium-ai/AlphaCodium
**Language**: Python
**Paper**: "Code Generation with AlphaCodium: From Prompt Engineering to Flow Engineering"

**What it is**: Research implementation introducing "flow engineering" for code generation

**Key Innovation**:
Traditional prompt engineering proved insufficient for code generation. AlphaCodium moves from "asking better questions" to "designing better workflows."

**Research Finding**: 95% of development effort should go to flow architecture, not prompt refinement

**The Flow Engineering Approach**:
1. **Initial analysis**: Break problems into semantic components
2. **Code generation**: Create modular, well-structured solutions
3. **AI-generated testing**: Create comprehensive test cases
4. **Iterative refinement**: Fix code based on test failures
5. **Validation**: Double-check outputs before finalization

**Performance Benchmarks** (CodeContests dataset):
- **GPT-4 (pass@5)**: 19% with direct prompting → 44% with AlphaCodium (+131% improvement)
- **Efficiency**: Uses 15-20 API calls per solution (vs millions in comparable approaches)
- **Current leader**: GPT-4o achieves highest performance

**Transferable Principles**:
- Structured YAML outputs matching specific formats
- Semantic reasoning through organized analysis
- Modular code generation with named sub-functions
- "Double validation" where models review their own output

**Relevance to Qodo Products**:
AlphaCodium research informs Qodo Gen's code generation architecture and testing workflows.

**SE Demo Points**:
- Reference in technical deep dives
- Cite performance benchmarks (19% → 44%)
- Position Qodo as research-driven (not just product)
- Highlight flow engineering in Qodo Gen architecture

---

#### 5. Agents & Command (Customization) ⭐ 118 stars + 86 stars
**Repositories**:
- https://github.com/qodo-ai/agents (Playbooks)
- https://github.com/qodo-ai/command (CLI)

**What they are**: Configurable AI workflows combining instructions, tools, arguments, execution strategy, output schema, and exit expressions

**Core Components**:
- **Instructions**: Natural language directives defining behavior
- **Tools**: MCP servers and integrations available to agents
- **Arguments**: Configurable parameters
- **Execution Strategy**: Planning vs. direct action
- **Output Schema**: Structured result formatting
- **Exit Expressions**: Success/failure conditions for CI/CD

**Available Agent Templates**:

**Development Workflow**:
- Code review automation
- Test generation
- GitHub issue handling

**Security & Compliance**:
- OpenSSF Scorecard fixes
- Package health assessment
- License compliance checking

**Infrastructure**:
- AWS static site deployment automation

**Customization Options**:
1. **Remote Configuration**: Point to remote URL with agent config
2. **Local TOML Files**: Download and modify `.toml` files

**Creating Custom Agents**:
```toml
[agent]
name = "custom-reviewer"
instructions = "Review code for HIPAA compliance"
tools = ["filesystem", "git", "code-analysis"]
execution_strategy = "planning"

[arguments]
compliance_standard = "HIPAA"
severity_threshold = "medium"

[output_schema]
format = "json"
fields = ["issues", "suggestions", "compliance_score"]

[exit_expressions]
success = "compliance_score >= 90"
```

**SE Demo Points**:
- Show customization for customer-specific compliance
- Demonstrate agent creation workflow
- Highlight vs competitors (fixed workflows)
- Show CI/CD integration with exit expressions

---

#### 6. PR Compliance Templates ⭐ 8 stars
**Repository**: https://github.com/qodo-ai/pr-compliance-templates

**What it is**: Production-ready `pr_compliance_checklist.yaml` templates for intelligent code review automation

**Available Categories**:
- **Universal**: Global compliance applicable across all projects
- **Tech-Specific**: Back-end, C++, C#, Dart, Dockerfile, Front-end, Go, JavaScript, Kotlin, PHP, Python, Ruby, Rush, Scala, Swift, TypeScript

**What Each Template Includes**:
- Architecture patterns
- Performance considerations
- Maintainability issues
- Framework-specific pitfalls
- Security vulnerabilities

**Implementation Options**:

**Local Setup**:
```
your-repo/
├── pr_compliance_checklist.yaml
└── src/
```

**Hierarchical Setup** (monorepos):
```
pr-agent-settings/
├── metadata.yaml
└── compliance/
    ├── backend-python.yaml
    ├── frontend-react.yaml
    └── mobile-kotlin.yaml
```

**Customization**:
Each compliance item requires:
- Title
- Objective
- Success criteria
- Failure criteria

**What Templates DON'T Include**:
Basic linting, syntax checking, import organization (handled by existing automation)

**SE Demo Points**:
- Show Python compliance template in action
- Demonstrate customization for customer standards
- Highlight vs generic linters (contextual understanding)
- Show monorepo multi-project setup

---

### Supporting Repositories

#### SDKs & APIs
- **qodo-py-sdk**: Python SDK for Qodo API
- **qodo-ts-sdk**: TypeScript SDK for Qodo API
- **qodo-go-sdk**: Go library for Qodo chat API with streaming support
- **qodo-git-sdk**: Git functionality across different providers

#### IDE Extensions
- **codiumai-vscode-release** ⭐ 309 stars: VS Code extension
- **codiumai-jetbrains-release** ⭐ 69 stars: JetBrains extension

#### Enterprise & On-Premises
- **qodo-onprem-examples**: On-premises deployment examples
- **qodo-onprem-charts**: Helm charts for Kubernetes deployment
- **perforce**: Helm chart for Perforce Helix Core/Swarm on GKE

#### Developer Resources
- **qodo-docs**: Product documentation
- **product-workshop**: Onboarding project for first-time experience
- **qodo-ci-example**: Examples for Qodo Cover GitHub Action
- **git-markdown-templates**: PR messages and Markdown variations across Git providers

#### Monitoring & Observability
- **grafana-dashboards**: Qodo's Grafana dashboards
- **queues**: Queue abstraction library (RabbitMQ, Pub/Sub, local)

---

## 🔧 Technical Architecture & Integration Patterns

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Qodo Platform Architecture                                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Qodo Gen    │  │ Qodo Merge   │  │ Qodo Command │     │
│  │  (IDE)       │  │ (PR Review)  │  │ (CLI/CI)     │     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
│         │                  │                  │              │
│         └──────────────────┼──────────────────┘              │
│                            │                                 │
│                   ┌────────▼────────┐                       │
│                   │  Qodo Aware     │                       │
│                   │  (Context       │                       │
│                   │   Engine)       │                       │
│                   └────────┬────────┘                       │
│                            │                                 │
│         ┌──────────────────┼──────────────────┐            │
│         │                  │                  │              │
│  ┌──────▼───────┐  ┌──────▼───────┐  ┌──────▼───────┐    │
│  │ Vector DB    │  │ Multi-Repo   │  │ MCP Server   │    │
│  │ (Embeddings) │  │ Indexing     │  │ (Tools)      │    │
│  └──────────────┘  └──────────────┘  └──────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### API Integration Patterns

#### 1. Python SDK Integration
```python
from qodo import QodoClient

# Initialize client
client = QodoClient(api_key="your-api-key")

# Generate tests
tests = client.gen.generate_tests(
    source_file="src/calculator.py",
    coverage_target=85,
    framework="pytest"
)

# Review PR
review = client.merge.review_pr(
    repo="owner/repo",
    pr_number=123,
    severity_threshold="medium"
)

# Query codebase
context = client.aware.get_context(
    query="authentication flow in microservices",
    repos=["service-a", "service-b"],
    language="python"
)
```

#### 2. TypeScript SDK Integration
```typescript
import { QodoClient } from '@qodo/ts-sdk';

const client = new QodoClient({ apiKey: process.env.QODO_API_KEY });

// Generate code
const code = await client.gen.generateCode({
  prompt: "Create a REST API endpoint for user authentication",
  language: "typescript",
  framework: "express"
});

// Review code
const review = await client.merge.reviewChanges({
  files: changedFiles,
  rules: customRules
});
```

#### 3. CLI Integration (Qodo Command)
```bash
# Install CLI
npm install -g @qodo/cli

# Configure
qodo auth login

# Run agent
qodo run code-review \
  --agent compliance-checker \
  --input ./src \
  --config compliance.toml

# CI/CD integration
qodo run test-generator \
  --source src/ \
  --tests tests/ \
  --coverage-target 85 \
  --exit-on-failure
```

### CI/CD Integration Examples

#### GitHub Actions (Qodo Merge)
```yaml
name: Qodo PR Review
on: [pull_request]

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Qodo PR Review
        uses: qodo-ai/pr-agent-action@v1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          command: /review

      - name: Qodo Improve
        if: github.event.review.state == 'changes_requested'
        uses: qodo-ai/pr-agent-action@v1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          command: /improve
```

#### GitLab CI (Qodo Cover)
```yaml
qodo-test-generation:
  stage: test
  image: qodo/cover-agent:latest
  script:
    - cover-agent \
        --source-file-path "src/**/*.py" \
        --test-file-path "tests/" \
        --coverage-type "cobertura" \
        --desired-coverage 85
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml
```

#### Jenkins (Qodo Command)
```groovy
pipeline {
  agent any

  stages {
    stage('Code Review') {
      steps {
        sh '''
          qodo run compliance-checker \
            --input ${WORKSPACE}/src \
            --config compliance.toml \
            --output-format json
        '''
      }
    }

    stage('Test Generation') {
      steps {
        sh '''
          qodo run test-generator \
            --source src/ \
            --coverage-target 80
        '''
      }
    }
  }
}
```

### Webhook Integration

#### Setting Up PR-Agent Webhook
```python
from flask import Flask, request
import hmac
import hashlib

app = Flask(__name__)

@app.route('/webhook/pr-agent', methods=['POST'])
def handle_pr_webhook():
    # Verify signature
    signature = request.headers.get('X-Hub-Signature-256')
    body = request.get_data()

    if not verify_signature(body, signature):
        return 'Invalid signature', 403

    # Parse PR event
    event = request.json

    if event['action'] == 'opened':
        # Trigger PR review
        trigger_pr_agent_review(
            repo=event['repository']['full_name'],
            pr_number=event['pull_request']['number']
        )

    return 'OK', 200

def verify_signature(body, signature):
    secret = os.environ['WEBHOOK_SECRET']
    expected = 'sha256=' + hmac.new(
        secret.encode(),
        body,
        hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(signature, expected)
```

### Model Context Protocol (MCP) Integration

#### Connecting Qodo Aware via MCP
```json
{
  "mcpServers": {
    "qodo-aware": {
      "url": "https://open-aware.qodo.ai/mcp",
      "apiKey": "${QODO_API_KEY}"
    }
  }
}
```

#### Using MCP Tools
```python
# In Claude or compatible AI system
tools = [
  {
    "name": "get_context",
    "description": "Retrieve relevant code context",
    "parameters": {
      "query": "authentication implementation",
      "repos": ["backend", "auth-service"],
      "language": "python"
    }
  },
  {
    "name": "deep_research",
    "description": "Analyze code patterns and architecture",
    "parameters": {
      "topic": "error handling patterns",
      "scope": "multi-repo"
    }
  }
]
```

### Multi-Repo Setup (Qodo Aware)

#### Indexing Multiple Repositories
```bash
# CLI indexing
qodo aware index \
  --repos "org/service-a,org/service-b,org/common-lib" \
  --update-schedule daily

# Configuration file
cat > aware-config.yaml << EOF
repos:
  - org/service-a
  - org/service-b
  - org/common-lib

indexing:
  schedule: daily
  languages: [python, typescript]
  exclude_patterns:
    - "*/tests/*"
    - "*/node_modules/*"
EOF

qodo aware index --config aware-config.yaml
```

#### Querying Across Repos
```bash
# Cross-repo query
qodo aware query \
  "How do services communicate with each other?" \
  --repos service-a,service-b \
  --format markdown

# Output includes context from both repos with citations
```

---

## 🏢 Enterprise Deployment Patterns

### On-Premises Deployment

#### Kubernetes/Helm Chart Deployment
```bash
# Add Qodo Helm repository
helm repo add qodo https://charts.qodo.ai
helm repo update

# Install Qodo Platform
helm install qodo-platform qodo/qodo-platform \
  --namespace qodo \
  --create-namespace \
  --set global.domain=qodo.company.internal \
  --set aiProvider.type=azure-openai \
  --set aiProvider.endpoint=https://company.openai.azure.com \
  --values custom-values.yaml
```

#### Custom Values for Enterprise
```yaml
# custom-values.yaml
global:
  domain: qodo.company.internal
  tlsEnabled: true
  sso:
    enabled: true
    provider: okta
    domain: company.okta.com

aiProvider:
  type: azure-openai  # or: openai, anthropic, custom
  endpoint: https://company.openai.azure.com
  apiKeySecret: azure-openai-key

security:
  dataRetention: 48h  # Auto-purge
  auditLogging: true
  networkPolicy: strict

storage:
  type: postgresql
  host: postgres.company.internal
  database: qodo_prod

cache:
  type: redis
  cluster: true
  nodes:
    - redis-0.company.internal:6379
    - redis-1.company.internal:6379
    - redis-2.company.internal:6379

scaling:
  gen:
    replicas: 3
    resources:
      cpu: 2000m
      memory: 4Gi
  merge:
    replicas: 5
    resources:
      cpu: 1000m
      memory: 2Gi
  aware:
    replicas: 2
    resources:
      cpu: 4000m
      memory: 8Gi
```

#### Air-Gapped Deployment
```bash
# 1. Download container images
docker pull qodo/gen:latest
docker pull qodo/merge:latest
docker pull qodo/command:latest
docker pull qodo/aware:latest

# 2. Save images
docker save qodo/gen:latest > qodo-gen.tar
docker save qodo/merge:latest > qodo-merge.tar
docker save qodo/command:latest > qodo-command.tar
docker save qodo/aware:latest > qodo-aware.tar

# 3. Transfer to air-gapped environment

# 4. Load images
docker load < qodo-gen.tar
docker load < qodo-merge.tar
docker load < qodo-command.tar
docker load < qodo-aware.tar

# 5. Deploy using internal registry
helm install qodo-platform qodo/qodo-platform \
  --set global.imageRegistry=registry.company.internal \
  --set aiProvider.type=custom \
  --set aiProvider.endpoint=http://local-llm.company.internal
```

---

## 📚 SE Quick Reference: GitHub Resources

### Demo Preparation Resources

**Show customers actual code**:
- AlphaCodium: https://github.com/Codium-ai/AlphaCodium
- PR-Agent: https://github.com/qodo-ai/pr-agent
- Qodo-Cover: https://github.com/qodo-ai/qodo-cover

**Reference in demos**:
- "This is open-source - 10,000+ stars on GitHub"
- "Fortune 100 companies use this exact code"
- "You can self-host and customize everything"

### Integration Examples for Customers

**CI/CD Examples**:
- GitHub Actions: qodo-ci-example repo
- GitLab CI: pr-agent repo docs
- Jenkins: agents repo templates

**Compliance Templates**:
- Tech-specific: pr-compliance-templates repo
- Customization: Show TOML/YAML files
- Enterprise setup: Hierarchical config example

### Technical Deep Dive Resources

**Architecture discussions**:
- AlphaCodium paper for flow engineering concepts
- PR-Agent architecture for review system
- Open Aware MCP integration for context engine

**Performance benchmarks**:
- AlphaCodium: 19% → 44% improvement
- PR-Agent: ~30s per review
- Qodo-Cover: 45% → 85% coverage examples

### Competitive Differentiation

**Open Source Advantage**:
- 20,000+ total stars across repos
- AGPL-3.0 license (transparent)
- Self-hosting available
- Community-driven improvements

**Research-Backed**:
- AlphaCodium published research
- Flow engineering innovation
- Continuous improvement from community

---

## 🛠️ Internal Development Tools: Server-Agents Platform

### Overview

**Server-Agents** is an enterprise-grade AI Agent Platform for automating workflows across the Software Development Lifecycle (SDLC). It provides a client-server architecture where AI-powered agents assist developers, QA engineers, and other contributors with intelligent automation.

**Repository**: `/Users/wallonwalusayi/Downloads/server-agents-trunk`
**Status**: ✅ Running Locally
**Architecture**: Client-Server with WebSocket communication

---

### Platform Components

#### 1. **spring-agents** (Server - Port 8080)
**Purpose**: Central hub orchestrating AI agent interactions

**Key Features**:
- **WebSocket Server**: `/agent` endpoint with API key authentication
- **Multi-LLM Support**: Anthropic Claude + Ollama via Spring AI
- **Remote Tool Execution**: Proxies tool calls to connected clients
- **Multi-Tenant Architecture**: Per-customer token allowances
- **Usage Tracking**: Per-model token usage with configurable reset policies
- **Security**: JWT tokens, API key hashing, audit logging, rate limiting
- **Observability**: Prometheus metrics, Grafana dashboards, structured logging

**Database Entities**:
- `CUSTOMER` - Multi-tenant customer records
- `CUSTOMER_TOKEN` - Hashed API tokens with versioned secrets
- `LLM_MODEL` - Supported LLM models (Claude, Ollama)
- `POLICY_TYPE` - Token reset policies (daily, weekly, monthly, unlimited)
- `CUSTOMER_MODEL_ALLOWANCE` - Per-customer, per-model token limits
- `SECURITY_AUDIT_LOG` - Comprehensive audit trail

**Tech Stack**: Spring Boot, Java 21, H2/PostgreSQL

---

#### 2. **agent-sdk** (Client - Port 8081)
**Purpose**: Runs on developer machines, bridging local tools with remote server

**Key Features**:
- **WebSocket Client**: Auto-reconnect with exponential backoff
- **MCP Server Manager**: Manages local Model Context Protocol servers
- **Session Isolation**: Each session gets its own MCP server instances
- **Tool Execution**: Executes tools locally and returns results to server
- **Configuration**: YAML/JSON-based agent and MCP server configuration

**Supported MCP Server Types**:
| Type | Transport | Example |
|------|-----------|---------|
| STDIO | stdin/stdout | `npx @modelcontextprotocol/server-filesystem` |
| HTTP | Streamable HTTP | `https://mcp.sentry.dev/mcp` |
| SSE | Server-Sent Events | Legacy remote servers |

**Tech Stack**: Spring Boot, Java 21, Spring AI MCP

---

#### 3. **admin-client-spring-agents** (Admin Portal - Port 3000)
**Purpose**: Web application for platform administration

**Features**:
| Page | Functionality |
|------|---------------|
| Dashboard | System statistics, recent activity, quick actions |
| Customers | Create, enable/disable, manage API tokens, view allowances |
| Models | Add/configure LLM models, set default token allocations |
| Policies | Configure token reset policies (daily, weekly, monthly) |
| Audit Logs | View/filter security audit trail, cleanup old logs |
| Settings | Configure admin token and API settings |

**Tech Stack**: Next.js 15, TypeScript, Tailwind CSS, React Query

**Access**: http://localhost:3000

---

#### 4. **agent-message-protocol** (Shared Library)
**Purpose**: Shared Java library defining WebSocket message protocol

**Message Types**:
| Direction | Message | Description |
|-----------|---------|-------------|
| Server → Client | `ConnectionEstablished` | Connection confirmation |
| Server → Client | `SessionStarted` | Session creation confirmation |
| Server → Client | `ToolCallRequest` | Request to execute a tool |
| Server → Client | `StreamChunk` | Streaming response chunk |
| Server → Client | `SessionResult` | Final session result |
| Server → Client | `ErrorMessage` | Error notification |
| Client → Server | `CreateSession` | Create new session with agent config |
| Client → Server | `ToolCallResponse` | Tool execution result |
| Client → Server | `CancelSession` | Cancel active session |
| Bidirectional | `Heartbeat` | Keep-alive message |

---

### Agent Types (SDLC Roles)

| Agent Type | Purpose | Writes Code | Uses Tools |
|------------|---------|-------------|------------|
| **ANALYST** | Understands intent, resolves ambiguity, produces execution plans and technical designs | No | Yes |
| **ENGINEER** | Implements approved designs by producing production-ready code | Yes | Yes |
| **REVIEWER** | Validates correctness, security, and alignment with requirements | No | Yes |
| **DIAGNOSTICIAN** | Performs root cause analysis when other agents fail | No | Yes |

---

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│          ADMIN PORTAL (Port 3000)                            │
│          Next.js Web Application                             │
│  Dashboard | Customers | Models | Policies | Audit Logs     │
└────────────────────────┬────────────────────────────────────┘
                         │ REST API (Bearer Token Auth)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│          SPRING-AGENTS SERVER (Port 8080)                    │
│                                                              │
│  WebSocket: /agent (API Key Auth)                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ LLM (Claude) │  │ Customer     │  │ Agents:      │     │
│  │ (Spring AI)  │  │ Management   │  │ • ANALYST    │     │
│  │ + Ollama     │  │ • Tokens     │  │ • ENGINEER   │     │
│  └──────────────┘  │ • Usage      │  │ • REVIEWER   │     │
│                    └──────────────┘  │ • DIAGNOSTICIAN│     │
│                                      └──────────────┘     │
│  Database: CUSTOMER | TOKEN | MODEL | POLICY | AUDIT      │
└────────────────────────┬────────────────────────────────────┘
                         │ WebSocket (TLS)
                         │ Tool Call Requests ↓ / Results ↑
                         ▼
┌─────────────────────────────────────────────────────────────┐
│          AGENT-SDK (Port 8081)                               │
│          Developer Machine                                   │
│                                                              │
│  WebSocket Client Handler (Auto-reconnect)                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ MCP Server Manager (Spring AI MCP)                    │  │
│  │ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │  │
│  │ │Filesystem│ │ Terminal │ │   Git    │ │ Custom   │ │  │
│  │ │ (STDIO)  │ │ (STDIO)  │ │ (STDIO)  │ │(HTTP/SSE)│ │  │
│  │ └──────────┘ └──────────┘ └──────────┘ └──────────┘ │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  Local Resources: File System | Terminal | Git | APIs       │
└─────────────────────────────────────────────────────────────┘
```

---

### Current Status (Running Locally)

**Services Running**:
- ✅ Spring-Agents Server: http://localhost:8080 (PID in `server.pid`)
- ✅ Admin Portal: http://localhost:3000 (PID in `admin-portal.pid`)
- ✅ Agent SDK Client: http://localhost:8081 (PID in `agent-sdk.pid`)

**Credentials** (Local Dev):
```bash
# Admin Portal Token
Bearer MyFixedAdminToken123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ==

# Agent SDK API Token (JWT)
eyJhbGciOiJIUzM4NCJ9.eyJqdGkiOiIzMmViNTZiMS0zNDY3LTQ5ODQtYTU4OS1jNDRkZWE1ZjdlZTEiLCJpc3MiOiJzcHJpbmctYWdlbnRzIiwic3ViIjoiYjA2MTdhMzYtOWE0YS00ODQ4LThmOGUtOGNhYTQ3OGVjOGI4IiwiaWF0IjoxNzcxMjk0NzgwLCJjdXN0b21lcklkIjoiYjA2MTdhMzYtOWE0YS00ODQ4LThmOGUtOGNhYTQ3OGVjOGI4IiwiY3VzdG9tZXJOYW1lIjoiYWNtZSIsInRva2VuVHlwZSI6IkFQSSJ9.2jpzpSkq26D2kxro1rUKfL8TtcGbVVMOsaQK77wt2J892EYQ4PpnVFw28tUiwTmE

# Stored in:
# - .env.fixed (server)
# - .env.agent-sdk (client)
# - .admin-token (backup)
```

**Demo Customers**:
- `acme` (ID: b0617a36-9a4a-4848-8f8e-8caa478ec8b8)
- `globex` (second demo customer)

---

### Usage Patterns

#### 1. **Admin Portal (Web UI)**
**Access**: http://localhost:3000

**Common Tasks**:
- View dashboard and system statistics
- Manage customers and generate API tokens
- Configure LLM models and token allowances
- View audit logs and monitor usage
- Enable/disable customers

**Quick Actions**:
```
1. Go to http://localhost:3000
2. Click "Customers" → View demo customers
3. Click "acme" → View details and token usage
4. Click "Generate Token" → Create new API tokens
```

---

#### 2. **REST API (Automation)**

**Get System Stats**:
```bash
curl -H "Authorization: Bearer MyFixedAdminToken123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ==" \
  http://localhost:8080/api/admin/stats
```

**List All Customers**:
```bash
curl -H "Authorization: Bearer MyFixedAdminToken123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ==" \
  http://localhost:8080/api/customers
```

**Create New Customer**:
```bash
curl -X POST \
  -H "Authorization: Bearer MyFixedAdminToken123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ==" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-team",
    "enabled": true,
    "defaultMinTokenNotificationThreshold": 10000
  }' \
  http://localhost:8080/api/customers
```

**Generate API Token**:
```bash
curl -X POST \
  -H "Authorization: Bearer MyFixedAdminToken123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ==" \
  http://localhost:8080/api/customers/b0617a36-9a4a-4848-8f8e-8caa478ec8b8/tokens
```

**View Customer Details**:
```bash
curl -H "Authorization: Bearer MyFixedAdminToken123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ==" \
  http://localhost:8080/api/customers/b0617a36-9a4a-4848-8f8e-8caa478ec8b8
```

---

#### 3. **WebSocket Agent Sessions (Python)**

**Test WebSocket Connection**:
```bash
cd /Users/wallonwalusayi/Downloads/server-agents-trunk/examples/
python3 3-test-websocket-connection.py
```

**Create Agent Session**:
```bash
python3 4-create-agent-session.py
```

---

### Agent Configuration Example

**YAML Configuration**:
```yaml
version: "1.0"
agents:
  code-reviewer:
    description: "Reviews code for quality and security"
    type: REVIEWER
    instructions: |
      Review the provided code for:
      1. Code quality and maintainability
      2. Security vulnerabilities
      3. Performance issues
      4. Adherence to best practices
    mcpServers: |
      {
        "filesystem": {
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-filesystem", "/project"]
        }
      }
    tools:
      - filesystem.read_file
      - filesystem.list_directory
    output_schema: '{"type": "object", "properties": {"findings": {...}}}'
```

---

### Prerequisites

**Required**:
- Java 21+
- Node.js 18+
- Gradle 8+
- Anthropic API key (for Claude models)

**Optional**:
- Ollama (for local LLM support)

---

### Starting Services

**1. Start Spring-Agents Server**:
```bash
cd spring-agents

# Set environment variables
export ANTHROPIC_API_KEY=your-key
export AGENT_ADMIN_API_TOKEN=$(openssl rand -base64 48)
export AGENT_HASHING_SECRET_V1=$(openssl rand -base64 64)
export AGENT_JWT_SIGNING_KEY=$(openssl rand -base64 48)

# Run with local profile
./gradlew bootRun --args='--spring.profiles.active=local'
```

**2. Start Admin Portal**:
```bash
cd admin-client-spring-agents/admin-ui
npm install
npm run dev
```

**3. Start Agent SDK Client**:
```bash
cd agent-sdk
# Configure in application.yml or environment variables
./gradlew bootRun
```

---

### Example Scripts

Located in `examples/` directory:
- `1-create-customer.sh` - Create new customer via API
- `2-generate-api-token.sh` - Generate API token for customer
- `3-test-websocket-connection.py` - Test WebSocket connectivity
- `4-create-agent-session.py` - Create and interact with agent session

---

### Security Model

**Authentication**:
- Admin API: Bearer token authentication
- WebSocket: API key in `X-API-Key` header
- JWT tokens for session management

**Token Management**:
- Hashed storage with versioned secrets
- Configurable reset policies (daily, weekly, monthly)
- Per-customer, per-model allowances
- Low balance notifications

**Audit Logging**:
- All API calls logged
- Token generation/usage tracked
- Security events captured
- Cleanup policies configurable

---

### Observability

**Metrics** (Prometheus):
- Customer-level token usage
- Model-specific metrics
- WebSocket connection statistics
- Tool execution metrics

**Logging**:
- Structured JSON logging
- Per-service log files (server.log, agent-sdk.log, admin-portal.log)
- Configurable log levels

**Health Endpoints**:
- `/actuator/health` - Service health
- `/actuator/metrics` - Prometheus metrics
- `/actuator/info` - Build/version information

---

### SDLC Workflow Examples

#### Code Review Workflow
1. Developer commits code to Git
2. REVIEWER agent analyzes changes via filesystem MCP
3. Agent produces structured review findings
4. Results returned to developer via UI/API

#### Test Generation Workflow
1. ANALYST agent examines codebase structure
2. ENGINEER agent generates test cases
3. REVIEWER agent validates test coverage
4. Tests committed to repository

#### Bug Diagnosis Workflow
1. Developer reports issue
2. DIAGNOSTICIAN agent analyzes logs and code
3. Agent identifies root cause
4. Provides fix recommendations

---

### Integration Points

**Works With**:
- Model Context Protocol (MCP) servers
- Anthropic Claude API
- Ollama (local LLMs)
- Git repositories (via MCP)
- File systems (via MCP)
- Terminal/shell commands (via MCP)
- Custom HTTP/SSE MCP servers

**Can Be Extended With**:
- Custom MCP servers
- Additional LLM providers
- Custom agent types
- Specialized tools

---

### SE Knowledge: Using Server-Agents for Development

**Use Cases for SEs**:
1. **Demo Environment Setup**: Automated environment provisioning with ENGINEER agents
2. **Code Review Automation**: REVIEWER agents for customer demo code
3. **Integration Testing**: DIAGNOSTICIAN agents for troubleshooting
4. **Documentation Generation**: ANALYST agents for technical docs
5. **Custom Workflow Automation**: Agent chains for repetitive tasks

**Tips**:
- Use ANALYST agents for understanding customer requirements
- Use ENGINEER agents for generating demo code quickly
- Use REVIEWER agents to QA customer integrations
- Use DIAGNOSTICIAN agents when demos fail unexpectedly

---

### Quick Reference

**Key Files**:
- `README.md` - Complete platform documentation
- `HOW_TO_USE.md` - Usage guide with examples
- `SETUP_COMPLETE.md` - Current running status
- `agent_types.md` - Detailed agent type specifications

**Key Directories**:
- `spring-agents/` - Server implementation
- `agent-sdk/` - Client implementation
- `admin-client-spring-agents/` - Admin portal
- `agent-message-protocol/` - Shared protocol library
- `examples/` - Example scripts and usage patterns

**Logs**:
- `server.log` - Spring-Agents server logs
- `agent-sdk.log` - Agent SDK client logs
- `admin-portal.log` - Admin portal logs

**Process Management**:
- `server.pid` - Server process ID
- `agent-sdk.pid` - Client process ID
- `admin-portal.pid` - Portal process ID

---

*This knowledge-core.md is maintained by Claude's adaptive learning system and updated as new patterns emerge from actual SE workflows.*
