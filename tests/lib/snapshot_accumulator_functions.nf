/*
 * Thin wrapper for testing ValidationSnapshotAccumulator via nf-test.
 * The class is auto-loaded from lib/ by Nextflow.
 *
 * Replays an ordered list of [key, file, isBoundary] events through one
 * accumulator instance and returns the list of [shouldAggregate, values]
 * results, so a test can assert the exact running-snapshot sequence.
 */

def snapshotSequence(List events, int interval) {
    def acc = new ValidationSnapshotAccumulator(interval)
    return events.collect { e -> acc.update(e[0], e[1], e[2]) }
}

/*
 * Replays [sampleId, batchId] Kraken2 report arrivals through the SAME key
 * construction the validation subworkflow uses, so a test can pin the bound on
 * the snapshot store rather than restating the key format and letting the two
 * drift.
 *
 * @param reports  list of [sampleId, batchId] pairs; batchId null = the
 *                 end-of-session cumulative report
 * @return  [ keys in arrival order, final snapshot file set ]
 */

def krakenSnapshotKeys(List reports) {
    def acc = new ValidationSnapshotAccumulator(0)
    def keys = []
    def last = null
    reports.each { r ->
        def key = ValidationSnapshotAccumulator.krakenKey(r[0], r[1])
        keys.add(key)
        last = acc.update(key, "${r[0]}_batch${r[1]}.report", true)
    }
    return [ keys, last == null ? [] : last[1] ]
}
