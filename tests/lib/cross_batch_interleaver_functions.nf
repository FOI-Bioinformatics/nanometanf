/*
 * Thin wrapper for testing CrossBatchInterleaver via nf-test.
 * The class is auto-loaded from lib/ by Nextflow.
 *
 * Replays an ordered list of batches (each a list of files) through ONE
 * interleaver instance and returns, per batch, the emitted file basenames -- so a
 * test can assert both within-batch ordering and cross-batch fairness (the served
 * counts carried between batches).
 */

def crossBatchOrder(List batches) {
    def xbi = new CrossBatchInterleaver()
    return batches.collect { b ->
        xbi.interleave(b).collect { it.toString().tokenize('/').last() }
    }
}
