# Production Readiness Report

**Date**: 2026-03-15
**Scope**: Cross-repo verification of production-readiness changes across nanometanf, nanometa_live, and nanorunner.

---

## 1. nanometanf -- Pipeline Backend

### 1.1 Error Isolation (`conf/error_isolation.config`)

**Status**: VERIFIED

- **Exit codes**: Only exit codes 1 and 2 are ignored (tool-specific errors such as empty input or malformed reads). All other exit statuses trigger `retry` with `maxRetries = 2`.
- **OOM safety**: Exit code 137 (OOM kill) is NOT in the ignore list and will trigger retry, as intended.
- **Signal safety**: Exit codes 130-145 (SIGINT, SIGTERM, SIGKILL, etc.) are NOT in the ignore list and will trigger retry.
- **Process names verified against codebase**:
  - `CHOPPER` -- matches `modules/nf-core/chopper/main.nf`
  - `FASTP_STREAMING` -- matches `modules/local/fastp_streaming/main.nf`
  - `KRAKEN2_KRAKEN2` -- matches `modules/nf-core/kraken2/kraken2/main.nf`
  - `KRAKEN2_OPTIMIZED` -- matches `modules/local/kraken2_optimized/main.nf`
  - `KRAKEN2_INCREMENTAL_CLASSIFIER` -- matches `modules/local/kraken2_incremental_classifier/main.nf`
  - `BLASTN_VALIDATION` -- matches `modules/local/blastn_validation/main.nf`
  - `MINIMAP2_VALIDATION` -- matches `modules/local/minimap2_validation/main.nf`
  - `FLYE` -- matches `modules/nf-core/flye/main.nf`
- **Config inclusion**: `includeConfig 'conf/error_isolation.config'` is present at line 440 of `nextflow.config`, loaded after `modules.config` and `qc_profiles.config`.

### 1.2 Subworkflow Guards

**Status**: VERIFIED

- **qc_analysis/main.nf**: `.ifEmpty([])` guards present on all process outputs (FASTP, FASTP_STREAMING, FILTLONG, CHOPPER, KRAKEN2 variants, SEQKIT_STATS, FASTQC, NANOPLOT).
- **taxonomic_classification/main.nf**: `.ifEmpty([])` guards on all classifier outputs. `groupTuple(remainder: true)` on lines 264, 271, and `.join(..., remainder: true)` on line 278.
- **assembly/main.nf**: `.ifEmpty([])` guards on FLYE and MINIASM outputs. `.join(..., remainder: true)` on line 78 for miniasm input.
- **validation/main.nf**: `.ifEmpty([])` guards on BLASTN_VALIDATION, MINIMAP2_VALIDATION outputs. `remainder: true` on join (line 92) and groupTuple (line 129).

### 1.3 Realtime Safeguard

**Status**: VERIFIED

- `workflows/nanometanf.nf` lines 126-136: `log.warn` issued when `realtime_mode` is enabled without `max_files` or `realtime_timeout_minutes`.

### 1.4 Scaling Configuration

**Status**: VERIFIED

- **production.config**: `cpus`, `memory`, and `time` reference `params.max_cpus`, `params.max_memory`, `params.max_time` via `Math.min()` expressions. `resourceLimits` block present (lines 56-60) referencing params. Executor `cpus` and `memory` also reference params (lines 152-153).
- **promethion.config**: `resourceLimits` block (lines 48-52) uses ternary expressions referencing `params.max_cpus` and `params.max_memory` with fallback defaults.
- **NanoPlot `.collect()` comment**: Present in `workflows/nanometanf.nf` lines 359-363, explaining that `.collect()` blocks until real-time session completes and documenting why `enable_nanoplot_comparison` defaults to false.

### 1.5 Documentation (`docs/meta_fields.md`)

**Status**: VERIFIED

- Documents all custom meta fields: `id`, `single_end`, `barcode`, `batch_id`, `is_final_batch`, `batch_count`, `batch_time`.
- Each field includes Type, Set by, Used by, and description.
- Accurately reflects current pipeline behavior (e.g., `batch_id` set by synchronized counter in taxonomic_classification, `is_final_batch` checked in QC and classification subworkflows).

---

## 2. nanometa_live -- Frontend Dashboard

### 2.1 Sample Detection Caching (`core/utils/sample_detector.py`)

**Status**: VERIFIED

