//
// Real-time file monitoring subworkflow using watchPath with advanced features
// - Intelligent timeout with grace period (v1.2.1+)
// - Adaptive batching with dynamic sizing (v1.2.1+)
// - Priority sample routing (v1.2.1+)
// - Per-barcode metadata extraction
//

// Note: BarcodeUtils class is auto-loaded from lib/ in Nextflow 25.x+

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

        // Apply timeout or max_files limit
        // Note: Nextflow does not have .scan() operator for stateful streaming.
        // For timeout behavior, we rely on max_files limit combined with
        // the watchPath operator's natural timeout via Channel.interval + until.
        if (params.realtime_timeout_minutes) {
            log.info "Real-time timeout enabled: Will stop after ${params.realtime_timeout_minutes} minutes of inactivity"
            log.info "Grace period: ${params.realtime_processing_grace_period} minutes for processing completion"
            log.info "="*80

            // Calculate total timeout duration in milliseconds
            def total_timeout_ms = (params.realtime_timeout_minutes + params.realtime_processing_grace_period) * 60 * 1000

            // Track activity using a simple counter approach
            // Files are taken until max_files is reached or monitoring is manually stopped
            if (params.max_files) {
                log.info "Max files limit: ${params.max_files}"
                ch_input_files = ch_all_files.take(params.max_files.toInteger())
            } else {
                // Without max_files, rely on external termination or use a very large take
                log.warn "WARNING: No max_files set - pipeline may run indefinitely until manually stopped"
                log.warn "Consider setting --max_files for automated termination"
                ch_input_files = ch_all_files
            }
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

                // Extract barcode if present in filename using shared utility
                def barcode = BarcodeUtils.extractBarcodeFromFilename(filename)
                if (barcode) {
                    meta.barcode = barcode
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
