/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ERROR_HANDLER SUBWORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Comprehensive error handling with classification, retry logic, circuit breaker,
    and dead letter queue for failed samples.

    Implements Section 3.3 - Error Handling & Retry Logic:
    1. Error classification (retryable vs fatal)
    2. Exponential backoff for transient failures
    3. Circuit breaker pattern for repeated failures
    4. Dead letter queue for permanently failed samples
    5. Partial failure recovery - continue processing other samples
----------------------------------------------------------------------------------------
*/

include { ERROR_CLASSIFIER             } from "${projectDir}/modules/local/error_classifier/main"
include { EXPONENTIAL_BACKOFF_HANDLER  } from "${projectDir}/modules/local/exponential_backoff_handler/main"
include { CIRCUIT_BREAKER              } from "${projectDir}/modules/local/circuit_breaker/main"
include { DEAD_LETTER_QUEUE            } from "${projectDir}/modules/local/dead_letter_queue/main"

workflow ERROR_HANDLER {

    take:
    ch_failed_samples    // channel: [ val(meta), val(error_message), val(error_type) ]
    base_delay           // val: Base delay for exponential backoff (default: 2s)
    max_delay            // val: Maximum backoff delay (default: 300s)
    backoff_factor       // val: Exponential factor (default: 2.0)
    failure_threshold    // val: Circuit breaker failure threshold (default: 5)
    time_window          // val: Circuit breaker time window (default: 300s)
    max_retries          // val: Maximum retry attempts (default: 10)

    main:
    ch_versions = Channel.empty()

    // Track failure history for circuit breaker
    def failure_history = []

    // Track permanently failed samples for dead letter queue
    def dead_letter_samples = []

    //
    // MODULE: Classify errors as retryable or fatal
    //
    ERROR_CLASSIFIER (
        ch_failed_samples
    )
    ch_versions = ch_versions.mix(ERROR_CLASSIFIER.out.versions.first())

    // Split classified errors into retryable and fatal
    ch_classified = ERROR_CLASSIFIER.out.classified_error

    ch_retryable = ch_classified
        .filter { meta, error_msg, category, retry_recommended ->
            retry_recommended == 'YES'
        }
        .map { meta, error_msg, category, retry_recommended ->
            [meta, error_msg, category]
        }

    ch_fatal = ch_classified
        .filter { meta, error_msg, category, retry_recommended ->
            retry_recommended == 'NO'
        }
        .map { meta, error_msg, category, retry_recommended ->
            // Add to failure history
            failure_history.add([
                sample_id: meta.id,
                error_category: category,
                timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss")
            ])

            // Add to dead letter queue
            dead_letter_samples.add([
                sample_id: meta.id,
                error_message: error_msg,
                error_category: category,
                error_type: 'FATAL',
                retry_count: meta.retry_count ?: 0,
                timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss"),
                metadata: meta
            ])

            log.error "❌ FATAL ERROR: ${meta.id} - ${category} - ${error_msg}"
            return [meta, error_msg, category]
        }

    //
    // MODULE: Handle retryable errors with exponential backoff
    //
    ch_retry_candidates = ch_retryable
        .map { meta, error_msg, category ->
            def retry_count = meta.retry_count ?: 0
            [meta, retry_count]
        }

    EXPONENTIAL_BACKOFF_HANDLER (
        ch_retry_candidates,
        base_delay,
        max_delay,
        backoff_factor
    )
    ch_versions = ch_versions.mix(EXPONENTIAL_BACKOFF_HANDLER.out.versions.first())

    // Process backoff decisions
    ch_backoff_results = EXPONENTIAL_BACKOFF_HANDLER.out.backoff_decision
        .join(ch_retryable)
        .map { meta, delay, should_retry, error_msg, category ->

            if (should_retry == 'YES') {
                // Increment retry count
                def updated_meta = meta + [retry_count: (meta.retry_count ?: 0) + 1]

                log.warn "⏱️  RETRY: ${meta.id} will retry in ${delay}s (attempt ${updated_meta.retry_count})"

                return ['RETRY', updated_meta, error_msg, category, delay]
            } else {
                // Max retries exceeded - send to dead letter queue
                log.error "🛑 MAX RETRIES: ${meta.id} exceeded maximum retry attempts"

                dead_letter_samples.add([
                    sample_id: meta.id,
                    error_message: error_msg,
                    error_category: category,
                    error_type: 'MAX_RETRIES_EXCEEDED',
                    retry_count: meta.retry_count ?: 0,
                    timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss"),
                    metadata: meta
                ])

                failure_history.add([
                    sample_id: meta.id,
                    error_category: category,
                    timestamp: new Date().format("yyyy-MM-dd'T'HH:mm:ss")
                ])

                return ['DEAD_LETTER', meta, error_msg, category, delay]
            }
        }

    // Split into retry and dead letter channels
    ch_for_retry = ch_backoff_results
        .filter { status, meta, error_msg, category, delay -> status == 'RETRY' }
        .map { status, meta, error_msg, category, delay -> [meta, error_msg, category] }

    ch_max_retries_exceeded = ch_backoff_results
        .filter { status, meta, error_msg, category, delay -> status == 'DEAD_LETTER' }
        .map { status, meta, error_msg, category, delay -> [meta, error_msg, category] }

    //
    // MODULE: Circuit breaker - detect repeated failures
    //
    CIRCUIT_BREAKER (
        Channel.value(failure_history),
        failure_threshold,
        time_window,
        'error_handler'
    )
    ch_versions = ch_versions.mix(CIRCUIT_BREAKER.out.versions.first())

    // Monitor circuit breaker state
    CIRCUIT_BREAKER.out.circuit_state
        .subscribe { state ->
            if (state == 'OPEN') {
                log.error """
                🚨 CIRCUIT BREAKER OPEN 🚨
                Too many failures detected - pipeline may be experiencing systemic issues.
                Review circuit_breaker_report.json for details.
                """.stripIndent()
            } else if (state == 'HALF_OPEN') {
                log.warn """
                ⚠️  CIRCUIT BREAKER HALF-OPEN
                Failure threshold approaching - proceed with caution.
                """.stripIndent()
            }
        }

    //
    // MODULE: Dead letter queue - collect permanently failed samples
    //
    DEAD_LETTER_QUEUE (
        Channel.value(dead_letter_samples),
        'error_handler'
    )
    ch_versions = ch_versions.mix(DEAD_LETTER_QUEUE.out.versions.first())

    emit:
    retryable_samples        = ch_for_retry              // channel: [ val(meta), val(error_msg), val(category) ]
    fatal_samples            = ch_fatal                  // channel: [ val(meta), val(error_msg), val(category) ]
    max_retries_exceeded     = ch_max_retries_exceeded   // channel: [ val(meta), val(error_msg), val(category) ]
    circuit_breaker_state    = CIRCUIT_BREAKER.out.circuit_state
    circuit_breaker_report   = CIRCUIT_BREAKER.out.breaker_report
    dead_letter_manifest     = DEAD_LETTER_QUEUE.out.manifest
    dead_letter_summary      = DEAD_LETTER_QUEUE.out.summary
    error_reports            = ERROR_CLASSIFIER.out.error_report
    backoff_reports          = EXPONENTIAL_BACKOFF_HANDLER.out.backoff_report
    versions                 = ch_versions
}