- **Mtime caching**: `_get_dir_mtimes()` computes a hashable fingerprint from 5 watched subdirectories (kraken2, fastp, seqkit, nanoplot, validation).
- **Thread safety**: `_sample_cache_lock` (threading.Lock) guards all reads and writes to `_sample_cache` dict.
- **Cache invalidation**: `invalidate_sample_cache()` exposed for manual clearing. Cache miss occurs when any watched subdirectory mtime changes.

### 2.2 Classification Loaders (`core/utils/classification_loaders.py`)

**Status**: VERIFIED

- **Recursive globs replaced**: `_scan_subdirs_for_pattern()` replaces `glob.glob(..., recursive=True)` with targeted two-level scans (parent -> immediate subdirs).
- **v1.5 nested fallback preserved**: All lookup sequences follow the pattern: (1) top-level cumulative, (1b) v1.5 nested cumulative, (2) standard top-level, (2b) v1.5 nested standard, (3) batch files with `batch_reports/` subdirectory scan. Verified at lines 296-341 (all samples) and 427-464 (specific sample).
- **`.copy()` removal**: The `load_kraken_data()` function returns DataFrames without `.copy()` on cache hits (line 277). The cache stores its own copy at write time (lines 419-420, 505-506, 529-530). See risk assessment below.
- **Incremental aggregation**: Lines 373-414 use a running dict (`agg`) keyed by taxid instead of `pd.concat`, reducing memory from O(all_rows) to O(unique_taxa).

### 2.3 DataFrame Immutability Risk Assessment

**Status**: VERIFIED SAFE

- All `.iloc[]` and `.loc[]` usages in callback tabs are read-only (extracting values for display, not modifying in-place). Grep for `inplace=True` across all tab files returned zero results.
- `kraken2_helpers.py` line 345 uses `.copy()` when returning filtered DataFrames.
- `classification_tab.py` line 573 and 1172 call `.reset_index()` (which returns a new DataFrame) before any `.loc[]` operations.
- No in-place mutations found on cached DataFrames.

### 2.4 QC Loaders (`core/utils/qc_loaders.py`)

**Status**: VERIFIED

- **`_is_file_stable()` check**: Used before reading fastp JSON files (lines 118, 174) and batch stats files (line 237). Non-blocking implementation in `loader_utils.py` compares mtime age against threshold without sleeping.
- **Specific exception handling**: `json.JSONDecodeError` and `OSError` caught separately in fastp loading (lines 140-145, 192-199) and batch stats loading (lines 247-252).

### 2.5 Loader Utilities (`core/utils/loader_utils.py`)

**Status**: VERIFIED

- **`get_last_freshness_fingerprint()`**: Present at line 283. Returns the last computed fingerprint without triggering a filesystem rescan. Thread-safe via `_cache_lock`.
- **`_is_file_stable()`**: Non-blocking mtime-age check (line 47). Threshold set to max(wait_ms/1000, 1.0 second). Returns False for files smaller than 10 bytes or modified within the threshold.

### 2.6 Data Loaders Re-export (`core/utils/data_loaders.py`)

**Status**: VERIFIED

- `get_last_freshness_fingerprint` is re-exported at line 25.
- All loader functions from classification_loaders, qc_loaders, validation_loaders, canonical_loaders, and loader_utils are re-exported for backward compatibility.

### 2.7 Debounce in Interval Callbacks

**Status**: VERIFIED

- **qc_tab.py**: `should_skip_update()` with 2000ms debounce applied to 8 interval-triggered callbacks (lines 91, 163, 407, 740, 783, 890, 1009, 1135, 1318).
- **dashboard_tab.py**: `should_skip_update()` with 2000ms debounce applied to 8 interval-triggered callbacks (lines 245, 617, 698, 810, 880, 1035, 1379, 1526).
- Debounce utility imported from `nanometa_live.app.utils.debounce`.

---

## 3. nanorunner -- Nanopore Simulator

### 3.1 Signal Handlers (`nanopore_simulator/runner.py`)

**Status**: VERIFIED

- `_signal_handler()`: Converts SIGTERM and SIGHUP into KeyboardInterrupt for clean shutdown (line 49).
- `_install_signal_handlers()`: Installs handlers and saves previous handlers for restoration (line 57).
- `_restore_signal_handlers()`: Restores original handlers in the finally block (line 68).
- Handler lifecycle: installed before manifest execution, restored in `finally` block (lines 180, 211).

### 3.2 Temporary File Cleanup (`nanopore_simulator/runner.py`)

**Status**: VERIFIED

- `_cleanup_tmp_files()`: Recursively removes `*.tmp` files from target directory (line 77). Called in `finally` block after manifest execution (line 210), ensuring cleanup on both normal completion and interruption.

