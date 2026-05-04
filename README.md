# foi-bioinformatics/nanometanf

[![GitHub Actions CI Status](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/nf-test.yml/badge.svg)](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/nf-test.yml)
[![GitHub Actions Linting Status](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/linting.yml/badge.svg)](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/linting.yml)
[![nf-test](https://img.shields.io/badge/unit_tests-nf--test-337ab7.svg)](https://www.nf-test.com)

[![Nextflow](https://img.shields.io/badge/version-%E2%89%A525.10.0-green?style=flat&logo=nextflow&logoColor=white&color=%230DC09D&link=https%3A%2F%2Fnextflow.io)](https://www.nextflow.io/)
[![nf-core template version](https://img.shields.io/badge/nf--core_template-3.3.2-green?style=flat&logo=nfcore&logoColor=white&color=%2324B064&link=https%3A%2F%2Fnf-co.re)](https://github.com/nf-core/tools/releases/tag/3.3.2)
[![run with conda](http://img.shields.io/badge/run%20with-conda-3EB049?labelColor=000000&logo=anaconda)](https://docs.conda.io/en/latest/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)
[![Launch on Seqera Platform](https://img.shields.io/badge/Launch%20%F0%9F%9A%80-Seqera%20Platform-%234256e7)](https://cloud.seqera.io/launch?pipeline=https://github.com/foi-bioinformatics/nanometanf)

## Introduction

**nanometanf** is an nf-core compliant Nextflow pipeline for Oxford Nanopore
long-read sequencing data analysis. It serves as the computational backend for
[Nanometa Live](https://github.com/FOI-Bioinformatics/nanometa_live) and covers
quality control (Chopper, FASTP, NanoPlot), taxonomic classification (Kraken2),
and validation (BLAST, minimap2). Real-time and batch execution modes are
supported.

Capabilities:

- Real-time FASTQ monitoring during a sequencing run, using Nextflow `watchPath`
- Streaming Kraken2 architecture (v1.5+) with per-sample parallelism, append-only
  batch storage, and incremental taxid counting
- POD5 basecalling via Dorado (GPU optional)
- Pre-demultiplexed barcode directory support (flat or per-barcode layouts)
- Adaptive batching and configurable backpressure for high-throughput runs
- nf-core compliance with an extensive nf-test suite

## Quick start

The recommended environment is the `nf-core` conda environment with Nextflow
25.10 or later.

QC only:

```bash
nextflow run foi-bioinformatics/nanometanf \
    --input samplesheet.csv \
    --outdir results \
    -profile conda
```

Full analysis with classification:

```bash
nextflow run foi-bioinformatics/nanometanf \
    --input samplesheet.csv \
    --kraken2_db /path/to/kraken2_db \
    --outdir results \
    -profile conda
```

CI smoke test (Docker is used in CI; locally use conda):

```bash
nextflow run foi-bioinformatics/nanometanf -profile test,docker --outdir test_results
```

<details>
<summary>Real-time monitoring examples</summary>

```bash
# Watch a directory during sequencing
nextflow run foi-bioinformatics/nanometanf \
    --realtime_mode \
    --nanopore_output_dir /path/to/fastq \
    --kraken2_db /path/to/db \
    --outdir results \
    -profile conda

# High-throughput real-time with the streaming classifier (v1.5+)
nextflow run foi-bioinformatics/nanometanf \
    --realtime_mode \
    --kraken2_enable_incremental true \
    --max_classification_forks 8 \
    --max_concurrent_batches 4 \
    --nanopore_output_dir /path/to/fastq \
    --kraken2_db /path/to/db \
    --outdir results \
    -profile conda
```

</details>

## Streaming classification architecture (v1.5+)

For runs with many barcodes (more than ten), the pipeline uses a streaming
Kraken2 architecture with the following properties:

- **Per-sample parallelism.** Merger and report modules no longer use
  `maxForks 1` globally; samples are processed independently.
- **Append-only batch storage.** Each batch is written to its own file with an
  atomic JSON index. Cumulative output is rebuilt only at end of session,
  giving O(1) per batch instead of O(n) cumulative rewrites.
- **Incremental taxid counting.** Per-sample state files accumulate counts
  without re-reading prior outputs.
- **Backpressure controls.** `max_concurrent_batches` and
  `max_classification_forks` limit concurrency.

Internal benchmarks measure roughly four to five times higher throughput on
runs with twelve or more barcodes compared with the previous architecture.

```bash
nextflow run foi-bioinformatics/nanometanf \
    --realtime_mode \
    --kraken2_enable_incremental true \
    --max_concurrent_batches 4 \
    --max_classification_forks 8 \
    ...
```

## Deployment profiles

Hardware-specific profiles set resource defaults for different sequencer
platforms and deployment scenarios. Combine with an execution-engine profile
(`conda`, `docker`, or `singularity`).

| Profile         | Use case              | Description |
|-----------------|-----------------------|-------------|
| `test`          | CI and validation     | Minimal dataset with reduced resources for fast tests |
| `minion`        | MinION / Mk1C         | Conservative memory and CPU allocation |
| `promethion`    | PromethION (standard) | Higher throughput defaults |
| `promethion_8`  | PromethION (8-barcode)| Tuned for multiplexed PromethION runs |
| `field`         | Field deployments     | Reduced resource footprint for laptops |

Examples:

```bash
# PromethION run on a workstation with conda
nextflow run foi-bioinformatics/nanometanf -profile promethion,conda --input samplesheet.csv

# MinION field run with conda and real-time monitoring
nextflow run foi-bioinformatics/nanometanf -profile minion,conda \
    --input samplesheet.csv --realtime_mode

# CI smoke test
nextflow run foi-bioinformatics/nanometanf -profile test,docker
```

For additional resource tuning, see `conf/production.config`.

## Documentation

[Documentation index](docs/README.md).

User documentation:

- [Usage guide](docs/usage.md) -- parameters and execution modes
- [Output reference](docs/output.md) -- directory layout and file formats
- [Quick start](docs/user/quickstart.md) -- scenario-based walkthrough
- [Real-time processing](docs/user/realtime_processing.md)
- [Performance tuning](docs/user/performance_tuning.md)
- [Troubleshooting](docs/user/troubleshooting.md)

Development documentation:

- [Development guide](docs/development/README.md)
- [Testing guide](docs/development/TESTING.md) -- nf-test conventions
- [CLAUDE.md](CLAUDE.md) -- developer notes for AI-assisted work

Release information:

- [Current version](docs/releases/CURRENT_VERSION.md)
- [Release notes](docs/releases/)
- [Migration guide](docs/releases/MIGRATION_GUIDE.md)

## Pipeline summary

```
Input -> QC -> Classification -> Validation -> Reports
  |       |          |                |            |
FASTQ  Chopper    Kraken2          BLAST       MultiQC
       FASTP    (streaming)       minimap2     JSON
       NanoPlot Taxpasta                       HTML
```

Supported inputs:

1. FASTQ samplesheet (standard batch analysis)
2. Pre-demultiplexed barcode directories (automated discovery)
3. Real-time FASTQ monitoring (during sequencing)

See the [usage guide](docs/usage.md) for parameter details.

## Credits

nanometanf was originally written by Andreas Sjodin
([@andreassjodin](https://github.com/andreassjodin)).

The pipeline is built on the nf-core framework. We thank the nf-core community
and the developers of the integrated tools.

## Citations

If you use nanometanf in your work, please cite:

> **nanometanf: an Oxford Nanopore sequencing analysis pipeline.**
>
> Andreas Sjodin. _GitHub_ 2025. DOI to be assigned upon Zenodo deposit.

A full list of tool references is available in [CITATIONS.md](CITATIONS.md).

The nf-core framework reference:

> **The nf-core framework for community-curated bioinformatics pipelines.**
>
> Philip Ewels, Alexander Peltzer, Sven Fillinger, Harshil Patel, Johannes
> Alneberg, Andreas Wilm, Maxime Ulysse Garcia, Paolo Di Tommaso, Sven Nahnsen.
>
> _Nat Biotechnol._ 2020 Feb 13. doi: [10.1038/s41587-020-0439-x](https://dx.doi.org/10.1038/s41587-020-0439-x).

## License

Released under the MIT License. See [LICENSE](LICENSE).
