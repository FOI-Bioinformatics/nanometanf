/*
 * Thin wrapper for testing CrossBatchInterleaver via nf-test.
 * The class is auto-loaded from lib/ by Nextflow.
 *
 * Replays an ordered list of batches (each a list of files) through ONE
 * interleaver instance and returns, per batch, the emitted file basenames -- so a
 * test can assert both within-batch ordering and cross-batch fairness (the served
 * counts carried between batches).
 *
 * The interleaver is constructed with the production sample-id resolver, the
 * same one BatchUtils.interleaveFilesBySample is keyed on: the two run in
 * sequence over one stream and must agree (audit finding F1,
 * docs/performance/realtime_many_barcodes_audit_2026-10-26.md).
 */

def crossBatchOrder(List batches) {
    def xbi = new CrossBatchInterleaver({ f ->
        InputDetector.extractSampleId(f, null, null, null)
    })
    return batches.collect { b ->
        xbi.interleave(b).collect { it.toString().tokenize('/').last() }
    }
}
