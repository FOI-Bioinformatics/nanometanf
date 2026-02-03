# CLAUDE.md

**AI-Assisted Development Guide for nanometanf**

This file provides guidance for AI assistants working on the nanometanf pipeline. For complete developer documentation, see [docs/development/README.md](docs/development/README.md).

---

## Pipeline Overview

**nanometanf** is an nf-core compliant Nextflow pipeline for Oxford Nanopore Technologies (ONT) sequencing data analysis, serving as the computational backend for Nanometa Live.

**Core Capabilities:**
- Real-time analysis during active sequencing (POD5 or FASTQ monitoring)
- POD5 basecalling with Dorado (GPU-accelerated)
- Pre-demultiplexed barcode directory processing
- Taxonomic classification with Kraken2 (incremental mode with scalable streaming)
- Quality control (Chopper, FASTP, NanoPlot) and validation (BLAST/minimap2)
- Platform-specific optimizations (MinION, PromethION profiles)

**Current Version:** 1.5.0dev
**nf-core Compliance:** 96/100

---

## Critical Architecture: Scalable Streaming (v1.5+)

### Problem Solved

The previous architecture had global serialization bottlenecks:
- `maxForks 1` in merger/report modules serialized ALL batches from ALL samples
- O(n^2) file I/O: each batch re-read entire cumulative file before appending
- No backpressure: unlimited batch queuing when downstream was slow

**Impact:** CPU utilization dropped to 15-20%, throughput limited to ~10-15 files/sec with >10 barcodes.

### New Architecture

| Component | Before | After |
|-----------|--------|-------|
| Merger serialization | `maxForks 1` (global) | Per-sample parallelism |
| File storage | Single cumulative file (rewritten each batch) | Batch files + index (append-only) |
| Report generation | Full merge every batch | Incremental taxid counting |
| I/O per batch | O(cumulative_size) | O(batch_size) |

### Key Modules

**`modules/local/kraken2_output_merger/main.nf`** - Append-only batch storage
- Writes each batch to separate file: `batches/batch_N.kraken2.output.txt`
- Maintains atomic index file with batch manifest
- Per-sample parallelism (no maxForks 1)

**`modules/local/kraken2_report_generator/main.nf`** - Incremental taxid counting
- Maintains `taxid_counts.json` state file per sample
- Accumulates counts without re-reading full output
- Atomic state updates prevent race conditions

**`modules/local/kraken2_final_aggregator/main.nf`** - End-of-session aggregation
- Concatenates batch files into cumulative outputs
- Runs once per sample when streaming completes
- Generates final files for downstream tools

### Output Directory Structure

```
outdir/kraken2/
├── {sample_id}/
│   ├── batches/
│   │   ├── batch_0.kraken2.output.txt
│   │   ├── batch_1.kraken2.output.txt
│   │   └── ...
│   ├── batch_reports/
│   │   ├── batch_0.kraken2.report.txt
│   │   └── ...
│   ├── index.json                    # Batch manifest
│   ├── taxid_counts.json             # Incremental taxid state
│   └── stats/
│       ├── merge_stats.json
│       └── report_stats.json
├── {sample_id}.cumulative.kraken2.output.txt  # End-of-session
└── {sample_id}.cumulative.kraken2.report.txt  # Updated per-batch for dashboard
```

### Concurrency Parameters

```groovy
// Scalable streaming architecture (v1.5+)
max_concurrent_batches   = 4    // Backpressure limit per sample
max_classification_forks = 8    // Max parallel Kraken2 jobs
```

---

## Critical Files for Development

### Entry Points
- `main.nf` - Pipeline entry point
- `workflows/nanometanf.nf` - Main workflow orchestration

### Core Configuration
- `nextflow.config` - Main configuration (150+ parameters)
- `nextflow_schema.json` - Parameter validation schema
- `conf/base.config` - Base process resource configuration
- `conf/modules.config` - Module-specific configurations (includes maxForks settings)
- `conf/minion.config`, `conf/promethion.config`, `conf/promethion_8.config` - Platform profiles

### Critical Subworkflows (subworkflows/local/)

- **`input_scanner/main.nf`** - Unified input directory scanning (v1.5+)
  - Replaces separate barcode_input_dir handling
  - Supports MinKNOW-style and flat directory structures
  - Uses InputDetector for type-agnostic path handling

- **`realtime_monitoring/main.nf`** - Real-time FASTQ monitoring with watchPath
  - Adaptive batching via BatchUtils, priority routing, barcode extraction
  - Backpressure configuration logging

- **`realtime_pod5_monitoring/main.nf`** - Real-time POD5 monitoring + basecalling

