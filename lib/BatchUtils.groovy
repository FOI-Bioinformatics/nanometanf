import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import nextflow.Channel

/**
 * Utility for count-or-timeout batch flushing in real-time mode.
 *
 * Emits a batch (as a list) when either:
 * - batchSize files have accumulated, or
 * - timeoutSeconds have elapsed since the last file arrived
 *
 * This replaces collate(N) which has no timeout support.
 */
class BatchUtils {

    /**
     * Create a channel that batches items by count or timeout.
     *
     * @param ch_input Input channel of individual items
     * @param batchSize Max items per batch before forced emit
     * @param timeoutSeconds Seconds of inactivity before flushing partial batch
     * @return New channel emitting lists of items
     */
    static def batchWithTimeout(ch_input, int batchSize, int timeoutSeconds) {
        def output = Channel.create()
        def buffer = Collections.synchronizedList(new ArrayList())
        def scheduler = Executors.newSingleThreadScheduledExecutor({ r ->
            def t = new Thread(r, "batch-timeout-flush")
            t.daemon = true
            return t
        })
        def flushTaskRef = new java.util.concurrent.atomic.AtomicReference<ScheduledFuture>(null)

        def flush = {
            synchronized (buffer) {
                if (buffer.size() > 0) {
                    def batch = new ArrayList(buffer)
                    buffer.clear()
                    output.bind(batch)
                }
            }
        }

        def resetTimer = {
            def prev = flushTaskRef.get()
            if (prev != null) prev.cancel(false)
            def task = scheduler.schedule(flush, timeoutSeconds, TimeUnit.SECONDS)
            flushTaskRef.set(task)
        }

        ch_input.subscribe(
            onNext: { item ->
                synchronized (buffer) {
                    buffer.add(item)
                    if (buffer.size() >= batchSize) {
                        // Cancel pending timer and flush immediately
                        def prev = flushTaskRef.get()
                        if (prev != null) prev.cancel(false)
                        flush()
                    } else {
                        resetTimer()
                    }
                }
            },
            onComplete: {
                // Cancel any pending timer
                def prev = flushTaskRef.get()
                if (prev != null) prev.cancel(false)
                flush()
                scheduler.shutdown()
                output.bind(Channel.STOP)
            }
        )
        return output
    }
}
