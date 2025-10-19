# CLAUDE.md

**Developer Guide for foi-bioinformatics/nanometanf**

This file provides guidance for AI assistants (Claude) and developers working on the nanometanf pipeline. For user documentation, see [README.md](README.md) and [docs/user/](docs/user/).

## Pipeline Overview

**nanometanf** is a nf-core compliant Nextflow pipeline for comprehensive real-time Oxford Nanopore Technologies (ONT) sequencing data analysis, serving as the computational backend for Nanometa Live.

**Core Capabilities:**
- Real-time analysis during active sequencing runs
- POD5 basecalling with Dorado
- Pre-demultiplexed barcode directory processing
- Taxonomic classification with Kraken2
- Quality control and validation workflows

## AI Assistant Integration

**Specialized Agent for Nextflow Development:**

When working on this pipeline, the `bioinformatics-pipeline-dev` agent is available as a specialized expert with deep knowledge of:
- **Nextflow DSL2**: Advanced workflow patterns, channel operations, and process definitions
- **nf-core standards**: Compliance requirements, best practices, and conventions
- **Pipeline development**: Testing with nf-test, module creation, and workflow optimization
- **ONT data processing**: Nanopore-specific patterns and real-time monitoring

**Use the agent for:**
- Debugging complex Nextflow workflows
- Implementing nf-core compliant features
- Optimizing channel operations and resource allocation
- Creating and maintaining nf-test test suites
- Real-time monitoring pattern implementation

## Current Release Status

### ⚠️ CRITICAL: v1.3.0 IS BROKEN - DO NOT USE

**v1.3.0 Release:** 2025-10-19 (BROKEN - parse-time error)
**Status:** 🚫 **Completely unusable** - fails immediately on ANY invocation
**Issue:** Missing Kraken2 incremental classifier modules cause parse error
**Workaround:** **Use v1.2.0 until v1.3.1 hotfix is released**

### Recommended Production Release: v1.2.0

**Release Date:** 2025-10-16
**Status:** ✅ Production Ready
**nf-core Compliance:** 100% (707/707 tests passing, 0 failures)

### Key Features (v1.1.0 + v1.2.0)

1. **Chopper as Default QC Tool** (v1.1.0)
   - **Performance:** 7x faster than NanoFilt for nanopore data
   - **Implementation:** Rust-based nanopore-native filtering
   - **Configuration:** `--qc_tool chopper` (default)
   - **Parameters:**
     - `--chopper_quality 10` - Minimum quality score
     - `--chopper_minlength 1000` - Minimum read length
     - `--chopper_maxlength null` - Maximum read length (no limit)
     - `--chopper_headcrop 0` - Trim bases from read start
   - **Files:** `modules/nf-core/chopper/`, `subworkflows/local/qc_analysis/main.nf`

2. **Multi-Tool QC Support** (v1.1.0)
   - **Tool-agnostic interface:** Easy switching between QC tools
   - **Supported tools:** chopper (default), fastp, filtlong
   - **Future-ready:** Architecture prepared for nanoq integration
   - **Switch:** `--qc_tool {chopper|fastp|filtlong}`

3. **Production Readiness** (v1.2.0)
   - **nf-core Compliance:** 100% lint compliance (707/707 tests)
   - **Version Consistency:** Clean semantic versioning (no 'dev' suffixes in releases)
   - **Module Synchronization:** All modules synced with nf-core remote
   - **RO-Crate Metadata:** FAIR principles compliance for workflow discoverability
   - **Professional Code Quality:** Zero template TODOs, production-ready documentation

4. **Dorado 1.1.1 Compatibility** (v1.1.0)
   - **Model syntax:** Simplified format (removed @version suffixes)
   - **Old:** `dna_r10.4.1_e4.3_400bps_hac@v5.0.0`
   - **New:** `dna_r10.4.1_e4.3_400bps_hac`
   - **Files updated:** nextflow.config, 5 test files (17 model references)

