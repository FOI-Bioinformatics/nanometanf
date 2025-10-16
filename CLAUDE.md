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

## Current Release: v1.2.0 (Production Ready)

**Release Date:** 2025-10-16
**Status:** ✅ Production Release
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
1. **Real-time tests require `max_files`** - Without it, watchPath() will wait indefinitely
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

**Last Updated**: 2025-10-16
**Current Release**: v1.2.0 (Production Ready)
**Development Version**: 1.2.1dev (preparing for bug fixes)
**Nextflow Version**: >=24.10.5
**nf-core Compliance**: 100% (707/707 tests passing)
