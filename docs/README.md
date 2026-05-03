# nanometanf documentation

Documentation index for the nanometanf Nextflow pipeline.

## User documentation

| Document                                                  | Purpose |
|-----------------------------------------------------------|---------|
| [Quick start](user/quickstart.md)                         | Scenario-based walkthrough |
| [Usage guide](usage.md)                                   | Parameters and execution modes |
| [Output reference](output.md)                             | Output directory layout and file formats |
| [QC guide](user/qc_guide.md)                              | Quality metrics |
| [Troubleshooting](user/troubleshooting.md)                | Common issues and resolutions |
| [Best practices](user/best_practices.md)                  | Workflow recommendations |
| [Performance tuning](user/performance_tuning.md)          | Resource optimisation |
| [Real-time processing](user/realtime_processing.md)       | Live monitoring guide |
| [Platform optimisations](user/OPTIMIZATIONS_QUICK_REFERENCE.md) | Per-platform tuning reference |

`docs/usage.md` and `docs/output.md` follow the nf-core convention and are
the canonical references for parameters and output, respectively.

## Developer documentation

| Document                                                | Purpose |
|---------------------------------------------------------|---------|
| [Development guide](development/README.md)              | Developer index |
| [Testing guide](development/TESTING.md)                 | nf-test conventions and runner |
| [Test organisation](development/test_organization.md)   | Layout of the test suite |
| [Developer API](development/developer_api.md)           | Internal APIs and helpers |
| [Implementation plan](development/IMPLEMENTATION_PLAN.md)| Roadmap and design notes |
| [Streaming Kraken2 implementation](development/incremental_kraken2_implementation.md) | v1.5+ classification architecture |
| [nf-core module maintenance](development/nfcore_module_maintenance.md) | Local modifications to upstream modules |
| [PromethION optimisations](development/PROMETHION_OPTIMIZATIONS.md) | Platform-specific tuning notes |
| [Production deployment](development/production_deployment.md) | Deployment guide |
| [Release process](development/RELEASE_PROCESS.md)       | Release procedures |
| [Phase 1.1 status](development/PHASE_1.1_STATUS.md)     | Feature status report |
| [v1.0 roadmap](development/v1_0_roadmap.md)             | Historical v1.0 roadmap |
| [Evaluation summary](development/EVALUATION_SUMMARY.md) | Production-readiness evaluation |

## Release information

| Document                                            | Purpose |
|-----------------------------------------------------|---------|
| [Current version](releases/CURRENT_VERSION.md)      | Version recommendations and known issues |
| [Migration guide](releases/MIGRATION_GUIDE.md)      | Upgrade instructions |
| [Release notes](releases/)                          | Per-version release notes |
| [Changelog](../CHANGELOG.md)                        | Cumulative change log |

## Other reference

- [Meta fields](meta_fields.md) -- channel `meta` map keys
- [Production readiness report](production-readiness-report.md)
- [Integration: output API](integration/output_api.md)
- [Performance: QC benchmarks](performance/qc_benchmarks.md)
- [Validation: test coverage](validation/test_coverage_report.md)
- [Validation: v1.3.0 testing plan](validation/V1_3_0_TESTING_PLAN.md)
- [Validation: v1.3.0 warning](validation/v1.3.0_warning.md)
- [Upstream issue #26: watchPath cleanup](upstream-issues/26-watchpath-cleanup-hang.md)

The `audit-*.md`, `plans/`, and `development/archive/` directories contain
dated audit reports and design plans from development cycles. They are
preserved as a historical record but should not be treated as current
specifications -- the code is the source of truth.

## Pipeline summary

Six execution modes are supported:

1. Standard FASTQ samplesheet (batch)
2. Pre-demultiplexed barcode directories (automated discovery)
3. Singleplex POD5 basecalling (single sample, Dorado)
4. Multiplex POD5 with demultiplexing
5. Real-time FASTQ monitoring during sequencing
6. Real-time POD5 processing (basecalling and analysis)

A canonical output layer (`results/canonical/`) writes tool-agnostic TSV
files for classification, QC, validation, and assembly, indexed by a
`_manifest.json`. Controlled by `--write_canonical` (default: true).

The streaming classification architecture (v1.5+) provides per-sample
parallelism, append-only batch storage, and incremental taxid counting.
See [`development/incremental_kraken2_implementation.md`](development/incremental_kraken2_implementation.md).

## Root files

- [README](../README.md) -- pipeline overview and quick start
- [CLAUDE.md](../CLAUDE.md) -- developer notes
- [CHANGELOG.md](../CHANGELOG.md)
- [CITATIONS.md](../CITATIONS.md)
- [SECURITY.md](../SECURITY.md)
- [CONTRIBUTING](../.github/CONTRIBUTING.md)
- [Pull request template](../.github/PULL_REQUEST_TEMPLATE.md)

---

**Version:** 1.5.1dev
**Last updated:** 2026-05-03
