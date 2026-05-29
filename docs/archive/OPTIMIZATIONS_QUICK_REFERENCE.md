# PromethION Optimisations - Quick Reference

**Pipeline version (introduced):** 1.3.0
**Date:** 2025-10-19

---

## Performance at a Glance (internal benchmark, 30 batches)

| Metric                        | Baseline          | With optimisations | Change         |
| ----------------------------- | ----------------- | ------------------ | -------------- |
| **Compute time** (30 batches) | ~324 min (~5.4 h) | ~18 min (~0.3 h)   | ~94% reduction |
| **Time saved**                | -                 | ~306 min (~5.1 h)  | ~18x speedup   |

Figures are from a single internal scenario with 30 batches; smaller runs see less gain.

---

## Quick Start: Choosing Your Profile

```bash
# Single Sample (Clinical Diagnostics)
nextflow run foi-bioinformatics/nanometanf \
  -profile minion,conda \
  --input sample.csv \
  --realtime_mode \
  --kraken2_db /databases/kraken2 \
  --outdir results/

# 8 Samples (Environmental Monitoring)
nextflow run foi-bioinformatics/nanometanf \
  -profile promethion_8,conda \
  --input environmental.csv \
  --realtime_mode \
  --kraken2_db /databases/kraken2 \
  --outdir results/

# 24 Samples (Wastewater Surveillance)
nextflow run foi-bioinformatics/nanometanf \
  -profile promethion,conda \
  --input wastewater.csv \
  --realtime_mode \
  --kraken2_db /databases/kraken2 \
  --outdir results/
```

---

## Profile Comparison

| Profile          | Sample Count | CPUs/Kraken2 | Parallel Samples (24-core) | Best For                                        |
| ---------------- | ------------ | ------------ | -------------------------- | ----------------------------------------------- |
| **minion**       | 1-4          | 8            | 3                          | Clinical diagnostics, single pathogen ID        |
| **promethion_8** | 5-12         | 6            | 4                          | Environmental surveys, metagenomic studies      |
| **promethion**   | 12-24+       | 4            | 6                          | Wastewater monitoring, large-scale surveillance |

**Throughput, 720-task internal scenario:**

- **minion**: ~12 hours (~1.7x speedup)
- **promethion_8**: ~10.5 hours (~1.9x speedup)
- **promethion**: ~10 hours (~2.0x speedup)

---

## Optimisation Phases

### Phase 1: Core Processing (automatic with `--realtime_mode`)

| Optimisation                 | Internal-benchmark savings | Auto-enabled            |
| ---------------------------- | -------------------------- | ----------------------- |
| **1.1** Incremental Kraken2  | ~30-90 min                 | yes (`--realtime_mode`) |
| **1.2** QC stats aggregation | ~5-15 min                  | yes (`--realtime_mode`) |
| **1.3** Conditional NanoPlot | ~54-81 min                 | yes (`--realtime_mode`) |
| **1.4** Deferred MultiQC     | ~3-9 min                   | yes (`--realtime_mode`) |

### Phase 2: Database Preloading (automatic)

| Feature                        | Internal-benchmark savings | Auto-enabled            |
| ------------------------------ | -------------------------- | ----------------------- |
| Memory-mapped database loading | ~30-90 min                 | yes (`--realtime_mode`) |

### Phase 3: Platform Profiles (manual selection)

| Profile      | Resource Strategy    | When to Use                      |
| ------------ | -------------------- | -------------------------------- |
| minion       | Max per-sample speed | 1-4 samples, urgent cases        |
| promethion_8 | Balanced             | 5-12 samples, routine monitoring |
| promethion   | Max throughput       | 12-24+ samples, large studies    |

---

## Automatic vs Manual Control

### Automatic (no configuration)

When you use `--realtime_mode` or any platform profile:

- Incremental Kraken2 classification
- QC statistics aggregation
- Conditional NanoPlot execution
- Deferred MultiQC
- Memory-mapped database loading

Just add: `-profile minion`, `-profile promethion_8`, or `-profile promethion`.

### Manual Override

```bash
# Disable specific optimizations
--kraken2_enable_incremental false
--qc_enable_incremental false
--nanoplot_realtime_skip_intermediate false

# Adjust intervals
--nanoplot_batch_interval 5  # Run every 5th batch (default: 10)

# Disable automatic enablement
--kraken2_memory_mapping false
--multiqc_realtime_final_only false
```

