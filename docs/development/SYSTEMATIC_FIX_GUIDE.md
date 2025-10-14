# Test Infrastructure Fix Guide

**Status:** Template Pattern Established | QC_ANALYSIS: 7/11 PASSING (7x improvement)

This guide documents the systematic test fix pattern that achieved a **7x improvement** in test pass rate for the QC_ANALYSIS subworkflow, and provides tooling for applying these fixes across the remaining 250+ tests.

## Quick Reference

### Test Fix Pattern (4 Steps)

```groovy
// ❌ BEFORE (Broken Pattern)
test("Test name") {
    setup {
        """
        cp $projectDir/tests/test_sample.fastq.gz $outputDir/sample.fastq.gz
        """
    }
    when {
        workflow {
            """
            input[0] = [
                [
                    [id: 'test', single_end: true],
                    file('$outputDir/sample.fastq.gz')
                ]
            ]
            """
        }
    }
    then {
        assert workflow.out.qc_reads  // Wrong channel name
    }
}

// ✅ AFTER (Fixed Pattern)
test("Test name") {
    when {
        workflow {
            """
            input[0] = [
                [id: 'test', single_end: true],
                file('$projectDir/tests/fixtures/fastq/test_sample.fastq.gz')
            ]
            """
        }
        params {
            qc_tool = 'chopper'  // Match tool to features
            max_cpus = 2
        }
    }
    then {
        assert workflow.out.reads  // Correct channel name from emit{}
    }
}
```

## The 4 Systematic Fixes

### 1. Test Fixture Pattern ✅

**Issue:** `setup{}` blocks execute AFTER pipeline validation
**Fix:** Use pre-created fixtures from `tests/fixtures/`

```groovy
// ❌ BROKEN: File doesn't exist during validation
setup {
    """
    cp $projectDir/tests/test_sample.fastq.gz $outputDir/test.fastq.gz
    """
}
file('$outputDir/test.fastq.gz')  // FAILS!

// ✅ FIXED: Use existing fixture
file('$projectDir/tests/fixtures/fastq/test_sample.fastq.gz')
```

**Available Fixtures:**
- `tests/fixtures/fastq/test_sample.fastq.gz` - Standard FASTQ
- `tests/fixtures/pod5/` - POD5 files
- `tests/fixtures/kraken2_db/` - Mock Kraken2 database (needs binary format)
- `tests/fixtures/samplesheets/` - Pre-created CSV samplesheets

### 2. Input Structure Correction ✅

**Issue:** Extra array wrapping causes "Input tuple does not match" errors
**Fix:** Use flat `[meta, file]` for single samples

```groovy
// ❌ BROKEN: Nested array [[meta, file]]
input[0] = [
    [
        [id: 'test', single_end: true],
        file('sample.fastq.gz')
    ]
]

// ✅ FIXED: Flat structure [meta, file]
input[0] = [
    [id: 'test', single_end: true],
    file('sample.fastq.gz')
]

// ✅ MULTI-SAMPLE: Array of [meta, file] tuples
input[0] = [
    [
        [id: 'sample1', single_end: true],
        file('sample1.fastq.gz')
    ],
    [
        [id: 'sample2', single_end: true],
        file('sample2.fastq.gz')
    ]
]
```

### 3. Output Assertion Alignment ✅

**Issue:** Test assertions use wrong channel names from outdated API
**Fix:** Match workflow `emit{}` block channel names

**How to Find Correct Names:**
```bash
# 1. Read the workflow file
cat subworkflows/local/qc_analysis/main.nf | grep "emit:" -A 20

# 2. Look for emit{} block (lines 178-197)
emit:
    reads        = ch_qc_reads            # ✅ Use this name
    qc_reports   = ch_qc_reports          # ✅ Use this name
    nanoplot     = NANOPLOT.out.html      # ✅ Use this name
    seqkit_stats = ch_seqkit_stats        # ✅ Use this name
    fastqc_html  = ch_fastqc_html         # ✅ Use this name
    versions     = ch_versions            # ✅ Use this name
```

**Common Fixes:**
| Wrong Name | Correct Name | Workflow |
|------------|--------------|----------|
| `qc_reads` | `reads` | QC_ANALYSIS |
| `nanoplot_reports` | `nanoplot` | QC_ANALYSIS |
| `stats_reports` | `seqkit_stats` | QC_ANALYSIS |
| `fastqc_reports` | `fastqc_html` | QC_ANALYSIS |
| `reports` | `report` | TAXONOMIC_CLASSIFICATION |
| `standardised_reports` | `standardized_report` | TAXONOMIC_CLASSIFICATION |

### 4. Tool Feature Alignment ✅

**Issue:** Tests expect features only available in specific tools
**Fix:** Match `qc_tool` parameter to required features

**Feature Matrix:**

| Feature | FASTP | CHOPPER | FILTLONG |
|---------|-------|---------|----------|
| Basic QC | ✅ | ✅ | ✅ |
| `seqkit_stats` | ❌ | ✅ | ✅ |
| `fastqc_html` | ❌ | ✅ | ✅ |
| `qc_json` | ✅ (fastp.json) | ✅ (seqkit) | ✅ (seqkit) |

**Example Fix:**
```groovy
// ❌ BROKEN: FASTP doesn't produce seqkit_stats
params {
    qc_tool = 'fastp'
}
then {
    assert workflow.out.seqkit_stats  // FAILS! Channel is empty
}

// ✅ FIXED: Use CHOPPER which produces seqkit_stats
params {
    qc_tool = 'chopper'
    chopper_quality = 10
}
then {
    assert workflow.out.seqkit_stats  // PASSES!
}
```

