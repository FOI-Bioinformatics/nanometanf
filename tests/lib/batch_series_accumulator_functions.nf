/*
 * Thin wrapper for testing BatchSeriesAccumulator via nf-test.
 * The class is auto-loaded from lib/ by Nextflow.
 *
 * Replays an ordered list of [key, batchId, file] events through one
 * accumulator instance and returns the set it reported after each, so a test
 * can assert the exact series the realtime statistics update is fed.
 */

def accumulateSeries(List events) {
    def acc = new BatchSeriesAccumulator()
    return events.collect { e -> acc.accumulate(e[0], e[1], e[2]) }
}
