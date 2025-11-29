# CLAUDE.md

**AI-Assisted Development Guide for nanometanf**

This file provides guidance specifically for AI assistants (Claude) working on the nanometanf pipeline. For complete developer documentation, see [docs/development/README.md](docs/development/README.md).

---

## Pipeline Overview

**nanometanf** is an nf-core compliant Nextflow pipeline for comprehensive Oxford Nanopore Technologies (ONT) sequencing data analysis, serving as the computational backend for Nanometa Live.

**Core Capabilities:**
- Real-time analysis during active sequencing (POD5 or FASTQ monitoring)
- POD5 basecalling with Dorado (GPU-accelerated)
- Pre-demultiplexed barcode directory processing
- Taxonomic classification with Kraken2 (with incremental mode)
- Quality control (Chopper, FASTP, NanoPlot) and validation (BLAST)
- Platform-specific optimizations (MinION, PromethION profiles)

**Production Status:** v1.2.0 (stable), v1.4.1dev (current development)

**nf-core Compliance:** 96/100 - Full meta.yml and stub block coverage
**See:** [docs/releases/CURRENT_VERSION.md](docs/releases/CURRENT_VERSION.md) for version guidance

---

## AI Assistant Integration

### Specialized Agent Available

The `bioinformatics-pipeline-dev` agent provides expert assistance with:
- **Nextflow DSL2**: Advanced workflow patterns, channel operations, process definitions
- **nf-core standards**: Compliance requirements, best practices, conventions
- **Pipeline development**: Testing with nf-test, module creation, workflow optimization
- **ONT data processing**: Nanopore-specific patterns, real-time monitoring

**Use the agent proactively for:**
- Debugging complex Nextflow workflows
- Implementing nf-core compliant features
- Optimizing channel operations and resource allocation
- Creating and maintaining nf-test test suites
- Real-time monitoring pattern implementation

---

## Critical Files for Development

### Entry Points
- `main.nf` - Pipeline entry point (150 lines)
- `workflows/nanometanf.nf` - Main workflow orchestration (387 lines)

### Core Configuration
- `nextflow.config` - Main configuration (150+ parameters, 876 lines)
- `nextflow_schema.json` - Parameter validation schema
- `conf/base.config` - Base process resource configuration
- `conf/modules.config` - Module-specific configurations
- `conf/minion.config`, `conf/promethion.config`, `conf/promethion_8.config` - Platform profiles

### Critical Subworkflows (subworkflows/local/)
- **`realtime_monitoring/main.nf`** - Real-time FASTQ monitoring with watchPath (CRITICAL)
  - Implements 2-stage timeout with grace period
  - Adaptive batching, priority routing, barcode extraction
  - Lines 56-190: Functional reactive patterns with `.scan()` operator

- **`realtime_pod5_monitoring/main.nf`** - Real-time POD5 monitoring + basecalling

- **`dorado_basecalling/main.nf`** - POD5 basecalling workflow

- **`barcode_discovery/main.nf`** - Automated barcode directory discovery

- **`pod5_barcode_discovery/main.nf`** - Pre-demultiplexed POD5 barcode discovery (NEW)
  - Discovers barcode subdirectories containing POD5 files
  - Supports dual folder structures: flat POD5 or barcode subdirectories
  - Used by detectPod5Structure() function in workflows/nanometanf.nf

- **`qc_analysis/main.nf`** - Quality control workflow (multi-tool support)
  - Lines 196-254: Conditional NanoPlot execution for real-time optimization

- **`taxonomic_classification/main.nf`** - Kraken2 taxonomic profiling
  - Lines 42-63, 128-142: Memory-mapped database loading
  - Incremental classification support (experimental)

### Key Modules (modules/local/)
- `dorado_basecaller/` - Dorado basecalling module
- `dorado_demux/` - Dorado demultiplexing module
- `kraken2_incremental_classifier/`, `kraken2_output_merger/`, `kraken2_report_generator/` - Incremental Kraken2 (experimental)

### Testing Infrastructure
- `tests/` - nf-test test suite (94 test files)
- `tests/fixtures/` - Pre-created test data (avoids setup{} timing issues)
- `nf-test.config` - nf-test configuration
- **See:** [docs/development/TESTING.md](docs/development/TESTING.md) for comprehensive testing guide

---

## Development Prerequisites

### Required Tools
```bash
# Nextflow (>= 25.10.0)
nextflow -version

# nf-test (>= 0.9.0)
nf-test version

# Java environment for nf-test
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH
```

### Optional Tools
- **Dorado** (for POD5 basecalling development/testing)
- **Docker/Singularity** (for containerized testing)

