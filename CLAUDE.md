# CLAUDE.md

Developer guidance for **foi-bioinformatics/nanometanf**, a nf-core compliant Nextflow pipeline for comprehensive real-time nanopore sequencing data analysis with integrated basecalling, quality control, taxonomic classification, and validation workflows.

## Scientific Context

This pipeline addresses critical bioinformatics challenges in Oxford Nanopore Technologies (ONT) sequencing workflows:
- **Real-time analysis** during active sequencing runs for pathogen detection
- **Multiple input modalities** supporting laboratory preprocessing workflows
- **Scalable taxonomic profiling** with Kraken2 for metagenomics applications
- **Quality-controlled basecalling** with modern Dorado algorithms
- **Reproducible containerized execution** following nf-core best practices

## Architecture

**Core Components:**
- `main.nf` - Pipeline entry point with workflow routing logic
- `workflows/nanometanf.nf` - Main workflow orchestration with intelligent input type detection
- `nextflow.config` - Comprehensive parameter configuration (54+ parameters)
- `nextflow_schema.json` - JSON Schema parameter validation and documentation

**Subworkflows (9):**
- `realtime_monitoring.nf` - watchPath-based FASTQ file monitoring for live sequencing
- `realtime_pod5_monitoring.nf` - watchPath-based POD5 file monitoring with basecalling
- `dorado_basecalling.nf` - High-accuracy POD5 basecalling with Dorado
- `barcode_discovery.nf` - **NEW** - Automated discovery of pre-demultiplexed barcode directories
- `demultiplexing.nf` - **ENHANCED** - Complete Dorado-based demultiplexing with proper output handling
- `qc_analysis.nf` - Comprehensive quality control with FASTP and NanoPlot
- `taxonomic_classification.nf` - Kraken2-based taxonomic profiling
- `validation.nf` - BLAST-based validation for targeted species confirmation
- `dynamic_resource_allocation.nf` - **NEW** - Intelligent resource prediction and optimization system

**Modules (16):**
- nf-core: fastp, fastqc, kraken2/kraken2, blast/blastn, blast/makeblastdb, multiqc, nanoplot, untar
- local: dorado_basecaller, dorado_demux **NEW** - Complete demultiplexing implementation
- local resource modules: analyze_input_characteristics, monitor_system_resources, predict_resource_requirements, optimize_resource_allocation, resource_optimization_profiles, resource_feedback_learning

## Prerequisites

```bash
# Required Java environment
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH
```

## Execution Modes

**1. Standard FASTQ Processing (Laboratory preprocessed samples):**
```bash
nextflow run . --input samplesheet.csv --outdir results
```

**2. Pre-demultiplexed Barcode Directories (NEW - Common laboratory workflow):**
```bash
nextflow run . --barcode_input_dir /path/to/barcode/folders --outdir results
# Automatically discovers barcode01/, barcode02/, unclassified/ directories
```

**3. Singleplex POD5 Basecalling:**
```bash
nextflow run . --use_dorado --pod5_input_dir /path/to/pod5 --dorado_model dna_r10.4.1_e4.3_400bps_hac@v5.0.0 --outdir results
```

**4. Multiplex POD5 with Dorado Demultiplexing (FIXED):**
```bash
nextflow run . --use_dorado --pod5_input_dir /path/to/pod5 --barcode_kit SQK-NBD114-24 --trim_barcodes --outdir results
```

**5. Real-time FASTQ Monitoring (Live sequencing):**
```bash
nextflow run . --realtime_mode --nanopore_output_dir /path/to/watch --file_pattern "**/*.fastq{,.gz}" --outdir results
```

**6. Real-time POD5 Processing with Basecalling (Live sequencing + basecalling):**
```bash
nextflow run . --realtime_mode --use_dorado --nanopore_output_dir /path/to/pod5 --file_pattern "**/*.pod5" --outdir results
```