5. **Real-time Monitoring Optimizations** (v1.2.1dev)
   - **Processing-Aware Timeout**: Two-stage timeout prevents premature stop during active processing
     - **Detection timeout**: `--realtime_timeout_minutes` triggers after N minutes without new files
     - **Grace period**: `--realtime_processing_grace_period` (default: 5 min) waits for downstream processing completion
     - **Impact**: Eliminates incomplete analysis from premature timeout
   - **Per-Barcode Batching**: Files grouped by barcode before batching for efficient processing
     - **Implementation**: `groupTuple(by: barcode)` ensures barcode-specific batches
     - **Benefit**: No cross-barcode contamination, maintains sample context
     - **Files**: `subworkflows/local/realtime_monitoring/main.nf`
   - **Adaptive Batch Sizing**: Dynamic adjustment based on file arrival rate
     - **Parameter**: `--adaptive_batching` (default: true)
     - **Configuration**: `--min_batch_size`, `--max_batch_size`, `--batch_size_factor`
     - **Behavior**: Automatically scales batch size between min/max based on throughput
   - **Priority Routing**: High-priority samples processed before normal samples
     - **Parameter**: `--priority_samples` (list of sample IDs or barcodes)
     - **Implementation**: Channel branching with priority stream mixed first
     - **Use case**: Urgent pathogen detection, clinical samples, control samples

