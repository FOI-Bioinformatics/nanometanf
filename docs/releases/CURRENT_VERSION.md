# Current Version Status

**Last Updated:** 2025-01-26

---

## Recommended Versions

### Production: v1.2.0 (Stable)

**Release Date:** 2025-10-16
**Status:** Stable LTS
**nf-core Compliance:** 100%

**Use for:** Production deployments, critical analyses, publication-quality data.

### Development: v1.5.0dev (Active Development)

**Status:** Development
**nf-core Compliance:** 96%

**New in v1.5.0dev:**
- Scalable streaming architecture for high-throughput real-time processing
- Per-sample parallelism (no global serialization bottlenecks)
- Append-only batch storage (O(1) per batch)
- Incremental taxid counting
- Backpressure control parameters
- 4-5x throughput improvement for runs with >10 barcodes

---

## Version Matrix

| Version | Status | Release Date | Recommendation |
|---------|--------|--------------|----------------|
| **v1.2.0** | Stable | 2025-10-16 | **Production use** |
| v1.3.0 | Broken | 2025-10-19 | **Do not use** |
| v1.3.1 | Hotfix | 2025-10-20 | Testing only |
| v1.3.3 | Beta | 2025-10-25 | Advanced features, test first |
| **v1.5.0dev** | Dev | Ongoing | Scalable streaming, developers |

---

## Critical Issue: v1.3.0 is Broken

**DO NOT USE v1.3.0** - Missing modules cause parse-time error.

**Error:** `No such variable: KRAKEN2_INCREMENTAL_CLASSIFIER`

Use v1.2.0 (stable) or v1.5.0dev (development with scalable streaming).

---

## Version Selection Guide

### For Production
Use **v1.2.0** for proven stability and reliability.

### For High-Throughput Real-time Processing
Use **v1.5.0dev** if you need:
- Processing >10 barcodes simultaneously
- Improved CPU utilization (70-90% vs 15-20%)
- Higher throughput (50-75 files/sec vs 10-15 files/sec)

### For Development
Use **v1.5.0dev** (dev branch) for contributing or testing new features.

---

## Key Features by Version

### v1.2.0 (Current Stable)
- Chopper as default QC tool (7x faster than NanoFilt)
- Multi-tool QC support
- 100% nf-core compliance
- Dorado 1.1.1 compatibility

### v1.5.0dev (Development)

**Scalable Streaming Architecture:**
- Per-sample parallel processing (removed `maxForks 1` bottleneck)
- Append-only batch file storage
- Incremental taxid counting without cumulative file re-reads
- Atomic index updates to prevent race conditions
- End-of-session aggregation for final cumulative files

**New Parameters:**
```bash
--max_concurrent_batches 4    # Backpressure limit per sample
--max_classification_forks 8  # Max parallel Kraken2 jobs
--kraken2_sync_interval 10    # Batches between report regeneration
```

**New Output Structure:**
```
outdir/kraken2/{sample_id}/
├── batches/batch_N.kraken2.output.txt
├── batch_reports/batch_N.kraken2.report.txt
├── index.json
└── taxid_counts.json
```

---

## Installation

```bash
# Stable version (recommended for production)
nextflow run foi-bioinformatics/nanometanf -r v1.2.0 \
  --input samplesheet.csv \
  --outdir results \
  -profile docker

# Development version (scalable streaming)
nextflow run foi-bioinformatics/nanometanf -r dev \
  --realtime_mode \
  --kraken2_enable_incremental true \
  --input samplesheet.csv \
  --outdir results \
  -profile docker
```

---

## Migration Paths

### From v1.2.0 to v1.5.0dev

**Breaking Changes:** None for standard usage.

**New Directory Structure:** If using incremental Kraken2, output structure has changed to per-sample directories with batch files. Nanometa Live JSON outputs remain unchanged.

**Action Required:** Test with your data before production use.

---

## Quick Links

- **[Release Notes](./)**
- **[Migration Guide](MIGRATION_GUIDE.md)**
- **[Changelog](../../CHANGELOG.md)**
- **[GitHub Releases](https://github.com/foi-bioinformatics/nanometanf/releases)**

---

**Maintained By:** foi-bioinformatics team
**Update Frequency:** On each release
