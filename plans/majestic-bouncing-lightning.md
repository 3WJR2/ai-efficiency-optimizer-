# Azure Tenant & Azure DevOps Setup Tutorial for Qodo SaaS - Sales Engineering Demo Environment

## Overview
Create a comprehensive setup tutorial for a new Azure tenant with Azure DevOps, specifically designed for a Sales Engineering demo environment with Qodo SaaS integration. The tutorial will cover tenant setup, Azure AD groups, user management, permissions, and both PAT and OAuth authentication models.

## User Requirements
- **Audience**: Sales Engineering team (multiple users, not just one admin)
- **Purpose**: Demo environment that SE team can use to showcase Qodo to customers
- **Scope**:
  - Support both single project (multi-branch) and multi-project setups
  - Document both PAT (quick demos) and OAuth (enterprise demos) authentication
  - SE team needs Organization Administrator access for demo flexibility
- **Groups**: Four Azure AD groups for proper access control
- **Reference**: Based on Google doc about Single Tenant installation

## Tutorial Structure

### Part 1: Azure Tenant Foundation (NEW)
**Location**: `docs/setup/AZURE_TENANT_SETUP.md`

1. **Azure Tenant Prerequisites**
   - New Azure subscription or existing tenant
   - Global Administrator or User Administrator role
   - Billing setup for Azure DevOps

2. **Azure Active Directory (Entra ID) Configuration**
   - Verify tenant domain (e.g., `yourcompany.onmicrosoft.com`)
   - Configure external identities (if needed for SE team)
   - Set up MFA policies
   - Enable audit logging

3. **Azure AD Groups Setup**
   ```
   Group Name: Qodo-SE-Admins
   - Purpose: Full demo environment control
   - Members: SE leadership, demo environment admins
   - Permissions: Owner on Azure DevOps organization

   Group Name: Qodo-SE-Engineers
   - Purpose: Sales Engineers running customer demos
   - Members: All SE team members
   - Permissions: Project Collection Administrators

   Group Name: Qodo-SE-Viewers
   - Purpose: Read-only observers (management, executives)
   - Members: Leadership who need visibility
   - Permissions: Stakeholder access level

   Group Name: Qodo-Service-Accounts
   - Purpose: Bot accounts for Qodo integration
   - Members: qodo-bot@tenant.onmicrosoft.com
   - Permissions: Project Contributor + specific scopes
   ```

4. **User Account Creation**
   - Create individual SE team member accounts
   - Create service account: `qodo-service@tenant.onmicrosoft.com`
   - Assign to appropriate groups
   - Set password policies
   - Enable/configure SSO if needed

### Part 2: Azure DevOps Organization Setup (NEW)
**Location**: `docs/setup/AZURE_DEVOPS_ORGANIZATION_SETUP.md`

1. **Create Azure DevOps Organization**
   - Navigate to `dev.azure.com`
   - Create new organization (e.g., `qodoinc` or `yourcompany-demos`)
   - Link to Azure AD tenant
   - Configure organization settings

2. **Organization-Level Configuration**
   - Set policies (third-party extensions, public projects, etc.)
   - Enable Azure AD group integration
   - Configure billing/licensing
   - Set up audit log streaming (if needed)

3. **Permission Assignment at Organization Level**
   ```
   Qodo-SE-Admins → Organization Owner
   Qodo-SE-Engineers → Project Collection Administrators
   Qodo-SE-Viewers → Project Collection Valid Users
   Qodo-Service-Accounts → (assigned per project)
   ```

4. **Organization-Wide Settings**
   - Default permissions for new projects
   - Retention policies for builds/artifacts
   - Extension management
   - Pipeline settings

### Part 3: Project Setup - Multi-Project Strategy (NEW)
**Location**: `docs/setup/PROJECT_SETUP_GUIDE.md`

1. **Template Project Creation**
   ```
   Project: Qodo-Demo-Template
   - Purpose: Master template for SE to clone
   - Contains: Branches, work items, webhooks pre-configured
   - Process: Agile
   - Visibility: Private
   ```

