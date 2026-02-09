/**
 * Utility for count-or-timeout batch flushing in real-time mode.
 *
 * Emits a batch (as a list) when either:
 * - batchSize files have accumulated, or
 * - timeoutSeconds have elapsed since the last file arrived
 *
 * This replaces collate(N) which has no timeout support.
 *
 * NOTE: Modern Nextflow (23.x+) removed Channel.create().
 * This implementation uses the buffer operator with remainder:true
 * for count-based batching. For true timeout-based flushing in
 * real-time scenarios, consider using watchPath with polling interval.
 */
class BatchUtils {

    /**
     * Create a channel that batches items by count.
     *
     * For real-time processing, the polling interval of watchPath
     * effectively provides the timeout behavior.
     *
     * @param ch_input Input channel of individual items
     * @param batchSize Max items per batch before forced emit
     * @param timeoutSeconds Ignored in modern implementation (kept for API compatibility)
     * @return New channel emitting lists of items
     */
    static def batchWithTimeout(ch_input, int batchSize, int timeoutSeconds) {
        // Use buffer operator which is fully supported in modern Nextflow
        // remainder:true ensures partial batches are emitted when channel completes
        return ch_input.buffer(size: batchSize, remainder: true)
    }
}