6. **PromethION Real-Time Processing Optimizations** (v1.3.0 - Platform Profiles Only)
   - **⚠️  NOTE**: v1.3.0 released with **platform profiles only**. Incremental processing features (Phase 1.1 and 1.2) are **planned but not yet implemented**.
   - **Working features**: Platform-specific profiles, memory-mapped database loading (Phase 2), conditional NanoPlot execution (Phase 1.3)
   - **Non-functional**: Incremental Kraken2 classification, QC statistics aggregation (modules missing in v1.3.0)
   - **Performance gains**: 2-6x throughput improvement with platform profiles (Phase 3)

   **Phase 1: Core Processing Optimizations** (Partially Implemented)

   - **1.1 Incremental Kraken2 Classification** ⚠️  **NOT IMPLEMENTED IN v1.3.0**:
     - **Status**: Modules missing (`kraken2_incremental_classifier/`, `kraken2_output_merger/`, `kraken2_report_generator/`)
     - **Planned feature**: Batch-level caching to eliminate O(n²) re-classification complexity
     - **Expected time savings**: 30-90 minutes for 30-batch run (when implemented)
     - **Implementation**: Disabled in v1.3.1dev until modules are created

   - **1.2 QC Statistics Aggregation** ⚠️  **NOT IMPLEMENTED IN v1.3.0**:
     - **Status**: Module missing (`seqkit_merge_stats/`)
     - **Planned feature**: Weighted statistical merging from batch-level SeqKit stats
     - **Expected time savings**: 5-15 minutes for 30-batch run (when implemented)

   - **1.3 Conditional NanoPlot Execution**:
     - Skip intermediate batches, run every Nth batch + final batch
     - Intelligent channel filtering using `.filter{}` operator
     - **Time savings**: 54-81 minutes for 30-batch run (90 min → 9 min)
     - **Configure**: `--nanoplot_realtime_skip_intermediate true`, `--nanoplot_batch_interval 10`
     - **Platform defaults**: MinION (every 5th), PromethION-8 (every 7th), PromethION (every 10th)
     - **Files**: `subworkflows/local/qc_analysis/main.nf` (Lines 196-254)

   - **1.4 Deferred MultiQC Execution**:
     - Leverages `.collect()` operator for end-of-run processing
     - Avoids redundant file parsing during incremental batches
     - **Time savings**: 3-9 minutes for 30-batch run
     - **Control**: `--multiqc_realtime_final_only true` (default)
     - **Files**: `workflows/nanometanf.nf` (Lines 308-363)

   **Phase 2: Database Preloading**

   - **Memory-mapped database loading**:
     - Automatic enablement in real-time mode
     - OS-level page cache reuse across batches
     - First batch loads DB (~3 min), subsequent batches reuse cache (~instant)
     - **Time savings**: 30-90 minutes for 30-batch run (eliminates 29 DB loads)
     - **Kraken2 flag**: `--memory-mapping` automatically applied
     - **Control**: `--kraken2_memory_mapping true`, `--kraken2_use_optimizations true`
     - **Files**: `subworkflows/local/taxonomic_classification/main.nf` (Lines 42-63, 128-142)

   **Phase 3: Platform-Specific Profiles**

   Three profiles optimized for different sequencing scenarios:

   - **`-profile minion`** (Single Sample Focus):
     - **Target**: MinION/GridION, 1-4 samples, clinical diagnostics
     - **Strategy**: Speed over parallelism - maximize per-sample resources
     - **Resources**: 8 CPUs/Kraken2, 4 CPUs/FASTP, queueSize=8
     - **NanoPlot**: Every 5th batch (more frequent for real-time feedback)
     - **Best for**: Urgent pathogen ID, single patient samples
     - **Performance**: Fastest per-sample completion
     - **File**: `conf/minion.config`

   - **`-profile promethion_8`** (Balanced):
     - **Target**: PromethION, 5-12 samples, environmental surveillance
     - **Strategy**: Balanced speed and parallelism
     - **Resources**: 6 CPUs/Kraken2, 3 CPUs/FASTP, queueSize=24
     - **NanoPlot**: Every 7th batch
     - **Best for**: Multi-site environmental monitoring, metagenomic surveys
     - **Performance**: 4 samples in parallel on 24-core system
     - **File**: `conf/promethion_8.config`

   - **`-profile promethion`** (High Throughput):
     - **Target**: PromethION, 12-24+ samples, wastewater monitoring
     - **Strategy**: Throughput over speed - maximize sample parallelism
     - **Resources**: 4 CPUs/Kraken2, 2 CPUs/FASTP, queueSize=48
     - **NanoPlot**: Every 10th batch (less frequent for high throughput)
     - **Best for**: City-wide surveillance, large-scale studies
     - **Performance**: 6-12 samples in parallel on 24-48 core system
     - **File**: `conf/promethion.config`

   **Performance Benchmarks (30 batches, 24 barcodes)**:

   | Configuration | Computation Time | Speedup |
   |---------------|------------------|---------|
   | **Without optimizations** | 324 min (5.4 hrs) | 1.0x |
   | **With all optimizations** | 18 min (0.3 hrs) | 18x |
   | **Time saved** | 306 min (5.1 hrs) | **94% reduction** |

   | Profile | Parallel Samples | Per-Sample Speed | Total Time (720 tasks) | Throughput |
   |---------|------------------|------------------|------------------------|------------|
   | **minion** | 3 | Fastest | 12 hours | 1.7x |
   | **promethion_8** | 4 | Balanced | 10.5 hours | 1.9x |
   | **promethion** | 6 | Slower | 10 hours | 2.0x |

   **Automatic Optimization Enablement**:
   - All Phase 1+2 optimizations automatically enabled with `--realtime_mode` OR any platform profile
   - No manual parameter configuration required
   - Platform profiles set optimal `nanoplot_batch_interval` and executor settings automatically

   **Documentation**: See `docs/development/PROMETHION_OPTIMIZATIONS.md` for comprehensive technical details

   **Usage Examples**:
   ```bash
   # Single sample MinION (clinical diagnostics)
   nextflow run foi-bioinformatics/nanometanf \
     -profile minion,conda \
     --input sample.csv \
     --realtime_mode \
     --kraken2_db /databases/kraken2 \
     --outdir results/

   # 8 samples PromethION (environmental monitoring)
   nextflow run foi-bioinformatics/nanometanf \
     -profile promethion_8,conda \
     --input environmental.csv \
     --realtime_mode \
     --kraken2_db /databases/kraken2 \
     --outdir results/

   # 24 samples PromethION (wastewater surveillance)
   nextflow run foi-bioinformatics/nanometanf \
     -profile promethion,conda \
     --input wastewater.csv \
     --realtime_mode \
     --kraken2_db /databases/kraken2 \
     --outdir results/
   ```

### Known Issues and Constraints

**Test Dependencies (Non-functional):**
- **Dorado Binary Tests:** 4-5 tests require dorado in PATH or Docker image
  - **Status:** Not blocking - functionality verified manually
  - **Workaround:** Use local profile or ensure dorado binary available
  - **Future:** Add dorado to Docker image in v1.3.0

- **Kraken2 Real Database Tests:** Some tests require actual Kraken2 database
  - **Status:** Stub-mode tests passing, real DB tests for integration validation
  - **Workaround:** Use stub mode for CI/CD testing
  - **Note:** All workflow logic validated with stub mode

