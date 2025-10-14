# foi-bioinformatics/nanometanf: Output

## Introduction

This document describes the output produced by the nanometanf pipeline. Most plots and statistics are aggregated in the MultiQC report.

All output directories are created relative to the specified `--outdir`.

For comprehensive output documentation including file formats and interpretation guidelines, see the [main output documentation](../../docs/user/output.md).

## Pipeline Overview

The nanometanf pipeline processes Oxford Nanopore long-read sequencing data through the following stages:

1. **Basecalling** (optional) - Dorado basecalling from POD5 files
2. **Quality Control** - Chopper/FASTP/Filtlong read filtering
3. **Taxonomic Classification** - Kraken2 metagenomic profiling
4. **Validation** (optional) - BLAST sequence validation
5. **Report Generation** - MultiQC comprehensive reporting

## Output Directory Structure

```
results/
├── dorado/                 # Basecalled FASTQ files (if --use_dorado)
├── chopper/               # QC-filtered reads (default QC tool)
├── fastp/                 # Alternative QC tool output
├── filtlong/              # Alternative QC tool output
├── nanoplot/              # Nanopore-specific QC visualizations
├── kraken2/               # Taxonomic classification results
├── taxpasta/              # Standardized taxonomic profiles
├── blast/                 # Validation results (if --blast_validation)
├── multiqc/               # Comprehensive QC report
└── pipeline_info/         # Execution metadata and logs
```

## Key Output Files

### Dorado Basecalling

<details markdown="1">
<summary>Output files</summary>

- `dorado/`
  - `*.fastq.gz` - Basecalled reads in FASTQ format
  - `*_summary.txt` - Basecalling summary with model, device, and quality metrics

</details>

Generated when using `--use_dorado` with POD5 input files.

### Quality Control

<details markdown="1">
<summary>Output files</summary>

- `chopper/` (default)
  - `*.chopper.fastq.gz` - Quality-filtered reads
  - `*.chopper.log` - Filtering statistics

- `fastp/` (if `--qc_tool fastp`)
  - `*.fastp.fastq.gz` - Quality-filtered reads
  - `*.fastp.html` - Interactive QC report
  - `*.fastp.json` - Machine-readable statistics

- `filtlong/` (if `--qc_tool filtlong`)
  - `*.filtlong.fastq.gz` - Quality-filtered reads
  - `*.filtlong.log` - Filtering statistics

</details>

Quality-controlled reads after filtering based on quality scores and read length thresholds.

### NanoPlot Visualization

<details markdown="1">
<summary>Output files</summary>

- `nanoplot/`
  - `*_NanoPlot-report.html` - Interactive quality report
  - `*_NanoStats.txt` - Statistical summary
  - `*_LengthvsQualityScatterPlot_dot.png` - Read length vs quality visualization
  - `*_Weighted_HistogramReadlength.png` - Read length distribution

</details>

Comprehensive nanopore-specific quality control visualizations.

### Taxonomic Classification

<details markdown="1">
<summary>Output files</summary>

- `kraken2/`
  - `*.kraken2.report.txt` - Taxonomic classification report
  - `*.kraken2.classified.fastq.gz` - Classified reads (if `--save_output_fastqs`)
  - `*.kraken2.unclassified.fastq.gz` - Unclassified reads (if `--save_output_fastqs`)

- `taxpasta/`
  - `*.taxpasta.tsv` - Standardized taxonomic profile (default format)
  - `*.taxpasta.biom` - BIOM format (if `--taxpasta_format biom`)

</details>

Metagenomic taxonomic profiling using Kraken2 with optional taxpasta standardization.

### BLAST Validation

<details markdown="1">
<summary>Output files</summary>

- `blast/`
  - `*.blast.txt` - BLAST alignment results
  - `*.blast.summary.txt` - Validation summary statistics

</details>

Generated when using `--blast_validation` for sequence validation against reference databases.

### MultiQC Report

<details markdown="1">
<summary>Output files</summary>

- `multiqc/`
  - `multiqc_report.html` - Standalone HTML report viewable in web browsers
  - `multiqc_data/` - Parsed statistics from all pipeline tools
  - `multiqc_plots/` - Static images in various formats

</details>

[MultiQC](http://multiqc.info) aggregates results from all pipeline stages into a single comprehensive report. The report includes:

- Dorado basecalling statistics (if applicable)
- Quality control metrics (Chopper/FASTP/Filtlong)
- NanoPlot visualizations
- Kraken2 taxonomic composition
- Software versions and pipeline configuration

### Pipeline Information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - `execution_report_*.html` - Nextflow execution report with resource usage
  - `execution_timeline_*.html` - Interactive timeline of process execution
  - `execution_trace_*.txt` - Detailed trace of all executed tasks
  - `pipeline_dag_*.html` - Pipeline directed acyclic graph visualization
  - `params.json` - Complete parameters used for the run
  - `software_versions.yml` - All software versions used in the pipeline

</details>

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) automatically generates these reports for troubleshooting and reproducibility.

## Real-time Output Updates

When running in real-time mode (`--realtime_mode`), output directories are updated incrementally as new files are processed.

Monitor progress with:

```bash
watch -n 30 "ls -lh results/multiqc/"
```

## Output Customization

### Saving Additional Files

- `--save_output_fastqs` - Save classified/unclassified FASTQ files from Kraken2
- `--save_reads_assignment` - Save read-level taxonomic assignments

### Output Formats

- `--taxpasta_format` - Choose standardized output format: `tsv`, `csv`, `arrow`, `parquet`, `biom`
- `--publish_dir_mode` - Control how files are published: `copy`, `symlink`, `move`

## Data Interpretation

For guidance on interpreting results and quality thresholds, see:

- [Quality Control Guide](../../docs/user/qc_guide.md)
- [Output Documentation](../../docs/user/output.md)
- [Troubleshooting Guide](../../README.md#troubleshooting)

## File Formats

- **FASTQ** - Sequence data with quality scores
- **TSV/CSV** - Taxonomic profiles and statistics
- **HTML** - Interactive reports and visualizations
- **JSON** - Machine-readable statistics
- **BIOM** - Biological Observation Matrix format for taxonomic data

## Additional Resources

- [MultiQC documentation](http://multiqc.info)
- [Kraken2 output format](https://github.com/DerrickWood/kraken2/wiki/Manual#output-formats)
- [Nextflow reports](https://www.nextflow.io/docs/latest/tracing.html)
