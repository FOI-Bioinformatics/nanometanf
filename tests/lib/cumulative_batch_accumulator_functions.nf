/*
 * Thin wrapper for testing CumulativeBatchAccumulator via nf-test.
 * The class is auto-loaded from lib/ by Nextflow.
 *
 * Replays an ordered list of [key, batchId, resultFile, statsFile] events
 * through one accumulator instance and returns the [results, stats] set it
 * reported after each, so a test can assert the exact accumulation sequence
 * the realtime validation aggregator is fed.
 */

def accumulateSequence(List events) {
    def acc = new CumulativeBatchAccumulator()
    return events.collect { e -> acc.accumulate(e[0], e[1], e[2], e[3]) }
}
