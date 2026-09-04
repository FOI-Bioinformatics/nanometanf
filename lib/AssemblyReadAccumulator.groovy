/**
 * Per-sample accumulation of realtime read files for assembly, with a cadence.
 *
 * In realtime mode the monitoring subworkflow flattens each batch back into one
 * emission per FASTQ file, and QC is per emission, so assembly saw one file at
 * a time. Measured before this existed: a run that fed 28 files across five
 * samples produced four assembly artifacts, one per sample, each holding a
 * single batch's assembly at a ninth to a thirty-fourth of what the sample
 * could give -- every earlier batch having been overwritten at the same publish
 * path (nanometa_live assembly audit, 2026-09-03, A3).
 *
 * This class remembers every read file seen for a key and hands the caller the
 * complete set, on the same reasoning as {@link CumulativeBatchAccumulator}:
 * the assembly is then a pure function of the accumulated set, so a late or
 * concurrent attempt cannot be built from less than an earlier one.
 *
 * It also answers when to attempt. Assembling on every arriving file is
 * pointless -- assembly is the most expensive step in the pipeline and its
 * result only improves as depth grows -- so an attempt is due when a whole
 * interval of files has arrived AND the pool has grown materially since the
 * last attempt. Batch mode collapses to a single final attempt, which is why
 * one code path serves both modes.
 *
 * ``accumulate`` is synchronized because Nextflow may run the calling operator
 * on several threads, and it returns fresh lists so callers never see the
 * internal collections mutate underneath them.
 */
class AssemblyReadAccumulator {

    private final Map store = [:]

    /**
     * Record one read file for a key and return the complete set so far.
     *
     * @param key   sample id, or "sample|taxid" for a targeted assembly
     * @param file  the read file, keyed by its own path so a re-emitted or
     *              retried task replaces its entry rather than doubling it
     * @return      every distinct read file seen for the key, in arrival order
     */
    synchronized List accumulate(String key, Object file) {
        def perKey = store.get(key, [files: [:] as LinkedHashMap, attempts: 0, lastCount: 0])
        if (file != null) {
            perKey.files[file.toString()] = file
        }
        return new ArrayList(perKey.files.values())
    }

    /**
     * Whether an attempt is due for a key, marking it taken when it is.
     *
     * Three rules, in order:
     *   1. A final attempt is always due, so a run always assembles what it
     *      ended with. This is the only rule batch mode ever uses.
     *   2. Otherwise a whole interval of new files must have arrived since the
     *      last attempt. An interval of 0 or less disables periodic attempts.
     *   3. And the pool must have grown by at least ``minGrowth`` since the
     *      last attempt: an interval tick that added a handful of reads to a
     *      large pool is not worth an hour of Flye.
     *
     * @param key        as for {@link #accumulate}
     * @param poolSize   number of files accumulated for the key
     * @param interval   files between periodic attempts
     * @param minGrowth  required fractional growth, e.g. 0.5 for 50%
     * @param isFinal    true for the end-of-run attempt
     * @return           true when the caller should assemble now
     */
    synchronized boolean attemptDue(String key, int poolSize, int interval,
                                    double minGrowth, boolean isFinal) {
        def perKey = store.get(key, [files: [:] as LinkedHashMap, attempts: 0, lastCount: 0])
        if (poolSize <= 0) {
            return false
        }
        if (!isFinal) {
            if (interval <= 0) {
                return false
            }
            if (poolSize - (perKey.lastCount as int) < interval) {
                return false
            }
            def needed = (perKey.lastCount as int) * (1.0d + minGrowth)
            if (perKey.lastCount as int > 0 && poolSize < needed) {
                return false
            }
        }
        // A final attempt that would repeat the last one exactly is not worth
        // re-running: the inputs are identical, so the result would be too.
        if (isFinal && (perKey.attempts as int) > 0 && poolSize == (perKey.lastCount as int)) {
            return false
        }
        perKey.attempts = (perKey.attempts as int) + 1
        perKey.lastCount = poolSize
        return true
    }

    /** How many attempts have been taken for a key. */
    synchronized int attemptsFor(String key) {
        def perKey = store.get(key)
        return perKey == null ? 0 : (perKey.attempts as int)
    }
}