### 3.3 Atomic Writes (`nanopore_simulator/executor.py`)

**Status**: VERIFIED

- `_atomic_tmp_path()`: Returns `.{name}.tmp` sibling path (line 26).
- `_copy_file()`: Copies to tmp, then renames. Cleans up tmp on failure (lines 69-84).
- `_rechunk_file()`: Writes to tmp, then renames. Cleans up tmp on failure (lines 166-174).
- `_generate_mixed_file()`: Same atomic pattern (lines 200-208).

### 3.4 Atomic Writes in Generators (`nanopore_simulator/generators.py`)

**Status**: VERIFIED

- `BuiltinGenerator.generate_reads()`: Writes to tmp, renames, cleans up on failure (lines 321-328).
- `SubprocessGenerator.generate_reads()`: Same atomic pattern (lines 568-580).
- Both use the same `_atomic_tmp_path()` helper (line 39).

### 3.5 FASTQ Compress Parameter (`nanopore_simulator/fastq.py`)

**Status**: VERIFIED

- `write_reads()`: Accepts `compress: Optional[bool] = None` parameter (line 79). When None, infers from path suffix. Explicit True/False overrides inference.

### 3.6 96-Barcode Stress Test (`tests/test_integration.py`)

**Status**: VERIFIED

- `TestStress96Barcodes.test_96_barcode_stress()` (line 789): Creates 96 genome files, generates 96 x 500 reads at 100 reads/file in multiplex mode.
- Assertions: 96 barcode directories, 480 total FASTQ files, no path collisions, zero orphaned `.tmp` files.

### 3.7 CI Configuration (`.github/workflows/ci.yml`)

**Status**: VERIFIED

- macOS added to matrix via `include` block (line 19): `macos-latest` with Python 3.12.
- Ubuntu matrix: Python 3.9, 3.11, 3.12.
- `fail-fast: false` ensures all matrix entries run independently.

---

## 4. Cross-Repo Integration Verification

### 4.1 Error Isolation + Frontend Compatibility

The error isolation config ignores exit codes 1 and 2, causing failed samples to produce empty outputs. The frontend handles this correctly:
- `classification_loaders.py` returns empty DataFrames when no report files are found.
- `qc_loaders.py` returns `_empty_fastp_stats()` / `_empty_nanoplot_stats()` when directories are missing.
- `sample_detector.py` gracefully handles missing subdirectories via `os.path.exists()` checks.

### 4.2 Pipeline Output + Frontend Polling Consistency

- Pipeline produces atomic writes for progressive cumulative reports (temp file + rename, `taxonomic_classification/main.nf` lines 232-240).
- Frontend uses `_is_file_stable()` to avoid reading partially-written files.
- Freshness fingerprint (`check_data_freshness()`) uses directory-level mtime scans, compatible with atomic write patterns.

### 4.3 Resource Parameterization + PromethION Profile

- Both `production.config` and `promethion.config` reference `params.max_cpus` and `params.max_memory`, allowing operator override via CLI flags.
- PromethION `resourceLimits` uses ternary with fallback defaults, so missing params do not cause failures.

---

## 5. Issues Found

### 5.1 Minor: No Issues Found

All verified changes are consistent and correctly implemented across the three repositories.

---

## 6. Remaining Items / Known Limitations

1. **KRAKEN2/NANOPLOT nf-core modules**: Marked `ACTION REQUIRED` for upstream re-sync when convenient. No functional divergence.
2. **Watchlist GTDB-to-NCBI name mapping**: Feature request for pathogen detection with GTDB taxonomy databases. Not yet implemented.
3. **pathogens.yaml taxid accuracy**: E. coli O157:H7 uses generic taxid 562 instead of serotype-specific 83334.
4. **dash-ag-grid**: Needs addition to conda env nf-core specification.
5. **Enable/Disable All watchlist**: Can cause 30+ second UI freeze with large pathogen lists. Batch method needed in WatchlistManager.
6. **Uncommitted changes**: Multiple bugfixes across nanometa_live remain uncommitted.
7. **Unicode in Nextflow**: `promethion.config` comment block (lines 155-158) contains Unicode checkmark characters. These should be replaced with ASCII equivalents per project convention.

---

## 7. Verdict

**Production-ready** with the caveats listed above. The error isolation, resource parameterization, frontend performance optimizations, and simulator hardening are all correctly implemented and verified across repositories. The three systems integrate consistently through their shared data contracts (file paths, output formats, polling behavior).
