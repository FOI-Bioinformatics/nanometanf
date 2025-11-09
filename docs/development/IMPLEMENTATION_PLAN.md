# Code Quality Implementation Plan

**Created:** 2025-11-04
**Based on:** [CODE_QUALITY_EVALUATION_2025-11-04.md](CODE_QUALITY_EVALUATION_2025-11-04.md)
**Target Completion:** 4 weeks (part-time effort)
**Current Version:** 1.3.1dev

---

## Overview

This implementation plan addresses the findings from the comprehensive code quality evaluation conducted on 2025-11-04. The plan is organized into 5 sequential phases focusing on the most critical improvements first.

**Total Estimated Effort:** 40-50 hours over 4 weeks

---

## Phase 1: Module Metadata (CRITICAL) ⚠️

**Priority:** CRITICAL
**Duration:** 1 week (8-10 hours)
**Blocker:** Required for full nf-core compliance

### Objective

Create `meta.yml` metadata files for all 24 local modules currently missing documentation.

### Why This Matters

- **nf-core compliance:** Meta.yml files are required by nf-core standards
- **Discoverability:** Tools like `nf-core modules info` depend on metadata
- **Maintainability:** Future developers need clear module documentation
- **Linting:** `nf-core modules lint` will pass without warnings

### Tasks

#### 1.1 Identify Missing Metadata Files

```bash
# Run audit to generate list
cd /Users/andreassjodin/Code/nanometanf

for module in modules/local/*/; do
    if [ ! -f "${module}meta.yml" ]; then
        echo "Missing: ${module}meta.yml"
    fi
done > docs/development/missing_meta_yml.txt
```

**Expected Output:** List of ~24 modules without meta.yml

#### 1.2 Create meta.yml Template

Use this standardized template:

```yaml
name: module_name
description: Brief one-line description of what the module does
keywords:
  - keyword1
  - keyword2
  - keyword3
tools:
  - tool_name:
      description: Tool description from official documentation
      homepage: https://tool.homepage.com
      documentation: https://tool.docs.com
      tool_dev_url: https://github.com/tool/repository
      doi: "10.xxxx/xxxxx"  # If available
      licence: ['MIT']  # Or appropriate license

input:
  - meta:
      type: map
      description: |
        Groovy Map containing sample information
        e.g. [ id:'test', single_end:false, barcode:'barcode01' ]
  - input_files:
      type: file
      description: Description of input files
      pattern: "*.{fastq,fastq.gz,bam}"  # Update pattern as needed

output:
  - meta:
      type: map
      description: |
        Groovy Map containing sample information
  - output_files:
      type: file
      description: Description of output files
      pattern: "*.{txt,json,html}"  # Update pattern as needed
  - versions:
      type: file
      description: File containing software versions
      pattern: "versions.yml"

authors:
  - "@andreassjodin"
maintainers:
  - "@andreassjodin"
```

#### 1.3 Generate meta.yml Files

**Prioritized Module List (Do These First):**

1. **Kraken2 modules** (3 modules):
   - `kraken2_incremental_classifier/`
   - `kraken2_output_merger/`
   - `kraken2_report_generator/`

2. **Core processing modules** (5 modules):
   - `dorado_basecaller/`
   - `dorado_demux/`
   - `seqkit_merge_stats/`
   - `chopper/` (if local)
   - `nanoplot_compare/`

3. **Resource allocation modules** (6 modules):
   - `analyze_input_characteristics/`
   - `monitor_system_resources/`
   - `predict_resource_requirements/`
   - `allocate_resources/`
   - `log_performance_metrics/`
   - `generate_resource_report/`

4. **Utility modules** (remaining modules)

**Workflow:**
```bash
# For each module
cd modules/local/<module_name>/

# 1. Examine main.nf to understand inputs/outputs
cat main.nf

# 2. Create meta.yml using template
nvim meta.yml  # Or your preferred editor

# 3. Verify format
nf-core modules lint <module_name>
```

#### 1.4 Verify Stub Blocks

While creating meta.yml files, verify each module has a `stub:` block:

