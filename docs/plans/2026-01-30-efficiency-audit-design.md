# Efficiency Audit: nanometanf as a Real-Time Multiplexed Nanopore Analyzer

**Date:** 2026-01-30
**Scope:** Throughput, resource utilization, architectural correctness, nf-core compliance
**Pipeline version:** 1.5.0 (scalable streaming architecture)

---

## Executive Summary

The v1.5 scalable streaming architecture is fundamentally sound. It eliminated the primary bottleneck (global `maxForks 1` serialization) and replaced O(n^2) cumulative I/O with append-only batch storage and incremental taxid counting. The pipeline is well-positioned for real-time multiplexed analysis.

This audit identifies six findings, ranked by impact:

| #   | Finding                                        | Severity | Category     |
| --- | ---------------------------------------------- | -------- | ------------ |
| 1   | No intermediate validation during streaming    | Medium   | Architecture |
| 2   | Report generator over-allocated at 6GB         | Low      | Resources    |
| 3   | FastQC + SeqKit stats redundancy               | Low      | Resources    |
| 4   | Progressive report rewrites every batch        | Low      | I/O          |
| 5   | Race condition window in progressive reporting | Low      | Correctness  |
| 6   | Final aggregator uses glob without validation  | Low      | Correctness  |

---

## Finding 1: No Intermediate Validation During Streaming

### Problem

The validation subworkflow uses `.collect()` to aggregate all results before `AGGREGATE_VALIDATION_RESULTS` runs. During a multi-hour real-time session, the dashboard receives classification results per-batch but zero validation data until the run completes.

**Location:** `subworkflows/local/validation/main.nf` (lines ~168-171)

```groovy
ch_blast_stats.collect().ifEmpty([])
ch_minimap2_stats.collect().ifEmpty([])
ch_extraction_stats.collect().ifEmpty([])
ch_kraken_report_files.collect().ifEmpty([])
```

### Recommended Fix

Add periodic validation aggregation using the same batch-interval pattern as NanoPlot:

```groovy
// In subworkflows/local/validation/main.nf

// Periodic intermediate aggregation (every N batches)
def validation_interval = params.validation_aggregate_interval ?: 10

ch_periodic_blast = ch_blast_stats
    .buffer(size: validation_interval, remainder: true)

ch_periodic_minimap2 = ch_minimap2_stats
    .buffer(size: validation_interval, remainder: true)

// Emit intermediate JSON for dashboard consumption
AGGREGATE_VALIDATION_RESULTS_INTERMEDIATE(
    ch_periodic_blast,
    ch_periodic_minimap2,
    ch_extraction_stats.collect().ifEmpty([]),
    ch_kraken_report_files.collect().ifEmpty([])
)

// Keep the final collect() for end-of-session complete aggregation
AGGREGATE_VALIDATION_RESULTS(
    ch_blast_stats.collect().ifEmpty([]),
    ch_minimap2_stats.collect().ifEmpty([]),
    ch_extraction_stats.collect().ifEmpty([]),
    ch_kraken_report_files.collect().ifEmpty([])
)
```

**New parameter in `nextflow.config`:**

```groovy
validation_aggregate_interval = 10  // Emit intermediate validation every N samples
```

**Trade-off:** Adds a second aggregation module. Dashboard gets partial validation updates during streaming, at the cost of slightly more compute.

---

## Finding 2: Report Generator Over-Allocated at 6GB

### Problem

`KRAKEN2_REPORT_GENERATOR` parses a single batch report (<1MB text) and emits a JSON with taxid counts. This is lightweight text parsing allocated 6GB memory. On a 64GB machine with 8 classifier forks at 12GB each (96GB demanded), this wastes headroom.

**Location:** `conf/base.config` or module `main.nf`

### Recommended Fix

```groovy
// In conf/modules.config or conf/base.config
withName: 'KRAKEN2_REPORT_GENERATOR' {
    memory = { 1.GB * task.attempt }  // Was 6.GB
    cpus   = 1                         // Was 2; single-threaded Python script
}
```

**Impact:** Frees ~5GB per concurrent report generator instance. With 16 maxForks, this recovers up to 80GB of scheduler headroom.

---

## Finding 3: FastQC + SeqKit Stats Redundancy

### Problem

Both FastQC and SeqKit Stats run on the same QC-filtered reads, producing overlapping statistics (read count, length distribution, quality scores). This doubles QC compute per sample.

**Location:** `subworkflows/local/qc_analysis/main.nf` (lines ~110-157)

### Recommended Fix

Use SeqKit Stats for machine-readable JSON (consumed by dashboard) and drop FastQC from the per-batch QC path. Keep FastQC only for the final MultiQC report if HTML visualization is needed:

```groovy
// In subworkflows/local/qc_analysis/main.nf

// Always run SeqKit for JSON stats (lightweight, fast)
SEQKIT_STATS(ch_qc_reads)

// Run FastQC only at end-of-session for MultiQC HTML report
if (!params.realtime_mode || params.force_fastqc) {
    FASTQC(ch_qc_reads)
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip)
}
```

**New parameter:**

```groovy
force_fastqc = false  // Force FastQC even in real-time mode
```

**Trade-off:** Loses per-batch FastQC HTML in real-time mode. SeqKit JSON provides the same numerical data for dashboards.

---

## Finding 4: Progressive Report Rewrites Every Batch

### Problem

Each batch triggers a full rewrite of the cumulative Kraken2 report to the output directory. With 30 batches and 5000 taxa, this produces ~150k write operations. Files are small (~100KB) so the impact is modest, but a buffered approach reduces filesystem load.

