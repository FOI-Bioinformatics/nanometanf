# Re-runnable performance probes

## realtime_fairness_probe.groovy

Measures cross-barcode fairness of the real-time interleavers
(`lib/BatchUtils.interleaveFilesByParentDir` and
`lib/CrossBatchInterleaver`) by loading them from `lib/` and feeding them a
synthetic start-up backlog in two supported on-disk layouts. It reports how
many files must be consumed before every barcode has one result.

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
