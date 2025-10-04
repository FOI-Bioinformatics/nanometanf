# nanometanf Usage Guide

Comprehensive usage instructions for all execution modes and advanced configurations.

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Input Preparation](#input-preparation)
- [Execution Modes](#execution-modes)
- [Parameter Reference](#parameter-reference)
- [Advanced Configuration](#advanced-configuration)
- [Troubleshooting](#troubleshooting)

## Installation

### Prerequisites

- Nextflow ≥24.10.5
- Java ≥11
- Docker, Singularity, or Conda

### Install Nextflow

```bash
# Method 1: Quick install
curl -s https://get.nextflow.io | bash
sudo mv nextflow /usr/local/bin/

# Method 2: Conda
conda install -c bioconda nextflow

# Verify installation
nextflow -version
```

### Install Docker (optional but recommended)

```bash
# macOS: Download from docker.com
# Linux Ubuntu/Debian:
sudo apt-get install docker.io
sudo usermod -aG docker $USER  # Add user to docker group
```

## Quick Start

### Test the Pipeline

```bash
# Basic test (uses test profile with minimal data)
nextflow run foi-bioinformatics/nanometanf \
  -profile test,docker \
  --outdir test_results

# Full test (comprehensive validation)
nextflow run foi-bioinformatics/nanometanf \
  -profile test_full,docker \
  --outdir test_full_results
```

### Run with Your Data

```bash
# Standard FASTQ processing
nextflow run foi-bioinformatics/nanometanf \
  --input samplesheet.csv \
  --outdir results \
  -profile docker
```

## Input Preparation

### Samplesheet Format

The samplesheet is a CSV file with the following format:

```csv
sample,fastq,barcode
SAMPLE_1,/path/to/sample1.fastq.gz,
SAMPLE_2,/path/to/sample2.fastq.gz,BC01
SAMPLE_3,/path/to/sample3.fastq.gz,BC02
```

**Columns:**
- `sample` (required): Unique sample identifier
- `fastq` (required): Absolute or relative path to FASTQ file
- `barcode` (optional): Barcode identifier (leave empty for non-barcoded samples)

**Example - Non-barcoded samples:**

```csv
sample,fastq,barcode
control_1,data/control1.fastq.gz,
treatment_1,data/treatment1.fastq.gz,
treatment_2,data/treatment2.fastq.gz,
```

**Example - Barcoded samples:**

```csv
sample,fastq,barcode
patient_A,data/multiplexed.fastq.gz,barcode01
patient_B,data/multiplexed.fastq.gz,barcode02
patient_C,data/multiplexed.fastq.gz,barcode03
```

### Pre-demultiplexed Barcode Directories

If your laboratory preprocessing creates barcode folders:

```
barcodes/
├── barcode01/
│   ├── reads.fastq.gz
│   └── other.fastq.gz
├── barcode02/
│   └── reads.fastq.gz
├── unclassified/
│   └── unclass.fastq.gz
```

Use `--barcode_input_dir` instead of samplesheet:

```bash
nextflow run foi-bioinformatics/nanometanf \
  --barcode_input_dir barcodes/ \
  --outdir results \
  -profile docker
```

## Execution Modes

### Mode 1: Standard FASTQ Processing

**Use case**: Batch analysis of preprocessed FASTQ files

```bash
nextflow run foi-bioinformatics/nanometanf \
  --input samplesheet.csv \
  --outdir results \
  --kraken2_db /databases/k2_standard \
  -profile docker
```

**Features:**
- Quality filtering with FASTP
- Nanopore-specific QC with NanoPlot
- Taxonomic classification with Kraken2
- Optional BLAST validation
- MultiQC comprehensive report

**When to use:**
- Laboratory has already performed basecalling
- FASTQ files are ready for analysis
- Standard batch processing workflow

### Mode 2: Pre-demultiplexed Barcode Directories

**Use case**: Laboratory-prepared barcode folders

```bash
nextflow run foi-bioinformatics/nanometanf \
  --barcode_input_dir /data/barcodes \
  --outdir results \
  --kraken2_db /databases/k2_standard \
  -profile docker
```

**Features:**
- Automatic barcode directory discovery
- Processes barcode01/, barcode02/, unclassified/
- Sample names derived from barcode IDs
- Same analysis as Mode 1

**When to use:**
- MinKNOW or Guppy created barcode folders
- Laboratory preprocessing separated barcodes
- Want automatic sample detection

### Mode 3: Singleplex POD5 Basecalling

**Use case**: Single-sample POD5 basecalling

```bash
nextflow run foi-bioinformatics/nanometanf \
  --use_dorado \
  --pod5_input_dir /data/pod5 \
  --dorado_model dna_r10.4.1_e4.3_400bps_hac@v5.0.0 \
  --min_qscore 9 \
  --outdir results \
  -profile docker
```

**Dorado models:**
- `dna_r10.4.1_e4.3_400bps_hac@v5.0.0` - High accuracy (recommended)
- `dna_r10.4.1_e4.3_400bps_sup@v5.0.0` - Super accurate (slower)
- `dna_r10.4.1_e4.3_400bps_fast@v4.1.0` - Fast (lower accuracy)
- `dna_r9.4.1_e8_hac@v3.3` - R9.4.1 flowcell

**When to use:**
- Starting from raw POD5 files
- Single sample without barcoding
- Want to control basecalling parameters

### Mode 4: Multiplex POD5 with Demultiplexing

**Use case**: Barcoded samples requiring Dorado demultiplexing

```bash
nextflow run foi-bioinformatics/nanometanf \
  --use_dorado \
  --pod5_input_dir /data/pod5 \
  --barcode_kit SQK-NBD114-24 \
  --trim_barcodes \
  --dorado_model dna_r10.4.1_e4.3_400bps_hac@v5.0.0 \
  --outdir results \
  -profile docker
```

**Barcode kits:**
- `SQK-NBD114-24` - Native Barcoding Kit 24 (V14)
- `SQK-RBK114-24` - Rapid Barcoding Kit 24 (V14)
- `SQK-NBD114-96` - Native Barcoding Kit 96 (V14)
- `SQK-RPB004` - Rapid Barcoding Kit 1-12 (R9)
- `SQK-RAB204` - Rapid Barcoding Kit 1-24 (R10)

**When to use:**
- Multiplexed sequencing with barcodes
- Want Dorado to perform demultiplexing
- Starting from POD5 files

### Mode 5: Real-time FASTQ Monitoring

**Use case**: Live analysis during sequencing

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --nanopore_output_dir /sequencing/run_001 \
  --file_pattern "**/*.fastq{,.gz}" \
  --batch_size 10 \
  --batch_interval 5min \
  --kraken2_db /databases/k2_standard \
  --outdir results \
  -profile docker
```

**Real-time parameters:**
- `--batch_size`: Number of files per batch (default: 10)
- `--batch_interval`: Time between batches (default: 5min)
- `--max_files`: Maximum files to process (optional, for testing)
- `--adaptive_batching`: Enable dynamic batch sizing

**When to use:**
- Active sequencing in progress
- Need results before run completes
- Pathogen detection or quality monitoring

### Mode 6: Real-time POD5 Processing

**Use case**: Live basecalling + analysis

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --use_dorado \
  --nanopore_output_dir /sequencing/pod5_output \
  --file_pattern "**/*.pod5" \
  --batch_size 5 \
  --batch_interval 10min \
  --dorado_model dna_r10.4.1_e4.3_400bps_fast@v4.1.0 \
  --outdir results \
  -profile docker
```

**Recommendations:**
- Use `fast` model for real-time (faster basecalling)
- Smaller batch_size for POD5 (5-10 files)
- Longer batch_interval for POD5 (10-15min)
- GPU acceleration highly recommended

**When to use:**
- Active sequencing producing POD5 files
- Want real-time basecalling + analysis
- Need immediate pathogen detection

### Mode 7: Dynamic Resource Optimization

**Use case**: Intelligent resource allocation

```bash
nextflow run foi-bioinformatics/nanometanf \
  --input samplesheet.csv \
  --optimization_profile auto \
  --enable_performance_logging \
  --outdir results \
  -profile docker
```

**Optimization profiles:**

| Profile | CPU | Memory | Use Case |
|---------|-----|--------|----------|
| `auto` | Adaptive | Adaptive | Unknown workload (recommended) |
| `high_throughput` | High (80%) | High (80%) | Batch processing, many samples |
| `balanced` | Medium (60%) | Medium (60%) | General use, mixed workloads |
| `resource_conservative` | Low (40%) | Low (40%) | Shared systems, limited resources |
| `gpu_optimized` | High + GPU | High | Dorado basecalling with GPU |
| `realtime_optimized` | Medium | Medium | Low-latency real-time analysis |
| `development_testing` | Low | Low | Development, quick tests |

**When to use:**
- Uncertain about optimal resource allocation
- Want automatic performance tuning
- Processing varies between runs

## Parameter Reference

### Core Parameters

#### Input/Output
```bash
--input <file>              # Samplesheet CSV (required unless --barcode_input_dir)
--barcode_input_dir <dir>   # Pre-demultiplexed barcode folders (alternative to --input)
--outdir <dir>              # Output directory (required)
```

#### Dorado Basecalling
```bash
--use_dorado                # Enable POD5 basecalling
--pod5_input_dir <dir>      # POD5 files directory
--dorado_path <path>        # Dorado binary path
--dorado_model <model>      # Basecalling model
--barcode_kit <kit>         # Barcode kit for demultiplexing
--trim_barcodes             # Remove barcode sequences
--min_qscore <int>          # Minimum quality score (default: 9)
```

#### Real-time Processing
```bash
--realtime_mode             # Enable file monitoring
--nanopore_output_dir <dir> # Directory to monitor
--file_pattern <pattern>    # File matching pattern
--batch_size <int>          # Files per batch (default: 10)
--batch_interval <duration> # Processing interval (default: 5min)
--max_files <string>        # Maximum files to process (optional)
--adaptive_batching         # Enable dynamic batch sizing
```

#### Quality Control
```bash
--skip_fastp                # Skip FASTP quality filtering
--skip_nanoplot             # Skip NanoPlot QC
--fastp_qualified_quality <int>     # Min quality score (default: 15)
--fastp_length_required <int>       # Min read length (default: 1000)
--fastp_cut_mean_quality <int>      # Sliding window quality (default: 20)
```

#### Taxonomic Classification
```bash
--kraken2_db <path>         # Kraken2 database path
--skip_kraken2              # Skip Kraken2 classification
--enable_taxpasta_standardization   # Standardize taxonomy format
--taxpasta_format <format>  # Output format (tsv, csv, biom)
```

#### Validation
```bash
--blast_validation          # Enable BLAST validation
--blast_db <path>           # BLAST database path
--validation_taxa <taxa>    # Specific taxa to validate
```

#### Resource Optimization
```bash
--optimization_profile <profile>    # auto, high_throughput, balanced, etc.
--enable_dynamic_resources          # Enable resource optimization
--resource_safety_factor <float>    # Safety factor 0.0-1.0 (default: 0.8)
--enable_performance_logging        # Detailed performance logs
--max_cpus <int>            # Maximum CPU cores
--max_memory <memory>       # Maximum memory (e.g., 16.GB)
--max_time <duration>       # Maximum runtime (e.g., 48.h)
```

### Advanced Parameters

#### Assembly (Experimental)
```bash
--enable_assembly           # Enable genome assembly
--assembler <tool>          # flye or miniasm
--genome_size <size>        # Expected genome size (e.g., 5m, 3.2g)
```

#### Adapter Trimming
```bash
--enable_adapter_trimming   # Enable PORECHOP trimming
```

#### QC Benchmarking
```bash
--enable_qc_benchmark       # Compare FASTP vs FILTLONG
```

## Advanced Configuration

### Custom Configuration File

Create `custom.config`:

```nextflow
// Custom resource limits
process {
    withName: KRAKEN2 {
        cpus = 16
        memory = 32.GB
        time = 4.h
    }

    withName: DORADO_BASECALLER {
        cpus = 8
        memory = 16.GB
        accelerator = 1  // Request GPU
    }
}

// Docker configuration
docker {
    enabled = true
    runOptions = '--gpus all'  // Enable GPU in Docker
}
```

Use with `-c` flag:

```bash
nextflow run foi-bioinformatics/nanometanf \
  --input samplesheet.csv \
  --outdir results \
  -profile docker \
  -c custom.config
```

### Profile Combinations

```bash
# HPC cluster with Singularity
-profile singularity,cluster

# AWS cloud execution
-profile docker,aws

# Local testing
-profile test,docker

# Full test with Singularity
-profile test_full,singularity
```

### Resume Failed Runs

```bash
# Resume from last checkpoint
nextflow run foi-bioinformatics/nanometanf \
  --input samplesheet.csv \
  --outdir results \
  -profile docker \
  -resume
```

## Troubleshooting

### Common Issues

**1. Docker permission denied**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Log out and back in
```

**2. Kraken2 database not found**
```bash
# Check database path
ls -lh /databases/k2_standard/
# Should contain: hash.k2d, opts.k2d, taxo.k2d
```

**3. Real-time mode not detecting files**
```bash
# Verify file pattern with quotes
--file_pattern "**/*.fastq.gz"

# Check directory permissions
ls -la /path/to/monitor

# Test pattern manually
find /path/to/monitor -name "*.fastq.gz"
```

**4. Out of memory**
```bash
# Reduce resource allocation
--optimization_profile resource_conservative \
--max_memory 8.GB \
--max_cpus 4
```

**5. Dorado model download fails**
```bash
# Pre-download models
dorado download --model dna_r10.4.1_e4.3_400bps_hac

# Check model cache
ls ~/.cache/dorado/models/
```

### Performance Tuning

**For faster processing:**
```bash
--optimization_profile high_throughput \
--max_cpus 16 \
--max_memory 32.GB \
--skip_nanoplot  # If QC plots not needed
```

**For limited resources:**
```bash
--optimization_profile resource_conservative \
--max_cpus 4 \
--max_memory 8.GB \
--skip_fastp \
--skip_nanoplot
```

**For real-time analysis:**
```bash
--optimization_profile realtime_optimized \
--batch_size 5 \
--batch_interval 5min \
--skip_nanoplot  # Reduce processing time
```

## Next Steps

- Review [Output Structure](output.md) to understand results
- See [Production Deployment](production_deployment.md) for cluster setup
- Check [Testing Guide](testing_guide.md) for validation
- Read [QC Guide](qc_guide.md) for result interpretation

---

**Need help?** Open an issue: https://github.com/foi-bioinformatics/nanometanf/issues