**Advisory Warnings (28 total, non-blocking):**
- **Module Updates Available:** 5 modules have newer versions available
  - `blast/blastn`, `blast/makeblastdb`, `fastp`, `kraken2/kraken2`, `untar`
  - **Recommendation:** Schedule for v1.3.0 maintenance cycle

- **Subworkflow Patterns:** 22 structural warnings (valid DSL2 patterns)
  - Acceptable patterns for simple/orchestration subworkflows
  - nf-core template boilerplate version tracking
  - **Impact:** None - architectural choices, not errors

**Operational Constraints:**
1. **Real-time tests require `max_files` or `realtime_timeout_minutes`** - Without limits, watchPath() will wait indefinitely
   - **Recommended**: Use `--realtime_timeout_minutes` for automatic stop
   - **Alternative**: Use `--max_files` for fixed limit (useful for tests)
2. **Setup blocks don't work for pipeline tests** - Use fixtures instead
3. **Dynamic resources experimental** - Disabled by default for stability
4. **Input types mutually exclusive** - Cannot mix POD5 and FASTQ in same run

### Migration Guides

#### v1.0.0 → v1.2.0

**Breaking Changes:** None - Fully backward compatible

**Recommended Updates:**

1. **QC Performance:** Switch to Chopper (automatic with v1.2.0 defaults)
   ```bash
   # Automatic with defaults (Chopper is now default)
   nextflow run foi-bioinformatics/nanometanf --input samplesheet.csv

   # Or explicitly specify
   nextflow run foi-bioinformatics/nanometanf --qc_tool chopper
   ```

2. **Dorado Model Syntax:** Update to simplified format (backward compatible)
   ```bash
   # Old format (still works)
   --dorado_model dna_r10.4.1_e4.3_400bps_hac@v5.0.0

   # New format (recommended)
   --dorado_model dna_r10.4.1_e4.3_400bps_hac
   ```

3. **Test Assertions:** Use tool-agnostic patterns for QC tests
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

## Critical Files for Development

### Configuration
- `nextflow.config` - Main configuration file (150+ parameters)
- `nextflow_schema.json` - Parameter validation schema
- `conf/base.config` - Base process resource configuration
- `conf/modules.config` - Module-specific configurations
- `conf/qc_profiles.config` - QC strategy profiles

### Core Workflow Files
- `main.nf` - Pipeline entry point
- `workflows/nanometanf.nf` - Main workflow orchestration
- `lib/WorkflowMain.groovy` - Workflow initialization logic
- `lib/WorkflowNanometanf.groovy` - Pipeline-specific workflow logic

### Subworkflows (subworkflows/local/)
- `realtime_monitoring/main.nf` - **CRITICAL** - Real-time FASTQ file monitoring (watchPath)
- `realtime_pod5_monitoring/main.nf` - **CRITICAL** - Real-time POD5 monitoring + basecalling
- `enhanced_realtime_monitoring/main.nf` - Advanced real-time with priority/batching
- `dorado_basecalling/main.nf` - POD5 basecalling workflow
- `barcode_discovery/main.nf` - Automated barcode directory discovery
- `qc_analysis/main.nf` - Quality control workflow
- `taxonomic_classification/main.nf` - Kraken2 taxonomic profiling
- `validation/main.nf` - BLAST validation
- `dynamic_resource_allocation/main.nf` - **EXPERIMENTAL** - Intelligent resource optimization

**Note:** All subworkflows now follow nf-core structure with `main.nf` in subdirectories and `meta.yml` metadata files.

### Key Modules (modules/local/)
- `dorado_basecaller/` - Dorado basecalling module
- `dorado_demux/` - Dorado demultiplexing module
- Resource allocation modules (analyze_input_characteristics, monitor_system_resources, etc.)

### Testing Infrastructure
- `tests/` - nf-test test suite directory
- `tests/fixtures/` - **IMPORTANT** - Pre-created test data (avoids setup{} timing issues)
- `tests/edge_cases/` - Edge case test scenarios
- `nf-test.config` - nf-test configuration
- `tests/nextflow.config` - Test-specific Nextflow configuration

## Development Prerequisites

```bash
# Required Java environment for nf-test
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH

# Verify setup
nextflow -version  # Should be >= 24.10.5
nf-test version    # Should be >= 0.9.0
```

## Key Development Patterns