- **`taxonomic_classification/main.nf`** - Kraken2 taxonomic profiling
  - Scalable streaming architecture with per-sample parallelism
  - End-of-session aggregation via `groupTuple()` + `KRAKEN2_FINAL_AGGREGATOR`
  - Three execution modes: incremental (scalable), optimized, standard

- **`qc_analysis/main.nf`** - Quality control workflow
- **`validation/main.nf`** - Pathogen validation via BLAST/minimap2

### Key Modules (modules/local/)

| Module | Purpose |
|--------|---------|
| `kraken2_incremental_classifier/` | Classify only NEW reads per batch |
| `kraken2_output_merger/` | Append-only batch storage with atomic index |
| `kraken2_report_generator/` | Incremental taxid counting |
| `kraken2_final_aggregator/` | End-of-session concatenation |
| `dorado_basecaller/` | POD5 basecalling |
| `dorado_demux/` | Dorado demultiplexing |
| `extract_reads_by_taxid/` | Extract reads for validation |
| `blastn_validation/` | BLAST validation |
| `minimap2_validation/` | Fast minimap2 validation |

### Library Utilities (lib/)

| File | Purpose |
|------|---------|
| `InputDetector.groovy` | Type-agnostic input detection (POD5/FASTQ/directory) |
| `BatchUtils.groovy` | Batching utilities using `buffer()` operator |
| `WorkflowMain.groovy` | Main workflow initialization |
| `Utils.groovy` | General utility functions |
| `NfcoreSchema.groovy` | Schema validation helpers |

---

## Development Prerequisites

```bash
# Nextflow (>= 25.10.0)
nextflow -version

# nf-test (>= 0.9.0)
nf-test version

# Java environment for nf-test
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH
```

---

## Platform Compatibility

### ARM Mac (Apple Silicon)

**Working Configuration:**
```bash
nextflow run main.nf \
  --kraken2_memory_mapping false \
  --skip_krona true \
  -profile docker
```

**Required Parameters:**
| Parameter | Value | Reason |
|-----------|-------|--------|
| `--kraken2_memory_mapping` | `false` | x86 emulation via Rosetta crashes with SIGSEGV |
| `--skip_krona` | `true` | Krona container has permission issues |

---

## Key Development Patterns

### 1. Append-Only Batch Storage (v1.5+)

**Pattern:** Write each batch to separate file, maintain index atomically.

```python
# O(1) per batch instead of O(n)
batch_output_file = batches_dir / f'batch_{batch_id}.kraken2.output.txt'
with open(batch_output_file, 'w') as f_out:
    for line in current_batch:
        f_out.write(line)

# Atomic index update
temp_index = outdir / f'index.{batch_id}.tmp'
with open(temp_index, 'w') as f:
    json.dump(index, f)
os.rename(temp_index, existing_index_path)  # Atomic on POSIX
```

### 2. Incremental Taxid Counting (v1.5+)

**Pattern:** Accumulate counts in state file, avoid re-reading outputs.

```python
# Load existing state
if taxid_state_file.exists():
    taxid_counts = json.load(open(taxid_state_file))

# Merge batch counts (O(batch_taxa) not O(cumulative_taxa))
for taxid, data in batch_taxa.items():
    if taxid not in taxid_counts['taxa']:
        taxid_counts['taxa'][taxid] = {'reads': 0, 'cumul': 0, ...}
    taxid_counts['taxa'][taxid]['reads'] += data['reads']
    taxid_counts['taxa'][taxid]['cumul'] += data['cumul']
```

### 3. Test Fixtures Pattern

**CRITICAL**: Pipeline validation runs BEFORE nf-test `setup{}` blocks. Always use pre-created fixtures:

```groovy
// CORRECT - uses pre-existing fixture
when {
    params {
        input = "$projectDir/tests/fixtures/samplesheets/minimal.csv"
    }
}

// WRONG - file doesn't exist during validation
setup { "cat > $outputDir/test.csv ..." }
```

**Fixture location:** `tests/fixtures/`

### 4. nf-core Compliance

```bash
nf-core lint
nf-core schema lint
nf-core modules update
```

### 5. Testing Workflow

The test suite is designed to run in stub mode without Docker or external tools.

**Test structure:**
- **17 pipeline/subworkflow/lib tests** (`tests/`) - smoke tests and parameter validation
- **38 module tests** (`modules/local/*/tests/`, `modules/nf-core/*/tests/`) - stub-mode unit tests