```bash
# Check for missing stubs
for module in modules/local/*/main.nf; do
    if ! grep -q "stub:" "$module"; then
        echo "Missing stub: $module"
    fi
done
```

**Add stub blocks where missing:**
```groovy
stub:
def prefix = task.ext.prefix ?: "${meta.id}"
"""
touch ${prefix}.output
cat <<-END_VERSIONS > versions.yml
"${task.process}":
    tool_name: 1.0.0
END_VERSIONS
"""
```

#### 1.5 Final Validation

```bash
# Run full module lint
nf-core modules lint modules/local/

# Expected: All modules pass, 0 critical errors
```

### Deliverables

- [ ] 24 new `meta.yml` files created
- [ ] All modules have stub blocks
- [ ] `nf-core modules lint` passes with 0 critical errors
- [ ] Update CLAUDE.md with module count verification

### Time Breakdown

- Module audit and planning: 1 hour
- Create 24 meta.yml files (20 min each): 8 hours
- Verify/add stub blocks: 1-2 hours
- Final validation and documentation: 1 hour

**Total: 11-12 hours**

---

## Phase 2: Documentation Cleanup ✅ (COMPLETED)

**Priority:** HIGH
**Duration:** Completed 2025-11-04
**Status:** ✅ DONE

### What Was Accomplished

1. ✅ Created archive directory structure:
   - `docs/development/archive/sessions/`
   - `docs/development/archive/progress/`
   - `docs/development/archive/phases/`
   - `docs/development/archive/v1.3.3/`

2. ✅ Moved session notes to archive:
   - `CODE_QUALITY_IMPROVEMENTS_SESSION.md` → `archive/sessions/`
   - `session_2025-10-04_critical_fixes.md` → `archive/sessions/`

3. ✅ Moved progress documents to archive:
   - `FUNCTIONAL_REFACTOR_SUMMARY.md` → `archive/progress/`
   - `PROGRESS_SUMMARY.md` → `archive/progress/`
   - `SYSTEMATIC_FIX_GUIDE.md` → `archive/progress/`

4. ✅ Moved phase documents to archive:
   - `PHASE2_TEST_IMPROVEMENTS.md` → `archive/phases/`
   - `phase_4_execution_plan.md` → `archive/phases/`
   - `phase_4_readiness.md` → `archive/phases/`
   - `OUTPUT_ORGANIZATION_TEST_ISSUE.md` → `archive/phases/`

5. ✅ Moved v1.3.3 documents to archive:
   - All 4 v1.3.3 documents → `archive/v1.3.3/`

6. ✅ Relocated misplaced docs:
   - `EVALUATION_SUMMARY.md` → `docs/development/`
   - `OPTIMIZATIONS_QUICK_REFERENCE.md` → `docs/user/`

7. ✅ Updated documentation indices:
   - Created `docs/development/README.md`
   - Updated `docs/README.md` with new structure

8. ✅ Cleaned up backup files:
   - Removed `.backup` file from tests

---

## Phase 3: Repository Cleanup ✅ (COMPLETED)

**Priority:** MEDIUM
**Duration:** Completed 2025-11-04
**Status:** ✅ DONE

### What Was Accomplished

1. ✅ Removed backup files
2. ✅ Updated `.gitignore` with patterns:
   - `*.backup`
   - `*.bak`
   - `*~`

3. ✅ Verified clean repository state

---

## Phase 4: Documentation Updates (Week 3)

**Priority:** MEDIUM
**Duration:** 1 week (4-6 hours)
**Dependencies:** Phase 2 complete ✅

### Objective

Update all documentation cross-references to reflect new structure and add helpful navigation.

### Tasks

#### 4.1 Update CLAUDE.md

**File:** `/Users/andreassjodin/Code/nanometanf/CLAUDE.md`

**Changes needed:**

1. Update documentation structure section (lines ~290-340)
2. Add reference to new archive structure
3. Update links to moved documents
4. Add reference to CODE_QUALITY_EVALUATION
5. Update "Last Updated" date to 2025-11-04

