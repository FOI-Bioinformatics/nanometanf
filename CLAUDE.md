# CLAUDE.md

Developer guidance for **foi-bioinformatics/nanometanf**, a nf-core compliant Nextflow pipeline providing real-time nanopore sequencing analysis with taxonomic classification.

## Architecture

**Core Components:**
- `main.nf` - Pipeline entry point
- `workflows/nanometanf.nf` - Main workflow orchestration
- `nextflow.config` - Configuration and parameters
- `nextflow_schema.json` - Parameter validation (52 parameters)

**Subworkflows (5):**
- `realtime_monitoring.nf` - watchPath-based file monitoring
- `dorado_basecalling.nf` - POD5 basecalling and demultiplexing
- `qc_analysis.nf` - FASTP and NanoPlot quality control
- `taxonomic_classification.nf` - Kraken2 classification
- `validation.nf` - BLAST validation

**Modules (10):**
- nf-core: fastp, fastqc, kraken2/kraken2, blast/blastn, blast/makeblastdb, multiqc, nanoplot, untar
- local: dorado_basecaller, dorado_demux

## Prerequisites

```bash
# Required Java environment
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH
```

## Execution Modes

**Standard Processing:**
```bash
nextflow run . --input samplesheet.csv --outdir results
```

**Dorado Basecalling:**
```bash
nextflow run . --use_dorado true --pod5_input_dir /path/to/pod5 --outdir results
```

**Real-time FASTQ Monitoring:**
```bash
nextflow run . --realtime_mode true --nanopore_output_dir /path/to/watch --outdir results
```

**Real-time POD5 Processing with Dorado:**
```bash
nextflow run . --realtime_mode true --use_dorado true --nanopore_output_dir /path/to/pod5 --file_pattern "**/*.pod5" --outdir results
```

**Available profiles:** docker, singularity, conda, test, local_test

## Testing

```bash
# nf-test suite (7 tests)
nf-test test --profile docker

# Manual testing
nextflow run . -c conf/local_test.config --input test_samplesheet.csv --outdir test_results

# nf-core compliance
nf-core lint
nf-core modules list local
nf-core schema lint
```

## Key Parameters

**Input/Output:**
- `--input` - Samplesheet CSV with nanopore format: `sample,fastq,barcode`
- `--outdir` - Output directory (required)

**Samplesheet Format (Nanopore-specific):**
```csv
sample,fastq,barcode
SAMPLE_1,sample1.fastq.gz,
SAMPLE_2,sample2.fastq.gz,BC01
```
- `barcode` column optional (empty for non-barcoded samples)
- Empty samplesheets only work with `--realtime_mode true`

**Dorado Integration (default: disabled):**
- `--use_dorado true` - Enable basecalling from POD5 files
- `--dorado_path` - Binary path (/Users/andreassjodin/Downloads/dorado-1.1.1-osx-arm64/bin/dorado)
- `--pod5_input_dir` - POD5 files directory
- `--dorado_model` - Basecalling model (default: dna_r10.4.1_e4.3_400bps_hac@v5.0.0)
- `--demultiplex false` - Enable barcode demultiplexing
- `--barcode_kit` - Barcode kit (e.g., SQK-PBK004)
- `--min_qscore 9` - Quality threshold

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

## Configuration Files
- `conf/local_test.config` - Local development (2GB memory, 1 CPU)
- `conf/test.config` - nf-core test profile
- `conf/test_dorado.config` - Dorado testing configuration

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