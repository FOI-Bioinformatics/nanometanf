# Real-time Processing Guide

Live sequencing analysis with nanometanf during active Oxford Nanopore runs.

**Prerequisites:** Familiarity with [usage.md](../usage.md) and ONT sequencing workflows.

---

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Real-time Modes](#real-time-modes)
- [Advanced Features](#advanced-features)
- [Platform Optimization](#platform-optimization)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Performance Tuning](#performance-tuning)

---

## Overview

### What is Real-time Processing?

Real-time processing analyses sequencing data **during** an active run, returning results as files arrive rather than after the run completes.

**Use cases:**

- See classifications minutes after reads are generated
- Stop runs early once a target is detected (or ruled out)
- Avoid waiting for run completion before downstream work
- Adjust parameters based on incoming data

### How It Works

```
Sequencing Device → File Generation → nanometanf Monitor → Analysis → Results
     (MinION)          (POD5/FASTQ)       (watchPath)      (Pipeline)  (Live)
```

**Process:**

1. Sequencer writes POD5 or FASTQ files to output directory
2. nanometanf monitors directory for new files (using Nextflow's `watchPath`)
3. Files are batched and processed as they arrive
4. Results appear in output directory in real-time
5. Monitoring continues until timeout or manual stop

### When to Use Real-time Mode

Suitable for:

- Clinical pathogen detection (urgent diagnosis)
- Contamination screening (early detection)
- Adaptive sequencing decisions (run until target coverage reached)
- Live dashboard visualisation (Nanometa Live)
- Quality monitoring during the run

Not recommended for:

- Archival data analysis (use standard mode)
- Batch processing of multiple completed runs
- Workflows that require deterministic, order-independent results
- Resource-constrained systems (real-time mode is CPU-intensive)

---

## Quick Start

### Basic Real-time FASTQ Monitoring

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --nanopore_output_dir /path/to/sequencing/output \
  --file_pattern "**/*.fastq{,.gz}" \
  --kraken2_db /databases/k2_standard \
  --realtime_timeout_minutes 30 \
  --outdir results/live_run \
  -profile conda
```

### Real-time POD5 with Basecalling

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --use_dorado \
  --nanopore_output_dir /path/to/sequencing/pod5_pass \
  --file_pattern "**/*.pod5" \
  --dorado_model dna_r10.4.1_e4.3_400bps_hac \
  --kraken2_db /databases/k2_standard \
  --realtime_timeout_minutes 30 \
  --outdir results/live_run \
  -profile conda
```

**What happens:**

1. Pipeline starts monitoring the specified directory
2. As files appear, they're batched (default: 10 files/batch)
3. Each batch is processed: basecalling (if POD5) → QC → classification
4. Results appear in `outdir` progressively
5. After 30 minutes of no new files, pipeline stops gracefully

---

## Real-time modes

The three real-time modes (FASTQ monitoring, POD5 with basecalling,
pre-demultiplexed barcoded input) are documented as Modes 5 and 6 in
the [usage guide](../usage.md#execution-modes). This document covers
the advanced features that build on top of those modes; refer to
`usage.md` for the basic invocation patterns.

---

## Advanced features

### Two-stage Timeout with Grace Period (v1.3.3+)

A single timeout can stop processing while downstream tasks are still running. The two-stage system separates file-detection timeout from a grace period that waits for in-flight processing.

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --nanopore_output_dir /data/sequencing/run_001 \
  --realtime_timeout_minutes 15 \
  --realtime_processing_grace_period 10 \
  --outdir results \
  -profile conda
```

**How it works:**

1. **Detection timeout** (`--realtime_timeout_minutes`):
   - Triggers after N minutes without detecting new files
   - Enters grace period (doesn't stop immediately)

2. **Grace period** (`--realtime_processing_grace_period`):
   - Waits additional N minutes for downstream processing to complete
   - Checks if QC, classification, etc. are still running
   - Only stops when processing actually complete

**Total maximum wait:** Detection timeout + Grace period (15 + 10 = 25 minutes max)

**Log messages:**

```
No new files detected for 15 minutes. Entering grace period...
Grace period: Waiting for processing to complete (2/10 minutes)
...
Grace period complete. All processing finished. Stopping gracefully.
```

### Adaptive Batching (v1.3.3+)

Fixed batch sizes do not adapt to varying file arrival rates. Adaptive batching adjusts batch size dynamically.

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --adaptive_batching true \
  --min_batch_size 5 \
  --max_batch_size 50 \
  --batch_size_factor 1.5 \
  --outdir results \
  -profile conda
```

**How it works:**

- **Low throughput**: Small batches (5-10 files) for faster results
- **High throughput**: Large batches (30-50 files) for efficiency
- **Factor**: Multiplier for batch size scaling

**Example progression:**

```
Batch 1: 5 files (starting small)
Batch 2: 8 files (1.5x factor applied)
Batch 3: 12 files (scaled up)
Batch 4: 18 files
...
Batch N: 50 files (capped at max_batch_size)
```

### Priority Sample Routing (v1.3.3+)

By default urgent and routine samples share one queue. Priority routing pulls listed samples to the front of the queue.

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --priority_samples "patient_ICU_01,patient_ICU_02,positive_control" \
  --outdir results \
  -profile conda
```

**How it works:**

- Priority samples processed **before** normal samples
- Pattern matching: exact match, substring, or regex
- Separate channel ensures priority queue

**Use cases:**

- Critical patient samples (ICU, immunocompromised)
- Known positive controls (validation)
- High-value samples (rare specimens)

**Matching logic:**

```
Sample ID: "barcode01_patient_ICU_01"
Priority list: "patient_ICU_01"
Result: MATCH (substring contains) → Priority queue
```

### Per-Barcode Metadata Extraction (v1.3.3+)

Barcode identifiers are extracted from filenames and stored in `meta.barcode`, removing the need for manual tracking.

```bash
# Files like: /path/to/barcode01/reads.fastq.gz
# Extracted as: meta.barcode = "barcode01"

nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --nanopore_output_dir /data/barcoded_run \
  --file_pattern "**/barcode??/*.fastq.gz" \
  --outdir results \
  -profile conda
```

**Pattern recognized:**

- `barcode01`, `barcode02`, ..., `barcode96`
- Case-insensitive
- Extracted via regex: `barcode(\d+)`

---

## Platform Optimization

### Platform Profiles (v1.3.3+)

Pre-configured profiles for different Oxford Nanopore devices:

#### Profile: minion

**Target:** MinION/GridION (1-4 samples, clinical diagnostics)

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --nanopore_output_dir /data/minion_run \
  --outdir results \
  -profile minion,conda
```

**Settings:**

- 8 CPUs per Kraken2 task (maximises per-sample speed)
- 4 CPUs per FASTP task
- NanoPlot every 5th batch
- Queue size: 8

**Best for:**

- Urgent pathogen ID
- Single patient samples
- Clinical diagnostics
- Rapid turnaround

#### Profile: promethion_8

**Target:** PromethION (5-12 samples, balanced throughput)

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --nanopore_output_dir /data/promethion_run \
  --outdir results \
  -profile promethion_8,conda
```

**Settings:**

- 6 CPUs per Kraken2 task
- 3 CPUs per FASTP task
- NanoPlot every 7th batch
- Queue size: 24 (4 samples in parallel on a 24-core host)

**Best for:**

- Environmental monitoring
- Multi-site surveillance
- Metagenomic surveys

#### Profile: promethion

**Target:** PromethION (12-24+ samples, high throughput)

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --nanopore_output_dir /data/promethion_run \
  --outdir results \
  -profile promethion,conda
```

**Settings:**

- 4 CPUs per Kraken2 task (high parallelism)
- 2 CPUs per FASTP task
- NanoPlot every 10th batch
- Queue size: 48 (6-12 samples in parallel)

**Best for:**

- City-wide wastewater surveillance
- Large-scale studies
- Throughput-priority workloads

### Benchmarks (internal, indicative)

| Profile          | Samples Parallel | Per-Sample Time  | Total Throughput |
| ---------------- | ---------------- | ---------------- | ---------------- |
| **minion**       | 3                | Fastest (~2.5 h) | ~1.7x baseline   |
| **promethion_8** | 4                | Balanced (~3 h)  | ~1.9x baseline   |
| **promethion**   | 6-12             | Slower (~4 h)    | ~2.0x baseline   |

**With all optimisations enabled (30-batch internal run):**

- Without: ~324 minutes (~5.4 hours)
- With: ~18 minutes (~0.3 hours)
- Approximately 18x faster on this scenario; figures are scenario-specific.

---

## Best Practices

### 1. Directory Organization

**Good structure:**

```
/data/sequencing/run_001/
├── fastq_pass/              # Monitor this directory
│   ├── barcode01/
│   │   ├── batch_0.fastq.gz
│   │   ├── batch_1.fastq.gz
│   │   └── ...
│   ├── barcode02/
│   └── ...
└── other/                   # Don't monitor
```

**Command:**

```bash
--nanopore_output_dir /data/sequencing/run_001/fastq_pass
--file_pattern "**/*.fastq.gz"
```

### 2. Timeout Configuration

**Short runs (< 2 hours):**

```bash
--realtime_timeout_minutes 10
--realtime_processing_grace_period 5
```

**Long runs (> 6 hours):**

```bash
--realtime_timeout_minutes 30
--realtime_processing_grace_period 10
```

**Overnight runs:**

```bash
--realtime_timeout_minutes 60
--realtime_processing_grace_period 15
```

### 3. Batch Size Selection

**Fast feedback (clinical):**

```bash
--batch_size 5
--min_batch_size 1
--max_batch_size 20
```

**Balanced (research):**

```bash
--batch_size 10
--min_batch_size 5
--max_batch_size 50
```

**High throughput (surveillance):**

```bash
--batch_size 20
--min_batch_size 10
--max_batch_size 100
```

### 4. Resource Allocation

**Compute-limited systems:**

```bash
--max_cpus 8
--max_memory 16.GB
-profile minion,conda  # Lower parallelism
```

**High-performance systems:**

```bash
--max_cpus 48
--max_memory 128.GB
-profile promethion,conda  # Higher parallelism
```

### 5. Monitoring Progress

**Check real-time outputs:**

```bash
# Watch output directory
watch -n 30 "ls -lh results/kraken2/*.report.txt"

# Check logs
tail -f .nextflow.log

# Monitor resource usage
htop
```

---

## Troubleshooting

### Issue: Pipeline hangs indefinitely

**Symptoms:**

```
Launching workflow monitoring...
[No further output]
```

**Cause:** No timeout configured and no files detected.

**Solution:**

```bash
# Always set timeout for real-time mode
--realtime_timeout_minutes 30
```

### Issue: Stops too early

**Symptoms:**

```
Real-time monitoring stopped after 10 minutes
Some batches still processing...
```

**Cause:** Grace period too short.

**Solution:**

```bash
# Increase grace period
--realtime_processing_grace_period 10  # or higher
```

### Issue: Batches too large/small

**Symptoms:**

- Batches have 1-2 files (too small, inefficient)
- Batches have 100+ files (too large, delayed results)

**Solution:**

```bash
# Configure adaptive batching
--adaptive_batching true \
--min_batch_size 5 \
--max_batch_size 50
```

### Issue: High-priority samples not prioritized

**Symptoms:**
Priority samples processed in normal queue.

**Solution:**

```bash
# Check pattern matching
--priority_samples "exact_sample_id,barcode01"

# Verify sample IDs
ls /path/to/data/  # Check actual filenames
```

### Issue: Memory errors during real-time

**Symptoms:**

```
Process KRAKEN2 failed: Out of memory
```

**Solution:**

```bash
# Reduce parallel tasks
--max_cpus 16  # Lower than system max

# Or use resource-conservative profile
-profile minion,conda  # Lower parallelism
```

### Issue: Files not detected

**Symptoms:**

```
Watching /path/to/data
[No files detected]
```

**Solution:**

```bash
# Verify directory exists
ls /path/to/data

# Check file pattern
--file_pattern "**/*.fastq.gz"  # Note: quotes required!

# Test pattern
find /path/to/data -name "*.fastq.gz"
```

---

## Performance Tuning

### Streaming Kraken2 Architecture (v1.5+)

The previous architecture used `maxForks 1` for cumulative classification, which serialised work across samples and capped throughput on multi-barcode runs (>10 barcodes). The streaming architecture replaces this with per-sample parallelism and append-only batch storage.

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --kraken2_enable_incremental true \
  --max_concurrent_batches 4 \
  --max_classification_forks 8 \
  --outdir results \
  -profile conda
```

**What changed:**

- Per-sample parallelism (no global serialisation)
- Append-only batch files (O(1) per batch instead of O(n) rewrites)
- Incremental taxid counting (no cumulative file re-reads)
- Backpressure control to prevent queue saturation

**Throughput in internal benchmarks:**

- CPU utilisation: ~15-20% -> ~70-90%
- File throughput: ~10-15 files/sec -> ~50-75 files/sec
- Roughly 4-5x improvement on internal benchmarks for runs with 12+ barcodes; smaller runs see less gain.

**New parameters:**
| Parameter | Default | Description |
|-----------|---------|-------------|
| `--max_concurrent_batches` | 4 | Backpressure limit per sample |
| `--max_classification_forks` | 8 | Max parallel Kraken2 jobs |

**Output structure change:**

```
outdir/kraken2/{sample_id}/
├── batches/batch_N.kraken2.output.txt
├── batch_reports/batch_N.kraken2.report.txt
├── index.json
└── taxid_counts.json
```

**Nanometa Live compatibility:** JSON outputs are unchanged; dashboard polling continues to work.

### Incremental Kraken2 (v1.3.2+)

Re-classifying all reads each batch in cumulative mode scales as O(n^2). Incremental classification only processes new reads per batch.

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --kraken2_enable_incremental true \
  --outdir results \
  -profile conda
```

**Internal benchmark:** roughly 90% reduction in Kraken2 time on 30-batch runs (~30-90 minutes saved).

**Note:** Combine with the streaming architecture (v1.5+) for the largest gains.

### Conditional NanoPlot Execution

Skip intermediate NanoPlot runs to save wall-clock time:

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --nanoplot_realtime_skip_intermediate true \
  --nanoplot_batch_interval 10 \
  --outdir results \
  -profile conda
```

**Effect:** NanoPlot runs every 10th batch plus the final batch.

**Internal benchmark:** approximately 54-81 minutes saved on a 30-batch run.

### Memory-mapped Database Loading

Enabled automatically in real-time mode.

- First batch loads the Kraken2 DB (~3 min)
- Subsequent batches reuse the OS page cache (near-instant)

**Internal benchmark:** approximately 30-90 minutes saved on a 30-batch run.

---

## Complete Example

### Clinical Pathogen Detection (Urgent)

```bash
nextflow run foi-bioinformatics/nanometanf \
  --realtime_mode \
  --use_dorado \
  --nanopore_output_dir /data/urgent/patient_001/pod5_pass \
  --file_pattern "**/*.pod5" \
  --dorado_model dna_r10.4.1_e4.3_400bps_hac \
  --dorado_device auto \
  --kraken2_db /databases/k2_pluspf \
  --priority_samples "patient_001" \
  --batch_size 5 \
  --min_batch_size 1 \
  --max_batch_size 20 \
  --realtime_timeout_minutes 15 \
  --realtime_processing_grace_period 10 \
  --outdir results/patient_001_urgent \
  -profile minion,conda
```

**What this configures:**

- POD5 basecalling on GPU
- Small batches (5 files) for fast turnaround
- Priority routing for the patient sample
- 15-minute detection timeout + 10-minute grace period
- MinION profile (maximises per-sample speed)

**Expected:** First results within roughly 10-15 minutes.

---

## Related Documentation

- **[Usage Guide](../usage.md)** - Complete parameter reference
- **[Performance Tuning](performance_tuning.md)** - Advanced optimisation
- **[Performance tuning](performance_tuning.md)** - Platform-specific tips and resource configuration
- **[Troubleshooting](troubleshooting.md)** - General troubleshooting

---

**Last Updated:** 2025-01-26
**Version:** 1.5.0 (streaming architecture requires v1.5.0+; basic real-time features work with v1.2.0+)
**Maintainer:** foi-bioinformatics team