---

## Key Development Patterns

### 1. Real-time Monitoring with watchPath()

**CRITICAL**: The `watchPath()` operator requires proper limiting to avoid infinite hangs.

**Pattern: Intelligent inactivity timeout (v1.3.3+)**

```groovy
// Apply timeout logic if realtime_timeout_minutes is set
if (params.realtime_timeout_minutes) {
    log.info "Real-time timeout: ${params.realtime_timeout_minutes} min inactivity"
    log.info "Grace period: ${params.realtime_processing_grace_period} min for processing"

    // Track last file detection time
    def last_file_time = System.currentTimeMillis()

    // Create heartbeat channel (checks timeout every minute)
    def ch_timeout_check = Channel.interval('1min').map { 'TIMEOUT_CHECK' }

    // Tag files and mix with timeout checks
    def ch_files_tagged = ch_all_files.map { file -> ['FILE', file] }
    def ch_checks_tagged = ch_timeout_check.map { check -> ['CHECK', check] }
    def ch_mixed = ch_files_tagged.mix(ch_checks_tagged)

    // Define immutable state object (functional reactive pattern)
    def initialState = [
        last_file_time: System.currentTimeMillis(),
        grace_period_start: null,
        in_grace_period: false,
        files_processed: 0,
        should_stop: false
    ]

    // Apply timeout logic using .scan() for immutable state transitions
    ch_input_files = ch_mixed
        .scan(initialState) { state, tuple ->
            def (type, item) = tuple

            if (type == 'FILE') {
                // File detected - reset timer
                return [
                    last_file_time: System.currentTimeMillis(),
                    grace_period_start: null,
                    in_grace_period: false,
                    files_processed: state.files_processed + 1,
                    should_stop: params.max_files && (state.files_processed + 1) >= params.max_files,
                    type: type,
                    item: item
                ]
            } else if (type == 'CHECK') {
                // Timeout check logic here
                // (see realtime_monitoring/main.nf for complete implementation)
            }
        }
        .until { state -> state.should_stop }
        .filter { state -> state.type == 'FILE' }
        .map { state -> state.item }
}
```

**Key concepts:**
- **Heartbeat channel**: `Channel.interval('1min')` creates periodic checks
- **Tagged channels**: Mix file events with timeout checks using tuples
- **Functional reactive**: `.scan()` operator for immutable state transitions
- **2-stage timeout**: Detection timeout → Grace period for processing completion

**Files:** `subworkflows/local/realtime_monitoring/main.nf`, `subworkflows/local/realtime_pod5_monitoring/main.nf`

### 2. Test Fixtures Pattern

**CRITICAL**: Pipeline validation runs BEFORE nf-test `setup{}` blocks execute. Always use pre-created fixtures:

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

### 3. nf-core Compliance

Run before committing:

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
# Setup Java environment
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH

# Quick validation (core + fast tests)
nf-test test --tag core --tag fast

# All core tests
nf-test test --tag core

# Full test suite
nf-test test

# Run specific test
nf-test test tests/nanoseq_test.nf.test --verbose

