/**
 * Ordered accumulation of one file per batch, for a run-so-far recompute.
 *
 * REALTIME_STATISTICS used to hand UPDATE_CUMULATIVE_STATS the PRIOR
 * cumulative state read straight out of ``params.outdir`` inside a channel
 * ``.map`` closure. That read happened when the snapshot module emitted, which
 * is not ordered against the task that writes the very same path, and the
 * update task was not serialised. Two batches that finished close together
 * therefore both saw the same prior -- on a start-up backlog usually none --
 * and each published ``prior + own``. Last writer won and the other batch was
 * gone from the session totals the Reports tab shows. The statistics are on by
 * default, so this was the normal case rather than a rare one.
 *
 * This class removes the dependence on the output directory, the same way
 * CumulativeBatchAccumulator does for the validation aggregator. It remembers
 * every batch's snapshot seen so far and hands the update task the complete
 * ordered set, so each cumulative file is a pure function of its inputs:
 *
 *   * a later emission's input is always a superset of an earlier one's, so a
 *     concurrent or late task can only ever be less complete, never wrong;
 *   * entries are keyed by batch id, so a retried or re-emitted task replaces
 *     its own entry instead of being counted twice;
 *   * accumulation is monotone, which is what lets ``maxForks 1`` on the
 *     update task finish the job: submission order equals completion order, so
 *     the most complete result is also the last one published.
 *
 * The cost is that batch N re-reads N small JSON snapshots instead of two.
 *
 * ``accumulate`` is synchronized because Nextflow may run the calling operator
 * on multiple threads, and it returns a fresh list so callers never see the
 * internal collection mutate underneath them.
 */
class BatchSeriesAccumulator {

    private final Map store = [:]

    /**
     * Record one batch's file and report the full ordered set for its key.
     *
     * @param key      accumulation key, e.g. the session or a sample id
     * @param batchId  this batch's id; replaces an earlier entry with the same
     *                 id rather than adding a duplicate
     * @param file     the batch's file
     * @return  every file seen so far for this key, one per batch, ordered by
     *          first appearance
     */
    synchronized List accumulate(String key, Object batchId, Object file) {
        def perKey = store.get(key, [:])
        perKey[String.valueOf(batchId)] = file
        return new ArrayList(perKey.values())
    }
}
