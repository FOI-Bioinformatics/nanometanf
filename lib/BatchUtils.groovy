import java.util.concurrent.ConcurrentLinkedDeque
import groovyx.gpars.dataflow.DataflowQueue
import groovyx.gpars.dataflow.operator.PoisonPill

/**
 * Utility for count-or-timeout batch flushing in real-time mode.
 *
 * Emits a batch (as a list) when either:
 *   - batchSize items have accumulated, or
 *   - timeoutSeconds have elapsed since the last flush, with at least
 *     one pending item in the buffer.
 *
 * The timeout branch is the difference between this operator and a
 * plain buffer(size: N, remainder: true): on a low-throughput run
 * (single barcode, slow MinKNOW release cadence) buffer alone would
 * sit at e.g. 0/10 forever and never produce a Kraken2 report until
 * the upstream watchPath channel finally closed via the idle timeout.
 *
 * Implementation notes:
 *   - subscribe() is used as the upstream consumer; it routes each
 *     incoming item into a thread-safe deque and emits a batch on the
 *     output channel as soon as either the size threshold or a timer
 *     tick says so. Earlier revisions of this method tried to use
 *     subscribe purely as a side-effect listener while feeding the
 *     same channel into mix() -- but Nextflow's subscribe is built
 *     on Dataflow.operator and acts as a competing consumer, so the
 *     mix branch only saw a fraction of the items.
 *   - A daemon Timer (so it cannot pin the JVM) periodically calls
 *     flushIfPending(). The same Timer / DataflowQueue idiom is used
 *     in subworkflows/local/realtime_monitoring/main.nf for the
 *     realtime_timeout_minutes sentinel.
 *   - timeoutSeconds <= 0 falls back to the previous count-only
 *     behaviour, so callers that explicitly want no timeout can pass
 *     0 or a negative value.
 */
class BatchUtils {

    /**
     * Run a closure under synchronization on the given lock target.
     *
     * The Nextflow strict grammar (NXF_SYNTAX_PARSER=v2, default in 26+)
     * rejects `synchronized` and `finally` keywords in script scope, so
     * `.nf` callers cannot use them directly. This helper lives in a
     * Groovy class (parsed by the Groovy compiler, not Nextflow's
     * grammar) and provides a v2-safe wrapper.
     *
     * @param lockTarget  The object to synchronize on
     * @param action      Closure to invoke under the lock
     * @return            The closure's return value
     */
    static def withLock(Object lockTarget, Closure action) {
        synchronized(lockTarget) {
            return action.call()
        }
    }

    /**
     * Create a channel that batches items by count or by elapsed time.
     *
     * @param ch_input         Input channel of individual items
     * @param batchSize        Max items per batch before forced emit
     * @param timeoutSeconds   Max seconds between flushes; <= 0 disables the timeout branch
     * @return New channel emitting lists of items
     */
    static def batchWithTimeout(ch_input, int batchSize, int timeoutSeconds) {
        // Edge case: no timeout requested -- preserve the prior simple behaviour.
        if (timeoutSeconds <= 0) {
            return ch_input.buffer(size: batchSize, remainder: true)
        }

        final DataflowQueue ch_output = new DataflowQueue()
        final ConcurrentLinkedDeque buffer = new ConcurrentLinkedDeque()
        final Object lock = new Object()

        // Drain the current buffer into a list and emit it as one batch.
        // Caller must hold `lock`.
        Closure drainAndEmit = {
            if (buffer.isEmpty()) {
                return
            }
            def batch = []
            def item = buffer.pollFirst()
            while (item != null) {
                batch.add(item)
                item = buffer.pollFirst()
            }
            try {
                ch_output.bind(batch)
            } catch (Exception e) {
                // Output already closed; nothing more we can do.
            }
        }

        // Daemon Timer so JVM shutdown is not blocked by us.
        // scheduleAtFixedRate with both initial delay and period so the
        // first flush only fires after timeoutSeconds (callers that emit
        // a quick burst should reach the size threshold before this
        // first tick).
        final long periodMs = timeoutSeconds * 1000L
        final Timer timer = new Timer('batch-timeout-flush', /* daemon */ true)
        timer.scheduleAtFixedRate({
            try {
                synchronized(lock) {
                    drainAndEmit()
                }
            } catch (Exception e) {
                timer.cancel()
            }
        } as TimerTask, periodMs, periodMs)

        // Drive the buffer from ch_input via subscribe. Nextflow's
        // subscribe binds to a Dataflow.operator, so it acts as the
        // single consumer of ch_input -- exactly what we want here.
        // The closures fire serially per channel item, so the lock
        // really just guards against the timer thread racing the
        // subscribe thread.
        ch_input.subscribe(
            onNext: { item ->
                synchronized(lock) {
                    buffer.add(item)
                    if (buffer.size() >= batchSize) {
                        drainAndEmit()
                    }
                }
            },
            onComplete: {
                try {
                    synchronized(lock) {
                        drainAndEmit()
                    }
                    ch_output.bind(PoisonPill.instance)
                } catch (Exception e) {
                    // Already closed.
                }
                timer.cancel()
            }
        )

        return ch_output
    }

    /**
     * Round-robin interleave a list of files by their parent directory
     * (typically the barcode folder), so downstream per-file consumption
     * rotates fairly across barcodes instead of draining one barcode before
     * the next. For [bc1/a, bc1/b, bc2/c] this yields [bc1/a, bc2/c, bc1/b].
     *
     * Pure and side-effect-free: it only reorders the input (every input file
     * appears exactly once in the output), so it cannot stall or lose data.
     * Used both for the startup existing-files scan and to interleave each
     * realtime batch before it is flattened into the per-file classifier
     * stream, giving per-barcode fairness against the GLOBAL classifier
     * maxForks without a per-key semaphore / feedback loop (audit P2.9).
     *
     * Files within a barcode keep a stable name-sorted order; a single
     * barcode (or a list with no resolvable parent) is name-sorted as-is.
     *
     * @param files  list of file/Path objects (each exposing .parent.name and .name)
     * @return       a new list, round-robin interleaved by parent dir
     */
    static List interleaveFilesByParentDir(List files) {
        if (!files || files.size() <= 1) {
            return files ? new ArrayList(files) : []
        }
        def grouped = files.groupBy { it?.parent?.name ?: 'unknown' }
        if (grouped.size() <= 1) {
            return files.sort(false) { it?.name ?: '' }
        }
        // Sort each barcode's files by name, then take one from each group per
        // round until every group is exhausted.
        def sorted_groups = grouped.values().collect { g -> g.sort(false) { it?.name ?: '' } }
        def max_group_size = sorted_groups.collect { it.size() }.max()
        def out = []
        (0..<max_group_size).each { i ->
            sorted_groups.each { group ->
                if (i < group.size()) {
                    out.add(group[i])
                }
            }
        }
        return out
    }
}
