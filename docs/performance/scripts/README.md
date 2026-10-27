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