### 1. Real-time Monitoring with watchPath()

**CRITICAL**: Real-time monitoring is a core feature. The `watchPath()` operator requires proper limiting to avoid infinite hangs.

**Pattern 1: Basic limiting with max_files (v1.0+)**

```groovy
def ch_watched = Channel.watchPath("${dir}/${pattern}", 'create,modify')
ch_files = params.max_files
    ? ch_watched.take(params.max_files.toInteger())
    : ch_watched
```

**Pattern 2: Intelligent inactivity timeout (v1.2.1+)**

```groovy
// Apply timeout logic if realtime_timeout_minutes is set
if (params.realtime_timeout_minutes) {
    log.info "Real-time timeout enabled: Will stop after ${params.realtime_timeout_minutes} minutes of inactivity"

    // Track last file detection time
    def last_file_time = System.currentTimeMillis()

    // Create heartbeat channel that checks timeout every minute
    def ch_timeout_check = Channel.interval('1min').map { 'TIMEOUT_CHECK' }

    // Tag files and mix with timeout checks
    def ch_files_tagged = ch_all_files.map { file -> ['FILE', file] }
    def ch_checks_tagged = ch_timeout_check.map { check -> ['CHECK', check] }
    def ch_mixed = ch_files_tagged.mix(ch_checks_tagged)

    // Apply timeout logic with until()
    def files_processed = 0
    ch_input_files = ch_mixed
        .until { type, item ->
            if (type == 'FILE') {
                // Update last file time when file is detected
                last_file_time = System.currentTimeMillis()
                files_processed++

                // Stop if max_files reached
                if (params.max_files && files_processed >= params.max_files) {
                    log.info "Real-time monitoring: Reached max_files limit (${params.max_files})"
                    return true
                }
                return false

            } else if (type == 'CHECK') {
                // Check if timeout exceeded
                def current_time = System.currentTimeMillis()
                def inactive_ms = current_time - last_file_time
                def inactive_minutes = inactive_ms / (1000 * 60)

                if (inactive_minutes >= params.realtime_timeout_minutes) {
                    log.info "Real-time monitoring stopped: No new files detected for ${params.realtime_timeout_minutes} minutes"
                    return true
                }
                return false
            }
            return false
        }
        .filter { type, item -> type == 'FILE' }  // Remove timeout checks
        .map { type, file -> file }  // Extract file from tuple
}
```

**Key concepts:**
- **Heartbeat channel**: `Channel.interval('1min')` creates periodic timeout checks
- **Tagged channels**: Mix file events with timeout checks using tuples
- **Inactivity tracking**: `last_file_time` updated on each file detection
- **Graceful termination**: Stops ingestion but completes processing of queued files

**Files using watchPath():**
- `subworkflows/local/realtime_monitoring/main.nf`
- `subworkflows/local/realtime_pod5_monitoring/main.nf`
- `subworkflows/local/enhanced_realtime_monitoring/main.nf`

### 2. Test Fixtures Pattern

**CRITICAL**: Pipeline validation runs BEFORE nf-test `setup{}` blocks execute. Always use pre-created fixtures for workflow/pipeline tests:

```groovy
// CORRECT - uses pre-existing fixture
when {
    params {
        input = "$projectDir/tests/fixtures/samplesheets/minimal.csv"
        outdir = "$outputDir"
    }
}

// WRONG - samplesheet doesn't exist yet during validation
setup {
    """
    cat > $outputDir/test.csv << 'EOF'
    sample,fastq,barcode
    EOF
    """
}
when {
    params {
        input = "$outputDir/test.csv"  // FAILS - file not created yet
    }
}
```

**Fixture location:** `tests/fixtures/`
- `tests/fixtures/samplesheets/` - Pre-created samplesheet CSV files
- `tests/fixtures/fastq/` - Test FASTQ files
- `tests/fixtures/pod5/` - Test POD5 files
- `tests/fixtures/README.md` - Fixture pattern documentation

### 3. nf-core Compliance

Run these commands before committing:

```bash
# Pipeline linting
nf-core lint

# Schema validation
nf-core schema lint

# Module/subworkflow updates
nf-core modules update
nf-core subworkflows update
```

### 4. Testing Workflow