**Example updates:**
```markdown
## Documentation Structure

```
docs/
├── README.md                              # Documentation index
├── user/                                  # User-facing documentation
│   ├── usage.md                           # Pipeline usage guide
│   ├── output.md                          # Output file descriptions
│   ├── qc_guide.md                        # Quality control guide
│   ├── troubleshooting.md                 # Troubleshooting guide
│   ├── best_practices.md                  # Best practices guide
│   ├── performance_tuning.md              # Performance tuning guide
│   ├── quickstart.md                      # Quick start guide
│   └── OPTIMIZATIONS_QUICK_REFERENCE.md   # Optimizations reference
├── development/                           # Developer documentation
│   ├── README.md                          # Development index
│   ├── TESTING.md                         # Comprehensive testing documentation
│   ├── testing_guide.md                   # Testing guide
│   ├── CODE_QUALITY_EVALUATION_2025-11-04.md  # Latest quality evaluation
│   ├── IMPLEMENTATION_PLAN.md             # Code quality implementation plan
│   ├── PROMETHION_OPTIMIZATIONS.md        # Platform optimizations
│   ├── PHASE_1.1_STATUS.md                # Incremental Kraken2 status
│   ├── incremental_kraken2_implementation.md  # Kraken2 architecture
│   ├── dynamic_resource_allocation.md     # Dynamic resource docs
│   ├── production_deployment.md           # Production deployment guide
│   ├── developer_api.md                   # Developer API
│   ├── test_organization.md               # Test organization
│   ├── v1_0_roadmap.md                    # v1.0 roadmap
│   ├── EVALUATION_SUMMARY.md              # Production readiness assessment
│   └── archive/                           # Historical documentation
│       ├── sessions/                      # Development session notes
│       ├── progress/                      # Historical progress reports
│       ├── phases/                        # Completed development phases
│       └── v1.3.3/                        # v1.3.3 development history
├── releases/                              # Release notes
│   ├── v1.2.0.md
│   ├── v1.3.0.md
│   ├── v1.3.1.md
│   └── v1.3.3.md
├── validation/                            # Test coverage reports
├── integration/                           # API documentation
└── performance/                           # Performance benchmarks
```
```

#### 4.2 Update Main README.md

**File:** `/Users/andreassjodin/Code/nanometanf/README.md`

**Changes needed:**

1. Update documentation links section
2. Add reference to docs/README.md as main documentation index
3. Update version string to 1.3.1dev
4. Add note about code quality improvements

**Example addition:**
```markdown
## Documentation

Comprehensive documentation is available in the [`docs/`](docs/) directory:

- **[Documentation Index](docs/README.md)** - Complete documentation map
- **[Quick Start](docs/user/quickstart.md)** - Get started in 5 minutes
- **[Usage Guide](docs/user/usage.md)** - Complete usage instructions
- **[Development Guide](docs/development/README.md)** - For contributors

For AI-assisted development, see [CLAUDE.md](CLAUDE.md).
```

#### 4.3 Add Archive README

**File:** Create `docs/development/archive/README.md`

```markdown
# Documentation Archive

This directory contains historical documentation that is no longer actively maintained but preserved for reference.

## Structure

### `sessions/`
Development session notes and meeting summaries from specific dates. Useful for understanding the evolution of features and decisions made during development.

### `progress/`
Historical progress reports, summaries, and systematic guides from various development phases. Provides context for past development efforts.

### `phases/`
Documentation from completed development phases, including test improvements, execution plans, and readiness assessments.

### `v1.3.3/`
Complete development documentation from the v1.3.3 release cycle, including implementation summaries, testing validation, and verification reports.

## Note

These documents are preserved for historical reference and should not be updated. For current development documentation, see the parent [development/](../) directory.

**Last Updated:** 2025-11-04
```

#### 4.4 Update Cross-References

Search and replace old paths with new paths in all documentation:

```bash
# Find references to moved documents
cd /Users/andreassjodin/Code/nanometanf
grep -r "EVALUATION_SUMMARY.md" docs/ --include="*.md"
grep -r "OPTIMIZATIONS_QUICK_REFERENCE.md" docs/ --include="*.md"

# Update references manually
```

### Deliverables

- [ ] CLAUDE.md updated with new structure
- [ ] README.md updated with documentation links
- [ ] Archive README.md created
- [ ] All cross-references updated
- [ ] Dead links verified and fixed