2. **Vertical-Specific Projects** (optional)
   ```
   Project: FinTech-Security-Demo
   - Focus: Security vulnerabilities (OWASP, PCI DSS)
   - Demo branches: auth-security, payment-security

   Project: Healthcare-Compliance-Demo
   - Focus: HIPAA, data privacy, PHI handling
   - Demo branches: hipaa-violations, phi-logging

   Project: E-Commerce-Performance-Demo
   - Focus: Performance, scalability, N+1 queries
   - Demo branches: performance-issues, scalability
   ```

3. **Project Cloning Procedure**
   - How SE team members clone template for custom demos
   - Git repository cloning
   - Work item template import
   - Webhook reconfiguration

4. **Project-Level Permissions**
   - Assign groups to projects
   - Branch policies
   - Build validation rules

### Part 4: Authentication Setup - Dual Approach (ENHANCED)
**Location**: `docs/setup/AUTHENTICATION_SETUP.md`

**Approach A: PAT Token (Quick Demos)**
1. Create Personal Access Token
   - Scopes: Code (R/W), PR Threads (R/W), Work Items (Read)
   - Expiration: 90 days
   - Naming: `qodo-demo-{se-name}-{date}`
2. Store in environment variable
3. Use for webhook authentication
4. Rotation procedure

**Approach B: OAuth 2.0 with Azure App Registration (Enterprise Demos)**

Based on Single Tenant installation doc:

1. **Azure App Registration**
   ```
   Navigate: Azure Portal → App Registrations → New

   App Name: Qodo-SaaS-Integration
   App Logo: https://www.qodo.ai/wp-content/uploads/2025/03/qodo-logo.svg
   Supported Account Types: Single tenant
   Redirect URI: https://register.oauth.app.azure.merge.qodo.ai/oauth/callback
   ```

2. **API Permissions**
   ```
   Add Permission: Azure DevOps
   Permission: user_impersonation
   Grant Admin Consent: Yes (requires Global Admin)
   ```

3. **Certificates & Secrets**
   - Generate client secret
   - Record: Application (client) ID, Tenant ID, Secret Value
   - Store securely (Azure Key Vault recommended)

4. **Service Account Setup**
   ```
   User: qodo-service@tenant.onmicrosoft.com
   Type: Native Azure user (not external)
   License: Basic (Azure DevOps)
   Groups: Qodo-Service-Accounts
   Projects: Add to demo projects as Project Administrator
   ```

5. **Register with Qodo (Incognito Browser)**
   ```
   Login as: qodo-service@tenant.onmicrosoft.com
   Navigate to: https://register.oauth.app.azure.merge.qodo.ai/
   Submit:
     - Application ID (from App overview)
     - Client Secret (secret value, not secret ID)
     - Tenant ID (from App overview)
   Save: Access token from success window
   ```

6. **Comparison Matrix**
   | Factor | PAT Token | OAuth |
   |--------|-----------|-------|
   | Setup Time | 5 min | 20 min |
   | Security | Medium | High |
   | Audit Trail | Limited | Full |
   | Best For | Quick demos | Enterprise demos |
   | Rotation | Manual | Automatic |

### Part 5: Webhook Configuration (ENHANCED)
**Location**: `docs/setup/WEBHOOK_SETUP.md`

1. **Single Tenant URL**
   - Format: `qodo-merge.{yourcompany}.st.qodo.ai`
   - Verify with Qodo contact before setup

2. **Azure DevOps Service Hooks Setup**
   ```
   Navigate: Project Settings → Service hooks → + Create subscription

   Service: Web Hooks

   Trigger Events (create 4 webhooks):
   1. Pull request created
   2. Pull request updated
   3. Pull request commented (optional)
   4. Pull request merged (optional)

   Webhook URL: https://qodo-merge.{yourcompany}.st.qodo.ai/webhook/ado

   HTTP Headers:
   X-Webhook-Secret: {access-token-from-oauth-registration}

   Filters:
   - Repository: All (or specific demo repos)
   - Branch: refs/heads/* (all branches)
   ```

3. **Testing Webhook**
   - Create test PR in demo project
   - Check Service Hook history (green checkmarks = success)
   - Verify Qodo comment appears on PR (~60 seconds)

4. **Webhook Troubleshooting**
   - 400 Bad Request: Check access token validity
   - 404 Not Found: Verify Single Tenant URL
   - Timeout: Check network connectivity
   - No comments: Verify service account permissions

