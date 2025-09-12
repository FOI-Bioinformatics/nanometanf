# foi-bioinformatics/nanometanf

[![GitHub Actions CI Status](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/nf-test.yml/badge.svg)](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/nf-test.yml)
[![GitHub Actions Linting Status](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/linting.yml/badge.svg)](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/linting.yml)[![Cite with Zenodo](http://img.shields.io/badge/DOI-10.5281/zenodo.XXXXXXX-1073c8?labelColor=000000)](https://doi.org/10.5281/zenodo.XXXXXXX)
[![nf-test](https://img.shields.io/badge/unit_tests-nf--test-337ab7.svg)](https://www.nf-test.com)

[![Nextflow](https://img.shields.io/badge/version-%E2%89%A524.10.5-green?style=flat&logo=nextflow&logoColor=white&color=%230DC09D&link=https%3A%2F%2Fnextflow.io)](https://www.nextflow.io/)
[![nf-core template version](https://img.shields.io/badge/nf--core_template-3.3.2-green?style=flat&logo=nfcore&logoColor=white&color=%2324B064&link=https%3A%2F%2Fnf-co.re)](https://github.com/nf-core/tools/releases/tag/3.3.2)
[![run with conda](http://img.shields.io/badge/run%20with-conda-3EB049?labelColor=000000&logo=anaconda)](https://docs.conda.io/en/latest/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)
[![Launch on Seqera Platform](https://img.shields.io/badge/Launch%20%F0%9F%9A%80-Seqera%20Platform-%234256e7)](https://cloud.seqera.io/launch?pipeline=https://github.com/foi-bioinformatics/nanometanf)

## Introduction

**foi-bioinformatics/nanometanf** is a bioinformatics pipeline that performs comprehensive analysis of Oxford Nanopore long-read sequencing data with real-time processing capabilities. The pipeline serves as the computational backend for Nanometa Live, supporting both standard FASTQ processing and direct basecalling from POD5 files using Dorado. It provides quality control, taxonomic classification, and validation workflows optimized for metagenomics and genomics applications.

The pipeline workflow includes:

1. **Basecalling** ([`Dorado`](https://github.com/nanoporetech/dorado)) - Direct basecalling from POD5 files with optional demultiplexing
2. **Quality control** ([`FASTP`](https://github.com/OpenGene/fastp), [`NanoPlot`](https://github.com/wdecoster/NanoPlot)) - Read filtering and quality assessment
3. **Taxonomic classification** ([`Kraken2`](https://github.com/DerrickWood/kraken2)) - Metagenomic taxonomic profiling
4. **Validation** ([`BLAST`](https://blast.ncbi.nlm.nih.gov/Blast.cgi)) - Optional sequence validation against reference databases
5. **Real-time monitoring** - Continuous processing of incoming POD5 files (with basecalling) or FASTQ files
6. **Report generation** ([`MultiQC`](http://multiqc.info/)) - Comprehensive quality control reporting

## Usage

> [!NOTE]
> If you are new to Nextflow and nf-core, please refer to [this page](https://nf-co.re/docs/usage/installation) on how to set-up Nextflow. Make sure to [test your setup](https://nf-co.re/docs/usage/introduction#how-to-run-a-pipeline) with `-profile test` before running the workflow on actual data.

First, prepare a samplesheet with your input data that looks as follows:

`samplesheet.csv`:

```csv
sample,fastq,barcode
SAMPLE_1,sample1.fastq.gz,
SAMPLE_2,sample2.fastq.gz,BC01
```

Each row represents a sample with its associated nanopore FASTQ file. The `barcode` column is optional and used for barcoded samples (leave empty for non-barcoded samples). This format follows nf-core nanopore pipeline best practices. 

**Important**: 
- **Static mode**: Samplesheet must contain actual file paths to existing FASTQ files
- **Real-time mode**: Samplesheet can be empty (header only) as files are detected automatically
- **Dorado mode**: Empty samplesheet can be provided when processing POD5 files directly

> [!CRITICAL]
> **Empty samplesheets ONLY work with real-time mode enabled (`--realtime_mode true`)**. Using an empty samplesheet in static mode will cause the pipeline to fail. This is by design - real-time mode bypasses samplesheet file paths and creates sample metadata dynamically from detected files.

### Basic Usage

Run the pipeline with standard FASTQ processing:

```bash
nextflow run foi-bioinformatics/nanometanf \
   -profile docker \
   --input samplesheet.csv \
   --outdir results
```

### Dorado Basecalling

For direct basecalling from POD5 files with Dorado:

```bash
nextflow run foi-bioinformatics/nanometanf \
   -profile docker \
   --input samplesheet.csv \
   --outdir results \
   --use_dorado true \
   --pod5_input_dir /path/to/pod5_files \
   --dorado_model dna_r10.4.1_e4.3_400bps_hac@v5.0.0
```

### Real-time Processing

Enable real-time monitoring of sequencing output. **Note**: In real-time mode, the pipeline monitors a directory for new files and creates sample metadata automatically. You can provide an empty samplesheet:

#### Real-time FASTQ Processing
```bash
# Create minimal samplesheet for real-time mode
echo "sample,fastq,barcode" > empty_samplesheet.csv

# Run with real-time FASTQ monitoring
nextflow run foi-bioinformatics/nanometanf \
   -profile docker \
   --input empty_samplesheet.csv \
   --outdir results \
   --realtime_mode true \
   --nanopore_output_dir /path/to/fastq_output \
   --file_pattern "**/*.fastq.gz"
```

#### Real-time POD5 Processing with Dorado ⭐ **NEW**
```bash
# Create empty samplesheet and run real-time POD5 monitoring
echo "sample,fastq,barcode" > empty_samplesheet.csv
nextflow run foi-bioinformatics/nanometanf \
   -profile docker \
   --input empty_samplesheet.csv \
   --outdir results \
   --realtime_mode true \
   --use_dorado true \
   --nanopore_output_dir /path/to/pod5_output \
   --file_pattern "**/*.pod5" \
   --dorado_model dna_r10.4.1_e4.3_400bps_hac@v5.0.0
```

In real-time mode:
- **POD5 + Dorado**: Monitors for POD5 files, basecalls them automatically, then processes FASTQ
- **FASTQ only**: Monitors for FASTQ files and processes them directly
- Sample names are derived automatically from filenames
- Files are processed as they appear in the monitored directory
- The samplesheet requirement is bypassed for dynamic file detection

### Taxonomic Classification

Include taxonomic profiling with Kraken2:

```bash
nextflow run foi-bioinformatics/nanometanf \
   -profile docker \
   --input samplesheet.csv \
   --outdir results \
   --kraken2_db /path/to/kraken2_database
```

## Pipeline Parameters

### Core Parameters

| Parameter | Description | Type | Default |
|-----------|-------------|------|---------|
| `--input` | Path to samplesheet CSV file | string | - |
| `--outdir` | Output directory path | string | - |

### Dorado Basecalling

| Parameter | Description | Type | Default |
|-----------|-------------|------|---------|
| `--use_dorado` | Enable Dorado basecalling | boolean | `false` |
| `--pod5_input_dir` | Directory containing POD5 files | string | - |
| `--dorado_model` | Dorado basecalling model | string | `dna_r10.4.1_e4.3_400bps_hac@v5.0.0` |
| `--demultiplex` | Enable demultiplexing | boolean | `false` |
| `--barcode_kit` | Barcode kit for demultiplexing | string | - |
| `--min_qscore` | Minimum quality score | integer | `9` |

### Real-time Processing

| Parameter | Description | Type | Default |
|-----------|-------------|------|---------|
| `--realtime_mode` | Enable real-time file monitoring (bypasses samplesheet files) | boolean | `false` |
| `--nanopore_output_dir` | Directory to monitor for new FASTQ files | string | - |
| `--file_pattern` | File pattern to match (e.g., `**/*.fastq.gz`) | string | `**/*.fastq{,.gz}` |
| `--batch_size` | Files per processing batch | integer | `10` |
| `--batch_interval` | Processing interval for batching | string | `5min` |

### Analysis Options

| Parameter | Description | Type | Default |
|-----------|-------------|------|---------|
| `--kraken2_db` | Kraken2 database path | string | - |
| `--blast_validation` | Enable BLAST validation | boolean | `false` |
| `--skip_fastp` | Skip FASTP quality filtering | boolean | `false` |
| `--skip_nanoplot` | Skip NanoPlot QC | boolean | `false` |

## Pipeline Output

The pipeline generates the following outputs in the specified `--outdir`:

- **`fastp/`** - Quality-filtered FASTQ files and filtering statistics
- **`nanoplot/`** - Comprehensive nanopore read quality control plots
- **`dorado/`** - Basecalled FASTQ files from POD5 input (if enabled)
- **`kraken2/`** - Taxonomic classification results (if enabled)
- **`blast/`** - Sequence validation results (if enabled)
- **`multiqc/`** - Comprehensive quality control report
- **`pipeline_info/`** - Pipeline execution reports and software versions

> [!WARNING]
> Please provide pipeline parameters via the CLI or Nextflow `-params-file` option. Custom config files including those provided by the `-c` Nextflow option can be used to provide any configuration _**except for parameters**_; see [docs](https://nf-co.re/docs/usage/getting_started/configuration#custom-configuration-files).

## Testing

The pipeline includes comprehensive testing using nf-test with nf-core test datasets:

```bash
# Test with nf-core FASTQ test data
nf-test test tests/nanoseq_test.nf.test --verbose

# Test Dorado basecalling with POD5 data
nf-test test tests/dorado_pod5.nf.test --verbose

# Test real-time processing with empty samplesheets
nf-test test tests/realtime_empty_samplesheet.nf.test --verbose

# Test real-time POD5 processing with Dorado basecalling
nf-test test tests/realtime_pod5_basecalling.nf.test --verbose

# Quick parameter validation
nf-test test tests/parameter_validation.nf.test --verbose
```

Test data includes:
- FASTQ files from nf-core/test-datasets (nanoseq branch)
- POD5 files for Dorado basecalling validation
- Synthetic data for parameter testing

## Troubleshooting

### Common Issues

**Java Environment**: Ensure Java runtime is properly configured when running nf-test:
```bash
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH
```

**Resource Limits**: For local testing, use resource-limited configurations:
```bash
nextflow run foi-bioinformatics/nanometanf -profile test,docker
```

**Dorado Installation**: Verify Dorado is accessible at the specified path:
```bash
/path/to/dorado/bin/dorado basecaller --help
```

**Empty Samplesheet Errors**: If you encounter errors with empty samplesheets:
- Ensure `--realtime_mode true` is enabled
- Empty samplesheets only work in real-time mode
- For static processing, provide actual file paths in the samplesheet

**Real-time Processing Issues**: The current implementation has known limitations with `Channel.timer()` - use simple file monitoring without time-based batching for now.

For additional support, please refer to the [nf-core guidelines](https://nf-co.re/docs/usage/troubleshooting) or open an issue on the [GitHub repository](https://github.com/foi-bioinformatics/nanometanf/issues).

## Credits

foi-bioinformatics/nanometanf was originally written by Andreas Sjödin.

This pipeline integrates multiple established bioinformatics tools and represents a collaborative effort in nanopore sequencing analysis. We thank the developers and maintainers of the underlying software packages that make this pipeline possible.

## Contributions and Support

If you would like to contribute to this pipeline, please see the [contributing guidelines](.github/CONTRIBUTING.md).

## Citations

<!-- TODO nf-core: Add citation for pipeline after first release. Uncomment lines below and update Zenodo doi and badge at the top of this file. -->
<!-- If you use foi-bioinformatics/nanometanf for your analysis, please cite it using the following doi: [10.5281/zenodo.XXXXXX](https://doi.org/10.5281/zenodo.XXXXXX) -->

<!-- TODO nf-core: Add bibliography of tools and data used in your pipeline -->

An extensive list of references for the tools used by the pipeline can be found in the [`CITATIONS.md`](CITATIONS.md) file.

This pipeline uses code and infrastructure developed and maintained by the [nf-core](https://nf-co.re) community, reused here under the [MIT license](https://github.com/nf-core/tools/blob/main/LICENSE).

> **The nf-core framework for community-curated bioinformatics pipelines.**
>
> Philip Ewels, Alexander Peltzer, Sven Fillinger, Harshil Patel, Johannes Alneberg, Andreas Wilm, Maxime Ulysse Garcia, Paolo Di Tommaso & Sven Nahnsen.
>
> _Nat Biotechnol._ 2020 Feb 13. doi: [10.1038/s41587-020-0439-x](https://dx.doi.org/10.1038/s41587-020-0439-x).
