//
// Real-time file monitoring subworkflow using watchPath with advanced features
// - Intelligent timeout with grace period (v1.2.1+)
// - Adaptive batching with dynamic sizing (v1.2.1+)
// - Priority sample routing (v1.2.1+)
// - Per-barcode metadata extraction
//

workflow REALTIME_MONITORING {

    take:
    watch_dir      // val: directory to watch
    file_pattern   // val: file pattern to match
    batch_size     // val: number of files per batch
    batch_interval // val: time interval for batching

    main:

    ch_versions = Channel.empty()

    //
    // CHANNEL: Watch for new FASTQ files using watchPath
    //
    if (params.realtime_mode) {
        log.info "="*80
        log.info "Starting real-time monitoring of: ${watch_dir}"
        log.info "File pattern: ${file_pattern}"
        log.info "Batch size: ${batch_size}"
        log.info "Batch interval: ${batch_interval}"

        // Watch for files
        def ch_watched = Channel.watchPath("${watch_dir}/${file_pattern}", 'create,modify')

        //
        // TIMEOUT LOGIC: Intelligent inactivity timeout with grace period (v1.2.1+)
        //
        def ch_all_files = ch_watched

        // Apply timeout logic if realtime_timeout_minutes is set
        if (params.realtime_timeout_minutes) {
            log.info "Real-time timeout enabled: Will stop after ${params.realtime_timeout_minutes} minutes of inactivity"
            log.info "Grace period: ${params.realtime_processing_grace_period} minutes for processing completion"
            log.info "="*80

            // Create heartbeat channel that checks timeout every minute
            def ch_timeout_check = Channel.interval('1min').map { 'TIMEOUT_CHECK' }

            // Tag files and mix with timeout checks
            def ch_files_tagged = ch_all_files.map { file -> ['FILE', file] }
            def ch_checks_tagged = ch_timeout_check.map { check -> ['CHECK', check] }
            def ch_mixed = ch_files_tagged.mix(ch_checks_tagged)

            // Define immutable state object for functional reactive pattern
            // Using .scan() operator to maintain state without mutations
            def initialState = [
                last_file_time: System.currentTimeMillis(),
                grace_period_start: null,
                in_grace_period: false,
                files_processed: 0,
                should_stop: false,
                type: null,
                item: null
            ]

            // Apply timeout logic using functional .scan() pattern
            // Each state transition returns a NEW immutable state object
            ch_input_files = ch_mixed
                .scan(initialState) { state, tuple ->
                    def (type, item) = tuple

                    if (type == 'FILE') {
                        // File detected - create new state with reset timer
                        def new_files_processed = state.files_processed + 1
                        def reached_max = params.max_files && new_files_processed >= params.max_files

                        // Log grace period exit if we were in one
                        if (state.in_grace_period) {
                            log.info "New file detected during grace period - resetting timeout"
                        }

                        // Log max_files limit reached
                        if (reached_max) {
                            log.info "Real-time monitoring: Reached max_files limit (${params.max_files})"
                        }

                        // Return new immutable state
                        return [
                            last_file_time: System.currentTimeMillis(),
                            grace_period_start: null,
                            in_grace_period: false,
                            files_processed: new_files_processed,
                            should_stop: reached_max,
                            type: type,
                            item: item
                        ]

                    } else if (type == 'CHECK') {
                        // Periodic timeout check - compute new state based on elapsed time
                        def current_time = System.currentTimeMillis()
                        def inactive_ms = current_time - state.last_file_time
                        def inactive_minutes = inactive_ms / (1000 * 60)

                        if (!state.in_grace_period) {
                            // Not yet in grace period - check if detection timeout reached
                            if (inactive_minutes >= params.realtime_timeout_minutes) {
                                // Detection timeout reached - enter grace period
                                log.info "="*80
                                log.info "TIMEOUT: No new files detected for ${params.realtime_timeout_minutes} minutes"
                                log.info "Entering grace period: ${params.realtime_processing_grace_period} minutes"
                                log.info "Waiting for downstream processing to complete..."
                                log.info "="*80

                                return [
                                    last_file_time: state.last_file_time,
                                    grace_period_start: current_time,
                                    in_grace_period: true,
                                    files_processed: state.files_processed,
                                    should_stop: false,
                                    type: type,
                                    item: item
                                ]
                            }
                        } else {
                            // Already in grace period - check if grace period exceeded
                            def grace_period_ms = current_time - state.grace_period_start
                            def grace_period_minutes = grace_period_ms / (1000 * 60)

                            // Log grace period progress
                            def total_inactive = inactive_minutes.round(1)
                            def grace_elapsed = grace_period_minutes.round(1)
                            log.info "Grace period: ${grace_elapsed}/${params.realtime_processing_grace_period} min elapsed"

                            if (grace_period_minutes >= params.realtime_processing_grace_period) {
                                log.info "="*80
                                log.info "Real-time monitoring STOPPED: Grace period completed"
                                log.info "Total files processed: ${state.files_processed}"
                                log.info "="*80

                                return [
                                    last_file_time: state.last_file_time,
                                    grace_period_start: state.grace_period_start,
                                    in_grace_period: state.in_grace_period,
                                    files_processed: state.files_processed,
                                    should_stop: true,
                                    type: type,
                                    item: item
                                ]
                            }
                        }

                        // No state change, preserve existing state with current event
                        return [
                            last_file_time: state.last_file_time,
                            grace_period_start: state.grace_period_start,
                            in_grace_period: state.in_grace_period,
                            files_processed: state.files_processed,
                            should_stop: false,
                            type: type,
                            item: item
                        ]
                    }

                    // Unknown type - preserve state
                    return [
                        last_file_time: state.last_file_time,
                        grace_period_start: state.grace_period_start,
                        in_grace_period: state.in_grace_period,
                        files_processed: state.files_processed,
                        should_stop: false,
                        type: type,
                        item: item
                    ]
                }
                .until { state -> state.should_stop }  // Stop when state indicates completion
                .filter { state -> state.type == 'FILE' }  // Only emit file events
                .map { state -> state.item }  // Extract file from state object
        } else {
            // No timeout - use max_files only or run indefinitely
            ch_input_files = params.max_files
                ? ch_all_files.take(params.max_files.toInteger())
                : ch_all_files

            if (!params.max_files) {
                log.warn "WARNING: No timeout or max_files set - pipeline will run indefinitely!"
                log.warn "Consider setting --realtime_timeout_minutes or --max_files"
            }
            log.info "="*80
        }

        //
        // ADAPTIVE BATCHING: Dynamic batch size adjustment (v1.2.1+)
        //
        def effective_batch_size = batch_size

        if (params.adaptive_batching) {
            log.info "Adaptive batching ENABLED"

            def min_size = params.min_batch_size ?: 1
            def max_size = params.max_batch_size ?: 50
            def factor = params.batch_size_factor ?: 1.0

            // Use batch_size as baseline, scaled by factor
            effective_batch_size = (batch_size * factor).toInteger()
            effective_batch_size = Math.max(min_size, Math.min(max_size, effective_batch_size))

            log.info "  Batch size range: ${min_size} - ${max_size}"
            log.info "  Batch size factor: ${factor}"
            log.info "  Effective batch size: ${effective_batch_size}"
        }

        //
        // PRIORITY ROUTING: Process priority samples first (v1.2.1+)
        //
        if (params.priority_samples && params.priority_samples.size() > 0) {
            log.info "Priority routing ENABLED"
            log.info "  Priority samples (${params.priority_samples.size()}): ${params.priority_samples.join(', ')}"

            // Branch into priority and normal streams
            ch_input_files
                .branch { file ->
                    def sample_id = file.baseName.replaceAll(/\.(fastq|fq)(\.gz)?$/, '')

                    // Check if this file matches any priority sample pattern
                    def is_priority = params.priority_samples.any { priority_pattern ->
                        sample_id.contains(priority_pattern) || sample_id.matches(priority_pattern)
                    }

                    priority: is_priority
                        log.debug "Priority sample detected: ${sample_id}"
                        return file
                    normal: true
                        return file
                }
                .set { ch_branched_files }

            // Mix priority files first (they will be processed before normal files)
            ch_batched_files = ch_branched_files.priority
                .mix(ch_branched_files.normal)
                .buffer(size: effective_batch_size, remainder: true)

            log.info "Priority samples will be processed before normal samples"
        } else {
            // Standard batching without priority
            ch_batched_files = ch_input_files
                .buffer(size: effective_batch_size, remainder: true)
        }

        log.info "="*80

        //
        // CHANNEL: Convert files to meta map format with barcode extraction
        //
        ch_samples = ch_batched_files
            .flatten()
            .map { file ->
                def meta = [:]
                def filename = file.baseName.replaceAll(/\.(fastq|fq)(\.gz)?$/, '')

                // Extract barcode if present in filename (barcode01, barcode02, etc.)
                def barcode_match = filename =~ /barcode(\d+)/
                if (barcode_match) {
                    meta.barcode = "barcode" + barcode_match[0][1]
                }

                meta.id = filename
                meta.single_end = true // Assume single-end for nanopore
                meta.batch_time = new Date().format('yyyy-MM-dd_HH-mm-ss')

                return [ meta, file ]
            }

    } else {
        // Static mode - process existing files once
        ch_samples = Channel.empty()
    }

    emit:
    samples  = ch_samples    // channel: [ val(meta), path(reads) ]
    versions = ch_versions   // channel: [ versions.yml ]
}