### Time Breakdown

- CLAUDE.md updates: 1 hour
- README.md updates: 0.5 hour
- Archive README creation: 0.5 hour
- Cross-reference updates: 1-2 hours
- Verification and testing: 1 hour

**Total: 4-5 hours**

---

## Phase 5: Testing Enhancements (Week 4)

**Priority:** MEDIUM-LOW
**Duration:** 1 week (6-8 hours)
**Dependencies:** Phase 1 complete

### Objective

Improve test organization, add test tags, and standardize test patterns.

### Tasks

#### 5.1 Add tags.yml to Test Files

Create `tags.yml` in test directories for better test organization:

```bash
# Create tags.yml for modules
for test_dir in modules/local/*/tests/; do
    if [ ! -f "${test_dir}tags.yml" ]; then
        cat > "${test_dir}tags.yml" << 'EOF'
tags:
  - modules
  - modules_local
EOF
    fi
done

# Create tags.yml for subworkflows
for test_dir in subworkflows/local/*/tests/; do
    if [ ! -f "${test_dir}tags.yml" ]; then
        cat > "${test_dir}tags.yml" << 'EOF'
tags:
  - subworkflows
  - subworkflows_local
EOF
    fi
done
```

#### 5.2 Standardize Test Descriptions

Review and update test descriptions to follow consistent format:

```groovy
// Good format
test("Should process paired-end FASTQ files successfully") {
    // ...
}

test("Should handle empty input gracefully") {
    // ...
}

test("Should fail with invalid parameters") {
    // ...
}

// Avoid vague descriptions
test("Test 1") {  // Bad
test("it works") {  // Bad
```

#### 5.3 Document Test Patterns

Update `docs/development/TESTING.md` with:

1. Test naming conventions
2. Common test patterns used in the pipeline
3. How to use tags for test organization
4. Examples of good vs. bad tests

**Add section:**
```markdown
## Test Organization with Tags

### Using tags.yml

Create `tags.yml` in your test directory:

\`\`\`yaml
tags:
  - modules
  - modules_local
  - realtime
  - qc_analysis
\`\`\`

### Running Tests by Tag

\`\`\`bash
# Run all realtime tests
nf-test test --tag realtime

# Run QC analysis tests
nf-test test --tag qc_analysis

# Run all local module tests
nf-test test --tag modules_local
\`\`\`

### Recommended Tags

| Tag | Purpose |
|-----|---------|
| `modules` | All module tests |
| `modules_local` | Local module tests |
| `modules_nfcore` | nf-core module tests |
| `subworkflows` | All subworkflow tests |
| `subworkflows_local` | Local subworkflow tests |
| `workflows` | Workflow tests |
| `realtime` | Real-time processing tests |
| `qc_analysis` | Quality control tests |
| `taxonomic` | Taxonomic classification tests |
| `basecalling` | Dorado basecalling tests |
```

#### 5.4 Run Full Test Suite

```bash
# Run all tests
nf-test test --verbose

# Generate coverage report (if available)
nf-test test --with-coverage

# Update snapshots if needed
nf-test test --update-snapshot
```

### Deliverables

- [ ] tags.yml files created for all test directories
- [ ] Test descriptions standardized
- [ ] TESTING.md updated with tag documentation
- [ ] Full test suite passes
- [ ] Test coverage verified

### Time Breakdown

- Create tags.yml files: 1 hour
- Standardize test descriptions: 2-3 hours
- Update TESTING.md: 1-2 hours
- Run and verify tests: 2 hours

**Total: 6-8 hours**

---

## Post-Implementation Verification

### After Phase 1 (Module Metadata)

```bash
# Verify module compliance
nf-core modules lint modules/local/

# Expected: 0 critical errors, 0 warnings about missing meta.yml
```

### After Phase 4 (Documentation Updates)

```bash
# Check for broken links (use markdown link checker)
npm install -g markdown-link-check
find docs/ -name "*.md" -exec markdown-link-check {} \;

# Or manually verify key documents
```

### After Phase 5 (Testing Enhancements)

