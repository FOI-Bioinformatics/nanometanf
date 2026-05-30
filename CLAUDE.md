# CLAUDE.md

Developer guidance for nanometanf, the Nextflow backend for
[Nanometa Live](https://github.com/FOI-Bioinformatics/nanometa_live). For
end-user documentation see [docs/usage.md](docs/usage.md); for
contributor documentation see
[docs/development/README.md](docs/development/README.md).

The recommended development environment is the `nf-core` conda environment.

---

## Pipeline overview

`nanometanf` is an nf-core compliant Nextflow pipeline for Oxford Nanopore
sequencing data analysis. It covers:

- Real-time FASTQ monitoring during active sequencing via Nextflow `watchPath`
- Pre-demultiplexed barcode directory processing
- Taxonomic classification with Kraken2 (streaming or batch)
- Quality control (Chopper, FASTP, NanoPlot) and validation (BLAST, minimap2)
- Platform-specific resource profiles (MinION, PromethION)
- Canonical tool-agnostic output layer for downstream consumers (Nanometa Live)

POD5 basecalling via Dorado was removed in the 2026-04 refactor and the
`use_dorado` / `pod5_input_dir` parameters are no longer accepted.

**Current version:** 1.5.1dev (development); 1.5.0 (released)
**nf-core lint score:** 96/100

---

## Streaming classification architecture (v1.5+)

### Background

The previous architecture serialised work globally, with three observed
bottlenecks:

- `maxForks 1` on the merger and report modules serialised every batch from
  every sample.
- O(n^2) file I/O: each batch re-read the full cumulative file before
  appending.
- No backpressure: batches queued without bound when downstream was slow.

In internal benchmarks, CPU utilisation fell to 15--20% and throughput plateaued
at roughly 10--15 files per second with more than ten barcodes.

### Current architecture

| Component            | Before                                        | After                             |
| -------------------- | --------------------------------------------- | --------------------------------- |
| Merger serialization | `maxForks 1` (global)                         | Per-sample parallelism            |
| File storage         | Single cumulative file (rewritten each batch) | Batch files + index (append-only) |
| Report generation    | Full merge every batch                        | Incremental taxid counting        |
| I/O per batch        | O(cumulative_size)                            | O(batch_size)                     |

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
max_concurrent_batches   = 4    // ADVISORY (not enforced; see audit P2.9)
max_classification_forks = 8    // Max parallel Kraken2 jobs (global cap, enforced via process maxForks)
```

> `max_concurrent_batches` is logged for visibility but has no
> enforcement effect today. Per-barcode backpressure is tracked under
> audit item P2.9. Operators who see one slow barcode starving others
> should raise `--max_classification_forks` proportionally to the
> barcode count.

---

## Canonical Output Layer

The pipeline produces tool-agnostic canonical outputs via five writer modules wired into each subworkflow and the main workflow. Output is written to `results/canonical/` with subdirectories for `classification/`, `qc/`, `validation/`, and `assembly/`, plus a `_manifest.json` index file.

Controlled by `params.write_canonical` (default: true).

Corresponding `bin/` scripts handle the format conversion: `kreport_to_canonical.py`, `qc_to_canonical.py`, `alignment_to_canonical.py`, `assembly_to_canonical.py`, `write_manifest.py`.

---

## Key files

### Entry points

- `main.nf` - Pipeline entry point
- `workflows/nanometanf.nf` - Main workflow orchestration

### Core Configuration

- `nextflow.config` - Main configuration (150+ parameters)
- `nextflow_schema.json` - Parameter validation schema
- `conf/base.config` - Base process resource configuration
- `conf/modules.config` - Module-specific configurations (includes maxForks settings)
- `conf/minion.config`, `conf/promethion.config`, `conf/promethion_8.config` - Platform profiles

### Subworkflows (subworkflows/local/)

- **`input_scanner/main.nf`** - Unified input directory scanning (v1.5+)
  - Replaces separate barcode_input_dir handling
  - Supports MinKNOW-style and flat directory structures
  - Uses InputDetector for type-agnostic path handling

- **`realtime_monitoring/main.nf`** - Real-time FASTQ monitoring with watchPath
  - Adaptive batching via BatchUtils, priority routing, barcode extraction
  - Concurrency configuration logging
  - Optional `[runtime-metrics]` daemon-Timer snapshot
    (`--runtime_metrics_interval_seconds N`)

- **`taxonomic_classification/main.nf`** - Kraken2 taxonomic profiling
  - Scalable streaming architecture with per-sample parallelism
  - End-of-session aggregation via `groupTuple()` + `KRAKEN2_FINAL_AGGREGATOR`
  - Three execution modes: incremental (scalable), optimized, standard

- **`qc_analysis/main.nf`** - Quality control workflow
  - Routes to `FASTP_STREAMING` in streaming/watchPath mode, upstream `FASTP` in batch mode
  - FASTQC and SEQKIT_STATS use `topic: versions` (not `.out.versions` channel)

- **`validation/main.nf`** - Pathogen validation via BLAST/minimap2

### Key Modules (modules/local/)

| Module                             | Purpose                                      |
| ---------------------------------- | -------------------------------------------- |
| `kraken2_incremental_classifier/`  | Classify only NEW reads per batch            |
| `kraken2_output_merger/`           | Append-only batch storage with atomic index  |
| `kraken2_report_generator/`        | Incremental taxid counting                   |
| `kraken2_final_aggregator/`        | End-of-session concatenation                 |
| `emit_empty_kraken2_report/`       | Placeholder report for samples with 0 reads  |
| `fastp_streaming/`                 | FASTP wrapper for multi-file streaming input |
| `extract_reads_by_taxid/`          | Extract reads for validation                 |
| `blastn_validation/`               | BLAST validation                             |
| `minimap2_validation/`             | Fast minimap2 validation                     |
| `canonical_classification_writer/` | Kraken2 report to canonical TSV              |
| `canonical_qc_writer/`             | FASTP/SeqKit metrics to canonical TSV        |
| `canonical_validation_writer/`     | BLAST/minimap2 results to canonical TSV      |
| `canonical_assembly_writer/`       | Assembly stats to canonical TSV              |
| `manifest_writer/`                 | Generates \_manifest.json for canonical dir  |

### Library Utilities (lib/)

| File                   | Purpose                                           |
| ---------------------- | ------------------------------------------------- |
| `InputDetector.groovy` | Type-agnostic input detection (FASTQ / directory) |
| `BatchUtils.groovy`    | Batching utilities using `buffer()` operator      |
| `WorkflowMain.groovy`  | Main workflow initialization                      |
| `Utils.groovy`         | General utility functions                         |
| `NfcoreSchema.groovy`  | Schema validation helpers                         |

---

## Development Prerequisites

```bash
# Nextflow (>= 26.04.0)
nextflow -version

# nf-test (>= 0.9.5)
nf-test version

# Java environment for nf-test
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH
```

The pipeline parses under the Nextflow 26 strict v2 grammar (default
in 26+). No `NXF_SYNTAX_PARSER` opt-in is required.

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

Pipeline validation runs before nf-test `setup{}` blocks. Always reference pre-created fixtures rather than building them in `setup`:

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

### 4. nf-core Module Maintenance

Four nf-core modules have local modifications. See [nfcore_module_maintenance.md](docs/development/nfcore_module_maintenance.md) for full details.

| Module            | Modification                   | Update Strategy                                                           |
| ----------------- | ------------------------------ | ------------------------------------------------------------------------- |
| `blast/blastn`    | `export BLASTDB=${db}` env var | Protected in `.nf-core.yml` skip list. Re-apply after manual update.      |
| `fastp`           | None (restored to upstream)    | Safe to update freely. Streaming handled by local `fastp_streaming/`.     |
| `kraken2/kraken2` | Container SHAs, stub versions  | Run `nf-core modules update kraken2/kraken2` -- no functional divergence. |
| `nanoplot`        | Stub hardcoded version         | Run `nf-core modules update nanoplot` -- upstream uses same convention.   |

```bash
nf-core lint
nf-core schema lint
nf-core modules update
```

### 5. Testing Workflow

The test suite is designed to run in stub mode without Docker or external tools.

**Test structure:**

- **59 pipeline-level test functions** under `tests/*.nf.test` -- smoke tests,
  scaling stubs, parameter validation, and the V4 ifEmpty regression cover
- **23 module-internal test files** under `modules/local/*/tests/` -- stub-mode
  unit tests, three of which (output_merger, report_generator, final_aggregator)
  also exercise the real Python algorithm without containers

**Required skip flags for pipeline tests:** All pipeline-level tests must include
`skip_kraken2 = true` and `blast_validation = false` in their params blocks
unless the test specifically exercises that feature in stub mode.

```bash
# Quick validation (via test runner)
./tests/run_tests.sh fast

# Core tests
./tests/run_tests.sh core

# Full suite
./tests/run_tests.sh full

# Specific test
nf-test test tests/nanoseq_test.nf.test --verbose

# Update snapshots after test changes
nf-test test --update-snapshot

# CI parallelism via sharding (e.g. split into 4 shards)
NFT_SHARD=1/4 ./tests/run_tests.sh full
NFT_SHARD=2/4 ./tests/run_tests.sh full
```

### 6. Local benchmarking with simulated data

`nanorunner` (installed in the `nf-core` env) can generate small mock
communities and replay them through the pipeline. A worked example
covering classifier modes, platform profiles, fork counts, and realtime
vs batch input is at
[docs/development/eval_2026-05-29_options_sweep.md](docs/development/eval_2026-05-29_options_sweep.md).

```bash
# Generate ~4000 reads across 3 barcodes from a 3-species mock
nanorunner generate --mock quick_3species --read-count 4000 \
  --target results/sim-data --offline --seed 1 --quiet
```

Three gotchas the eval surfaced that are easy to hit otherwise:

1. **`realtime_mode=true` forces the incremental Kraken2 branch** at
   `subworkflows/local/taxonomic_classification/main.nf:175`. The
   optimized and standard branches are unreachable from any realtime
   run, including any of the platform profiles. To compare classifier
   modes, set `realtime_mode: false` and use `input_dir`.

2. **Platform profiles are tuned for the platform they name.** Running
   `-profile promethion` on dev hardware is a pessimization, not a
   stress test: with `kraken2_memory_mapping=false` (ARM Mac default)
   each Kraken2 fork reloads the DB and the laptop is CPU-oversubscribed.
   For local dev use `-profile minion` for single-sample work or drop
   the platform profile entirely and tune `max_classification_forks`
   to your machine (forks ~ available_cpus / 4 is a reasonable start).

3. **Realtime-mode runs do not exit cleanly after MULTIQC**
   (issue [#22](https://github.com/FOI-Bioinformatics/nanometanf/issues/22)).
   Setting `runtime_metrics_interval_seconds: 0` is not sufficient.
   For benchmarks or CI, run with an external watchdog that kills the
   JVM N seconds after the MultiQC task's `.exitcode` is written.
   Identify the MultiQC task by `.command.sh` content, not by the
   work-dir path -- Nextflow work dirs are hex-hashed, never
   process-named.

---

## Important Parameters

### Input Modes (Mutually Exclusive)

Enforced at the schema level via a `oneOf` constraint
(`nextflow_schema.json:input_mode_selection`). Exactly one must be set.

- `--input` - Samplesheet CSV
- `--input_dir` - Unified directory scanning (v1.5+; replaces `barcode_input_dir`)
- `--barcode_input_dir` - Deprecated, hidden in `--help`; use `--input_dir`
- `--realtime_mode` + `--nanopore_output_dir` - Live FASTQ monitoring

### Real-time Processing

- `--realtime_mode` - Enable real-time monitoring
- `--nanopore_output_dir` - Directory to monitor
- `--max_files` - hard cap on files processed; required for bounded tests
- `--batch_size` - Files per batch (default: 10)
- `--realtime_timeout_minutes` - Inactivity timeout
- `--realtime_processing_grace_period` - Processing completion wait

### Scalable Streaming (v1.5+)

- `--max_concurrent_batches` - Advisory only; not currently enforced (default: 4, see audit P2.9)
- `--max_classification_forks` - Max parallel Kraken2 jobs (default: 8)
- `--kraken2_enable_incremental` - Enable scalable streaming architecture

### Runtime metrics (audit V5)

- `--runtime_metrics_interval_seconds` - Interval (s) for periodic
  `[runtime-metrics]` snapshots emitted by `REALTIME_MONITORING`.
  Default `0` (off); set e.g. `--runtime_metrics_interval_seconds 60`
  on a 24-barcode field run to collect the queue-depth evidence the
  audit asked for. Combined with the expanded `trace.fields`
  (`submit / start / complete / queue`) the resulting
  `execution_trace_*.txt` lets you chart per-task waiting time and
  per-barcode batch counts without instrumenting Nextflow internals.
  Grep `.nextflow.log` for `[runtime-metrics]` to extract:

  ```
  [runtime-metrics] elapsed_s=N files=X batches=Y barcodes=Z \
      batches_per_barcode_min=A batches_per_barcode_max=B
  ```

### Taxonomic Classification

- `--kraken2_db` - Path to Kraken2 database
- `--kraken2_memory_mapping` - Memory-mapped loading (set `false` on ARM Mac)
- `--skip_krona` - Skip Krona (set `true` on ARM Mac)

### Canonical Outputs

- `--write_canonical` - Enable canonical output layer (default: true)

### Platform Profiles

- `-profile minion` - MinION/GridION (1-4 samples)
- `-profile promethion_8` - Balanced (5-12 samples)
- `-profile promethion` - High throughput (12-24+ samples)

---

## Architecture Highlights

### Input Type Detection

Auto-detects in `workflows/nanometanf.nf`:

1. **Real-time FASTQ**: `realtime_mode && nanopore_output_dir`
2. **Directory scan**: `!realtime_mode && input_dir`
3. **Barcode discovery (deprecated alias)**: `!realtime_mode && barcode_input_dir`
4. **Standard samplesheet**: `!realtime_mode && input`

### Channel Flow

```
Input Detection -> QC -> Classification -> Validation -> Reports
     |              |         |               |            |
   FASTQ        CHOPPER   Kraken2          BLAST       MultiQC
   Barcodes     NanoPlot  (scalable)       minimap2    Canonical JSON
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

- **[User Guide](docs/usage.md)** - Complete usage instructions
- **[Development Guide](docs/development/README.md)** - Developer documentation
- **[Testing Guide](docs/development/TESTING.md)** - nf-test documentation
- **[Canonical Output Specification](docs/development/canonical_output_specification.md)** - Source of truth for `outdir/canonical/` (contracts A-D + manifest)
- **[nf-core Module Maintenance](docs/development/nfcore_module_maintenance.md)** - Local modification tracking
- **[Real-time Processing](docs/user/realtime_processing.md)** - Advanced real-time guide
- **[2026-05-29 options-sweep eval](docs/development/eval_2026-05-29_options_sweep.md)** - Benchmark across classifier modes, profiles, fork counts, realtime vs batch
- [nf-core guidelines](https://nf-co.re/docs/contributing/guidelines)
- [Nextflow documentation](https://www.nextflow.io/docs/latest/)

---

**Last updated:** 2026-05-30
**Version:** 1.5.1dev (development); 1.5.0 (released)
**Maintainer:** foi-bioinformatics team (@andreassjodin)

### Recent changes (v1.5.0)

- Streaming classification architecture with per-sample parallelism
- Append-only batch storage with atomic JSON index (O(1) per batch)
- Incremental taxid counting (no cumulative re-reads)
- End-of-session aggregation module
- Backpressure control parameters
- Roughly four to five times higher throughput on high-barcode runs in
  internal benchmarks
- Unified input handling via the `INPUT_SCANNER` subworkflow and `InputDetector`
- `BatchUtils` refactoring: replaced deprecated `Channel.create()` with `buffer()`

### Production-readiness audit closure (2026-05-29)

The 2026-05-28 audit at
`/Users/andreassjodin/.claude/plans/make-an-audit-of-steady-iverson.md`
was shipped across PRs #11-#18 and merged to `dev`. Highlights:

- **P0** (correctness): defensive filters on every `.ifEmpty([])` consumer
  in `workflows/nanometanf.nf` and `subworkflows/local/taxonomic_classification/main.nf`
  so an empty QC output channel can no longer crash with `MissingMethodException`;
  Kraken2 CPU allocation in `conf/modules.config` now scales as
  `max(4, max_cpus / max_classification_forks)` instead of the hard-coded
  serialising `cpus = 8` (the platform-profile overrides were dead code under
  the config load order); `params.max_cpus`, `max_memory`, `max_time` declared.
- **P1** (nf-core posture): `nextflow_schema.json` gained a `oneOf`
  input-mode constraint and entries for the resource params; explicit
  CI matrix runs `nf-test` under `26.04.0` and `latest-everything`
  with profile-sanity stub-mode runs against `minion`, `promethion`, and
  `promethion_8`.
- **P2 / P3** (hardening): `promethion_8` Kraken2 memory cap reduced to
  40 GB via `kraken2_memory_gb`; `MultiQC` config extended with `fastp`,
  `fastqc`, `filtlong`, `seqkit`, and `samtools` modules; canonical-output
  schema documented in `docs/development/canonical_output_specification.md`;
  real-execution `nf-test`s added for the three pure-Python streaming
  Kraken2 modules; per-sample cumulative-taxid state released on
  `is_final_batch`; validation join now `log.warn`s silent drops; type
  hints added across `bin/`.
- **V4 / V5** (verification): `tests/ifempty_sentinel_regression.nf.test`
  forces an empty CHOPPER output channel via `ext.when = false` and
  asserts the `MissingMethodException` cannot return; a periodic
  `[runtime-metrics]` snapshot logger plus expanded `trace.fields`
  give 24-barcode field runs the queue-depth evidence the audit asked
  for, gated on `--runtime_metrics_interval_seconds N`.

CI is fully green for the first time since February 2026: all nine jobs
pass on every PR (nf-test 26.04.0 + latest-everything, profile-sanity
matrix, verify-pipeline matrix, nf-core-lint, pre-commit). Test suite
counts after the audit: 59 pipeline-level test functions across
`tests/`, 23 module-internal test files under `modules/local/*/tests/`.

### Hardening notes (2026-03-01)

- `FASTP_STREAMING` local module: multi-file concatenation for `watchPath`
  mode; upstream `fastp` module restored unchanged
- `MULTIQC` updated to single-tuple input API
- `FASTQC` and `SEQKIT_STATS` version channel fixes (`topic: versions`)
- `kraken2_optimized`: division-by-zero guard and output declaration fix
- Stub-block fixes across 15+ modules (hardcoded versions, output files)
- nf-core module maintenance: `.nf-core.yml` skip list with
  `ACTION REQUIRED` comments
- Removed Unicode from Nextflow files (project policy)
