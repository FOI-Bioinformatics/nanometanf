# nanometanf v1.3.0 Real Data Validation Testing Plan

**Version:** v1.3.0
**Status:** Ready for Execution
**Created:** 2025-10-19

## Overview

Comprehensive testing plan for validating v1.3.0 PromethION optimizations with real Oxford Nanopore data. This plan ensures all execution modes and optimization features work correctly with production-like data.

## Test Data Location

```
/Users/andreassjodin/Desktop/test_data/
├── single_fastq/          # 4 FASTQ files (~19KB each, barcode02)
├── multiple_fastq/        # Pre-demultiplexed barcode directories (barcode01/, barcode02/)
├── single_pod5/           # 2 POD5 files (~5.4MB total)
└── multiple_pod5/         # Pre-demultiplexed POD5 barcode directories
```

## Test Script

**Location:** `/Users/andreassjodin/Code/nanometanf/test_v1.3.0_real_data.sh`

**Usage:**
```bash
# Run full test suite (all 21+ scenarios)
./test_v1.3.0_real_data.sh

# Run only baseline tests (quick validation)
./test_v1.3.0_real_data.sh --quick

# Run specific category
./test_v1.3.0_real_data.sh --category A   # Standard FASTQ processing
./test_v1.3.0_real_data.sh --category B   # POD5 basecalling
./test_v1.3.0_real_data.sh --category C   # Real-time processing
./test_v1.3.0_real_data.sh --category D   # PromethION optimizations
```

**Output Location:** `test_results_v1.3.0/`
- `logs/` - Execution logs for each test
- `metrics/` - Performance metrics (JSON format)
- `TEST_SUMMARY_*.md` - Generated summary report

## Test Categories

### Category A: Standard FASTQ Processing (Baseline Validation)

**Purpose:** Validate core FASTQ processing functionality across profiles

| Test ID | Description | Profile | Input Mode |
|---------|-------------|---------|------------|
| A1 | Single FASTQ - Baseline | test,docker | Samplesheet |
| A2 | Single FASTQ - MinION | minion,test,docker | Samplesheet |
| A3 | Single FASTQ - PromethION | promethion,test,docker | Samplesheet |
| A4 | Multiple FASTQ - Barcode Discovery | test,docker | barcode_input_dir |
| A5 | Multiple FASTQ - PromethION + Barcodes | promethion,test,docker | barcode_input_dir |

**Success Criteria:**
- All tests complete without errors
- MultiQC reports generated
- QC outputs (Chopper) present
- Pipeline versions file created

### Category B: POD5 Basecalling Workflows

**Purpose:** Validate Dorado basecalling integration

| Test ID | Description | Profile | Basecalling | Demux |
|---------|-------------|---------|-------------|-------|
| B1 | Single POD5 - Baseline | test,docker | Yes | No |
| B2 | Single POD5 - PromethION | promethion,test,docker | Yes | No |
| B3 | Multiple POD5 - Barcode Discovery | test,docker | Yes | No |
| B4 | POD5 + Demultiplexing | test,docker | Yes | Yes |

**Requirements:**
- Dorado binary available in PATH or Docker image
- Model: `dna_r10.4.1_e8.2_400bps_hac`

**Success Criteria:**
- POD5 files basecalled to FASTQ
- Demultiplexing works correctly (B4)
- QC analysis runs on basecalled reads
- Performance metrics collected

**Known Limitations:**
- Tests will skip if Dorado not available (warning logged)
- Actual basecalling requires compatible hardware

### Category C: Real-time Processing Modes

**Purpose:** Validate real-time file monitoring and batch processing

| Test ID | Description | Profile | Input Type | Optimizations |
|---------|-------------|---------|------------|---------------|
| C1 | Real-time FASTQ - Baseline | test,docker | FASTQ | No |
| C2 | Real-time FASTQ - PromethION | promethion,test,docker | FASTQ | Yes |
| C3 | Real-time POD5 - Baseline | test,docker | POD5 | No |
| C4 | Real-time POD5 - PromethION | promethion,test,docker | POD5 | Yes |

**Configuration:**
- `--max_files 4` (FASTQ) / `--max_files 2` (POD5) - Prevents infinite watchPath()
- `--batch_size 2` (FASTQ) / `--batch_size 1` (POD5)
- Uses `watchPath()` operator for file monitoring

**Success Criteria:**
- Real-time monitoring activates correctly
- Batch processing works as expected
- Tests terminate after max_files reached
- No infinite hangs

### Category D: PromethION v1.3.0 Optimization Validation

**Purpose:** Validate all three optimization phases introduced in v1.3.0

| Test ID | Description | Optimizations Tested |
|---------|-------------|---------------------|
| D1 | PromethION 8-core Workstation | promethion_8 profile resource allocation |
| D2 | Real-time Auto-optimizations | Automatic Phase 2 activation in realtime_mode |
| D3 | Full Optimization Stack | Phase 1 + Phase 2 + Phase 3 (optimized MultiQC) |
| D4 | Kraken2 Preloading | Phase 2 database memory mapping |
| D5a | Performance Baseline | Baseline for comparison |
| D5b | Performance PromethION | PromethION optimized for comparison |

**Optimization Phases:**
1. **Phase 1:** Platform-specific resource allocation (minion, promethion_8, promethion)
2. **Phase 2:** Kraken2 database preloading (automatic in realtime_mode)
3. **Phase 3:** Optimized MultiQC generation (--enable_optimized_multiqc)