```bash
# Run full test suite
export JAVA_HOME=$CONDA_PREFIX/lib/jvm && export PATH=$JAVA_HOME/bin:$PATH
nf-test test --verbose

# Run specific test file
nf-test test tests/nanoseq_test.nf.test --verbose

# Run tests with specific tag
nf-test test --tag core
```

## Important Parameters

### Input Mode Selection (Mutually Exclusive)
- `--input` - Samplesheet CSV (standard mode)
- `--barcode_input_dir` - Pre-demultiplexed barcode directories
- `--pod5_input_dir` + `--use_dorado` - POD5 basecalling mode

### Real-time Processing

**Basic Configuration:**
- `--realtime_mode` - Enable real-time file monitoring (default: false)
- `--nanopore_output_dir` - Directory to monitor for new files
- `--file_pattern` - File matching pattern (default: `**/*.fastq{,.gz}`)
- `--max_files` - **CRITICAL FOR TESTS** - Limit files processed (prevents watchPath hangs)
- `--batch_size` - Files per batch (default: 10)

**Timeout Configuration (v1.2.1+):**
- `--realtime_timeout_minutes` - Stop monitoring after N minutes of inactivity (default: null = indefinite)
  - **Use case**: Automatic stop when sequencing completes
  - **Example**: `--realtime_timeout_minutes 10` stops after 10 minutes without new files
  - **Behavior**: Triggers detection timeout, then enters grace period
- `--realtime_processing_grace_period` - Additional minutes to wait for downstream processing after detection timeout (default: 5)
  - **Purpose**: Prevents premature stop while QC tasks (CHOPPER, FASTQC, NANOPLOT) are still running
  - **Example**: With `--realtime_timeout_minutes 10` and grace period of 5, total max wait = 15 minutes from last file
  - **Logging**: Shows progress during grace period: "No new files for X min. Grace period: waiting for processing to complete (Y/5 min)"

**Advanced Batching (v1.2.1+):**
- `--adaptive_batching` - Enable dynamic batch size adjustment (default: true)
  - **Benefit**: Automatically scales batch size based on file arrival rate
  - **Implementation**: `batch_size` adjusted between `min_batch_size` and `max_batch_size`
- `--min_batch_size` - Minimum files per batch (default: 1)
- `--max_batch_size` - Maximum files per batch (default: 50)
- `--batch_size_factor` - Multiplier for dynamic batch sizing (default: 1.0)
  - **Example**: `--batch_size_factor 1.5` increases batches by 50% in high-throughput scenarios

**Priority Routing (v1.2.1+):**
- `--priority_samples` - List of high-priority sample IDs or barcodes (default: [])
  - **Format**: Comma-separated list: `--priority_samples "sample1,barcode01,urgent_patient"`
  - **Behavior**: Priority samples routed through dedicated channel and processed before normal samples
  - **Use cases**: Urgent pathogen detection, clinical diagnostics, positive controls
  - **Logging**: Shows "Priority routing enabled for N samples: [list]"

### Dorado Basecalling
- `--use_dorado` - Enable Dorado basecalling (default: false)
- `--pod5_input_dir` - Directory containing POD5 files for basecalling
- `--dorado_path` - Path to dorado executable (default: 'dorado' from PATH)
  - **Use case**: When dorado is not in PATH or using specific version
  - **Example**: `--dorado_path /usr/local/bin/dorado-1.1.1/bin/dorado`
  - **Fixed in v1.2.1**: Parameter now properly used (was ignored in v1.2.0)
- `--dorado_model` - Basecalling model (default: dna_r10.4.1_e4.3_400bps_hac)
  - **Simplified syntax in v1.1.0**: Use `dna_r10.4.1_e4.3_400bps_hac` (no @version suffix)
  - **Backward compatible**: Old format with @version still works
- `--dorado_device` - Device for basecalling: `cpu`, `auto` (default: auto)
  - **auto**: Automatically detects GPU (Metal on Apple Silicon, CUDA on NVIDIA)
  - **Performance**: GPU ~1.65x faster than CPU (tested on M1 Max)

### Quality Control
- `--qc_tool` - QC tool selection: `chopper` (default), `fastp`, `filtlong`
  - **chopper**: Nanopore-native Rust-based filtering (7x faster than NanoFilt)
  - **fastp**: General-purpose QC with rich HTML reporting
  - **filtlong**: Nanopore-optimized length-weighted filtering