**7. Dynamic Resource Allocation (Intelligent resource optimization - NEW):**
```bash
# Auto-select optimal profile based on system characteristics
nextflow run . --input samplesheet.csv --optimization_profile auto --outdir results

# Use specific optimization profile for high-throughput processing
nextflow run . --input samplesheet.csv --optimization_profile high_throughput --outdir results

# GPU-optimized processing for Dorado basecalling
nextflow run . --use_dorado --pod5_input_dir /path/to/pod5 --optimization_profile gpu_optimized --outdir results
```

**Available profiles:** docker, singularity, conda, test, local_test

## Comprehensive Testing Framework

```bash
# Complete nf-test suite (12+ tests including new functionality)
nf-test test --verbose

# New functionality tests
nf-test test tests/barcode_discovery.nf.test            # Pre-demux barcode directory discovery
nf-test test tests/dorado_multiplex.nf.test             # POD5 multiplex demultiplexing 
nf-test test modules/local/dorado_demux/tests/main.nf.test     # Dorado demux module unit test
nf-test test subworkflows/local/barcode_discovery/tests/main.nf.test  # Barcode discovery unit test

# Existing comprehensive tests
nf-test test tests/nanoseq_test.nf.test                 # Complete workflow with nf-core data
nf-test test tests/dorado_pod5.nf.test                  # Singleplex POD5 basecalling
nf-test test tests/realtime_processing.nf.test         # Real-time FASTQ monitoring
nf-test test tests/parameter_validation.nf.test        # Schema validation

# Manual testing with local resources
nextflow run . -c conf/local_test.config --input test_samplesheet.csv --outdir test_results

# nf-core compliance validation
nf-core lint                    # Pipeline compliance (passing)
nf-core modules list local      # Module tracking
nf-core schema lint             # Parameter schema validation
```

## Key Parameters

**Input/Output:**
- `--input` - Samplesheet CSV with nanopore format: `sample,fastq,barcode`
- `--barcode_input_dir` - **NEW** - Directory containing pre-demultiplexed barcode folders (alternative to samplesheet)
- `--outdir` - Output directory (required)

**Input Type Selection (mutually exclusive):**
```bash
# Option 1: Samplesheet-based input (standard)
--input samplesheet.csv

# Option 2: Pre-demultiplexed barcode directories (NEW)
--barcode_input_dir /path/to/barcode_folders/

# Option 3: POD5 directory input
--pod5_input_dir /path/to/pod5/ --use_dorado

# Option 4: Real-time monitoring
--realtime_mode --nanopore_output_dir /path/to/monitor/
```

**Samplesheet Format (Nanopore-specific):**
```csv
sample,fastq,barcode
SAMPLE_1,sample1.fastq.gz,
SAMPLE_2,sample2.fastq.gz,BC01
```
- `barcode` column optional (empty for non-barcoded samples)
- Empty samplesheets only work with `--realtime_mode true`
- **Do not mix POD5 and FASTQ in same run** - choose one workflow type

**Dorado Integration (default: disabled):**
- `--use_dorado true` - Enable basecalling from POD5 files
- `--dorado_path` - Binary path (/Users/andreassjodin/Downloads/dorado-1.1.1-osx-arm64/bin/dorado)
- `--pod5_input_dir` - POD5 files directory
- `--dorado_model` - Basecalling model (default: dna_r10.4.1_e4.3_400bps_hac@v5.0.0)
- `--barcode_kit` - Barcode kit for demultiplexing (e.g., SQK-NBD114-24) **FIXED**
- `--trim_barcodes true` - Remove barcode sequences from demultiplexed reads
- `--min_qscore 9` - Minimum quality threshold for basecalling

**Real-time Processing (default: disabled):**
- `--realtime_mode false` - Enable file monitoring (bypasses samplesheet file paths)
- `--nanopore_output_dir` - Directory to monitor
- `--file_pattern` - File matching pattern (default: `**/*.fastq{,.gz}` for FASTQ, `**/*.pod5` for POD5)
- `--batch_size 10` - Files per batch
- `--batch_interval 5min` - Processing interval
- **Note**: Empty samplesheets only work with real-time mode enabled