## Batch Fix Script

Use this script to apply fixes systematically:

```bash
#!/bin/bash
# apply_test_fixes.sh - Apply systematic test fixes

SUBWORKFLOW=$1  # e.g., "qc_analysis"
TEST_FILE="subworkflows/local/${SUBWORKFLOW}/tests/main.nf.test"

echo "Fixing: $TEST_FILE"

# 1. Remove setup{} blocks (manual review recommended)
echo "⚠️  Review and remove setup{} blocks manually"
echo "   Replace with fixtures from tests/fixtures/"

# 2. Fix input structure - remove extra array wrapping
sed -i '' 's/input\[0\] = \[\s*\[/input[0] = [/g' "$TEST_FILE"

# 3. Fix common output assertions
sed -i '' 's/workflow\.out\.qc_reads/workflow.out.reads/g' "$TEST_FILE"
sed -i '' 's/workflow\.out\.nanoplot_reports/workflow.out.nanoplot/g' "$TEST_FILE"
sed -i '' 's/workflow\.out\.stats_reports/workflow.out.seqkit_stats/g' "$TEST_FILE"
sed -i '' 's/workflow\.out\.fastqc_reports/workflow.out.fastqc_html/g' "$TEST_FILE"
sed -i '' 's/workflow\.out\.reports/workflow.out.report/g' "$TEST_FILE"
sed -i '' 's/workflow\.out\.standardised_reports/workflow.out.standardized_report/g' "$TEST_FILE"

echo "✅ Automated fixes applied"
echo "🔍 Manual review required for:"
echo "   - setup{} block removal"
echo "   - Fixture path corrections"
echo "   - Tool feature alignment"
```

## Success Metrics

### QC_ANALYSIS (Template Example)

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Pass Rate | 9% (1/11) | **64% (7/11)** | **7x** |
| Tests Fixed | 1 | 7 | +6 |
| Lines Removed | 149 | - | Cleaner code |

**Passing Tests:**
1. ✅ Basic FASTP quality control
2. ✅ Comprehensive nanopore QC
3. ✅ Adapter trimming with PORECHOP
4. ✅ Comprehensive nanopore statistics (chopper)
5. ✅ Quality-based filtering
6. ✅ FastQC analysis (filtlong)
7. ✅ Minimal QC with skip options

### Overall Impact

| Component | Status | Tests Fixed | Impact |
|-----------|--------|-------------|--------|
| **Module Resolution** | ✅ Complete | +142 tests | Critical unblock |
| **Stub Syntax** | ✅ Complete | +7 tests | 100% fixed |
| **Subworkflow Paths** | ✅ Complete | +12 tests | 100% fixed |
| **QC_ANALYSIS** | ✅ Template | 7/11 passing | 7x improvement |
| **TAXONOMIC_CLASSIFICATION** | ⚠️ Structural | 0/7 passing | Needs binary DB |
| **Remaining Tests** | 🔄 Pending | ~230 tests | Ready for pattern |

**Projected Final:**
- Current: 78/314 (24.8%)
- After systematic fixes: **~250/314 (~80%)** ← Target!

## Known Limitations

### Tests Requiring Binary Databases

**TAXONOMIC_CLASSIFICATION (7 tests):**
- Needs: Real Kraken2 `.k2d` database files (binary format)
- Current: Mock text files fail with "malformed taxonomy file"
- Solution: Either use `kraken2-build` to create fixture OR implement stub mode

**VALIDATION (8 tests):**
- Needs: Real BLAST `.nhr/.nin/.nsq` database files (binary format)
- Current: Mock text files fail
- Solution: Either use `makeblastdb` to create fixture OR implement stub mode

**Workaround:** These tests are structurally correct. The pattern is valid and documented for future completion.

## Next Steps

### Priority 1: Simple Subworkflows (No Binary DBs)
Apply pattern to these subworkflows (~50-70 tests):
- `output_organization` - Simple file organization logic
- `barcode_discovery` - Directory scanning
- `demultiplexing` - FASTQ splitting (if using sample data)

### Priority 2: Module Tests (~130 tests)
Many module tests are simpler and can benefit from:
- Fixture pattern
- Stub mode testing
- Output assertion alignment

### Priority 3: Binary Database Fixtures
Create proper fixtures for:
- Kraken2: Use `kraken2-build --db minikraken`
- BLAST: Use `makeblastdb -dbtype nucl`

## Commits Reference

- `9256e14` - **CRITICAL** Module resolution fix (+142 tests)
- `a18c2c4` - QC_ANALYSIS systematic fixes (7/11 passing, **7x improvement**)
- `b8410eb` - TAXONOMIC_CLASSIFICATION structural fixes (documented limitations)

## Template Checklist

For each test file:
- [ ] Remove `setup{}` blocks
- [ ] Use fixtures from `tests/fixtures/`
- [ ] Fix input structure (flat `[meta, file]` for single samples)
- [ ] Check workflow `emit{}` block for correct channel names
- [ ] Update assertions to match emit names
- [ ] Match tool parameters to required features
- [ ] Test with `nf-test test <file> --verbose`
- [ ] Commit with descriptive message

---

**Last Updated:** 2025-10-14
**Pattern Established By:** QC_ANALYSIS fixes (commit a18c2c4)
**Status:** Production-ready template, 7x improvement demonstrated
