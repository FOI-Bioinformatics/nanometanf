# Current version status

**Last updated:** 2026-05-04

---

## Recommended versions

### Production: v1.5.0

**Release date:** 2026-04 (initial; v1.5.x is the active line)
**nf-core compliance:** 96/100

Streaming Kraken2 architecture with per-sample parallelism, append-only
batch storage, incremental taxid counting, and backpressure controls.
Internal benchmarks show roughly 4-5x throughput improvement on runs
with 12+ barcodes compared with v1.3.x. Use this for new deployments.

See [`v1.5.0.md`](v1.5.0.md) for the full release notes.

### Development: v1.5.1dev

**Status:** active development on the `dev` branch
**Stability:** unstable; expect schema and parameter changes between
commits.

Use for contributing or for testing fixes before they ship.

---

## Version matrix

| Version    | Status         | Recommendation                                  |
|------------|----------------|--------------------------------------------------|
| v1.5.1dev  | Development    | Contributors and pre-release testing             |
| **v1.5.0** | **Production** | **Use this**                                     |
| v1.3.3     | Beta           | Superseded by v1.5.0                             |
| v1.3.1     | Hotfix         | Superseded by v1.5.0                             |
| v1.3.0     | **Broken**     | **Do not use** -- parse-time error               |
| v1.2.0     | Legacy stable  | Use only if v1.5.0 cannot be deployed            |

---

## Critical issue: v1.3.0 is broken

v1.3.0 fails at parse time with `No such variable:
KRAKEN2_INCREMENTAL_CLASSIFIER`. The hotfix v1.3.1 was published the
following day; v1.5.0 is the current recommended version. Full
details and the original release-note record are at
[`v1.3.0.md`](v1.3.0.md) (with a banner at the top) and
[`docs/validation/v1.3.0_warning.md`](../validation/v1.3.0_warning.md).

---

## Version selection guide

### For production

Use **v1.5.0**. The v1.5 line incorporates everything from the v1.3.x
line (PromethION optimizations, multi-tool QC, Chopper as default) plus
the streaming classification architecture.

### For high-throughput real-time runs

Use **v1.5.0** with `--kraken2_enable_incremental true` and
appropriate values for `--max_concurrent_batches` and
`--max_classification_forks`. See
[`docs/user/realtime_processing.md`](../user/realtime_processing.md).

### For development

Use the `dev` branch (currently v1.5.1dev) for contributing or testing
features that have not yet shipped.

---

## Key v1.5.0 features

**Streaming classification architecture:**

- Per-sample parallel processing (no global `maxForks 1` bottleneck)
- Append-only batch file storage
- Incremental taxid counting without cumulative file re-reads
- Atomic index updates to prevent race conditions
- End-of-session aggregation for final cumulative files

**Concurrency parameters (defaults shown):**

```bash
--max_concurrent_batches 4     # Backpressure limit per sample
--max_classification_forks 8   # Max parallel Kraken2 jobs
--kraken2_sync_interval 10     # Batches between report regeneration
--kraken2_enable_incremental true
```

**Output structure (per sample):**

```
outdir/kraken2/{sample_id}/
|-- batches/batch_N.kraken2.output.txt
|-- batch_reports/batch_N.kraken2.report.txt
|-- index.json
|-- taxid_counts.json
`-- stats/
```

End-of-session aggregation rebuilds the cumulative
`{sample_id}.cumulative.kraken2.{output,report}.txt` files; the
dashboard updates progressively from `batch_reports/` during a run.

---

## Installation

```bash
# Production (v1.5.0)
nextflow run foi-bioinformatics/nanometanf -r 1.5.0 \
    --input samplesheet.csv \
    --outdir results \
    -profile conda

# Development (dev branch)
nextflow run foi-bioinformatics/nanometanf -r dev \
    --realtime_mode \
    --kraken2_enable_incremental true \
    --input samplesheet.csv \
    --outdir results \
    -profile conda
```

The conda profile is recommended; `docker` and `singularity` are also
supported.

---

## Migration paths

### From v1.2.0 to v1.5.0

No breaking changes for standard usage. New optional concurrency
parameters; the output directory layout for Kraken2 has moved to
per-sample subdirectories with `batches/` and `batch_reports/`.
Nanometa Live JSON outputs are unchanged.

See [`MIGRATION_GUIDE.md`](MIGRATION_GUIDE.md) for the parameter
mapping and a step-by-step upgrade.

### From v1.3.x to v1.5.0

The v1.3.x stream-classifier-as-flag work is replaced by the integrated
streaming architecture in v1.5. Remove any references to
`KRAKEN2_INCREMENTAL_CLASSIFIER` in custom configs (the module is
internal and should not be referenced directly). The
`--kraken2_enable_incremental` parameter remains.

---

## Quick links

- [Release notes index](./)
- [v1.5.0](v1.5.0.md) -- current release
- [Migration guide](MIGRATION_GUIDE.md)
- [Changelog](../../CHANGELOG.md)
- [GitHub releases](https://github.com/foi-bioinformatics/nanometanf/releases)

---

**Maintained by:** foi-bioinformatics team
**Update frequency:** at each release.