**Success Criteria:**
- D1: promethion_8 profile applies correct resource limits
- D2: Real-time mode auto-enables Kraken2 optimizations (log confirms)
- D3: All three phases activate successfully
- D4: Kraken2 reports memory-mapping enabled (if database available)
- D5: Performance comparison shows measurable improvement (baseline vs optimized)

**Expected Performance Improvements:**
- PromethION vs Baseline: 94% time reduction (per v1.3.0 benchmarks)
- Real-time with preloading: 1-3 minutes saved per batch after initial load
- Optimized MultiQC: Deferred execution (runs once at end)

## Metrics Collection

Each test collects:
- **Duration:** Total execution time
- **CPU hours:** Cumulative CPU time
- **Peak memory:** Maximum memory usage
- **Work directory:** Location of intermediate files

**Metrics Files:** `test_results_v1.3.0/metrics/<TEST_ID>_<PROFILE>_metrics.json`

Example:
```json
{
  "test_name": "A1_test",
  "timestamp": "2025-10-19T14:30:00Z",
  "duration": "5m 23s",
  "cpu_hours": "0.5h",
  "peak_memory": "4.2 GB",
  "work_dir": "test_results_v1.3.0/A1_test/work"
}
```

## Output Validation

For each test, the script validates:

1. **MultiQC Report:** `<outdir>/multiqc/multiqc_report.html` exists
2. **Pipeline Info:** `<outdir>/pipeline_info/` directory created
3. **Software Versions:** `<outdir>/pipeline_info/*versions.yml` generated
4. **Test-specific outputs:**
   - FASTQ tests: QC outputs (Chopper JSON/HTML)
   - POD5 tests: Basecalled FASTQ files
   - Real-time tests: Batch processing logs
   - PromethION tests: Performance metrics, optimization logs

## Execution Time Estimates

| Category | Tests | Estimated Time | Quick Mode |
|----------|-------|----------------|------------|
| A | 5 | 30-45 minutes | 5-10 minutes (A1 only) |
| B | 4 | 60-90 minutes* | 10-15 minutes (B1 only) |
| C | 4 | 20-30 minutes | 5-10 minutes (C1 only) |
| D | 6 | 60-75 minutes | 10-15 minutes (D1 only) |
| **Total** | **19+** | **2.5-4 hours** | **30-50 minutes** |

*Category B depends on Dorado performance and hardware

## Prerequisites

1. **Nextflow:** >= 24.10.5
2. **Docker/Singularity:** Test profile requires containerization
3. **Dorado (optional):** For POD5 tests (Category B, C3-C4)
4. **Kraken2 Database (optional):** For D4 optimization test
5. **Test Data:** Available at `/Users/andreassjodin/Desktop/test_data/`

## Quick Start

```bash
# Navigate to pipeline directory
cd /Users/andreassjodin/Code/nanometanf

# Ensure script is executable
chmod +x test_v1.3.0_real_data.sh

# Run quick validation (baseline tests only, ~30-50 minutes)
./test_v1.3.0_real_data.sh --quick

# Review results
cat test_results_v1.3.0/TEST_SUMMARY_*.md

# Run full suite (all tests, ~2.5-4 hours)
./test_v1.3.0_real_data.sh
```

## Monitoring Execution

```bash
# Watch main test log
tail -f test_results_v1.3.0/logs/test_suite_*.log

# Check specific test progress
tail -f test_results_v1.3.0/logs/<TEST_ID>_<PROFILE>_*.log

# View collected metrics
cat test_results_v1.3.0/metrics/*.json
```

## Troubleshooting

### Test Hangs Indefinitely
- **Cause:** Real-time test without `--max_files`
- **Solution:** Script includes `--max_files` for all real-time tests

### Dorado Tests Skip
- **Cause:** Dorado binary not in PATH
- **Solution:** Install Dorado or ensure it's in PATH. Tests will log warning and skip.

### Kraken2 Database Not Found
- **Cause:** Test D4 requires Kraken2 database at specific path
- **Solution:** Test will skip with warning if database not found

### Out of Memory
- **Cause:** Insufficient system memory for tests
- **Solution:** Use `--quick` mode or run categories individually

## Success Criteria Summary

**Overall Test Suite Success:**
- ✅ All category A tests pass (baseline validation)
- ✅ At least 2 category D tests pass (optimization validation)
- ✅ Performance comparison (D5) shows improvement over baseline
- ✅ No critical errors in any test
- ✅ All expected outputs generated

**Acceptable Warnings:**
- POD5 tests skipping (if Dorado unavailable)
- Kraken2 optimization test skipping (if database unavailable)
- Docker image pull warnings (network issues)

## Results Documentation

After test execution, results will be documented in:
- **Summary Report:** `test_results_v1.3.0/TEST_SUMMARY_*.md`
- **Validation Document:** `docs/validation/v1_3_0_real_data_tests.md` (to be created)

The validation document will include:
- Test execution summary
- Performance comparison data
- Known issues encountered
- Recommendations for production deployment

## Next Steps After Testing

1. ✅ Review `TEST_SUMMARY_*.md` for overall results
2. ✅ Compare baseline vs PromethION performance (D5a vs D5b)
3. ✅ Document any issues or unexpected behavior
4. ✅ Create `docs/validation/v1_3_0_real_data_tests.md` with findings
5. ✅ Update user documentation with v1.3.0 features
6. ✅ Commit test results and documentation updates

---

**Last Updated:** 2025-10-19
**Tested Version:** v1.3.0
**Test Data Version:** Production-like ONT data (barcode01, barcode02)
