/*
 * Thin wrapper functions for testing BatchUtils via nf-test.
 * The BatchUtils and InputDetector classes are auto-loaded from lib/ by Nextflow.
 */

// The production resolver: BatchUtils.interleaveFilesBySample must be keyed on
// the SAME sample id the pipeline gives a file downstream, so the wrapper uses
// InputDetector.extractSampleId rather than a parent-directory shortcut. That
// is the whole point of the key being a parameter -- see audit finding F1 in
// docs/performance/realtime_many_barcodes_audit_2026-10-26.md.
def interleaveFilesBySample(List files) {
    return BatchUtils.interleaveFilesBySample(files, { f ->
        InputDetector.extractSampleId(f, null, null, null)
    })
}

// BatchUtils.sampleKeyOf is the one door both interleavers resolve keys
// through. Its contract is that a resolver which throws or yields nothing
// gives 'unknown' -- grouping those files together rather than dropping them.
def sampleKeyFallbacks(String relPath) {
    def f = java.nio.file.Paths.get(relPath)
    return [
        resolved:  BatchUtils.sampleKeyOf(f, { x -> InputDetector.extractSampleId(x, null, null, null) }),
        throwing:  BatchUtils.sampleKeyOf(f, { x -> throw new IllegalStateException("boom") }),
        nullKey:   BatchUtils.sampleKeyOf(f, { x -> null }),
        emptyKey:  BatchUtils.sampleKeyOf(f, { x -> "" }),
        noClosure: BatchUtils.sampleKeyOf(f, null),
    ]
}

def exactTaxidReadCounts(Object krakenOutput) {
    return BatchUtils.exactTaxidReadCounts(krakenOutput)
}
