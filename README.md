# foi-bioinformatics/nanometanf

[![GitHub Actions CI Status](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/nf-test.yml/badge.svg)](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/nf-test.yml)
[![GitHub Actions Linting Status](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/linting.yml/badge.svg)](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/linting.yml)
[![nf-test](https://img.shields.io/badge/unit_tests-nf--test-337ab7.svg)](https://www.nf-test.com)

[![Nextflow](https://img.shields.io/badge/version-%E2%89%A525.04.7-green?style=flat&logo=nextflow&logoColor=white&color=%230DC09D&link=https%3A%2F%2Fnextflow.io)](https://www.nextflow.io/)
[![nf-core template version](https://img.shields.io/badge/nf--core_template-3.3.2-green?style=flat&logo=nfcore&logoColor=white&color=%2324B064&link=https%3A%2F%2Fnf-co.re)](https://github.com/nf-core/tools/releases/tag/3.3.2)
[![run with conda](http://img.shields.io/badge/run%20with-conda-3EB049?labelColor=000000&logo=anaconda)](https://docs.conda.io/en/latest/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)
[![Launch on Seqera Platform](https://img.shields.io/badge/Launch%20%F0%9F%9A%80-Seqera%20Platform-%234256e7)](https://cloud.seqera.io/launch?pipeline=https://github.com/foi-bioinformatics/nanometanf)

## Introduction

**nanometanf** is a bioinformatics pipeline for Oxford Nanopore long-read sequencing data analysis with real-time processing capabilities. It serves as the computational backend for Nanometa Live, covering quality control (Chopper, FASTP, NanoPlot), taxonomic classification (Kraken2), and validation workflows (BLAST, minimap2) for metagenomics and genomics applications.

**Key Features:**

- Real-time FASTQ monitoring during active sequencing
- Scalable streaming architecture for high-throughput runs (v1.5+)
- Multiple execution modes supporting diverse laboratory workflows
- Pre-demultiplexed barcode directory support (flat FASTQ or per-barcode layout)
- Intelligent resource optimization and backpressure control
- Production-ready with full nf-core compliance and an extensive nf-test suite

## Quick Start

**Minimal command (QC only):**

```bash
nextflow run foi-bioinformatics/nanometanf \
  --input samplesheet.csv \
  --outdir results \
  -profile docker
```

**Full analysis with classification:**

```bash
nextflow run foi-bioinformatics/nanometanf \
  --input samplesheet.csv \
  --kraken2_db /path/to/kraken2_db \
  --outdir results \
  -profile docker
```

**Test the pipeline:**

```bash
nextflow run foi-bioinformatics/nanometanf -profile test,docker --outdir test_results
```

<details>
<summary>More examples (real-time monitoring)</summary>

```bash
# Real-time FASTQ monitoring during sequencing
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --nanopore_output_dir /path/to/fastq \
  --kraken2_db /path/to/db \
  --outdir results \
  -profile docker

# High-throughput real-time with scalable streaming (v1.5+)
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --kraken2_enable_incremental true \
  --max_classification_forks 8 \
  --nanopore_output_dir /path/to/fastq \
  --kraken2_db /path/to/db \
  --outdir results \
  -profile docker
```

</details>

## Scalable Streaming Architecture (v1.5+)

For high-throughput sequencing runs with many barcodes (>10), the pipeline now uses a scalable streaming architecture:

- **Per-sample parallelism**: No global serialization bottlenecks
- **Append-only storage**: O(1) per batch instead of O(n) cumulative rewrites
- **Incremental taxid counting**: No full file re-reads for report generation
- **Backpressure control**: Configurable concurrency limits

**Performance improvement:** 4-5x throughput increase for runs with 12+ barcodes.

```bash
# Enable scalable streaming
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --kraken2_enable_incremental true \
  --max_concurrent_batches 4 \
  --max_classification_forks 8 \
  ...
```

## Deployment Profiles

The pipeline includes hardware-specific profiles that adjust resource allocation
for different Oxford Nanopore sequencing instruments and deployment scenarios.
Select a profile with `-profile <name>` when launching the pipeline.

| Profile | Use Case | Description |
|---|---|---|
| `test` | CI and validation | Minimal dataset with reduced resources for rapid testing |
| `minion` | MinION / Mk1C | Conservative memory and CPU allocation for portable sequencers |
| `promethion` | PromethION (standard) | Higher throughput settings for PromethION runs |
| `promethion_8` | PromethION (8-barcode) | Tuned for multiplexed PromethION runs with up to 8 barcodes |
| `field` | Field deployments | Reduced resource footprint for laptop-based analysis |

Profiles can be combined with an execution engine profile (e.g., `docker`,
`singularity`, `conda`):

```bash
# PromethION run with Docker
nextflow run foi-bioinformatics/nanometanf -profile promethion,docker --input samplesheet.csv

# MinION field analysis with Conda
nextflow run foi-bioinformatics/nanometanf -profile minion,conda --input samplesheet.csv --realtime_mode

# CI stub test
nextflow run foi-bioinformatics/nanometanf -profile test,docker
```

For production deployments requiring additional resource tuning, see
`conf/production.config` for enhanced resource allocation settings.

## Documentation

**[Complete Documentation](docs/README.md)** - Main documentation hub

### For Users

- **[Usage Guide](docs/user/usage.md)** - Complete parameter reference and execution modes
- **[Quick Start Tutorial](docs/user/quickstart.md)** - 5-minute scenario-based walkthrough
- **[Output Files](docs/user/output.md)** - Output directory structure and file descriptions
- **[Real-time Processing](docs/user/realtime_processing.md)** - Advanced real-time monitoring guide
- **[Performance Tuning](docs/user/performance_tuning.md)** - Resource optimization and benchmarks
- **[Troubleshooting](docs/user/troubleshooting.md)** - Common issues and solutions

### For Developers

- **[Development Guide](docs/development/README.md)** - Development documentation index
- **[Testing Guide](docs/development/TESTING.md)** - Comprehensive nf-test documentation
- **[CLAUDE.md](CLAUDE.md)** - AI-assisted development guide

### Release Information

- **[Current Version Status](docs/releases/CURRENT_VERSION.md)** - Recommended versions and known issues
- **[Release Notes](docs/releases/)** - Version history and changelogs
- **[Migration Guide](docs/releases/MIGRATION_GUIDE.md)** - Upgrade instructions

## Pipeline Summary

```
Input -> QC -> Classification -> Validation -> Reports
  |       |         |               |            |
FASTQ  Chopper   Kraken2         BLAST       MultiQC
       FASTP    (scalable)       minimap2     JSON
       NanoPlot Taxpasta                      HTML
```

**Supported Input Types:**

1. FASTQ samplesheet (standard batch analysis)
2. Pre-demultiplexed barcode directories (automated discovery)
3. Real-time FASTQ monitoring (during sequencing)

See [Usage Guide](docs/user/usage.md) for detailed instructions.

## Credits

nanometanf was originally written by Andreas Sjodin ([@andreassjodin](https://github.com/andreassjodin)).

We thank the following people for their extensive assistance in the development of this pipeline:

- The nf-core community for the excellent framework and tools
- All tool developers whose software is integrated in this pipeline

## Citations

If you use nanometanf for your analysis, please cite:

> **nanometanf: Comprehensive Oxford Nanopore sequencing analysis pipeline**
>
> Andreas Sjodin
>
> _GitHub_ 2025. DOI: TBD upon Zenodo deposit.

An extensive list of references for the tools used by the pipeline can be found in [CITATIONS.md](CITATIONS.md).

You can cite the `nf-core` publication as follows:

> **The nf-core framework for community-curated bioinformatics pipelines.**
>
> Philip Ewels, Alexander Peltzer, Sven Fillinger, Harshil Patel, Johannes Alneberg, Andreas Wilm, Maxime Ulysse Garcia, Paolo Di Tommaso & Sven Nahnsen.
>
> _Nat Biotechnol._ 2020 Feb 13. doi: [10.1038/s41587-020-0439-x](https://dx.doi.org/10.1038/s41587-020-0439-x).

## License

This pipeline is released under the MIT License. See [LICENSE](LICENSE) for details.
