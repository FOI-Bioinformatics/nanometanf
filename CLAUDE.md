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

## Version 1.1.0 Changes

**Release Focus:** Performance optimization and tool modernization

### Major Changes

1. **Chopper as Default QC Tool**
   - **Performance:** 7x faster than NanoFilt for nanopore data
   - **Implementation:** Rust-based nanopore-native filtering
   - **Configuration:** `--qc_tool chopper` (default in v1.1.0)
   - **Parameters:**
     - `--chopper_quality 10` - Minimum quality score
     - `--chopper_minlength 1000` - Minimum read length
     - `--chopper_maxlength null` - Maximum read length (no limit)
     - `--chopper_headcrop 0` - Trim bases from read start
   - **Files:** `modules/nf-core/chopper/`, `subworkflows/local/qc_analysis.nf`

2. **Multi-Tool QC Support**
   - **Tool-agnostic interface:** Easy switching between QC tools
   - **Supported tools:** chopper (default), fastp, filtlong
   - **Future-ready:** Architecture prepared for nanoq integration
   - **Switch:** `--qc_tool {chopper|fastp|filtlong}`

3. **Dorado 1.1.1 Compatibility**
   - **Model syntax:** Simplified format (removed @version suffixes)
   - **Old:** `dna_r10.4.1_e4.3_400bps_hac@v5.0.0`
   - **New:** `dna_r10.4.1_e4.3_400bps_hac`
   - **Files updated:** nextflow.config, 5 test files (17 model references)

4. **Dynamic Resource Allocation Fix**
   - **Bug:** Process name mismatch (RESOURCE_OPTIMIZATION_PROFILES vs LOAD_OPTIMIZATION_PROFILES)
   - **Fixed:** `subworkflows/local/dynamic_resource_allocation.nf:28, 54-58`

5. **Test Suite Enhancements**
   - **Tool-agnostic assertions:** Support any QC tool (chopper/fastp/filtlong)
   - **Pattern:** `it.name.contains('CHOPPER') || it.name.contains('FASTP') || it.name.contains('FILTLONG')`
   - **Files updated:** 20+ test files
   - **Status:** 2/3 core tests passing (Dorado test requires binary in PATH)

### Known Issues

- **Dorado Docker tests:** Docker profile tests fail because container lacks dorado binary
  - **Workaround:** Use local profile or ensure dorado in PATH
  - **Status:** Not blocking - functionality verified when binary available
  - **Future:** Add dorado to Docker image or use dorado_path parameter

### Migration Guide (v1.0.0 → v1.1.0)

**Breaking Changes:** None - fully backward compatible

**Recommended Updates:**
1. **Performance:** Switch to chopper for 7x faster QC (automatic with defaults)
2. **Dorado models:** Update to simplified syntax (no @version suffix)
3. **Testing:** Use tool-agnostic test assertions for QC processes

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
- `realtime_monitoring.nf` - **CRITICAL** - Real-time FASTQ file monitoring (watchPath)
- `realtime_pod5_monitoring.nf` - **CRITICAL** - Real-time POD5 monitoring + basecalling
- `enhanced_realtime_monitoring.nf` - Advanced real-time with priority/batching
- `dorado_basecalling.nf` - POD5 basecalling workflow
- `barcode_discovery.nf` - Automated barcode directory discovery
- `qc_analysis.nf` - Quality control workflow
- `taxonomic_classification.nf` - Kraken2 taxonomic profiling
- `validation.nf` - BLAST validation
- `dynamic_resource_allocation.nf` - **EXPERIMENTAL** - Intelligent resource optimization

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

**CRITICAL**: Real-time monitoring is a core feature. The `watchPath()` operator requires proper limiting to avoid infinite hangs:

```groovy
// CORRECT pattern (used in all realtime_*.nf subworkflows)
def ch_watched = Channel.watchPath("${dir}/${pattern}", 'create,modify')
ch_files = params.max_files
    ? ch_watched.take(params.max_files.toInteger())
    : ch_watched

// WRONG - will hang forever in tests
Channel.watchPath(...).until { file -> /* condition */ }
```

**Files using watchPath():**
- `subworkflows/local/realtime_monitoring.nf:25-29`
- `subworkflows/local/realtime_pod5_monitoring.nf:27-32`
- `subworkflows/local/enhanced_realtime_monitoring.nf:56-63`

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
- `--realtime_mode` - Enable real-time file monitoring (default: false)
- `--nanopore_output_dir` - Directory to monitor for new files
- `--file_pattern` - File matching pattern (default: `**/*.fastq{,.gz}`)
- `--max_files` - **CRITICAL FOR TESTS** - Limit files processed (prevents watchPath hangs)
- `--batch_size` - Files per batch (default: 10)

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

## Known Issues and Constraints

1. **Real-time tests require `max_files`** - Without it, watchPath() will wait indefinitely
2. **Setup blocks don't work for pipeline tests** - Use fixtures instead
3. **Dynamic resources experimental** - Disabled by default for v1.0 stability
4. **Input types mutually exclusive** - Cannot mix POD5 and FASTQ in same run

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

**Last Updated**: 2025-10-04
**Pipeline Version**: 1.0.0dev
**Nextflow Version**: >=24.10.5
