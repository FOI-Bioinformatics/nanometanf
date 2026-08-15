/**
 * Cross-batch per-barcode fair-queuing for the realtime classifier stream.
 *
 * The classifier maxForks is a GLOBAL cap, not per-barcode, so the order of the
 * flattened per-file stream is the order files are classified. BatchUtils
 * .interleaveFilesByParentDir round-robins WITHIN a single batch, but it is
 * stateless: each batch is ordered independently, so it cannot know that one
 * barcode is already far ahead of another across earlier batches. A fast barcode
 * that keeps filling batches can therefore stay ahead of a slow one for the whole
 * run (audit P2.9: one slow barcode starves -- here, is starved by -- the others).
 *
 * This class keeps a cumulative served-count per barcode across batches and, for
 * each batch, emits a deficit round-robin: the next file always comes from the
 * non-empty barcode that has been served LEAST so far (ties broken by barcode
 * name for determinism). A barcode that fell behind in earlier batches is drained
 * first until it catches up. With an empty history and a single batch this reduces
 * exactly to interleaveFilesByParentDir's round-robin, so it is a strict
 * generalisation.
 *
 * It only reorders files already present in a batch -- every input file is emitted
 * exactly once, within that same batch, so nothing is held back or lost and
 * termination is unaffected. Within a barcode, files keep a stable name-sorted
 * order. interleave() is synchronized because Nextflow may run the calling
 * operator on multiple threads.
 */
class CrossBatchInterleaver {

    private final Map<String, Long> served = [:]

    /**
     * Order one batch as a deficit round-robin across barcodes, updating the
     * cumulative served-counts so later batches stay fair across the run.
     *
     * @param batch  list of file/Path objects (each exposing .parent.name and .name)
     * @return       a new list, the batch reordered for cross-batch fairness
     */
    synchronized List interleave(List batch) {
        if (!batch) {
            return []
        }
        def grouped = batch.groupBy { it?.parent?.name ?: 'unknown' }
        def queues = [:]
        grouped.each { name, files ->
            queues[name] = new ArrayDeque(files.sort(false) { it?.name ?: '' })
        }
        def out = []
        while (queues.values().any { !it.isEmpty() }) {
            // Pick the non-empty barcode served least so far (tie: name).
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