```bash
# Run full test suite
nf-test test --verbose

# Verify all tags work
nf-test test --tag modules
nf-test test --tag subworkflows
nf-test test --tag realtime
```

### Final Validation

```bash
# Run nf-core lint
nf-core lint --verbose

# Check git status
git status

# Review changes
git diff
```

---

## Success Metrics

### Phase 1: Module Metadata
- ✅ 24/24 modules have meta.yml files
- ✅ 30/30 modules have stub blocks
- ✅ `nf-core modules lint` passes with 0 critical errors

### Phase 2-3: Documentation & Cleanup
- ✅ docs/ directory structure follows nf-core standards
- ✅ No orphaned or outdated documentation in main directories
- ✅ Clear navigation between related documents
- ✅ No .backup or temporary files tracked in git

### Phase 4: Documentation Updates
- ✅ All cross-references updated and working
- ✅ CLAUDE.md reflects current structure
- ✅ README.md links to documentation correctly

### Phase 5: Testing Enhancements
- ✅ All test directories have tags.yml
- ✅ Test descriptions are clear and consistent
- ✅ Full test suite passes
- ✅ Tests can be run by category using tags

---

## Timeline Summary

| Phase | Duration | Effort | Completion Target |
|-------|----------|--------|-------------------|
| 1: Module Metadata | Week 1 | 11-12 hours | 2025-11-11 |
| 2: Documentation Cleanup | ✅ Done | - | ✅ 2025-11-04 |
| 3: Repository Cleanup | ✅ Done | - | ✅ 2025-11-04 |
| 4: Documentation Updates | Week 3 | 4-5 hours | 2025-11-18 |
| 5: Testing Enhancements | Week 4 | 6-8 hours | 2025-11-25 |
| **Total** | **4 weeks** | **21-25 hours** | **2025-11-25** |

---

## Risk Assessment

### Low Risk
- ✅ Documentation cleanup (non-breaking changes)
- ✅ Repository cleanup (already completed)
- Creating meta.yml files (documentation only)
- Adding tags.yml files (test organization)

### Medium Risk
- Updating cross-references (potential for broken links)
- Standardizing test descriptions (requires careful review)

### Mitigation Strategies
1. **Test incrementally** - Run tests after each phase
2. **Use feature branch** - Don't commit directly to dev
3. **Peer review** - Have another developer review meta.yml files
4. **Link checking** - Use automated tools to verify documentation links
5. **Backup first** - Ensure clean git state before starting

---

## Getting Started

### Step 1: Review Evaluation Report

Read [CODE_QUALITY_EVALUATION_2025-11-04.md](CODE_QUALITY_EVALUATION_2025-11-04.md) thoroughly.

### Step 2: Set Up Work Environment

```bash
cd /Users/andreassjodin/Code/nanometanf
git checkout dev
git pull origin dev
git checkout -b feature/code-quality-improvements
```

### Step 3: Begin Phase 1

Follow Phase 1 tasks in order. Create meta.yml files for modules in priority order.

### Step 4: Track Progress

Update this document as you complete tasks. Mark checkboxes with `[x]`.

### Step 5: Commit Frequently

```bash
git add modules/local/<module_name>/meta.yml
git commit -m "feat: Add meta.yml for <module_name> module"
```

---

## Questions or Issues?

If you encounter any issues during implementation:

1. **Check the evaluation report** for context and recommendations
2. **Review nf-core guidelines** at https://nf-co.re/docs/contributing/guidelines
3. **Ask for clarification** in the development team
4. **Document blockers** in this plan for future reference

---

## Related Documents

- [CODE_QUALITY_EVALUATION_2025-11-04.md](CODE_QUALITY_EVALUATION_2025-11-04.md) - Source evaluation
- [TESTING.md](TESTING.md) - Testing guidelines
- [README.md](README.md) - Development documentation index
- [../README.md](../README.md) - Main documentation index
- [../../CLAUDE.md](../../CLAUDE.md) - AI development guide

---

**Plan Created:** 2025-11-04
**Created By:** nextflow-expert skill evaluation
**Status:** In Progress (Phases 2-3 completed)
**Next Action:** Begin Phase 1 (Module Metadata)
