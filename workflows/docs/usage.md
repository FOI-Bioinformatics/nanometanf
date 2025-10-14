# foi-bioinformatics/nanometanf: Usage

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Introduction

For comprehensive usage documentation including all input modalities, parameter descriptions, and advanced configurations, please see the [main README](../../README.md).

This document provides supplementary usage information specific to the nanometanf workflow implementation.

## Samplesheet Input

nanometanf supports nanopore long-read sequencing data. The samplesheet format is:

```csv
sample,fastq,barcode
SAMPLE_1,sample1.fastq.gz,
SAMPLE_2,sample2.fastq.gz,BC01
```

| Column    | Description                                                                                                   |
| --------- | ------------------------------------------------------------------------------------------------------------- |
| `sample`  | Custom sample name. Spaces are automatically converted to underscores (`_`).                                  |
| `fastq`   | Full path to FastQ file (can be gzipped). For nanopore data.                                                  |
| `barcode` | Optional barcode identifier (e.g., BC01, BC02). Leave empty for non-multiplexed samples.                      |

### Multiple Input Modes

nanometanf supports four distinct input paradigms:

1. **Standard Samplesheet** - Traditional CSV-based input (shown above)
2. **Pre-demultiplexed Barcode Directories** - Automatic discovery of barcode folders
3. **POD5 Basecalling** - Direct basecalling from POD5 files with Dorado
4. **Real-time Processing** - Live monitoring of sequencing runs

For detailed examples of each mode, see the [main README](../../README.md#supported-input-modalities).

## Running the Pipeline

### Basic Usage

```bash
nextflow run foi-bioinformatics/nanometanf \
    -profile docker \
    --input samplesheet.csv \
    --outdir results
```

### With Taxonomic Classification

```bash
nextflow run foi-bioinformatics/nanometanf \
    -profile docker \
    --input samplesheet.csv \
    --kraken2_db /path/to/kraken2/db \
    --outdir results
```

### Real-time POD5 Processing

```bash
nextflow run foi-bioinformatics/nanometanf \
    -profile docker \
    --realtime_mode \
    --use_dorado \
    --pod5_input_dir /path/to/pod5_output \
    --file_pattern "**/*.pod5" \
    --max_files 100 \
    --outdir results
```

For complete parameter documentation, run:

```bash
nextflow run foi-bioinformatics/nanometanf --help
```

## Core Nextflow Arguments

> [!NOTE]
> These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen)

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline:

- `test` - Complete configuration for automated testing
- `docker` - Use with [Docker](https://docker.com/)
- `singularity` - Use with [Singularity](https://sylabs.io/docs/)
- `podman` - Use with [Podman](https://podman.io/)
- `conda` - Use with [Conda](https://conda.io/docs/) (last resort)

> [!IMPORTANT]
> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility.

Multiple profiles can be loaded: `-profile test,docker`

### `-resume`

Specify this when restarting a pipeline. Nextflow will use cached results from any pipeline steps where the inputs are the same.

```bash
nextflow run foi-bioinformatics/nanometanf -profile docker -resume
```

### `-c`

Specify the path to a specific config file (core Nextflow command).

> [!WARNING]
> Do not use `-c <file>` to specify parameters. Use `-params-file <file>` instead.

## Resource Configuration

### GPU Support

For Dorado basecalling with GPU acceleration:

```bash
nextflow run foi-bioinformatics/nanometanf \
    -profile docker,gpu \
    --use_dorado \
    --pod5_input_dir /path/to/pod5 \
    --outdir results
```

### Custom Resource Limits

You can customize resource requests in a custom config file:

```groovy
process {
    withName: KRAKEN2 {
        memory = 128.GB
        cpus = 32
    }
}
```

Then run with:

```bash
nextflow run foi-bioinformatics/nanometanf -profile docker -c custom.config --input samplesheet.csv --outdir results
```

## Reproducibility

Specify the pipeline version for reproducibility:

```bash
nextflow run foi-bioinformatics/nanometanf -r 1.2.0 -profile docker --input samplesheet.csv --outdir results
```

Check available versions at: https://github.com/foi-bioinformatics/nanometanf/releases

## Running in the Background

Launch Nextflow in the background:

```bash
nextflow run foi-bioinformatics/nanometanf -profile docker --input samplesheet.csv --outdir results -bg
```

Or use screen/tmux for persistent sessions.

## Troubleshooting

For common issues and solutions, see the [main README troubleshooting section](../../README.md#troubleshooting).

For additional support:
- [nf-core documentation](https://nf-co.re/docs)
- [GitHub issues](https://github.com/foi-bioinformatics/nanometanf/issues)
