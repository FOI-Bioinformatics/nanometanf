# Migration Guide

**Guide for upgrading between nanometanf versions**

This guide provides step-by-step instructions for migrating between different versions of the nanometanf pipeline.

**Quick Version Check:** See [CURRENT_VERSION.md](CURRENT_VERSION.md) for recommended versions.

---

## Table of Contents

- [Quick Migration Matrix](#quick-migration-matrix)
- [From v1.0.x to v1.2.0](#from-v10x-to-v120)
- [From v1.2.0 to v1.3.3](#from-v120-to-v133)
- [From v1.3.0 to v1.3.1+](#from-v130-to-v131)
- [Breaking Changes History](#breaking-changes-history)
- [Common Migration Issues](#common-migration-issues)

---

## Quick Migration Matrix

| From       | To          | Difficulty   | Breaking Changes | Action Required                |
| ---------- | ----------- | ------------ | ---------------- | ------------------------------ |
| v1.0.x     | v1.2.0      | **Easy**     | None             | Optional - Update parameters   |
| v1.2.0     | v1.3.3      | **Medium**   | None             | Test before production         |
| **v1.3.0** | **v1.3.1+** | **Critical** | None             | **Immediate upgrade required** |
| v1.1.0     | v1.2.0      | **Easy**     | None             | Recommended                    |
| Any        | v1.2.0      | **Easy**     | None             | Safe stable version            |

---

## From v1.0.x to v1.2.0

### Overview

- **Difficulty:** Easy
- **Breaking Changes:** None
- **Backward Compatibility:** 100%
- **Recommended:** Yes (performance improvements)
- **Time Required:** 10-15 minutes

### What's New in v1.2.0

**Key Features:**

- Chopper as default QC tool (7x faster than NanoFilt)
- Multi-tool QC support (chopper, fastp, filtlong)
- 100% nf-core compliance (707/707 lint tests passing)
- Simplified Dorado model syntax
- RO-Crate metadata for FAIR principles

### Migration Steps

#### 1. Update Pipeline Version

**Option A: Pull latest version**

```bash
# Update to v1.2.0
nextflow pull foi-bioinformatics/nanometanf -r v1.2.0
```

**Option B: Specify version in command**

```bash
nextflow run foi-bioinformatics/nanometanf -r v1.2.0 \
  --input samplesheet.csv \
  --outdir results \
  -profile docker
```

#### 2. Update QC Tool (Recommended)

Chopper is now the default QC tool for better performance:

```bash
# Automatic with v1.2.0 (Chopper is default)
nextflow run foi-bioinformatics/nanometanf -r v1.2.0 \
  --input samplesheet.csv \
  --outdir results \
  -profile docker

# Or explicitly specify (same result)
nextflow run foi-bioinformatics/nanometanf -r v1.2.0 \
  --input samplesheet.csv \
  --qc_tool chopper \
  --outdir results \
  -profile docker
```

**To keep using FASTP:**

```bash
# Use FASTP instead of Chopper
--qc_tool fastp
```

#### 3. Update Dorado Model Syntax (Optional)

Simplified Dorado model format (backward compatible):

```bash
# Old format (still works)
--dorado_model dna_r10.4.1_e4.3_400bps_hac@v5.0.0

# New format (recommended)
--dorado_model dna_r10.4.1_e4.3_400bps_hac
```

#### 4. Update Test Assertions (For Developers)

If you have custom tests, update to tool-agnostic patterns:

```groovy
// Old (FASTP-specific)
assert workflow.trace.tasks().any { it.process =~ /.*FASTP.*/ }

// New (tool-agnostic)
assert workflow.trace.tasks().any {
    it.name.contains('CHOPPER') ||
    it.name.contains('FASTP') ||
    it.name.contains('FILTLONG')
}
```

### Verification

After migration, verify the pipeline works correctly:

```bash
# Test with your data
nextflow run foi-bioinformatics/nanometanf -r v1.2.0 \
  --input test_samplesheet.csv \
  --outdir test_v1.2.0_output \
  -profile docker

# Compare output structure (should be identical)
ls -R test_v1.2.0_output/
```

### Expected Changes

**Performance:**

- QC processing: ~7x faster with Chopper
- Overall pipeline: 10-15% faster for typical workflows

**Output:**

- QC reports: Different format if using Chopper (JSON instead of HTML)
- MultiQC: Includes Chopper stats instead of FASTP stats
- All other outputs: Identical

**No Changes:**

- Directory structure: Same
- File naming: Same
- Classification results: Identical
- Validation results: Identical

---

## From v1.2.0 to v1.3.3

### Overview

- **Difficulty:** Medium
- **Breaking Changes:** None
- **Backward Compatibility:** 100%
- **Recommended:** Test before production
- **Time Required:** 1-2 hours (testing)

### What's New in v1.3.3

**Key Features:**

- Advanced real-time monitoring (2-stage timeout with grace period)
- Adaptive batching (dynamic sizing between min/max)
- Priority sample routing
- Per-barcode metadata extraction
- Platform-specific profiles (minion, promethion_8, promethion)
- PromethION optimizations (18x throughput improvement possible)
- Incremental Kraken2 classification (experimental)

### Migration Steps

#### 1. Update Pipeline Version

```bash
nextflow pull foi-bioinformatics/nanometanf -r v1.3.3
```

#### 2. Review New Real-time Parameters

If using `--realtime_mode`, review new parameters:

```bash
# Old v1.2.0 command
nextflow run foi-bioinformatics/nanometanf -r v1.2.0 \
  --realtime_mode \
  --nanopore_output_dir /path/to/monitor \
  --batch_size 10 \
  --outdir results

# New v1.3.3 command with advanced features
nextflow run foi-bioinformatics/nanometanf -r v1.3.3 \
  --realtime_mode \
  --nanopore_output_dir /path/to/monitor \
  --batch_size 10 \
  --realtime_timeout_minutes 10 \          # NEW: Auto-stop after inactivity
  --realtime_processing_grace_period 5 \    # NEW: Grace period for processing
  --adaptive_batching true \                # NEW: Dynamic batch sizing
  --priority_samples "urgent,patient01" \   # NEW: Priority routing
  --outdir results
```

#### 3. Consider Platform Profiles

Use platform-specific profiles for better performance:

```bash
# MinION/GridION (1-4 samples, clinical)
-profile minion,docker

# PromethION balanced (5-12 samples)
-profile promethion_8,docker

# PromethION high-throughput (12-24+ samples)
-profile promethion,docker
```

#### 4. Test Real-time Features

**Test new timeout behavior:**

```bash
# Create test scenario
nextflow run foi-bioinformatics/nanometanf -r v1.3.3 \
  --realtime_mode \
  --nanopore_output_dir /path/to/test/data \
  --realtime_timeout_minutes 5 \
  --max_files 100 \
  --outdir test_timeout \
  -profile docker
```

**Expected:** Pipeline stops automatically after 5 minutes of no new files, plus 5-minute grace period.

#### 5. Optional: Enable Experimental Features

**Incremental Kraken2 (experimental):**

```bash
--kraken2_enable_incremental true
```

**Note:** Incremental Kraken2 is experimental and should be tested thoroughly before production use.

### Verification

```bash
# Run side-by-side comparison
# v1.2.0
nextflow run foi-bioinformatics/nanometanf -r v1.2.0 \
  --input test.csv --outdir results_v1.2.0 -profile docker

# v1.3.3
nextflow run foi-bioinformatics/nanometanf -r v1.3.3 \
  --input test.csv --outdir results_v1.3.3 -profile docker

# Compare results
diff -r results_v1.2.0/kraken2 results_v1.3.3/kraken2
```

### Expected Changes

**If NOT using real-time mode:**

- Behavior: Identical to v1.2.0
- Performance: Similar or slightly improved
- Results: Identical

**If using real-time mode:**

- Behavior: More intelligent timeout handling
- Performance: Potentially better with platform profiles
- Results: Identical (processing is same, just orchestration improved)

### Potential Issues

**Issue:** Real-time mode stops prematurely
**Solution:** Adjust `--realtime_processing_grace_period` (increase from 5 to 10 minutes)

**Issue:** Batch sizes too large/small
**Solution:** Configure adaptive batching:

```bash
--adaptive_batching true \
--min_batch_size 5 \
--max_batch_size 50 \
--batch_size_factor 1.5
```

---

## From v1.3.0 to v1.3.1+

### ⚠️ CRITICAL: v1.3.0 is Broken

**Status:** v1.3.0 has a parse-time error and is completely unusable.

**Error:**

```
ERROR ~ No such variable: KRAKEN2_INCREMENTAL_CLASSIFIER
```

**Impact:** Pipeline fails immediately on ANY invocation.

### Immediate Action Required

**Do NOT use v1.3.0. Upgrade immediately to:**

- **v1.2.0** (stable, recommended for production)
- **v1.3.1** (hotfix, fixed the parse error)
- **v1.3.3** (latest, includes all v1.3 features)

### Migration Steps

#### From v1.3.0 to v1.2.0 (Safe Path)

```bash
# Downgrade to stable version
nextflow pull foi-bioinformatics/nanometanf -r v1.2.0

# Run your analysis
nextflow run foi-bioinformatics/nanometanf -r v1.2.0 \
  --input samplesheet.csv \
  --outdir results \
  -profile docker
```

#### From v1.3.0 to v1.3.3 (Latest Features)

```bash
# Upgrade to latest
nextflow pull foi-bioinformatics/nanometanf -r v1.3.3

# Test first
nextflow run foi-bioinformatics/nanometanf -r v1.3.3 \
  -profile test,docker

# Then run your analysis
nextflow run foi-bioinformatics/nanometanf -r v1.3.3 \
  --input samplesheet.csv \
  --outdir results \
  -profile docker
```

### No Data Migration Required

Since v1.3.0 doesn't run, no output files exist that need migration.

---

## Breaking Changes History

### v1.3.3 (2025-10-25)

- **Breaking Changes:** None
- **Deprecations:** None

### v1.3.1 (2025-10-20)

- **Breaking Changes:** None (hotfix for v1.3.0)
- **Fixes:** Removed broken Kraken2 incremental classifier

### v1.3.0 (2025-10-19)

- **Status:** 🚫 BROKEN - Do not use
- **Issue:** Parse-time error

### v1.2.0 (2025-10-16)

- **Breaking Changes:** None
- **Deprecations:** None
- **New Defaults:** Chopper is now default QC tool

### v1.1.0 (2025-10-10)

- **Breaking Changes:** None
- **Deprecations:** None

### v1.0.0 (2025-09-15)

- **Initial Release**

---

## Common Migration Issues

### Issue: Pipeline version not updating

**Symptom:**

```
Pipeline version still shows old version after pull
```

**Solution:**

```bash
# Force re-download
rm -rf ~/.nextflow/assets/foi-bioinformatics/nanometanf
nextflow pull foi-bioinformatics/nanometanf -r v1.2.0

# Verify version
nextflow info foi-bioinformatics/nanometanf
```

### Issue: Different QC results after migration

**Symptom:**
QC metrics differ between versions

**Solution:**
This is expected if you migrated from v1.0.x/v1.1.x to v1.2.0 and switched from FASTP to Chopper.

```bash
# Use same QC tool for consistent results
--qc_tool fastp  # Keep using FASTP

# Or accept new Chopper results (recommended for performance)
--qc_tool chopper
```

### Issue: Real-time mode behavior changed

**Symptom:**
Real-time monitoring stops at different times in v1.3.3

**Solution:**
v1.3.3 introduced intelligent timeout. Configure to match old behavior:

```bash
# Disable timeout (like v1.2.0)
# Don't set --realtime_timeout_minutes

# Or use max_files for explicit control
--max_files 1000
```

### Issue: Tests failing after migration

**Symptom:**
nf-test tests fail after version upgrade

**Solution:**
Update test assertions for new QC tool:

```groovy
// Update assertions to be tool-agnostic
assert workflow.trace.tasks().any {
    it.name.contains('CHOPPER') ||
    it.name.contains('FASTP') ||
    it.name.contains('FILTLONG')
}
```

---

## Need Help?

### Documentation

- [Current Version Status](CURRENT_VERSION.md) - Which version to use
- [Usage Guide](../user/usage.md) - Complete parameter reference
- [Troubleshooting](../user/troubleshooting.md) - Common issues

### Support

- **GitHub Issues:** https://github.com/foi-bioinformatics/nanometanf/issues
- **Label:** Use `migration` label for migration-related issues

### Reporting Migration Issues

Include this information:

```
From version: v1.x.x
To version: v1.y.y
Issue: [description]
Command used: [full command]
Error message: [if any]
```

---

**Last Updated:** 2025-11-04
**Maintainer:** foi-bioinformatics team
**Version:** 1.3.1dev