- `--chopper_quality` - Minimum quality score for CHOPPER (default: 10)
- `--chopper_minlength` - Minimum read length for CHOPPER (default: 1000)
- `--chopper_maxlength` - Maximum read length for CHOPPER (default: null)
- `--chopper_headcrop` - Trim bases from read start (default: 0)
- `--chopper_tailcrop` - Trim bases from read end (default: 0)

### Experimental Features (Disabled by Default for v1.0)
- `--enable_dynamic_resources` - Intelligent resource allocation (default: false)
- `--optimization_profile` - Resource optimization profile (default: auto)

## Documentation Structure

```
docs/
├── README.md                      # Documentation index
├── user/                          # User-facing documentation
│   ├── usage.md                   # Pipeline usage guide
│   ├── output.md                  # Output file descriptions
│   └── qc_guide.md                # Quality control guide
└── development/                   # Developer documentation
    ├── testing_guide.md           # Testing guide
    ├── TESTING.md                 # Comprehensive testing documentation
    ├── production_deployment.md   # Production deployment guide
    └── dynamic_resource_allocation.md  # Dynamic resource feature docs
```

## Common Development Tasks

### Adding a New Module

```bash
# Install nf-core module
nf-core modules install <module_name>

# Create local module
nf-core modules create <module_name>

# Update module
nf-core modules update <module_name>
```

### Adding a New Test

1. Create test data in `tests/fixtures/` if needed
2. Create test file `tests/<test_name>.nf.test`
3. Use fixtures for samplesheet inputs
4. Set `max_files` for real-time tests
5. Run `nf-test test tests/<test_name>.nf.test --verbose`

### Debugging Failed Tests

```bash
# Check test log
cat .nf-test/tests/<test_id>/meta/nextflow.log

# Check test output
ls -la .nf-test/tests/<test_id>/output/

# Run test with detailed output
nf-test test <test_file> --verbose --debug
```

## Architecture Details

### Input Type Detection Logic

The pipeline automatically detects input type in `workflows/nanometanf.nf`:

1. **Real-time POD5 mode**: `realtime_mode && use_dorado && pod5_input_dir`
2. **Real-time FASTQ mode**: `realtime_mode && !use_dorado && nanopore_output_dir`
3. **Static POD5 basecalling**: `!realtime_mode && use_dorado && pod5_input_dir`
4. **Barcode directory discovery**: `!realtime_mode && barcode_input_dir`
5. **Standard samplesheet**: `!realtime_mode && input`

### Channel Flow

```
Input Detection
  ↓
Basecalling (if POD5)
  ↓
Barcode Discovery (if --barcode_input_dir)
  ↓
Quality Control (FASTP/Filtlong)
  ↓
Taxonomic Classification (Kraken2)
  ↓
Validation (BLAST, if enabled)
  ↓
MultiQC Report
```

## Release Process (For Maintainers)

### Standard Release Workflow

**1. Pre-Release Preparation**

```bash
# Ensure on dev branch with all changes committed
git checkout dev
git status  # Should be clean

# Run comprehensive tests
export JAVA_HOME=$CONDA_PREFIX/lib/jvm && export PATH=$JAVA_HOME/bin:$PATH
nf-test test --verbose

# Run nf-core lint
nf-core lint --release

# Verify no critical failures
```

**2. Version Bump**

Update versions in:
- `nextflow.config`: `version = '1.X.Y'` (remove 'dev' suffix)
- `.nf-core.yml`: `version: 1.X.Y` (remove 'dev' suffix)
- Commit with message: `Update version to 1.X.Y for release readiness`

**3. Update Documentation**

- **CHANGELOG.md**: Add comprehensive release section with all changes
- **EVALUATION_SUMMARY.md**: Create production readiness assessment (for major releases)
- **RELEASE_NOTES.md**: Create GitHub release notes file
- Commit with message: `Release v1.X.Y: [brief description]`

**4. Final Validation**

```bash
# Re-run lint with release flag
nf-core lint --release

# Verify 0 critical failures
# Check that version strings are clean (no 'dev')
```

**5. Merge and Tag**

