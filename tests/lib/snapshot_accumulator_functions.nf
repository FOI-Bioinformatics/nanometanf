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
