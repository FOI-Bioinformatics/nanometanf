# foi-bioinformatics/nanometanf

[![GitHub Actions CI Status](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/nf-test.yml/badge.svg)](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/nf-test.yml)
[![GitHub Actions Linting Status](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/linting.yml/badge.svg)](https://github.com/foi-bioinformatics/nanometanf/actions/workflows/linting.yml)
[![nf-test](https://img.shields.io/badge/unit_tests-nf--test-337ab7.svg)](https://www.nf-test.com)

[![Nextflow](https://img.shields.io/badge/version-%E2%89%A524.10.5-green?style=flat&logo=nextflow&logoColor=white&color=%230DC09D&link=https%3A%2F%2Fnextflow.io)](https://www.nextflow.io/)
[![nf-core template version](https://img.shields.io/badge/nf--core_template-3.3.2-green?style=flat&logo=nfcore&logoColor=white&color=%2324B064&link=https%3A%2F%2Fnf-co.re)](https://github.com/nf-core/tools/releases/tag/3.3.2)
[![run with conda](http://img.shields.io/badge/run%20with-conda-3EB049?labelColor=000000&logo=anaconda)](https://docs.conda.io/en/latest/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)
[![Launch on Seqera Platform](https://img.shields.io/badge/Launch%20%F0%9F%9A%80-Seqera%20Platform-%234256e7)](https://cloud.seqera.io/launch?pipeline=https://github.com/foi-bioinformatics/nanometanf)

## Introduction

**foi-bioinformatics/nanometanf** is a bioinformatics pipeline for comprehensive analysis of Oxford Nanopore long-read sequencing data with real-time processing capabilities. This directory contains the core workflow definitions.

For complete documentation, usage instructions, and examples, please see the [main README](../README.md) in the project root directory.

## Workflow Components

1. **Basecalling** - Dorado POD5 basecalling with GPU acceleration
2. **Quality Control** - Chopper/FASTP/Filtlong with nanopore optimization
3. **Taxonomic Classification** - Kraken2 metagenomic profiling
4. **Validation** - Optional BLAST validation
5. **Real-time Monitoring** - Continuous file processing during sequencing

## Usage

> [!NOTE]
> If you are new to Nextflow and nf-core, please refer to [this page](https://nf-co.re/docs/usage/installation) on how to set-up Nextflow. Make sure to [test your setup](https://nf-co.re/docs/usage/introduction#how-to-run-a-pipeline) with `-profile test` before running the workflow on actual data.

```bash
nextflow run foi-bioinformatics/nanometanf \
   -profile docker \
   --input samplesheet.csv \
   --outdir results
```

For detailed usage instructions, parameter descriptions, and advanced configurations, see the [main documentation](../README.md).

> [!WARNING]
> Please provide pipeline parameters via the CLI or Nextflow `-params-file` option. Custom config files including those provided by the `-c` Nextflow option can be used to provide any configuration _**except for parameters**_; see [docs](https://nf-co.re/docs/usage/getting_started/configuration#custom-configuration-files).

## Credits

foi-bioinformatics/nanometanf was originally written by Andreas Sjödin.

## Contributions and Support

If you would like to contribute to this pipeline, please see the [contributing guidelines](../.github/CONTRIBUTING.md).

## Citations

If you use foi-bioinformatics/nanometanf for your analysis, please cite it as described in the [main README](../README.md#citations).

An extensive list of references for the tools used by the pipeline can be found in the [`CITATIONS.md`](CITATIONS.md) file.

This pipeline uses code and infrastructure developed and maintained by the [nf-core](https://nf-co.re) community, reused here under the [MIT license](https://github.com/nf-core/tools/blob/main/LICENSE).

> **The nf-core framework for community-curated bioinformatics pipelines.**
>
> Philip Ewels, Alexander Peltzer, Sven Fillinger, Harshil Patel, Johannes Alneberg, Andreas Wilm, Maxime Ulysse Garcia, Paolo Di Tommaso & Sven Nahnsen.
>
> _Nat Biotechnol._ 2020 Feb 13. doi: [10.1038/s41587-020-0439-x](https://dx.doi.org/10.1038/s41587-020-0439-x).
