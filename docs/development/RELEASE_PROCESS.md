# Release Process

**Complete guide for creating nanometanf releases**

This document describes the standard release workflow for maintainers creating new versions of the nanometanf pipeline.

**Audience:** Pipeline maintainers only
**Prerequisites:** Write access to foi-bioinformatics/nanometanf repository

---

## Table of Contents

- [Quick Reference](#quick-reference)
- [Standard Release Workflow](#standard-release-workflow)
- [Release Types](#release-types)
- [Pre-Release Checklist](#pre-release-checklist)
- [Post-Release Tasks](#post-release-tasks)
- [Hotfix Releases](#hotfix-releases)
- [Troubleshooting](#troubleshooting)

---

## Quick Reference

### Release Commands Cheat Sheet

```bash
# 1. Pre-release checks
git checkout dev && git status
nf-test test --verbose
nf-core lint --release

# 2. Version bump
# Edit nextflow.config and .nf-core.yml

# 3. Merge and tag
git checkout master
git merge dev
git tag -a v1.X.Y -m "Release v1.X.Y - [description]"
git push origin master v1.X.Y

# 4. Create GitHub release
gh release create v1.X.Y --title "v1.X.Y - [name]" --notes-file docs/releases/vX.Y.Z.md

# 5. Prepare next cycle
git checkout dev
# Edit version to 1.X.Y+1dev
git commit -m "Prepare v1.X.Y+1dev: Post-v1.X.Y development cycle"
git push origin dev
```

---

## Standard Release Workflow

### Phase 1: Pre-Release Preparation

#### 1.1 Ensure Clean State

```bash
# Switch to dev branch
git checkout dev

# Pull latest changes
git pull origin dev

# Verify clean working directory
git status  # Should show "nothing to commit, working tree clean"
```

#### 1.2 Run Comprehensive Tests

```bash
# Set up Java environment (required for nf-test)
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH

# Run full test suite
nf-test test --verbose

# Expected: All tests pass
# If tests fail: Fix issues before proceeding
```

#### 1.3 Run nf-core Linting

```bash
# Run lint with release flag
nf-core lint --release

# Expected: 0 critical failures
# Warnings are acceptable if documented

# Check specific areas
nf-core modules lint
nf-core schema lint
```

### Phase 2: Version Bump

#### 2.1 Update Version Strings

Edit the following files to remove 'dev' suffix:

**`nextflow.config`:**

```groovy
// Before
version = '1.2.1dev'

// After
version = '1.2.1'
```

**`.nf-core.yml`:**

```yaml
# Before
version: 1.2.1dev

# After
version: 1.2.1
```

#### 2.2 Commit Version Bump

```bash
git add nextflow.config .nf-core.yml
git commit -m "Update version to 1.2.1 for release readiness"
git push origin dev
```

### Phase 3: Update Documentation

#### 3.1 Update CHANGELOG.md

Add comprehensive release section:

```markdown
## [1.2.1] - 2025-11-04

### Added

- Feature 1: Description
- Feature 2: Description

### Changed

- Change 1: Description
- Change 2: Description

### Fixed

- Bug fix 1: Description
- Bug fix 2: Description

### Deprecated

- Deprecation 1: Description (if any)

### Security

- Security fix 1: Description (if any)
```

#### 3.2 Create Release Notes

Create `docs/releases/v1.2.1.md`:

```markdown
# Release v1.2.1

**Release Date:** 2025-11-04
**Type:** Patch Release
**Status:** Stable

## Summary

[2-3 sentence summary of what this release accomplishes]

## Key Changes

### New Features

- Feature description with usage example

### Bug Fixes

- Bug fix description with impact

### Performance Improvements

- Performance improvement with benchmarks

## Breaking Changes

None (or list if any)

## Migration Guide

See [Migration Guide](MIGRATION_GUIDE.md#from-v120-to-v121) for upgrade instructions.

## Known Issues

- Issue 1 (if any)
- Workaround: [description]

## Installation

\`\`\`bash
nextflow run foi-bioinformatics/nanometanf -r v1.2.1 \\
--input samplesheet.csv \\
--outdir results \\
-profile docker
\`\`\`

## Credits

Contributors to this release:

- @contributor1
- @contributor2
```

#### 3.3 Update CURRENT_VERSION.md (if needed)

If this is a new stable release or fixes critical issues, update `docs/releases/CURRENT_VERSION.md`.

#### 3.4 Commit Documentation

```bash
git add CHANGELOG.md docs/releases/
git commit -m "Release v1.2.1: [brief description]

- Added: [key features]
- Fixed: [key bugs]
- Changed: [key changes]"
git push origin dev
```

### Phase 4: Final Validation

#### 4.1 Re-run Lint

```bash
# Final lint check with release flag
nf-core lint --release

# Verify:
# - 0 critical failures
# - Version strings clean (no 'dev')
# - All files committed
```

#### 4.2 Test Pipeline with Release Config

```bash
# Run test profile with release version
nextflow run . -profile test,docker

# Expected: All tests pass
```

### Phase 5: Merge and Tag

#### 5.1 Merge to Master

```bash
# Switch to master branch
git checkout master

# Pull latest (just in case)
git pull origin master

# Merge dev branch
git merge dev

# If fast-forward is not possible:
git pull origin master --no-rebase --no-edit

# Push to master
git push origin master
```

#### 5.2 Create Annotated Tag

```bash
# Create annotated tag with detailed message
git tag -a v1.2.1 -m "Release v1.2.1 - [Brief Description]

Key Changes:
- Feature 1: Description
- Bug fix 1: Description
- Performance improvement 1: Description

Breaking Changes: None

See docs/releases/v1.2.1.md for complete release notes."

# Push tag
git push origin v1.2.1
```

### Phase 6: Create GitHub Release

#### Option A: Using GitHub CLI (Recommended)

```bash
# Ensure authenticated
gh auth status

# If not authenticated
gh auth login

# Create release from tag
gh release create v1.2.1 \
  --title "v1.2.1 - [Release Name]" \
  --notes-file docs/releases/v1.2.1.md

# Verify release created
gh release view v1.2.1
```

#### Option B: Using GitHub Web UI

1. Navigate to: `https://github.com/foi-bioinformatics/nanometanf/releases/new?tag=v1.2.1`
2. **Release title:** `v1.2.1 - [Release Name]`
3. **Description:** Copy contents from `docs/releases/v1.2.1.md`
4. **Check:** "Set as the latest release" (for stable releases)
5. **Click:** "Publish release"

### Phase 7: Sync Branches

```bash
# Keep dev in sync with master post-release
git checkout dev
git merge master
git push origin dev
```

### Phase 8: Prepare Next Development Cycle

#### 8.1 Bump to Next Dev Version

Edit version files:

**`nextflow.config`:**

```groovy
version = '1.2.2dev'
```

**`.nf-core.yml`:**

```yaml
version: 1.2.2dev
```

#### 8.2 Add CHANGELOG Placeholder

Add to top of `CHANGELOG.md`:

```markdown
## [Unreleased]

### Added

-

### Changed

-

### Fixed

-
```

#### 8.3 Commit and Push

```bash
git add nextflow.config .nf-core.yml CHANGELOG.md
git commit -m "Prepare v1.2.2dev: Post-v1.2.1 development cycle"
git push origin dev
```

---

## Release Types

### Major Release (X.0.0)

**When to use:**

- Breaking changes to API or parameters
- Major architectural changes
- Removal of deprecated features

**Requirements:**

- Comprehensive EVALUATION_SUMMARY.md
- Full test suite validation on production data
- Extended beta testing period (2-4 weeks)
- Migration guide for users

**Example:** v2.0.0

### Minor Release (1.X.0)

**When to use:**

- New features
- Non-breaking improvements
- Performance enhancements
- New experimental features

**Requirements:**

- Comprehensive CHANGELOG section
- Full test suite passing
- Release notes with usage examples

**Example:** v1.3.0

### Patch Release (1.2.X)

**When to use:**

- Bug fixes
- Security patches
- Documentation improvements
- Minor performance fixes

**Requirements:**

- Quick turnaround (1-2 days)
- Minimal testing impact
- Clear bug fix descriptions

**Example:** v1.2.1

### Hotfix Release (1.2.X, urgent)

**When to use:**

- Critical bugs affecting production
- Security vulnerabilities
- Data corruption issues

**Requirements:**

- Immediate release (same day)
- Minimal changes (fix only)
- Clear communication to users

**Example:** v1.3.1 (fixing v1.3.0 parse error)

---

## Pre-Release Checklist

### Code Quality

- [ ] All tests passing (`nf-test test --verbose`)
- [ ] nf-core lint clean (`nf-core lint --release`)
- [ ] No 'dev' suffix in version strings
- [ ] All changes committed and pushed

### Documentation

- [ ] CHANGELOG.md updated
- [ ] Release notes created (`docs/releases/vX.Y.Z.md`)
- [ ] CURRENT_VERSION.md updated (if applicable)
- [ ] Migration guide updated (if needed)
- [ ] README.md accurate

### Testing

- [ ] Test profile passes
- [ ] Real-time tests verified (if applicable)
- [ ] Platform profiles tested (if changed)
- [ ] Integration tests passing

### Communication

- [ ] Breaking changes documented
- [ ] Deprecations announced
- [ ] Contributors acknowledged

---

## Post-Release Tasks

### Immediate (Within 1 hour)

1. **Verify GitHub Release**

   ```bash
   gh release view v1.2.1
   ```

2. **Test Installation**

   ```bash
   # Fresh install test
   nextflow run foi-bioinformatics/nanometanf -r v1.2.1 -profile test,docker
   ```

3. **Update Social Media** (if major release)
   - Twitter/X announcement
   - nf-core Slack #nanometanf channel

### Short-term (Within 1 week)

4. **Monitor Issues**
   - Watch for release-related issues
   - Respond to user questions
   - Document common problems

5. **Update Documentation Site** (if applicable)
   - Deploy updated docs
   - Update version selector

6. **Notify Stakeholders**
   - Email announcement to users (if mailing list exists)
   - Update project website

---

## Hotfix Releases

### When a Hotfix is Needed

**Indicators:**

- Pipeline completely broken (like v1.3.0)
- Data corruption or incorrect results
- Security vulnerability discovered
- Critical parameter validation missing

### Hotfix Process (Fast-Track)

#### 1. Create Hotfix Branch

```bash
# From master (not dev)
git checkout master
git pull origin master

# Create hotfix branch
git checkout -b hotfix-v1.2.2
```

#### 2. Apply Fix

```bash
# Make ONLY the critical fix
# Edit necessary files

# Test the fix
nf-test test path/to/affected/test.nf.test

# Commit
git commit -m "hotfix: Fix critical issue with [component]

- Issue: [description]
- Impact: [scope]
- Fix: [what was changed]

Fixes #123"
```

#### 3. Fast-Track Testing

```bash
# Run relevant tests only (not full suite if time-critical)
nf-test test --tag critical

# Verify fix resolves issue
nextflow run . -profile test,docker
```

#### 4. Merge and Release

```bash
# Merge hotfix to master
git checkout master
git merge hotfix-v1.2.2

# Update version (patch increment)
# Edit nextflow.config: version = '1.2.2'
# Edit .nf-core.yml: version: 1.2.2

git commit -m "Bump version to 1.2.2 for hotfix release"

# Tag and push
git tag -a v1.2.2 -m "Hotfix v1.2.2 - Critical fix for [issue]"
git push origin master v1.2.2

# Create GitHub release
gh release create v1.2.2 --title "v1.2.2 - Critical Hotfix" --notes "Critical fix for [issue]. All users should upgrade immediately."
```

#### 5. Back-Merge to Dev

```bash
# Merge hotfix back to dev
git checkout dev
git merge master
git push origin dev
```

---

## Troubleshooting

### Issue: Tests failing during release

**Solution:**

```bash
# Don't release with failing tests
# Fix tests first, then restart release process

git checkout dev
# Fix issues
nf-test test --verbose
# When all pass, restart from Phase 1
```

### Issue: Merge conflict during master merge

**Solution:**

```bash
# Resolve conflicts
git checkout master
git merge dev  # Conflict occurs

# Resolve conflicts in editor
git add resolved_files
git commit -m "Merge dev to master for v1.2.1 release"
git push origin master
```

### Issue: Tag already exists

**Solution:**

```bash
# Delete local and remote tag
git tag -d v1.2.1
git push origin :refs/tags/v1.2.1

# Recreate tag
git tag -a v1.2.1 -m "Release v1.2.1 - [description]"
git push origin v1.2.1
```

### Issue: Forgot to update CHANGELOG

**Solution:**

```bash
# Update CHANGELOG
git checkout master
# Edit CHANGELOG.md
git add CHANGELOG.md
git commit --amend --no-edit
git push origin master --force-with-lease

# Update tag
git tag -d v1.2.1
git push origin :refs/tags/v1.2.1
git tag -a v1.2.1 -m "Release v1.2.1 - [description]"
git push origin v1.2.1
```

---

## Best Practices

### DO

✅ Test thoroughly before releasing
✅ Write detailed release notes
✅ Communicate breaking changes clearly
✅ Follow semantic versioning
✅ Keep CHANGELOG up to date
✅ Tag releases with annotated tags
✅ Sync dev and master branches

### DON'T

❌ Release with failing tests
❌ Skip version bump commit
❌ Force push to master
❌ Release on Friday (unless hotfix)
❌ Skip documentation updates
❌ Forget to prepare next dev cycle
❌ Rush through checklists

---

## Resources

### Documentation

- [Semantic Versioning](https://semver.org/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [GitHub Release Guide](https://docs.github.com/en/repositories/releasing-projects-on-github)

### Tools

- [gh CLI](https://cli.github.com/) - GitHub CLI
- [nf-core tools](https://nf-co.re/tools) - nf-core utilities
- [nf-test](https://www.nf-test.com/) - Testing framework

### Internal Documentation

- [Testing Guide](TESTING.md) - How to run tests
- [Migration Guide](../releases/MIGRATION_GUIDE.md) - User upgrade guide
- [Current Version](../releases/CURRENT_VERSION.md) - Version status

---

**Last Updated:** 2025-11-04
**Maintainer:** foi-bioinformatics team
**Version:** 1.3.1dev

**This is a living document. Update it as the release process evolves.**
