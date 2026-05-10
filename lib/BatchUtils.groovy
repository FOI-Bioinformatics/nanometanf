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
}
