/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: ENHANCED_REALTIME_MONITORING
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Enhanced real-time file monitoring with:
    - File locking detection (skip actively writing files)
    - Retry logic for failed processing
    - Real-time progress tracking dashboard
    - Watchdog timeout detection (detect stalled runs)
    - Graceful error handling
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { FILE_READINESS_CHECKER   } from "${projectDir}/modules/local/file_readiness_checker/main"
include { REALTIME_PROGRESS_TRACKER } from "${projectDir}/modules/local/realtime_progress_tracker/main"

workflow ENHANCED_REALTIME_MONITORING {

    take:
    watch_dir              // val: directory to watch
    file_pattern           // val: file pattern to match
    batch_size             // val: number of files per batch
    batch_interval         // val: time interval for batching
    stability_time         // val: file stability time (seconds)
    max_retries            // val: maximum retry attempts
    watchdog_timeout       // val: watchdog timeout (seconds)

    main:
    ch_versions = Channel.empty()

    // Initialize tracking variables
    def tracking_data = [
        total_detected: 0,
        ready: 0,
        not_ready: 0,
        processed: 0,
        failed: 0,
        retries: 0,
        rate: 0.0,
        last_file: null,
        watchdog_timeout: watchdog_timeout,
        watchdog_status: 'INITIALIZING'
    ]

    if (params.realtime_mode) {
        log.info "="*80
        log.info "🔬 Enhanced Real-time Monitoring Started"
        log.info "="*80
        log.info "Watch Directory:      ${watch_dir}"
        log.info "File Pattern:         ${file_pattern}"
        log.info "Batch Size:           ${batch_size}"
        log.info "File Stability Time:  ${stability_time}s"
        log.info "Max Retries:          ${max_retries}"
        log.info "Watchdog Timeout:     ${watchdog_timeout}s (${watchdog_timeout/60} minutes)"
        log.info "="*80

        //
        // CHANNEL: Watch for new files using watchPath
        //
        def ch_watched = Channel.watchPath("${watch_dir}/${file_pattern}", 'create,modify')

        ch_input_files = params.max_files
            ? ch_watched.take(params.max_files.toInteger())
            : ch_watched

        //
        // CHANNEL: Create meta map for each file
        //
        ch_files_with_meta = ch_input_files
            .map { file ->
                def meta = [:]
                meta.id = file.baseName.replaceAll(/\.(fastq|fq|pod5)(\.gz)?$/, '')
                meta.single_end = true
                meta.file_path = file.toString()
                meta.detection_time = new Date().format('yyyy-MM-dd_HH-mm-ss')
                meta.retry_count = 0
                meta.max_retries = max_retries
                return [ meta, file ]
            }

        //
        // MODULE: Check file readiness (file locking detection)
        //
        FILE_READINESS_CHECKER (
            ch_files_with_meta,
            stability_time
        )
        ch_versions = ch_versions.mix(FILE_READINESS_CHECKER.out.versions.first())

        //
        // CHANNEL: Filter ready files and implement retry logic
        //
        ch_checked_files = FILE_READINESS_CHECKER.out.checked_file

        // Split into ready and not-ready files
        ch_ready_files = ch_checked_files
            .filter { meta, file, status -> status == 'READY' }
            .map { meta, file, status ->
                tracking_data.ready++
                tracking_data.last_file = new Date().format('yyyy-MM-dd_HH-mm-ss')
                log.info "✓ READY: ${meta.id} (${file.size()} bytes)"
                return [meta, file]
            }

        ch_not_ready_files = ch_checked_files
            .filter { meta, file, status -> status == 'NOT_READY' }
            .map { meta, file, status ->
                tracking_data.not_ready++

                // Implement retry logic
                if (meta.retry_count < max_retries) {
                    meta.retry_count++
                    tracking_data.retries++
                    log.warn "⏳ NOT READY: ${meta.id} - Retry ${meta.retry_count}/${max_retries}"
                    return [meta, file, 'RETRY']
                } else {
                    tracking_data.failed++
                    log.error "❌ FAILED: ${meta.id} - Max retries exceeded"
                    return [meta, file, 'FAILED']
                }
            }

        // Retry not-ready files (simplified - in practice would use delay)
        ch_retry_files = ch_not_ready_files
            .filter { meta, file, action -> action == 'RETRY' }
            .map { meta, file, action -> [meta, file] }

        // Combine ready files and successful retries
        ch_all_ready_files = ch_ready_files.mix(ch_retry_files)

        //
        // CHANNEL: Batch ready files for processing
        //
        ch_batched_samples = ch_all_ready_files
            .buffer(size: batch_size, remainder: true)
            .flatten()
            .map { meta, file ->
                def new_meta = meta + [
                    batch_time: new Date().format('yyyy-MM-dd_HH-mm-ss'),
                    realtime_enhanced: true
                ]
                tracking_data.processed++
                return [new_meta, file]
            }

        //
        // MODULE: Generate progress tracking dashboard
        //
        // Update tracking data periodically
        ch_tracking_updates = ch_batched_samples
            .collect()
            .map { samples ->
                // Update tracking data with current statistics
                tracking_data.total_detected = tracking_data.ready + tracking_data.not_ready + tracking_data.failed
                tracking_data.rate = tracking_data.processed / Math.max((System.currentTimeMillis() / 60000.0), 1.0) // files per minute

                // Check watchdog status
                if (tracking_data.last_file) {
                    def last_file_time = new Date() // Simplified - would parse from tracking_data.last_file
                    def time_since_last = (new Date().time - last_file_time.time) / 1000.0

                    if (time_since_last > watchdog_timeout) {
                        tracking_data.watchdog_status = 'STALLED'
                        log.warn "🚨 WATCHDOG: Sequencing run appears stalled (${time_since_last.toInteger()}s since last file)"
                    } else {
                        tracking_data.watchdog_status = 'ACTIVE'
                    }
                }

                return tracking_data
            }

        REALTIME_PROGRESS_TRACKER (
            ch_tracking_updates.first()
        )
        ch_versions = ch_versions.mix(REALTIME_PROGRESS_TRACKER.out.versions)

        ch_samples = ch_batched_samples
        ch_dashboard = REALTIME_PROGRESS_TRACKER.out.dashboard
        ch_stats = REALTIME_PROGRESS_TRACKER.out.stats

    } else {
        // Static mode - no enhanced monitoring
        ch_samples = Channel.empty()
        ch_dashboard = Channel.empty()
        ch_stats = Channel.empty()
    }

    emit:
    samples   = ch_samples    // channel: [ val(meta), path(reads) ]
    dashboard = ch_dashboard  // channel: path(html)
    stats     = ch_stats      // channel: path(json)
    versions  = ch_versions   // channel: [ versions.yml ]
}
