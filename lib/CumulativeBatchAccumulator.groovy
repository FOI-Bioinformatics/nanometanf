/**
 * Per-(sample, taxid) accumulation of realtime validation batch results.
 *
 * The cumulative validation aggregator used to be fed the PRIOR cumulative file
 * read straight out of ``params.outdir`` inside a channel ``.map`` closure. That
 * read happened when the validator emitted, which is not ordered against the
 * aggregator task that writes the very same path, and the aggregator was not
 * serialised. Two batches of one (sample, taxid) that finished close together
 * therefore both saw the same prior -- often none at all -- and each published
 * ``prior + own batch``. Last writer won and the other batch's alignments were
 * gone from the cumulative file the dashboard reads by default. The startup
 * backlog burst (every pre-existing file is emitted at once) makes that the
 * common case rather than a rare one.
 *
 * This class removes the dependence on the output directory entirely. It
 * remembers every batch result seen so far for a key and hands the aggregator
 * the complete set, so each aggregation is computed from its inputs alone:
 *
 *   * The published result is a pure function of the accumulated batch set, so
 *     a late or concurrent aggregation can no longer drop a batch -- a later
 *     emission's input is always a superset of an earlier one's.
 *   * Entries are keyed by batch id, so a retried or re-emitted task replaces
 *     its own entry instead of being counted twice.
 *   * Accumulation is monotone, which is what lets ``maxForks 1`` on the
 *     aggregator finish the job: submission order equals completion order, so
 *     the most complete result for a key is also the last one written.
 *
 * The cost is that batch N re-merges N per-taxid files instead of two. These
 * files are small (one taxon's alignments from one batch) and correctness is
 * not worth trading for the incremental form, which cannot be made safe while
 * its state lives in the publish directory.
 *
 * ``accumulate`` is synchronized because Nextflow may run the calling operator
 * on multiple threads, and it returns fresh lists so callers never see the
 * internal collections mutate underneath them.
 */
class CumulativeBatchAccumulator {

    private final Map store = [:]

    /**
     * Record one batch's result files and report the full set for its key.
     *
     * @param key        accumulation key, e.g. "barcode01|263"
     * @param batchId    this batch's id; replaces an earlier entry with the
     *                   same id rather than adding a duplicate
     * @param resultFile the batch's alignment/hit table (PAF or BLAST TSV)
     * @param statsFile  the batch's stats JSON, carrying its read count
     * @return  a two-element list [ result files, stats files ], one entry per
     *          batch seen so far for this key, ordered by first appearance
     */
    synchronized List accumulate(String key, Object batchId, Object resultFile, Object statsFile) {
        def perKey = store.get(key, [:])
        perKey[String.valueOf(batchId)] = [resultFile, statsFile]
        def results = []
        def stats = []
        perKey.values().each { entry ->
            results.add(entry[0])
            stats.add(entry[1])
        }
        return [results, stats]
    }
}
