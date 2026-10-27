# Re-runnable performance probes

## realtime_fairness_probe.groovy

Measures cross-sample fairness of the real-time interleavers
(`lib/BatchUtils.interleaveFilesBySample` and `lib/CrossBatchInterleaver`) by
loading them from `lib/` and feeding them a synthetic start-up backlog in two
supported on-disk layouts. It reports how many files must be consumed before
every sample has a first result, under the production sample-id key and under
the parent-directory key the interleavers used before audit finding F1 was
fixed, so one run shows the difference.

It needs no Nextflow: the two classes under test depend only on the JDK, and
the probe supplies stand-in path objects exposing `.parent.name` / `.name`
exactly as a Nextflow path does.

```bash
# groovy-4.x and gpars (BatchUtils imports gpars dataflow types)
java -cp groovy-4.0.24.jar:gpars-1.2.1.jar \
     groovy.ui.GroovyMain docs/performance/scripts/realtime_fairness_probe.groovy
```

Figures recorded from this probe are in
[`../realtime_many_barcodes_audit_2026-10-26.md`](../realtime_many_barcodes_audit_2026-10-26.md).

It builds `java.io.File` objects rather than Nextflow paths, so `.name`
resolves without Nextflow's `Path` extensions. That exercises the grouping and
ordering logic under test; the `.name` sort inside the interleavers relies on
those extensions at runtime and is unchanged by this fix.

## batch_timeout_probe.groovy

Measures how long a partial batch waits under `BatchUtils.batchWithTimeout`'s
fixed-rate flush timer, against the "reset the timer on each flush"
alternative. This is the measurement that **withdrew** audit finding F10:
resetting the clock is worse on both mean and maximum wait, because a
per-batch deadline makes every batch pay the whole period while a sampler only
costs whatever remains of the current tick.

It reimplements the two timer policies rather than calling the method, which
takes a Nextflow channel and cannot run outside Nextflow; the shipped policy
mirrors `lib/BatchUtils.groovy` exactly.

```bash
java -cp groovy-4.0.24.jar:gpars-1.2.1.jar \
     groovy.ui.GroovyMain docs/performance/scripts/batch_timeout_probe.groovy
```

## cumulative_lock_probe.groovy

Measures the one serialised section audit F9 names: the per-batch work the
real-time classification subworkflow does inside a single global lock, for
every batch of every barcode, so the costs add across barcodes. It replicates
the four steps from the subworkflow and drives the real `KreportTree` and
`RealtimeResume`, sweeping per-batch and cumulative diversity separately
because they scale different steps and only one has an operator knob.

This is what revised F9 down from "the most likely unmeasured ceiling" to tens
of seconds across a run, and showed that `report_write_interval` thins 76-79%
of it.

```bash
java -cp groovy-4.0.24.jar:gpars-1.2.1.jar:groovy-json-4.0.24.jar \
     groovy.ui.GroovyMain docs/performance/scripts/cumulative_lock_probe.groovy
```

## kraken2_fork_memory_probe.py

Answers the question `kraken2_task_memory_gb` exists for: what does ONE MORE
concurrent kraken2 fork cost in RAM? On a local executor Nextflow's per-task
`memory` is admission control, so if N forks share a memory-mapped index the
reservation should be the per-fork marginal cost, not the whole database.

Two traps it exists to avoid: with one process, file-backed mapped pages count
as PRIVATE (nothing else maps them), so sharing is invisible below two forks;
and RSS counts a shared page once per process, so summing RSS across forks
multiply-counts the index. PSS is the metric, and its slope against N is the
marginal.

Measured 2026-10-27 against two real databases, page cache warmed as
`KRAKEN2_DB_PRELOAD` warms it:

| database      | hash   | taxa   | marginal/fork, 1 thread | 4 threads |
| ------------- | ------ | ------ | ----------------------- | --------- |
| viral         | 619 MB | 27,069 | 54 MB                   | 139 MB    |
| standard_08gb | 8.0 GB | 50,333 | 54 MB                   | 149 MB    |

Flat across a 13x larger index: roughly 50 MB plus 25 MB per thread,
independent of index size, because the index is shared and the private part is
read buffers and per-thread state. Without memory mapping one fork took 7.7 GB
private, the whole index.

```bash
python3 docs/performance/scripts/kraken2_fork_memory_probe.py \
    /path/to/kraken2_db reads.fastq.gz "label"
```
