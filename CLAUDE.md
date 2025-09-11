# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is **foi-bioinformatics/nanometanf**, a Nextflow bioinformatics pipeline that serves as the backend for Nanometa-Live. It's built using the nf-core framework version 3.3.2 and provides real-time processing of nanopore sequencing data with taxonomic classification.

## Architecture

The pipeline follows the standard nf-core DSL2 architecture:

- **Main entry point**: `workflows/main.nf` - Entry point that imports and orchestrates workflows
- **Core workflow**: `workflows/nanometanf.nf` - Main analysis workflow with modular subworkflows for QC, taxonomic classification, and validation
- **Configuration**: `workflows/nextflow.config` - Main configuration with profiles and real-time processing parameters
- **Subworkflows**: `subworkflows/local/` - Custom subworkflows (QC analysis, taxonomic classification, validation, real-time monitoring, demultiplexing)
- **Modules**: `modules/nf-core/` - Individual process definitions (fastp, kraken2, blast, nanoplot, multiqc)

## Common Commands

### Running the Pipeline

**Standard Mode (batch processing):**
```bash
# Basic run with test profile
nextflow run foi-bioinformatics/nanometanf -profile test,docker --outdir results

# Full run with custom input
nextflow run foi-bioinformatics/nanometanf -profile docker --input samplesheet.csv --outdir results --kraken2_db /path/to/kraken2_db
```

**Real-time Mode (continuous monitoring):**
```bash
# Real-time processing with file monitoring
nextflow run foi-bioinformatics/nanometanf -profile docker \
    --realtime_mode true \
    --nanopore_output_dir /path/to/nanopore/output \
    --kraken2_db /path/to/kraken2_db \
    --batch_size 10 \
    --batch_interval 5min \
    --outdir results

# With demultiplexing and BLAST validation
nextflow run foi-bioinformatics/nanometanf -profile docker \
    --realtime_mode true \
    --nanopore_output_dir /path/to/nanopore/output \
    --use_dorado true \
    --dorado_path /path/to/dorado \
    --barcode_kit SQK-PBK004 \
    --kraken2_db /path/to/kraken2_db \
    --blast_validation true \
    --blast_db /path/to/blast_db \
    --outdir results
```

**Available profiles:** docker, singularity, conda, mamba, podman, charliecloud, apptainer, test, test_realtime

### Testing
```bash
# Run nf-test (primary testing framework)
nf-test test

# Run with specific profile
nf-test test --profile docker
```

### Linting and Quality Control
```bash
# Run pre-commit hooks (includes Prettier formatting)
pre-commit run --all-files

# Nextflow syntax validation
nextflow -log .nextflow.log run . -entry 'FOIBIOINFORMATICS_NANOMETANF' --help
```

## Development

### Configuration Profiles
The pipeline supports multiple execution environments:
- `docker` - Docker containers (default recommended)
- `singularity`/`apptainer` - Singularity/Apptainer containers
- `conda`/`mamba` - Conda package management
- `test` - Minimal test dataset
- `debug` - Debug mode with process dumps

### Pipeline Parameters

**Core Parameters:**
- `--input` - Input samplesheet (required for batch mode)
- `--outdir` - Output directory (required)

**Real-time Processing:**
- `--realtime_mode` - Enable real-time file monitoring (default: false)
- `--nanopore_output_dir` - Directory to watch for new files
- `--file_pattern` - File pattern to match (default: **/*.fastq{,.gz})
- `--batch_size` - Files per batch (default: 10)
- `--batch_interval` - Time interval for batching (default: 5min)
- `--max_files` - Maximum files to process (optional)

**Demultiplexing:**
- `--use_dorado` - Use dorado for demultiplexing (default: true)
- `--dorado_path` - Path to dorado installation
- `--barcode_kit` - Barcode kit used (e.g., SQK-PBK004)

**Taxonomic Classification:**
- `--kraken2_db` - Path to Kraken2 database (required)
- `--save_output_fastqs` - Save classified/unclassified reads (default: false)
- `--save_reads_assignment` - Save read assignments (default: false)

**BLAST Validation:**
- `--blast_validation` - Enable BLAST validation (default: false)
- `--blast_db` - Path to BLAST database
- `--validation_taxa` - List of taxa to validate

**Quality Control:**
- `--skip_fastp` - Skip fastp filtering (default: false)
- `--skip_nanoplot` - Skip NanoPlot QC (default: false)

### Module Structure
- Uses nf-core modules from `workflows/modules/nf-core/`
- Local utilities in `workflows/subworkflows/local/utils_nfcore_nanometanf_pipeline/`
- Standard nf-core utilities in `workflows/subworkflows/nf-core/`

### Testing Configuration
- **Standard testing**: `workflows/conf/test.config` - Batch mode with test data
- **Real-time testing**: `workflows/conf/test_realtime.config` - Tests file monitoring capabilities
- GitHub Actions runs tests with multiple Nextflow versions (24.10.5, latest) and profiles
- Test execution uses nf-test framework with sharded execution for parallel testing

### Output Structure
```
results/
├── qc/
│   ├── fastp/           # Read filtering and QC reports
│   └── nanoplot/        # Nanopore-specific QC visualizations
├── classification/
│   └── kraken2/         # Taxonomic classification results
├── validation/
│   └── blast/           # BLAST validation results (optional)
├── reports/
│   └── multiqc/         # Comprehensive QC report
└── pipeline_info/       # Pipeline execution information
```

## Key Files
- `.nf-core.yml` - nf-core configuration and template settings
- `.pre-commit-config.yaml` - Code formatting and linting rules using Prettier
- `workflows/nextflow_schema.json` - Parameter validation schema
- `workflows/conf/` - Environment-specific configurations