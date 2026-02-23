# Dependency Management Skill

**Version**: 1.0.0
**Purpose**: Systematic dependency management, conflict resolution, and safe upgrades
**Applies To**: brahma-dependency-resolver, brahma-security-scanner

---

## Overview

The Dependency Management skill provides systematic patterns for managing dependencies across all languages and package managers, resolving version conflicts, performing safe upgrades, and maintaining security.

**Key Capabilities**:
1. Semantic versioning mastery
2. Conflict resolution strategies
3. Safe upgrade workflows
4. Security-first dependency management
5. Multi-language support

---

## When to Use

Use Dependency Management when:
- Adding new dependencies
- Updating existing dependencies
- Resolving version conflicts
- Patching security vulnerabilities
- Migrating between major versions

Do NOT use for:
- Trivial dependency updates (single patch version)
- Dependencies in frozen/archived projects
- Third-party code you don't control

---

## Protocol

### Phase 1: Semantic Versioning Rules

```markdown
**Semver Format**: MAJOR.MINOR.PATCH (e.g., 2.5.3)

**Version Increment Rules**:
- MAJOR: Breaking changes (incompatible API changes)
- MINOR: New features (backward-compatible)
- PATCH: Bug fixes (backward-compatible)

**Version Range Syntax**:
```json
{
  "^2.5.3": ">=2.5.3 <3.0.0"  // Compatible updates
  "~2.5.3": ">=2.5.3 <2.6.0"  // Patch updates only
  "2.5.3": "2.5.3"             // Exact version
  ">=2.5.3": "2.5.3 or higher"
  "*": "any version"           // Dangerous!
}
```

**Compatibility Rules**:
```python
def is_compatible(required_version, available_version):
    """
    Check if available version satisfies required version range
    """
    if required_version.startswith('^'):
        # Caret: Allow minor and patch updates
        major = get_major(required_version)
        return get_major(available_version) == major

    elif required_version.startswith('~'):
        # Tilde: Allow patch updates only
        major_minor = get_major_minor(required_version)
        return get_major_minor(available_version) == major_minor

    else:
        # Exact match required
        return available_version == required_version
```

**Best Practices**:
- Use `^` for libraries (allow minor updates)
- Use `~` for applications (safer, patch-only)
- Never use `*` (unpredictable)
- Pin versions in lockfiles (reproducible builds)
```

---

### Phase 2: Conflict Resolution Strategies

```markdown
**Conflict Type 1: Diamond Dependency**

**Problem**:
```
App
├─ LibA (requires LibC ^2.0.0)
└─ LibB (requires LibC ^2.5.0)

Conflict: LibC version overlap exists
```

**Solution**:
Find intersection: ^2.5.0 satisfies both
```bash
# npm
npm install libc@^2.5.0

# pip
pip install libc>=2.5.0,<3.0.0

# go
go get github.com/org/libc@v2.5.0
```

---

**Conflict Type 2: Major Version Conflict**

**Problem**:
```
App
├─ LibA (requires LibC v2.x)
└─ LibB (requires LibC v3.x)

Conflict: No version overlap
```

**Resolution Options** (in order of preference):

1. **Upgrade LibA** to support LibC v3
```bash
npm install liba@latest
# Check if LibA now supports LibC v3
```

2. **Use Multiple Versions** (if supported)
```python
# Python: Use import aliasing
import libc_v2 as libc2
import libc_v3 as libc3
```

3. **Fork & Vendor** (last resort)
```bash
# Fork LibA, update to support LibC v3
git clone github.com/org/liba
# Make changes locally
# Use local version
```

---

**Conflict Type 3: Peer Dependency Conflict**

**Problem**:
```
react-router-dom requires react ^18.0.0
react-select requires react ^17.0.0
```

**Solution**:
```bash
# Option 1: Upgrade react-select
npm install react-select@latest
# Check if it now supports react 18

# Option 2: Use --legacy-peer-deps (temporary)
npm install --legacy-peer-deps
# Plan migration to compatible versions

# Option 3: Find alternative library
npm uninstall react-select
npm install downshift  # Alternative that supports react 18
```
```

---

### Phase 3: Safe Upgrade Workflow

```markdown
**Pre-Upgrade Checklist**:
- [ ] Read CHANGELOG.md for breaking changes
- [ ] Check GitHub issues for upgrade problems
- [ ] Ensure test suite exists and passes
- [ ] Create rollback plan
- [ ] Test in staging (if available)

**Upgrade Steps**:

**Step 1: Research**
```bash
# Check what's new
npm view package-name versions
npm view package-name@latest

# Read changelog
npm docs package-name
# or
curl https://api.github.com/repos/org/package/releases
```

**Step 2: Create Branch**
```bash
git checkout -b "upgrade-package-name-vX.Y.Z"
```

**Step 3: Update Dependency**
```bash
# For specific version
npm install package-name@X.Y.Z

