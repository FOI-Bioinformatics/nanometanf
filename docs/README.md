# nanometanf Documentation

Welcome to the comprehensive documentation for **nanometanf**, a production-ready Nextflow pipeline for Oxford Nanopore Technologies (ONT) sequencing data analysis.

## Quick Links

| Document | Description | Target Audience |
|----------|-------------|-----------------|
| [Usage Guide](usage.md) | Complete usage instructions with all 7 execution modes | All users |
| [Output Structure](output.md) | Output directory organization and file descriptions | All users |
| [Testing Guide](testing_guide.md) | nf-test framework and test development | Developers |
| [QC Guide](qc_guide.md) | Quality control metrics interpretation | Bioinformaticians |
| [Dynamic Resource Allocation](dynamic_resource_allocation.md) | Resource optimization system | HPC administrators |
| [Production Deployment](production_deployment.md) | Cloud, cluster, and on-premises deployment | IT/DevOps |

## Pipeline Overview

nanometanf provides comprehensive analysis of Oxford Nanopore long-read sequencing data with seven distinct execution modes:

```
Input → Basecalling → QC → Classification → Validation → Reports
  ↓         ↓         ↓        ↓             ↓          ↓
POD5    Dorado    FASTP    Kraken2       BLAST     MultiQC
FASTQ              NanoPlot  Taxpasta                HTML
Barcodes                                            JSON
```

### Key Features

- **Real-time Processing**: Continuous analysis during active sequencing runs
- **Multiple Input Types**: POD5 basecalling, FASTQ processing, pre-demultiplexed barcodes
- **Intelligent Resource Management**: ML-based resource prediction with 6 optimization profiles
- **Production Ready**: 119 tests, full nf-core compliance, comprehensive CI/CD
- **Flexible Deployment**: Local, HPC cluster, cloud (AWS/Azure/GCP)

## Getting Started

### Quick Start (5 minutes)

```bash
# 1. Install Nextflow (requires Java 11+)
curl -s https://get.nextflow.io | bash
sudo mv nextflow /usr/local/bin/

# 2. Test installation
nextflow run foi-bioinformatics/nanometanf -profile test,docker

# 3. Run with your data
nextflow run foi-bioinformatics/nanometanf \
  --input samplesheet.csv \
  --outdir results \
  -profile docker
```

See [Usage Guide](usage.md) for detailed instructions.

### System Requirements

**Minimum:**
- CPU: 4 cores
- RAM: 8 GB
- Disk: 50 GB free space
- OS: Linux, macOS (Intel/Apple Silicon), WSL2

**Recommended:**
- CPU: 8+ cores
- RAM: 16+ GB
- Disk: 200+ GB (for Kraken2 databases)
- GPU: Optional for Dorado basecalling acceleration

## Execution Modes

nanometanf supports seven execution modes optimized for different laboratory workflows:

### 1. Standard FASTQ Processing
**Use case**: Batch analysis of preprocessed FASTQ files

```bash
nextflow run foi-bioinformatics/nanometanf \
  --input samplesheet.csv \
  --outdir results \
  -profile docker
```

### 2. Pre-demultiplexed Barcode Directories ⭐ NEW
**Use case**: Laboratory-prepared barcode folders (barcode01/, barcode02/, etc.)

```bash
nextflow run foi-bioinformatics/nanometanf \
  --barcode_input_dir /path/to/barcode/folders \
  --outdir results \
  -profile docker
```

### 3. Singleplex POD5 Basecalling
**Use case**: Single-sample POD5 basecalling without demultiplexing

```bash
nextflow run foi-bioinformatics/nanometanf \
  --use_dorado \
  --pod5_input_dir /path/to/pod5 \
  --dorado_model dna_r10.4.1_e4.3_400bps_hac@v5.0.0 \
  --outdir results \
  -profile docker
```

### 4. Multiplex POD5 with Demultiplexing
**Use case**: Barcoded samples requiring Dorado demultiplexing