```bash
# Switch to master
git checkout master

# Merge dev (should be fast-forward if no remote changes)
git merge dev

# If remote has changes, pull and merge
git pull origin master --no-rebase --no-edit
git push origin master

# Create annotated tag
git tag -a v1.X.Y -m "Release v1.X.Y - [Brief description]

[Bullet points of key changes]"

# Push tag
git push origin v1.X.Y
```

**6. Sync Branches**

```bash
# Keep dev in sync with master post-release
git checkout dev
git merge master
git push origin dev
```

**7. Create GitHub Release**

Option A - Using GitHub CLI:
```bash
gh auth login
gh release create v1.X.Y \
  --title "v1.X.Y - [Release Name]" \
  --notes-file RELEASE_NOTES_v1.X.Y.md
```

Option B - Using GitHub Web UI:
1. Navigate to: `https://github.com/foi-bioinformatics/nanometanf/releases/new?tag=v1.X.Y`
2. Copy contents from RELEASE_NOTES file
3. Publish release

**8. Prepare Next Development Cycle**

```bash
# On dev branch
git checkout dev

# Bump to next dev version
# Update nextflow.config: version = '1.X.Y+1dev'
# Update .nf-core.yml: version: 1.X.Y+1dev

# Add CHANGELOG placeholder
# Add to top of CHANGELOG.md:
## [Unreleased]

### Added
-

### Changed
-

### Fixed
-

# Commit
git commit -m "Prepare v1.X.Y+1dev: Post-v1.X.Y development cycle"
git push origin dev
```

### Release Types

**Major Release (X.0.0)**
- Breaking changes
- Major new features
- Requires comprehensive EVALUATION_SUMMARY.md
- Full test suite validation on production data

**Minor Release (1.X.0)**
- New features
- Non-breaking improvements
- Performance enhancements
- Comprehensive CHANGELOG section

**Patch Release (1.2.X)**
- Bug fixes only
- Security patches
- Documentation improvements
- Quick turnaround, minimal testing impact

### Critical Files for Releases

- `nextflow.config` - Version string
- `.nf-core.yml` - Template version
- `CHANGELOG.md` - Complete change history
- `EVALUATION_SUMMARY.md` - Major release assessment
- `RELEASE_NOTES_vX.Y.Z.md` - GitHub release content
- `modules.json` - Module version tracking
- `ro-crate-metadata.json` - Auto-synced metadata

## nf-core Tools Integration

```bash
# Update pipeline template
nf-core sync

# Bump version
nf-core bump-version <new_version>

# Create params file
nf-core create-params-file

# Download pipeline for offline use
nf-core download foi-bioinformatics/nanometanf
```

## Git Workflow

```bash
# Never skip hooks or force push to main
git add <files>
git commit -m "descriptive message"  # Hooks will run automatically
git push origin <branch>

# Create PR using GitHub CLI
gh pr create --title "Title" --body "Description"
```

## Additional Resources

- [nf-core guidelines](https://nf-co.re/docs/contributing/guidelines)
- [Nextflow documentation](https://www.nextflow.io/docs/latest/)
- [nf-test documentation](https://www.nf-test.com/)
- [Dorado documentation](https://github.com/nanoporetech/dorado)

---

**Last Updated**: 2025-10-19
**Current Stable Release**: v1.2.0 (Production Ready - Recommended)
**Latest Release**: v1.3.0 (⚠️  BROKEN - Do not use)
**Development Version**: 1.3.1dev (Hotfix for v1.3.0 + future optimizations)
**Nextflow Version**: >=24.10.5
**nf-core Compliance**: 100% (707/707 tests passing)

**v1.3.0 Critical Issue**:
- **Status**: Parse-time error prevents ANY pipeline execution
- **Cause**: Missing Kraken2 incremental classifier modules
- **Fix**: Disabled in v1.3.1dev (commit a71652f)
- **Workaround**: Use v1.2.0 until v1.3.1 is released

**Major Features in v1.3.0** (Platform Profiles Working, Incremental Processing Planned):
- Platform-specific profiles (minion, promethion_8, promethion) ✅ WORKING
- Memory-mapped database preloading (Phase 2) ✅ WORKING
- Conditional NanoPlot execution (Phase 1.3) ✅ WORKING
- Incremental Kraken2 classification ❌ NOT IMPLEMENTED (planned for future)
- QC statistics aggregation ❌ NOT IMPLEMENTED (planned for future)