# For latest
npm install package-name@latest

# For next major version
npm install package-name@next
```

**Step 4: Update Lockfile**
```bash
# npm
npm install

# yarn
yarn install

# pnpm
pnpm install
```

**Step 5: Check for Breaking Changes**
```bash
# Search codebase for usage
grep -r "import.*package-name" src/
grep -r "from package-name" src/

# Check deprecation warnings
npm run build 2>&1 | grep -i deprecat
```

**Step 6: Fix Breaking Changes**
```bash
# Update code to match new API
# Use codemod if available
npx package-name-codemod transform src/
```

**Step 7: Test Thoroughly**
```bash
# Run full test suite
npm test

# Run integration tests
npm run test:integration

# Run e2e tests
npm run test:e2e

# Manual testing
npm start
# Test critical flows
```

**Step 8: Security Scan**
```bash
npm audit
# Verify no new vulnerabilities
```

**Step 9: Create PR**
```bash
git add package.json package-lock.json
git commit -m "upgrade: package-name to vX.Y.Z"
git push origin upgrade-package-name-vX.Y.Z
gh pr create --title "Upgrade package-name to vX.Y.Z"
```

**Step 10: Monitor Deployment**
```bash
# Deploy to staging
deploy-staging.sh

# Monitor for 30 minutes
# Check error rates, response times

# Deploy to production (canary)
deploy-production.sh --canary 10%

# Gradual rollout
# 10% → 25% → 50% → 100%
```
```

---

### Phase 4: Security-First Dependency Management

```markdown
**Security Principles**:

1. **Patch CRITICAL Within 1 Hour**
```bash
# Detect CRITICAL CVE
npm audit --audit-level=critical

# Immediate patch
npm install package@patched-version

# Fast-track to production
git commit -m "security: Patch CVE-YYYY-XXXXX (CRITICAL)"
deploy-emergency.sh
```

2. **Review Before Adding Dependencies**
```bash
# Before: npm install new-package

# Check security
npm view new-package
npm audit --package new-package

# Check maintainer
npm view new-package maintainers

# Check last publish date
npm view new-package time

# Check GitHub
# - Stars, forks, activity
# - Open issues, especially security
# - Maintainer responsiveness
```

3. **Minimize Dependency Count**
```bash
# Prefer:
# - Standard library functions
# - Small, focused libraries
# - Well-maintained packages

# Avoid:
# - Mega-frameworks (when small utility needed)
# - Abandoned packages (last update > 2 years)
# - Packages with many CVEs
```

4. **Pin Versions in Production**
```json
// package.json (for applications)
{
  "dependencies": {
    "express": "4.18.2",  // Exact version
    "lodash": "4.17.21"   // Not ^4.17.21
  }
}

// Use lockfiles for reproducibility
// package-lock.json, yarn.lock, pnpm-lock.yaml
```

5. **Audit Regularly**
```bash
# Daily automated audit
npm audit --json > audit-results.json

# Weekly manual review
npm outdated

# Monthly dependency update
npm update --save
```
```

---

### Phase 5: Multi-Language Support

```markdown
**JavaScript/TypeScript** (npm, yarn, pnpm)
```bash
# Add dependency
npm install package-name

# Update dependency
npm update package-name

# Audit security
npm audit

# View dependency tree
npm ls package-name

# Lockfile
package-lock.json
```

**Python** (pip, poetry, pipenv)
```bash
# Add dependency
pip install package-name

# Update dependency
pip install --upgrade package-name

# Audit security
pip-audit

# View dependency tree
pipdeptree

# Lockfile
requirements.txt (manual)
Pipfile.lock (pipenv)
poetry.lock (poetry)
```

**Go** (go modules)
```bash
# Add dependency
go get github.com/org/package

# Update dependency
go get -u github.com/org/package

# Audit security
govulncheck ./...

# View dependency tree
go mod graph

# Lockfile
go.sum
```

**Rust** (cargo)
```bash
# Add dependency
cargo add package-name

# Update dependency
cargo update package-name

# Audit security
cargo audit

# View dependency tree
cargo tree

# Lockfile
Cargo.lock
```

**Java** (maven, gradle)
```bash
# Add dependency (gradle)
# build.gradle:
# implementation 'group:artifact:version'

# Update dependency
gradle dependencyUpdates

# Audit security
./gradlew dependencyCheckAnalyze

# View dependency tree
gradle dependencies

# Lockfile
gradle.lockfile
```
```

---

## Common Patterns

### Pattern 1: Security Patch (Urgent)