### Part 6: Groups and Permissions Matrix (NEW)
**Location**: `docs/setup/PERMISSIONS_MATRIX.md`

**Comprehensive Permission Matrix**

| Action | SE Admin | SE Engineer | SE Viewer | Service Account |
|--------|----------|-------------|-----------|-----------------|
| Create projects | ✅ | ✅ | ❌ | ❌ |
| Delete projects | ✅ | ❌ | ❌ | ❌ |
| Create repos | ✅ | ✅ | ❌ | ❌ |
| Push code | ✅ | ✅ | ❌ | ❌ |
| Create PRs | ✅ | ✅ | ❌ | ❌ |
| Comment on PRs | ✅ | ✅ | ✅ | ✅ |
| Merge PRs | ✅ | ✅ | ❌ | ❌ |
| Create work items | ✅ | ✅ | ❌ | ❌ |
| Read work items | ✅ | ✅ | ✅ | ✅ |
| Configure webhooks | ✅ | ✅ | ❌ | ❌ |
| Manage users | ✅ | ❌ | ❌ | ❌ |
| View audit logs | ✅ | ❌ | ❌ | ❌ |

**Azure DevOps Permission Levels**
- Stakeholder: Free, read-only (SE Viewers)
- Basic: Standard access, $6/user/month (SE Engineers)
- Basic + Test Plans: Includes testing features
- Visual Studio Subscriber: Included with VS license

### Part 7: Demo Environment Configuration (ENHANCED)
**Location**: `docs/setup/DEMO_CONFIGURATION.md`

1. **Work Items for Each Project**
   - AB#101: Authentication Security Issues
   - AB#102: Data Validation (F-201 formatting)
   - AB#103: Performance Anti-patterns
   - AB#104: Compliance Requirements

2. **Demo Branches per Project**
   ```
   main (secure baseline)
   ├── demo/auth-security (hardcoded creds, SQL injection)
   ├── demo/data-validation (F-201 violations)
   ├── demo/performance-issues (N+1, forever loops)
   └── demo/compliance-scan (PII logging, GDPR violations)
   ```

3. **Pre-configured PRs**
   - Create sample PRs with Qodo findings
   - Save as "reference PRs" for SE team
   - Include PR templates

4. **Qodo Commands Reference**
   ```
   /review - Full security and quality review
   /improve - Code improvement suggestions
   /ask {question} - Ask questions about the code
   /describe - Generate PR description
   ```

### Part 8: SE Team Onboarding (NEW)
**Location**: `docs/setup/SE_TEAM_ONBOARDING.md`

1. **New SE Member Checklist**
   - [ ] Azure AD account created
   - [ ] Added to Qodo-SE-Engineers group
   - [ ] Access to Azure DevOps organization verified
   - [ ] Clone demo template project
   - [ ] Generate personal PAT token
   - [ ] Test webhook on sample PR
   - [ ] Complete demo walkthrough

2. **Demo Scenarios Walkthrough**
   - Scenario 1: Security Issues Demo (15 min)
   - Scenario 2: Compliance & Governance (10 min)
   - Scenario 3: Code Quality & Performance (10 min)
   - Scenario 4: Work Item Integration (5 min)

3. **Customer Demo Best Practices**
   - Pre-create PRs before customer calls
   - Use customer-relevant project names
   - Customize work items for their industry
   - Have "fix" PRs ready to show remediation

### Part 9: Maintenance & Operations (NEW)
**Location**: `docs/setup/MAINTENANCE_GUIDE.md`

1. **Quarterly Access Review**
   - Review group memberships
   - Remove departed SE members
   - Rotate PAT tokens
   - Audit service account activity

2. **Monitoring & Alerts**
   - Webhook delivery failures
   - Service account authentication errors
   - License usage
   - Storage/artifact cleanup

3. **Backup & Recovery**
   - Template project backup procedure
   - Git repository cloning
   - Work item export
   - Webhook configuration export

4. **Cost Management**
   - Azure DevOps licensing costs
   - Qodo SaaS subscription management
   - Storage costs for artifacts/repos
   - Optimization recommendations

