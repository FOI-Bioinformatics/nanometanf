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

**nanometanf** is a comprehensive bioinformatics pipeline for Oxford Nanopore long-read sequencing data analysis with real-time processing capabilities. It serves as the computational backend for Nanometa Live, supporting POD5 basecalling (Dorado), quality control (Chopper, FASTP, NanoPlot), taxonomic classification (Kraken2), and validation workflows (BLAST) optimized for metagenomics and genomics applications.

**Key Features:**
- Real-time POD5/FASTQ monitoring during active sequencing
- Seven execution modes supporting diverse laboratory workflows
- Intelligent resource optimization (experimental)
- Production-ready with 94 nf-tests and full nf-core compliance

## Quick Start

```bash
# Test the pipeline
nextflow run foi-bioinformatics/nanometanf -profile test,docker

# Run with your data (samplesheet)
nextflow run foi-bioinformatics/nanometanf \
  --input samplesheet.csv \
  --outdir results \
  -profile docker

# Real-time POD5 monitoring with basecalling
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --use_dorado \
  --nanopore_output_dir /path/to/pod5 \
  --dorado_model dna_r10.4.1_e4.3_400bps_hac \
  --outdir results \
  -profile docker
```

## Documentation

📚 **[Complete Documentation](docs/README.md)** - Main documentation hub

### For Users
- **[Usage Guide](docs/user/usage.md)** - Complete parameter reference and execution modes
- **[Quick Start Tutorial](docs/user/quickstart.md)** - 5-minute scenario-based walkthrough
- **[Output Files](docs/user/output.md)** - Output directory structure and file descriptions
- **[QC Guide](docs/user/qc_guide.md)** - Quality control metrics interpretation
- **[Best Practices](docs/user/best_practices.md)** - Workflow recommendations
- **[Performance Tuning](docs/user/performance_tuning.md)** - Resource optimization and benchmarks
- **[Troubleshooting](docs/user/troubleshooting.md)** - Common issues and solutions
- **[Real-time Processing](docs/user/realtime_processing.md)** - Advanced real-time monitoring guide

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
Input → Basecalling → QC → Classification → Validation → Reports
  ↓        ↓          ↓        ↓              ↓            ↓
POD5    Dorado    Chopper  Kraken2         BLAST       MultiQC
FASTQ              FASTP     Taxpasta                    JSON
Barcodes         NanoPlot                              HTML
```

**Supported Input Types:**
1. FASTQ samplesheet (standard batch analysis)
2. Pre-demultiplexed barcode directories (automated discovery)
3. POD5 files with Dorado basecalling (singleplex or multiplex)
4. Real-time monitoring (POD5 or FASTQ, during sequencing)

See [Usage Guide](docs/user/usage.md) for detailed instructions.

## Credits

nanometanf was originally written by Andreas Sjodin ([@andreassjodin](https://github.com/andreassjodin)).

We thank the following people for their extensive assistance in the development of this pipeline:

- The nf-core community for the excellent framework and tools
- Oxford Nanopore Technologies for Dorado and POD5 format
- All tool developers whose software is integrated in this pipeline

## Citations

If you use nanometanf for your analysis, please cite:

> **nanometanf: Comprehensive Oxford Nanopore sequencing analysis pipeline**
>
> Andreas Sjodin
>
> _GitHub_ 2025. doi: [10.5281/zenodo.XXXXXXX](https://doi.org/10.5281/zenodo.XXXXXXX)

An extensive list of references for the tools used by the pipeline can be found in [CITATIONS.md](CITATIONS.md).

You can cite the `nf-core` publication as follows:

> **The nf-core framework for community-curated bioinformatics pipelines.**
>
> Philip Ewels, Alexander Peltzer, Sven Fillinger, Harshil Patel, Johannes Alneberg, Andreas Wilm, Maxime Ulysse Garcia, Paolo Di Tommaso & Sven Nahnsen.
>
> _Nat Biotechnol._ 2020 Feb 13. doi: [10.1038/s41587-020-0439-x](https://dx.doi.org/10.1038/s41587-020-0439-x).

## License

This pipeline is released under the MIT License. See [LICENSE](LICENSE) for details.