```bash
# Workflow for CRITICAL CVE

# 1. Detect
npm audit --audit-level=critical
# CVE-YYYY-XXXXX in package@1.0.0

# 2. Find patch
npm view package versions
# Latest: 1.0.5 (includes patch)

# 3. Update
npm install package@1.0.5

# 4. Test
npm test

# 5. Deploy immediately
git commit -m "security: Patch CVE-YYYY-XXXXX"
git push
deploy.sh --emergency

# 6. Verify
npm audit
# No CRITICAL vulnerabilities
```

**Time**: < 30 minutes
**Success Rate**: 95%

---

### Pattern 2: Major Version Migration

```bash
# Workflow for major version upgrade (breaking changes)

# Example: React 17 → React 18

# 1. Research breaking changes
curl https://reactjs.org/blog/2022/03/29/react-v18.html

# 2. Create migration branch
git checkout -b "upgrade-react-18"

# 3. Update dependencies
npm install react@18 react-dom@18

# 4. Run codemod (if available)
npx react-codemod upgrade

# 5. Fix manual changes
# - Replace ReactDOM.render with createRoot
# - Update tests for new behavior
# - Fix TypeScript type errors

# 6. Test extensively
npm test
npm run test:e2e

# 7. Manual QA
npm start
# Test all critical user flows

# 8. Create detailed PR
git commit -m "upgrade: React 17 → 18 (breaking changes)"
gh pr create --body "Migration guide: ..."

# 9. Staged rollout
deploy-staging.sh
# Monitor for 24 hours
deploy-production.sh --canary 10%
# Gradual increase to 100%
```

**Time**: 4-8 hours
**Success Rate**: 70%

---

### Pattern 3: Lockfile Conflict Resolution

```bash
# Git merge caused lockfile conflict

# 1. Detect conflict
git status
# both modified: package-lock.json

# 2. Resolve: Regenerate lockfile
rm package-lock.json
npm install

# 3. Validate
npm ci
# Should succeed without changes

# 4. Commit resolved lockfile
git add package-lock.json
git commit -m "chore: Resolve lockfile conflict"
```

**Time**: < 5 minutes
**Success Rate**: 100%

---

### Pattern 4: Dependency Cleanup

```bash
# Remove unused dependencies

# 1. Find unused
npx depcheck

# 2. Remove unused
npm uninstall unused-package-1 unused-package-2

# 3. Find duplicates
npm dedupe

# 4. Update lockfile
npm install

# 5. Verify build still works
npm run build
npm test
```

**Time**: 30 minutes
**Success Rate**: 90%
**Benefit**: Reduce bundle size, security surface

---

### Pattern 5: Pin Transitive Dependencies

```bash
# Force specific version of transitive dependency

# Problem: LibA requires LibC@^2.0.0, but we need 2.5.0

# Solution 1: npm overrides (npm 8.3+)
# package.json:
{
  "overrides": {
    "libc": "2.5.0"
  }
}

# Solution 2: yarn resolutions
# package.json:
{
  "resolutions": {
    "libc": "2.5.0"
  }
}

# Solution 3: pnpm overrides
# package.json:
{
  "pnpm": {
    "overrides": {
      "libc": "2.5.0"
    }
  }
}
```

**Time**: < 5 minutes
**Success Rate**: 95%

---

## Best Practices

### DO:
✅ Read changelogs before upgrading
✅ Test upgrades in staging first
✅ Pin versions in production
✅ Use lockfiles for reproducibility
✅ Audit dependencies regularly
✅ Minimize dependency count
✅ Review security before adding new deps
✅ Keep dependencies up-to-date

### DON'T:
❌ Use wildcard versions (`*`)
❌ Upgrade multiple deps at once
❌ Skip testing after upgrades
❌ Ignore security advisories
❌ Add deps without review
❌ Commit without lockfile
❌ Use abandoned packages
❌ Deploy directly to production

---

## Integration with Agents

**brahma-dependency-resolver** uses this skill for:
- All dependency operations
- Conflict resolution
- Safe upgrades
- Lockfile management

**brahma-security-scanner** uses this skill for:
- CVE patch application
- Dependency security assessment
- Upgrade prioritization

---

## Troubleshooting

**Problem**: Dependency conflict can't be resolved automatically

**Solution**:
1. Check if both dependents can be upgraded
2. Look for alternative libraries
3. Use dependency overrides as last resort
4. Escalate to human for manual decision

---

**Problem**: Tests fail after dependency upgrade

**Solution**:
1. Read changelog for breaking changes
2. Search issues for similar problems
3. Bisect: Upgrade one version at a time to find breaking version
4. Fix code to match new API
5. If unfixable, rollback and document issue

---

**Problem**: Lockfile out of sync with dependency file

**Solution**:
```bash
rm *-lock.json *-lock.yaml
npm install  # or yarn install, pnpm install
```

---

**Skill Version**: 1.0.0
**Last Updated**: 2026-01-31
**Status**: Ready for Use