## Critical Files to Create/Modify

### New Files to Create:
1. `docs/setup/AZURE_TENANT_SETUP.md` (~500 lines)
2. `docs/setup/AZURE_DEVOPS_ORGANIZATION_SETUP.md` (~400 lines)
3. `docs/setup/PROJECT_SETUP_GUIDE.md` (~600 lines)
4. `docs/setup/AUTHENTICATION_SETUP.md` (~800 lines) - includes both PAT and OAuth
5. `docs/setup/WEBHOOK_SETUP.md` (~400 lines)
6. `docs/setup/PERMISSIONS_MATRIX.md` (~300 lines)
7. `docs/setup/DEMO_CONFIGURATION.md` (~500 lines)
8. `docs/setup/SE_TEAM_ONBOARDING.md` (~400 lines)
9. `docs/setup/MAINTENANCE_GUIDE.md` (~300 lines)

### Master Index File:
10. `docs/QODO_SAAS_COMPLETE_SETUP.md` (~200 lines)
    - Overview and navigation to all 9 setup guides
    - Quick start vs comprehensive paths
    - Troubleshooting index

### Files to Reference (Not Modify):
- `docs/setup/AZURE_DEVOPS_SETUP_GUIDE.md` - existing project/pipeline setup
- `.qodo_aware/config.yaml` - Qodo configuration reference
- `README.md` - Demo scenarios

## Key Design Decisions

1. **Dual Authentication Approach**
   - Document both PAT and OAuth
   - PAT: Quick demos, easier setup
   - OAuth: Enterprise demos, better security

2. **Multi-Level Structure**
   - Tenant → Organization → Projects → Repositories
   - Clear separation of concerns
   - SE team can work independently within projects

3. **Group-Based Permissions**
   - Use Azure AD groups, not individual assignments
   - Easier to manage as team grows
   - Follows Azure best practices

4. **Template Project Pattern**
   - One master template
   - SE can clone for custom demos
   - Consistent experience across demos

5. **Single Tenant Integration**
   - Based on Google doc reference
   - OAuth with service account
   - Dedicated Qodo instance per customer

## Implementation Sequence

1. **Phase 1**: Create tenant and organization setup docs
2. **Phase 2**: Create authentication setup with both approaches
3. **Phase 3**: Create webhook configuration guide
4. **Phase 4**: Create permissions matrix and group setup
5. **Phase 5**: Create project setup and demo configuration
6. **Phase 6**: Create SE onboarding and maintenance guides
7. **Phase 7**: Create master index document
8. **Phase 8**: Add cross-references and navigation between docs

## Verification Steps

After creating the tutorial, verify:

1. **Completeness Check**
   - [ ] All 10 documents created
   - [ ] Cross-references work
   - [ ] Screenshots/diagrams included where helpful
   - [ ] Code samples are accurate

2. **Accuracy Check**
   - [ ] Azure AD group names consistent
   - [ ] Permission levels match Azure DevOps capabilities
   - [ ] OAuth flow matches Google doc reference
   - [ ] Webhook URLs and headers correct

3. **Usability Check**
   - [ ] SE team member can follow from scratch
   - [ ] Both PAT and OAuth paths clear
   - [ ] Troubleshooting covers common issues
   - [ ] Navigation between docs is intuitive

4. **Demo Environment Validation**
   - [ ] Template project can be cloned
   - [ ] Webhooks trigger Qodo correctly
   - [ ] Service account has proper permissions
   - [ ] All demo branches work

## Success Criteria

The tutorial is successful when:
- An SE team member with Azure access can set up a complete demo environment in 2-3 hours
- Both PAT (quick) and OAuth (enterprise) authentication methods are documented
- Multi-project setup for different verticals is supported
- Four Azure AD groups properly segregate access levels
- Webhooks successfully trigger Qodo reviews
- Template projects can be cloned for custom demos
- Maintenance procedures keep environment clean and secure

## Notes

- Tutorial assumes Azure subscription exists (billing already configured)
- Google doc reference indicates Single Tenant OAuth is preferred for production
- SE team needs flexibility to create projects for different customer demos
- Service account pattern ensures consistent Qodo integration across demos
- Group-based permissions scale better than individual assignments as team grows