```bash
nextflow run foi-bioinformatics/nanometanf \
  --use_dorado \
  --pod5_input_dir /path/to/pod5 \
  --barcode_kit SQK-NBD114-24 \
  --trim_barcodes \
  --outdir results \
  -profile docker
```

### 5. Real-time FASTQ Monitoring
**Use case**: Live analysis during active sequencing

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --nanopore_output_dir /path/to/monitor \
  --file_pattern "**/*.fastq{,.gz}" \
  --outdir results \
  -profile docker
```

### 6. Real-time POD5 Processing
**Use case**: Live basecalling + analysis during sequencing

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --use_dorado \
  --nanopore_output_dir /path/to/pod5 \
  --file_pattern "**/*.pod5" \
  --outdir results \
  -profile docker
```

### 7. Dynamic Resource Optimization
**Use case**: Any mode with intelligent resource allocation

```bash
nextflow run foi-bioinformatics/nanometanf \
  --input samplesheet.csv \
  --optimization_profile auto \
  --outdir results \
  -profile docker
```

See [Usage Guide](usage.md#execution-modes) for complete mode documentation.

## Common Workflows

### Clinical Pathogen Detection

```bash
# Real-time pathogen detection with priority samples
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --nanopore_output_dir /sequencing/run_001 \
  --kraken2_db /databases/k2_standard \
  --priority_samples "patient_A,patient_B" \
  --optimization_profile realtime_optimized \
  --outdir results/clinical_run \
  -profile docker
```

### Environmental Metagenomics

```bash
# Comprehensive taxonomic profiling
nextflow run foi-bioinformatics/nanometanf \
  --input environmental_samples.csv \
  --kraken2_db /databases/k2_pluspf \
  --enable_taxpasta_standardization \
  --optimization_profile high_throughput \
  --outdir results/metagenomics \
  -profile singularity,cluster
```

### High-throughput Batch Processing

```bash
# Process 100+ samples with resource optimization
nextflow run foi-bioinformatics/nanometanf \
  --input large_cohort.csv \
  --optimization_profile balanced \
  --max_parallel_jobs 8 \
  --enable_performance_logging \
  --outdir results/cohort_study \
  -profile docker
```

## Configuration Profiles

| Profile | Description | Use Case |
|---------|-------------|----------|
| `docker` | Docker containers | Local workstations, dev/test |
| `singularity` | Singularity containers | HPC clusters (recommended) |
| `conda` | Conda environments | Systems without containers |
| `test` | Minimal test dataset | Pipeline validation, CI/CD |
| `test_full` | Comprehensive test | Full workflow validation |

### Profile Combinations

```bash
# HPC cluster with Singularity
-profile singularity,cluster

# Cloud execution
-profile docker,aws
-profile docker,azure
-profile docker,gcp

# Local testing
-profile test,docker
```

See [Production Deployment](production_deployment.md) for cluster-specific configurations.

## Resource Optimization

### Optimization Profiles

| Profile | CPU/Memory | Throughput | Best For |
|---------|------------|------------|----------|
| `auto` | Adaptive | Variable | Unknown workloads |
| `high_throughput` | High | Maximum | Batch processing |
| `balanced` | Medium | Balanced | General use (default) |
| `resource_conservative` | Low | Reduced | Shared systems |
| `gpu_optimized` | High + GPU | Maximum | Dorado basecalling |
| `realtime_optimized` | Medium | Low-latency | Live sequencing |
| `development_testing` | Low | Fast | Development/testing |

Example:

```bash
# Auto-select optimal profile
--optimization_profile auto

# High-throughput processing
--optimization_profile high_throughput \
--enable_performance_logging
```

See [Dynamic Resource Allocation](dynamic_resource_allocation.md) for detailed configuration.

## Key Parameters

### Input/Output
- `--input` - Samplesheet CSV (nanopore format)
- `--barcode_input_dir` - Pre-demultiplexed barcode folders
- `--outdir` - Output directory (required)

### Dorado Basecalling
- `--use_dorado` - Enable POD5 basecalling
- `--pod5_input_dir` - POD5 files directory
- `--dorado_model` - Basecalling model (e.g., `dna_r10.4.1_e4.3_400bps_hac@v5.0.0`)
- `--barcode_kit` - Barcode kit for demultiplexing (e.g., `SQK-NBD114-24`)
- `--trim_barcodes` - Remove barcode sequences

### Real-time Processing
- `--realtime_mode` - Enable file monitoring
- `--nanopore_output_dir` - Directory to monitor
- `--file_pattern` - File matching pattern (default: `**/*.fastq{,.gz}`)
- `--batch_size` - Files per batch (default: 10)
- `--batch_interval` - Processing interval (default: 5min)

### Analysis Options
- `--kraken2_db` - Kraken2 database path
- `--blast_validation` - Enable BLAST validation
- `--skip_fastp` - Skip quality filtering
- `--skip_nanoplot` - Skip nanopore QC

### Resource Management
- `--optimization_profile` - Resource optimization strategy
- `--max_cpus` - Maximum CPU cores
- `--max_memory` - Maximum memory (e.g., `16.GB`)
- `--max_time` - Maximum runtime per process

See [Usage Guide](usage.md#parameters) for complete parameter reference.

## Output Structure

```
results/
├── fastp/                          # Quality filtering
├── nanoplot/                       # Nanopore QC
├── kraken2/                        # Taxonomic classification
│   ├── *.kraken2.report.txt
│   └── *.classified.fastq.gz
├── taxpasta/                       # Standardized taxonomy
├── blast/                          # Validation (optional)
├── multiqc/                        # Comprehensive reports
│   └── multiqc_report.html
├── realtime_stats/                 # Live statistics (realtime mode)
│   ├── snapshots/
│   └── cumulative/
├── resource_monitoring/            # System metrics
└── pipeline_info/                  # Execution metadata
    ├── execution_report_*.html
    ├── execution_timeline_*.html
    └── execution_trace_*.txt
```

See [Output Structure](output.md) for complete descriptions.

## Troubleshooting

### Common Issues

**1. Docker daemon not running**
```bash
# macOS
open -a Docker

# Linux
sudo systemctl start docker
```

**2. Out of memory**
```bash
# Reduce resource allocation
--optimization_profile resource_conservative \
--max_memory 8.GB
```

**3. Kraken2 database not found**
```bash
# Download standard database
kraken2-build --standard --db k2_standard

# Or use custom database
--kraken2_db /path/to/custom/db
```

**4. Real-time mode hangs**
```bash
# Check file pattern matches
--file_pattern "**/*.fastq.gz"  # Note: quotes required

# Verify directory accessible
ls /path/to/monitor
```

### Getting Help

1. **Check logs**: `results/pipeline_info/execution_trace_*.txt`
2. **GitHub Issues**: https://github.com/foi-bioinformatics/nanometanf/issues
3. **nf-core Help**: https://nf-co.re/usage/troubleshooting

## Citation

If you use nanometanf in your research, please cite:

```bibtex
@software{nanometanf2025,
  author = {Sjodin, Andreas},
  title = {nanometanf: Comprehensive Oxford Nanopore sequencing analysis pipeline},
  year = {2025},
  publisher = {GitHub},
  url = {https://github.com/foi-bioinformatics/nanometanf},
  doi = {10.5281/zenodo.XXXXXXX}
}
```

Also cite the tools used:
- **Nextflow**: doi:10.1038/nbt.3820
- **nf-core**: doi:10.1038/s41587-020-0439-x
- **Dorado**: https://github.com/nanoporetech/dorado
- **Kraken2**: doi:10.1186/s13059-019-1891-0
- **FASTP**: doi:10.1093/bioinformatics/bty560
- **NanoPlot**: doi:10.1093/bioinformatics/bty149

## License

This pipeline is released under the MIT License. See [LICENSE](../LICENSE) for details.

## Contributing

We welcome contributions! See `.github/CONTRIBUTING.md` for guidelines.

---

**Version**: 1.0.0
**Last Updated**: 2025-10-03
**Maintainer**: Andreas Sjodin (foi-bioinformatics)
