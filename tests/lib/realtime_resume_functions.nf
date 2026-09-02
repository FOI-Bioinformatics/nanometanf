/*
 * Thin wrappers for testing RealtimeResume via nf-test.
 * The class is auto-loaded from lib/ by Nextflow.
 */

// Write the given [sample, batch, source] rows to a fresh outdir's ledger and
// read them back as the set of processed inputs.
def ledgerRoundTrip(String outdir, List rows) {
    rows.each { r -> RealtimeResume.recordProcessedInput(outdir, r[0], r[1], r[2]) }
    return RealtimeResume.readProcessedInputs(outdir).sort()
}

// Read a ledger that may be missing, or hold a header and a torn last line.
def readLedgerText(String outdir, String text) {
    if (text != null) {
        def f = RealtimeResume.ledgerFile(outdir)
        f.parentFile.mkdirs()
        f.text = text
    }
    return RealtimeResume.readProcessedInputs(outdir).sort()
}

// Merge a sequence of per-batch count maps into one fresh state.
def mergeSequence(List batches) {
    def state = [total_reads: 0, classified_reads: 0, unclassified_reads: 0, taxa: [:]]
    batches.each { RealtimeResume.mergeBatchCounts(state, it) }
    return state
}

// Seed-reading over a fake outdir: files is a map of relative path -> text.
def priorCounts(String outdir, Map files) {
    files.each { rel, text ->
        def f = new File(outdir, rel)
        f.parentFile.mkdirs()
        f.text = text
    }
    def warnings = []
    def counts = RealtimeResume.priorTaxidCounts(outdir, warnings)
    return [counts.collectEntries { k, v -> [k, v.collect { it.batch_id }] }, warnings.size()]
}

def priorBatches(String outdir, Map files, String subdir, String suffix) {
    files.each { rel, text ->
        def f = new File(outdir, rel)
        f.parentFile.mkdirs()
        f.text = text
    }
    return RealtimeResume.priorBatchFiles(outdir, subdir, suffix).collect { [it[0], it[1].fileName.toString()] }
}