**Location:** `subworkflows/local/taxonomic_classification/main.nf` (lines ~207-229)

### Recommended Fix

Buffer writes to every N batches:

```groovy
// In the .subscribe block for progressive reporting
def report_write_interval = params.report_write_interval ?: 5
def batch_counter = [:].withDefault { 0 }

KRAKEN2_REPORT_GENERATOR.out.taxid_counts
    .subscribe { meta, taxid_file ->
        def sample_id = meta.id
        synchronized(cumulative_taxa_state) {
            // ... existing accumulation logic ...

            batch_counter[sample_id]++

            // Write only every N batches or on final batch
            if (batch_counter[sample_id] % report_write_interval == 0
                || meta.is_final_batch == true) {
                // ... existing atomic write logic ...
            }
        }
    }
```

**New parameter:**

```groovy
report_write_interval = 5  // Write cumulative report every N batches
```

**Trade-off:** Dashboard updates every 5 batches instead of every batch. At batch_size=10, this means updates every 50 files instead of every 10.

---

## Finding 5: Race Condition Window in Progressive Reporting

### Problem

The `.subscribe` block reads `taxid_file.text` outside the `synchronized` block, then enters the lock to accumulate. If two batches for the same sample emit near-simultaneously, both reads complete before either lock acquisition. The accumulation itself is safe (additive), but a downstream consumer reading the output file could see data from batch N+1 without batch N if the writes interleave.

**Location:** `subworkflows/local/taxonomic_classification/main.nf` (lines ~179-236)

### Recommended Fix

Move the file read inside the synchronized block:

```groovy
KRAKEN2_REPORT_GENERATOR.out.taxid_counts
    .subscribe { meta, taxid_file ->
        def sample_id = meta.id
        synchronized(cumulative_taxa_state) {
            // Read inside lock to guarantee ordering
            def batch_counts = new groovy.json.JsonSlurper().parse(taxid_file.toFile())

            def state = cumulative_taxa_state[sample_id]
            batch_counts.taxa.each { taxid, data ->
                if (!state.taxa.containsKey(taxid)) {
                    state.taxa[taxid] = [reads: 0, cumul: 0, rank: '', name: '']
                }
                state.taxa[taxid].reads += data.reads
                state.taxa[taxid].cumul += data.cumul
            }
            state.total_reads += batch_counts.total_reads
            state.classified_reads += batch_counts.classified_reads

            // Atomic write while still holding lock
            def outdir = new File("${params.outdir}/kraken2")
            def temp = new File(outdir, "${sample_id}.cumulative.kraken2.report.txt.tmp")
            temp.text = generateReport(state)
            temp.renameTo(new File(outdir, "${sample_id}.cumulative.kraken2.report.txt"))
        }
    }
```

**Trade-off:** Slightly longer lock hold time. Acceptable because the operations inside the lock are fast (small file read + in-memory accumulation + small file write).

---

## Finding 6: Final Aggregator Uses Glob Without Validation

### Problem

The final aggregator discovers batch files via `glob.glob('batch_*.kraken2.output.txt')`. If a batch file fails to stage, the aggregator silently produces incomplete output.

**Location:** `modules/local/kraken2_final_aggregator/main.nf` (lines ~41-42)

### Recommended Fix

Pass expected batch count from the channel and validate:

```python
#!/usr/bin/env python3
import glob
import json
import sys

expected_batches = int(sys.argv[1])  # Passed from Nextflow channel

batch_output_files = sorted(glob.glob('batch_*.kraken2.output.txt'))
batch_report_files = sorted(glob.glob('batch_*.kraken2.report.txt'))

# Validate completeness
if len(batch_output_files) != expected_batches:
    print(f"WARNING: Expected {expected_batches} batch outputs, found {len(batch_output_files)}",
          file=sys.stderr)
    # Continue with available files but flag in stats

if len(batch_report_files) != expected_batches:
    print(f"WARNING: Expected {expected_batches} batch reports, found {len(batch_report_files)}",
          file=sys.stderr)

# ... existing concatenation logic ...

# Include completeness in stats output
stats = {
    'expected_batches': expected_batches,
    'found_output_batches': len(batch_output_files),
    'found_report_batches': len(batch_report_files),
    'complete': len(batch_output_files) == expected_batches
}
```

**Nextflow channel change:**

```groovy
ch_aggregator_input = ch_sample_outputs
    .map { meta, output_file -> tuple(meta.id, output_file) }
    .groupTuple(by: 0)
    .map { sample_id, files -> tuple([id: sample_id, batch_count: files.size()], files) }
```

**Trade-off:** Minimal. Adds a validation check with no performance cost.

---

## Overall Assessment

The nanometanf v1.5 architecture is an efficient real-time multiplexed nanopore analyzer. The scalable streaming design (append-only storage, incremental counting, per-sample parallelism) is architecturally sound and addresses the correct bottlenecks. The six findings above are refinements, not fundamental issues. The most impactful improvement would be Finding 1 (intermediate validation), as it closes a functional gap in the real-time monitoring use case.

**Recommended implementation order:**

1. Finding 2 (report generator memory) -- immediate, zero-risk config change
2. Finding 5 (race condition) -- small code change, correctness improvement
3. Finding 6 (aggregator validation) -- small code change, robustness improvement
4. Finding 4 (buffered writes) -- moderate change, I/O reduction
5. Finding 3 (FastQC redundancy) -- moderate change, compute reduction
6. Finding 1 (intermediate validation) -- larger change, new module required