**Analysis Options:**
- `--kraken2_db` - Taxonomic classification database
- `--blast_validation false` - Enable BLAST validation
- `--skip_fastp false` - Disable quality filtering
- `--skip_nanoplot false` - Disable nanopore QC

**Dynamic Resource Allocation (NEW - Intelligent Performance Optimization):**
- `--enable_dynamic_resources true` - Enable intelligent resource allocation system
- `--optimization_profile auto` - Resource optimization profile selection:
  - `auto` - Automatic profile selection based on system characteristics
  - `high_throughput` - Maximum processing speed with high resource usage
  - `balanced` - Balanced resource usage for standard processing
  - `resource_conservative` - Minimal resource usage for constrained environments
  - `gpu_optimized` - Optimized for GPU-accelerated workloads (Dorado basecalling)
  - `realtime_optimized` - Low-latency processing for real-time analysis
  - `development_testing` - Fast processing for development workflows
- `--resource_safety_factor 0.8` - Safety factor for resource allocation (0.0-1.0)
- `--enable_gpu_optimization true` - Enable GPU-specific optimizations
- `--resource_monitoring_interval 30` - System monitoring interval in seconds
- `--enable_performance_logging true` - Enable detailed performance logging

## Configuration Files
- `conf/local_test.config` - Local development (2GB memory, 1 CPU)
- `conf/test.config` - nf-core test profile
- `conf/test_dorado.config` - Dorado testing configuration

## Documentation
- `docs/qc_guide.md` - Quality control analysis guide
- `docs/dynamic_resource_allocation.md` - **NEW** - Comprehensive guide to intelligent resource allocation system

## Testing Infrastructure

**nf-test Implementation:**
- `tests/nanoseq_test.nf.test` - Complete pipeline tests with nf-core datasets
- `tests/dorado_pod5.nf.test` - Dorado basecalling tests with POD5 data
- `tests/parameter_validation.nf.test` - Fast parameter validation
- Local nf-core nanoseq test data in `assets/test_data/`

**Test Data Sources:**
- nf-core test-datasets (nanoseq branch)
- Local FASTQ files: MCF7_directcDNA_replicate3.fastq.gz, K562_directRNA_replicate6.fastq.gz
- Local POD5 files: batch_0.pod5 (664KB from nf-core nanoseq test data)
- Absolute paths in samplesheets for proper validation

**Test Execution:**
```bash
export JAVA_HOME=$CONDA_PREFIX/lib/jvm && export PATH=$JAVA_HOME/bin:$PATH

# Test FASTQ processing with nf-core data
nf-test test tests/nanoseq_test.nf.test --verbose

# Test Dorado basecalling with POD5 data  
nf-test test tests/dorado_pod5.nf.test --verbose

# Quick parameter validation
nf-test test tests/parameter_validation.nf.test --verbose
```

## nf-core Tools Integration

**Essential Developer Commands:**
- `nf-core lint` - Pipeline compliance checking against nf-core guidelines
- `nf-core modules` - Nextflow DSL2 module management (8 modules installed)
- `nf-core subworkflows` - Nextflow DSL2 subworkflow management  
- `nf-core schema` - Parameter validation and schema management (52 parameters)
- `nf-core sync` - Sync TEMPLATE branch with nf-core template updates
- `nf-core bump-version` - Update pipeline version numbers

**Pipeline Management:**
- `nf-core download` - Download pipelines and container images
- `nf-core create-params-file` - Generate parameter files for runs
- `nf-core launch` - Interactive pipeline launcher with GUI

**Key Features:**
- Complete modules.json tracking for reproducible module versions
- Automated template synchronization via TEMPLATE branch
- Schema-driven parameter validation with 52 defined parameters
- Compliance checking against nf-core community standards

**Update Workflow:**
```bash
# Update nf-core tools to latest version
conda update nf-core

# Sync pipeline template changes
nf-core sync

# Update individual modules
nf-core modules update
```