**Required skip flags for pipeline tests:** All pipeline-level tests must include
`skip_kraken2 = true`, `use_dorado = false`, and `blast_validation = false` in their
params blocks unless the test specifically exercises that feature in stub mode.

```bash
# Quick validation
nf-test test --tag core --tag fast

# Full suite
nf-test test

# Specific test
nf-test test tests/nanoseq_test.nf.test --verbose

# Update snapshots after test changes
nf-test test --update-snapshot
```

---

## Important Parameters

### Input Modes (Mutually Exclusive)
- `--input` - Samplesheet CSV
- `--input_dir` - Unified directory scanning (v1.5+, replaces barcode_input_dir)
- `--barcode_input_dir` - Pre-demultiplexed barcode directories (deprecated, use input_dir)
- `--pod5_input_dir` + `--use_dorado` - POD5 basecalling mode

### Real-time Processing
- `--realtime_mode` - Enable real-time monitoring
- `--nanopore_output_dir` - Directory to monitor
- `--max_files` - **CRITICAL FOR TESTS** - Limit files
- `--batch_size` - Files per batch (default: 10)
- `--realtime_timeout_minutes` - Inactivity timeout
- `--realtime_processing_grace_period` - Processing completion wait

### Scalable Streaming (v1.5+)
- `--max_concurrent_batches` - Backpressure limit per sample (default: 4)
- `--max_classification_forks` - Max parallel Kraken2 jobs (default: 8)
- `--kraken2_enable_incremental` - Enable scalable streaming architecture

### Taxonomic Classification
- `--kraken2_db` - Path to Kraken2 database
- `--kraken2_memory_mapping` - Memory-mapped loading (set `false` on ARM Mac)
- `--skip_krona` - Skip Krona (set `true` on ARM Mac)

### Platform Profiles
- `-profile minion` - MinION/GridION (1-4 samples)
- `-profile promethion_8` - Balanced (5-12 samples)
- `-profile promethion` - High throughput (12-24+ samples)

---

## Architecture Highlights

### Input Type Detection

Auto-detects in `workflows/nanometanf.nf`:
1. **Real-time POD5**: `realtime_mode && use_dorado && pod5_input_dir`
2. **Real-time FASTQ**: `realtime_mode && !use_dorado && nanopore_output_dir`
3. **Static POD5**: `!realtime_mode && use_dorado && pod5_input_dir`
4. **Barcode discovery**: `!realtime_mode && barcode_input_dir`
5. **Standard samplesheet**: `!realtime_mode && input`

### Channel Flow

```
Input Detection -> Basecalling -> QC -> Classification -> Validation -> Reports
     |               |           |         |               |            |
  POD5/FASTQ      Dorado     CHOPPER   Kraken2          BLAST       MultiQC
  Barcodes                   NanoPlot   (scalable)                    JSON
                                        Taxpasta
```

### Scalable Classification Flow (v1.5+)

```
Reads -> INCREMENTAL_CLASSIFIER -> OUTPUT_MERGER -> REPORT_GENERATOR
              |                        |                  |
         (parallel)            (per-sample dirs)   (taxid counting)
                                       |
                               FINAL_AGGREGATOR (end-of-session)
```

---

## Git Workflow

```bash
git add <files>
git commit -m "descriptive message"
git push origin <branch>
gh pr create --title "Title" --body "Description"
```

**Commit Guidelines:**
- Use conventional commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`
- Reference issues: `fix: resolve timeout issue (#123)`

---

## Additional Resources

- **[User Guide](docs/user/usage.md)** - Complete usage instructions
- **[Development Guide](docs/development/README.md)** - Developer documentation
- **[Testing Guide](docs/development/TESTING.md)** - nf-test documentation
- **[Real-time Processing](docs/user/realtime_processing.md)** - Advanced real-time guide
- [nf-core guidelines](https://nf-co.re/docs/contributing/guidelines)
- [Nextflow documentation](https://www.nextflow.io/docs/latest/)

---

**Last Updated:** 2026-02-03
**Version:** 1.5.0dev
**Maintainer:** foi-bioinformatics team (@andreassjodin)

**Recent Changes (v1.5.0dev):**
- Scalable streaming architecture with per-sample parallelism
- Append-only batch storage (O(1) per batch)
- Incremental taxid counting (no cumulative re-reads)
- End-of-session aggregation module
- Backpressure control parameters
- Expected 4-5x throughput improvement for high-barcode runs
- Unified input handling: INPUT_SCANNER subworkflow with InputDetector
- BatchUtils refactoring: replaced deprecated `Channel.create()` with `buffer()`
- Test suite fixes: 55 active tests (17 pipeline + 38 module) with stub mode compatibility
