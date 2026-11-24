/**
 * Cross-batch per-sample fair-queuing for the realtime classifier stream.
 *
 * The classifier maxForks is a GLOBAL cap, not per-sample, so the order of the
 * flattened per-file stream is the order files are classified. BatchUtils
 * .interleaveFilesBySample round-robins WITHIN a single batch, but it is
 * stateless: each batch is ordered independently, so it cannot know that one
 * sample is already far ahead of another across earlier batches. A fast sample
 * that keeps filling batches can therefore stay ahead of a slow one for the whole
 * run (audit P2.9: one slow sample starves -- here, is starved by -- the others).
 *
 * This class keeps a cumulative served-count per sample across batches and, for
 * each batch, emits a deficit round-robin: the next file always comes from the
 * non-empty sample that has been served LEAST so far (ties broken by sample id
 * for determinism). A sample that fell behind in earlier batches is drained
 * first until it catches up. With an empty history and a single batch this reduces
 * exactly to interleaveFilesBySample's round-robin, so it is a strict
 * generalisation.
 *
 * ``sampleKey`` is required and resolution goes through BatchUtils.sampleKeyOf,
 * the same door interleaveFilesBySample uses. The two are applied in sequence
 * over one stream, so a file that is sample A to one and sample B to the other
 * would be round-robined against itself. Keying on the immediate parent
 * directory name -- what this class did before -- is the sample id only when
 * the sample IS a directory; see interleaveFilesBySample and audit finding F1
 * in docs/performance/realtime_many_barcodes_audit_2026-10-26.md.
 *
 * It only reorders files already present in a batch -- every input file is emitted
 * exactly once, within that same batch, so nothing is held back or lost and
 * termination is unaffected. Within a sample, files keep a stable name-sorted
 * order. interleave() is synchronized because Nextflow may run the calling
 * operator on multiple threads.
 */
class CrossBatchInterleaver {

    private final Map<String, Long> served = [:]
    private final Closure sampleKey

    /**
     * @param sampleKey closure resolving one file to its sample id; it must be
     *                  the same resolver the pipeline uses to build meta.id
     */
    CrossBatchInterleaver(Closure sampleKey) {
        this.sampleKey = sampleKey
    }

    /**
     * Order one batch as a deficit round-robin across samples, updating the
     * cumulative served-counts so later batches stay fair across the run.
     *
     * @param batch  list of file/Path objects (each exposing .name)
     * @return       a new list, the batch reordered for cross-batch fairness
     */
    synchronized List interleave(List batch) {
        if (!batch) {
            return []
        }
        def grouped = batch.groupBy { BatchUtils.sampleKeyOf(it, sampleKey) }
        def queues = [:]
        grouped.each { name, files ->
            queues[name] = new ArrayDeque(files.sort(false) { it?.name ?: '' })
        }
        def out = []
        while (queues.values().any { !it.isEmpty() }) {
            // Pick the non-empty sample served least so far (tie: sample id).
            // A two-argument comparator closure is used because a single-arg
            // closure returning a [count, name] list would have min try to
            // compare ArrayLists, which are not Comparable.
            def pick = queues.entrySet()
                .findAll { !it.value.isEmpty() }
                .min { a, b ->
                    long sa = served[a.key] ?: 0L
                    long sb = served[b.key] ?: 0L
                    sa != sb ? (sa <=> sb) : (a.key <=> b.key)
                }
            out.add(pick.value.pollFirst())
            served[pick.key] = (served[pick.key] ?: 0L) + 1L
        }
        return out
    }
}
