/**
 * Running snapshot of the latest validation stats file per key, with a
 * per-batch aggregation trigger, for realtime validation.
 *
 * Realtime validation cannot use a .collect() barrier: the source channels stay
 * open until the watchPath timeout, so the live validation_results.json must be
 * rebuilt during the run. The aggregator (AGGREGATE_VALIDATION_LIVE) is fed the
 * full current set of per-(sample, taxid) cumulative stats files on each update,
 * so something has to remember the latest file seen per key across emissions.
 *
 * That is inherently cross-emission state. Nextflow has no scan/accumulate
 * operator, and its channel operators are not available in plain Groovy class
 * scope, so the state cannot be expressed as a pure pipeline. Encapsulating it
 * in this small class -- rather than mutating a raw synchronized Map and an
 * AtomicInteger inside a .map and a .filter in the subworkflow -- keeps the
 * mutation in one cohesive, unit-tested place and lets the subworkflow operators
 * stay pure (the filter just reads the returned trigger flag).
 *
 * Aggregation triggers only on a per-batch BOUNDARY (a Kraken2 report, one per
 * batch), thinned by ``interval`` (every Nth boundary). Stat-only updates refresh
 * the snapshot without triggering. This is the issue #29 cadence fix: aggregating
 * on every stat update overran the maxForks=1 live aggregator; once per batch
 * keeps the JSON fresh without hammering the single serialised slot.
 *
 * An ``interval`` of 0 or less means no periodic aggregation at all: the caller's
 * end-of-session emission is then the only one. That is what
 * params.validation_aggregate_interval = 0 has always been documented to mean, in
 * both nextflow.config and nextflow_schema.json.
 *
 * update() is synchronized because Nextflow may run the calling operator on
 * multiple threads; it returns a fresh copy of the value set so callers never
 * see the internal collection mutate underneath them.
 */
class ValidationSnapshotAccumulator {

    private final Map store = [:]
    private int boundaryCount = 0
    private final int interval

    ValidationSnapshotAccumulator(int interval) {
        // Kept verbatim, NOT floored at 1. The floor used to turn the documented
        // "0 = end-of-session only" into "aggregate on every batch" -- the exact
        // load issue #29 was filed for, reinstated by default, with no value left
        // that could express the documented behaviour.
        this.interval = interval
    }

    /**
     * Snapshot key for a Kraken2 report.
     *
     * Keyed by sample and by KIND, not by batch id. Keying per batch made the
     * store grow for the whole run while every emission re-emitted the entire
     * set, so the Nth aggregation staged and parsed N reports through a
     * maxForks=1 process -- quadratic work for taxid-to-species names that
     * barely change. Two entries per sample bound that: the latest per-batch
     * report, and the end-of-session cumulative one, which supersedes nothing
     * and is never overwritten by a batch report because it lands under its own
     * key.
     *
     * The null check is explicit: batch_id 0 is the first realtime batch and is
     * Groovy-falsy, so a truthiness test would file it as the cumulative report
     * and let batch 0 overwrite the run's complete one.
     *
     * @param sampleId  meta.id
     * @param batchId   meta.batch_id, or null for the cumulative report
     * @return  snapshot key
     */
    static String krakenKey(Object sampleId, Object batchId) {
        return "krak|${sampleId}|${batchId != null ? 'batch' : 'final'}".toString()
    }

    /**
     * Record the latest file for a key and report the current snapshot.
     *
     * @param key         snapshot key (e.g. "blast|sampleA|562")
     * @param file        the latest stats file for that key
     * @param isBoundary  true if this emission is a per-batch boundary (Kraken2
     *                    report) that may trigger an aggregation
     * @return  a two-element list [ shouldAggregate (boolean),
     *          values (List of the latest file per key, a fresh copy) ]
     */
    synchronized List update(String key, Object file, boolean isBoundary) {
        store[key] = file
        boolean shouldAggregate = false
        if (isBoundary && interval > 0) {
            boundaryCount += 1
            shouldAggregate = (boundaryCount % interval == 0)
        }
        return [shouldAggregate, new ArrayList(store.values())]
    }
}