---

## Key Files

### Configuration

- `conf/minion.config` - Single sample optimization (8 CPUs/Kraken2)
- `conf/promethion_8.config` - Balanced optimization (6 CPUs/Kraken2)
- `conf/promethion.config` - High throughput (4 CPUs/Kraken2)

### Subworkflows

- `subworkflows/local/taxonomic_classification/main.nf` - Phases 1.1, 2
- `subworkflows/local/qc_analysis/main.nf` - Phases 1.2, 1.3
- `workflows/nanometanf.nf` - Phase 1.4

### Modules

- `modules/local/seqkit_merge_stats/` - QC stats aggregation
- `modules/local/kraken2_incremental_classifier/` - Incremental classification
- `modules/local/kraken2_output_merger/` - Batch output merging
- `modules/local/kraken2_report_generator/` - Cumulative report generation

---

## Per-Phase Notes (internal benchmark, 30 batches)

### Phase 1.1: Incremental Kraken2

- **Problem**: O(n^2) re-classification complexity
- **Approach**: batch-level caching + final merge
- **Savings**: ~30-90 minutes
- **Example**: 30 batches x 4 min each = 120 min -> ~4 min final merge

### Phase 1.2: QC Stats Aggregation

- **Problem**: redundant SeqKit recalculations
- **Approach**: weighted statistical merging (weights by sequence length)
- **Savings**: ~5-15 minutes

### Phase 1.3: Conditional NanoPlot

- **Problem**: NanoPlot ran every batch (~3 min x 30 = ~90 min)
- **Approach**: run only every Nth batch + final
- **Savings**: ~54-81 minutes (~90 min -> ~9 min at every 10th batch)

### Phase 1.4: Deferred MultiQC

- **Problem**: repeated file parsing
- **Approach**: `.collect()` waits for completion, MultiQC runs once
- **Savings**: ~3-9 minutes (~18 sec x 30 batches -> 1 final run)

### Phase 2: Database Preloading

- **Problem**: Kraken2 DB loaded each batch (~3 min each)
- **Approach**: memory-mapped loading via OS page cache
- **Savings**: ~30-90 minutes (first load ~3 min, subsequent near-instant)

### Phase 3: Platform Profiles

- **Problem**: one-size-fits-all resource allocation
- **Approach**: platform-specific CPU/memory tuning
- **Effect**: roughly 2-6x throughput improvement on the corresponding workloads

---

## Troubleshooting

### Optimizations Not Activating

**Check**: Is `--realtime_mode` enabled OR using a platform profile?

```bash
# Either of these will activate optimizations
--realtime_mode
-profile minion
-profile promethion_8
-profile promethion
```

### Database Not Being Cached

**Check**: Kraken2 optimizations enabled in real-time mode

```bash
# Automatic with real-time mode
--realtime_mode

# Or manually enable
--kraken2_use_optimizations true
--kraken2_memory_mapping true
```

### NanoPlot Still Running Every Batch

**Check**: Conditional execution enabled

```bash
# Should be automatic with --realtime_mode
--nanoplot_realtime_skip_intermediate true

# Verify interval setting
--nanoplot_batch_interval 10  # Default: every 10th batch
```

### Wrong Profile for Sample Count

| Samples | Recommended Profile | Why                      |
| ------- | ------------------- | ------------------------ |
| 1-4     | minion              | Fastest per-sample speed |
| 5-12    | promethion_8        | Balanced resources       |
| 12-24+  | promethion          | Maximum throughput       |

---

## Validation

**Correctness:**

- Final Kraken2 reports match non-incremental mode
- QC statistics match a full recalculation within floating-point precision
- NanoPlot results match full runs
- MultiQC report contains the expected sections

**Performance (in our testing):**

- Linear, not quadratic, scaling with batch count
- ~94% reduction in compute time on the 30-batch scenario
- ~2-6x throughput improvement with platform profiles

---

## Further Reading

- **Comprehensive Technical Documentation**: `docs/development/PROMETHION_OPTIMIZATIONS.md`
- **Developer Guide**: `CLAUDE.md` (Section 6: PromethION Optimizations)
- **Platform Config Files**: `conf/minion.config`, `conf/promethion_8.config`, `conf/promethion.config`

---

## Contact

- **Implementation**: Andreas Sjödin (FOI)
- **Date**: 2025-10-19
- **Pipeline version (introduced)**: 1.3.0
