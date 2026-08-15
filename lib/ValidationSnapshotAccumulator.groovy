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
 * update() is synchronized because Nextflow may run the calling operator on
 * multiple threads; it returns a fresh copy of the value set so callers never
 * see the internal collection mutate underneath them.
 */
class ValidationSnapshotAccumulator {

    private final Map store = [:]
    private int boundaryCount = 0
    private final int interval

    ValidationSnapshotAccumulator(int interval) {
        // A boundary count modulo interval of <= 0 would never (or always
        // erratically) trigger; floor at 1 so interval=1 means "every batch".
        this.interval = Math.max(1, interval)
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
        if (isBoundary) {
            boundaryCount += 1
            shouldAggregate = (boundaryCount % interval == 0)
        }
        return [shouldAggregate, new ArrayList(store.values())]
    }
}