# Update snapshots
nf-test test --update-snapshot
```

**Tag System (4 tags):**
| Tag | Purpose |
|-----|---------|
| `core` | Must-pass tests |
| `extended` | Nice-to-pass tests |
| `fast` | Quick tests (< 1 min) |
| `slow` | Longer tests (> 1 min) |

Optional feature tags: `realtime`, `basecalling`, `qc`, `classification`

**See:** [docs/development/TESTING.md](docs/development/TESTING.md) for comprehensive guide

---

## Important Parameters

### Input Modes (Mutually Exclusive)
- `--input` - Samplesheet CSV (standard mode)
- `--barcode_input_dir` - Pre-demultiplexed barcode directories
- `--pod5_input_dir` + `--use_dorado` - POD5 basecalling mode

### Real-time Processing
- `--realtime_mode` - Enable real-time file monitoring
- `--nanopore_output_dir` - Directory to monitor
- `--file_pattern` - File matching pattern (default: `**/*.fastq{,.gz}`)
- `--max_files` - **CRITICAL FOR TESTS** - Limit files (prevents watchPath hangs)
- `--batch_size` - Files per batch (default: 10)

**Timeout Configuration (v1.3.3+):**
- `--realtime_timeout_minutes` - Stop after N minutes without new files
- `--realtime_processing_grace_period` - Wait for processing completion (default: 5 min)

**Advanced Batching:**
- `--adaptive_batching` - Enable dynamic batch sizing (default: true)
- `--min_batch_size`, `--max_batch_size` - Batch size constraints
- `--priority_samples` - High-priority sample list

### Dorado Basecalling
- `--use_dorado` - Enable Dorado basecalling
- `--pod5_input_dir` - POD5 files directory
- `--dorado_path` - Path to dorado executable (default: 'dorado' from PATH)
- `--dorado_model` - Basecalling model (e.g., `dna_r10.4.1_e4.3_400bps_hac`)
- `--dorado_device` - Device: `cpu`, `auto` (default: auto, detects GPU)

### Quality Control
- `--qc_tool` - QC tool: `chopper` (default, 7x faster), `fastp`, `filtlong`
- `--chopper_quality`, `--chopper_minlength`, `--chopper_maxlength` - Chopper parameters

### Platform Profiles (v1.3.3+)
- `-profile minion` - MinION/GridION optimization (1-4 samples, clinical)
- `-profile promethion_8` - Balanced (5-12 samples, environmental)
- `-profile promethion` - High throughput (12-24+ samples, surveillance)

**Complete parameter reference:** [docs/user/usage.md](docs/user/usage.md)

---

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

# Run with debug
nf-test test <test_file> --verbose --debug
```

---

## Architecture Highlights

### Input Type Detection Logic

Auto-detects in `workflows/nanometanf.nf`:

1. **Real-time POD5**: `realtime_mode && use_dorado && pod5_input_dir`
2. **Real-time FASTQ**: `realtime_mode && !use_dorado && nanopore_output_dir`
3. **Static POD5**: `!realtime_mode && use_dorado && pod5_input_dir`
4. **Barcode discovery**: `!realtime_mode && barcode_input_dir`
5. **Standard samplesheet**: `!realtime_mode && input`

### POD5 Folder Structure Detection

The pipeline auto-detects POD5 folder structures using `detectPod5Structure()`:

```groovy
// Detect if POD5 directory has barcode subdirectories or flat structure
def detectPod5Structure(pod5_dir) {
    def dir = file(pod5_dir)
    def barcode_dirs = dir.listFiles().findAll {
        it.isDirectory() && it.name.startsWith('barcode')
    }
    def has_barcode_subdirs = barcode_dirs.size() > 0
    def has_pod5_in_subdirs = barcode_dirs.any { bc_dir ->
        bc_dir.listFiles().any { it.name.endsWith('.pod5') }
    }
    return has_barcode_subdirs && has_pod5_in_subdirs ? 'barcode_subdirs' : 'flat'
}
```

**Supported structures:**
- **Flat**: POD5 files directly in input directory (singleplex)
- **Barcode subdirs**: `barcode01/`, `barcode02/`, etc. with POD5 files (pre-demultiplexed)

### Channel Flow

```
Input Detection → Basecalling → QC → Classification → Validation → Reports
     ↓              ↓           ↓       ↓              ↓           ↓
  POD5/FASTQ    Dorado     CHOPPER  Kraken2        BLAST      MultiQC
  Barcodes                 NanoPlot  Taxpasta                   JSON
```

---

## Git Workflow

```bash
# Never skip hooks or force push to main
git add <files>
git commit -m "descriptive message"  # Hooks run automatically
git push origin <branch>

# Create PR
gh pr create --title "Title" --body "Description"
```

**Commit Guidelines:**
- Use conventional commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`
- Reference issues: `fix: resolve timeout issue (#123)`
- For commits, see release process: [docs/development/RELEASE_PROCESS.md](docs/development/RELEASE_PROCESS.md)

---

## Additional Resources

### Documentation
- **[User Guide](docs/user/usage.md)** - Complete usage instructions
- **[Development Guide](docs/development/README.md)** - Developer documentation hub
- **[Testing Guide](docs/development/TESTING.md)** - Comprehensive nf-test documentation
- **[Current Version Status](docs/releases/CURRENT_VERSION.md)** - Version guidance
- **[Migration Guide](docs/releases/MIGRATION_GUIDE.md)** - Upgrade instructions
- **[Release Process](docs/development/RELEASE_PROCESS.md)** - How to create releases

### External Resources
- [nf-core guidelines](https://nf-co.re/docs/contributing/guidelines)
- [Nextflow documentation](https://www.nextflow.io/docs/latest/)
- [nf-test documentation](https://www.nf-test.com/)
- [Dorado documentation](https://github.com/nanoporetech/dorado)

---

**Last Updated:** 2025-11-29
**Version:** 1.4.1dev
**Maintainer:** foi-bioinformatics team (@andreassjodin)

**For AI Assistants:** This file contains the essential patterns and critical information needed for AI-assisted development. For complete details, refer to the linked documentation files.
