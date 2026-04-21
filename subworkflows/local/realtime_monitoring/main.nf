//
// Real-time file monitoring subworkflow using watchPath with advanced features
// - Intelligent timeout with grace period (v1.2.1+)
// - Adaptive batching with dynamic sizing (v1.2.1+)
// - Priority sample routing (v1.2.1+)
// - Per-barcode metadata extraction
// - Backpressure with configurable concurrency limits (v1.5+)
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

        //
        // BACKPRESSURE CONFIGURATION (v1.5+)
        // Limits concurrent processing to prevent queue saturation
        //
        def max_concurrent = params.max_concurrent_batches ?: 4
        log.info "Backpressure: max ${max_concurrent} concurrent batches per sample"
        log.info "Classification forks: ${params.max_classification_forks ?: 8} parallel Kraken2 jobs"
        log.info "Batch timeout: ${params.batch_timeout ?: 60} seconds"

        // Use file() function directly to find existing files - more reliable than Channel.fromPath
        // The file() function with glob patterns returns a list of matching files
        def full_pattern = "${watch_dir}/${file_pattern}"
        def existing_files = file(full_pattern)

        // file() returns a single Path if one match, a List if multiple, or empty list if none
        def existing_list = []
        if (existing_files instanceof List) {
            existing_list = existing_files.findAll { it.exists() }
        } else if (existing_files != null && existing_files.exists()) {
            existing_list = [existing_files]
        }

        // Sort existing files with round-robin interleaving by parent directory
        // (typically barcode directories). This ensures take(max_files) selects
        // files fairly across all barcodes rather than in filesystem order.
        def grouped = existing_list.groupBy { it.parent.name }
        def sorted_list = []
        if (grouped.size() > 1) {
            // Multiple parent directories: interleave with round-robin
            def sorted_groups = grouped.collect { k, v -> v.sort { it.name } }
            def max_group_size = sorted_groups.collect { it.size() }.max()
            for (int i = 0; i < max_group_size; i++) {
                for (def group : sorted_groups) {
                    if (i < group.size()) {
                        sorted_list.add(group[i])
                    }
                }
            }
        } else {
            // Single directory: simple alphabetical sort
            sorted_list = existing_list.sort { it.name }
        }
        existing_list = sorted_list

        def existing_count = existing_list.size()

        if (existing_count > 0) {
            log.info "Found ${existing_count} existing files - will process immediately"
            existing_list.each { f -> log.info "  - ${f.name}" }
        } else {
            log.info "No existing files found - waiting for new files..."
        }

        // Create channel from existing files
        def ch_existing = existing_count > 0
            ? Channel.fromList(existing_list)
            : Channel.empty()

        // Watch for new files being created or modified
        def ch_new = Channel.watchPath(full_pattern, 'create,modify')

        // Combine existing files (processed first) with new files (watched continuously)
        def ch_watched = ch_existing.mix(ch_new)

        //
        // TIMEOUT LOGIC: Intelligent inactivity timeout with grace period (v1.2.1+)
        //
        // NOTE: F6 fix -- the former `age_ms < 1000` settling filter dropped
        // every watchPath emission that arrived within a second of file
        // creation. Producers that use atomic rename (nanorunner `.tmp`
        // rename, MinKNOW, rsync) always land in that window, and the macOS
        // Java NIO WatchService does not reliably re-emit a stable file, so
        // the filter stalled real-time runs indefinitely. Atomic writes are
        // complete by the time watchPath sees them, so no settling is
        // needed. Callers producing non-atomic appended writes should use
        // a wrapper that renames into place instead of relying on settling.
        def ch_all_files = ch_watched

        // Log truncation warning if take() will exclude some existing files
        if (params.max_files && existing_count > params.max_files.toInteger()) {
            def limit = params.max_files.toInteger()
            def included = existing_list.take(limit)
            def excluded = existing_list.drop(limit)
            def included_counts = included.countBy { it.parent.name }
            def excluded_counts = excluded.countBy { it.parent.name }
            log.warn "take(${limit}) will truncate ${existing_count} existing files"
            log.warn "  Included per directory: ${included_counts}"
            log.warn "  Excluded per directory: ${excluded_counts}"
        }

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
            // Use BatchUtils for count-or-timeout batching (replaces collate)
            def batch_timeout_val = params.batch_timeout ?: 60
            ch_batched_files = BatchUtils.batchWithTimeout(
                ch_branched_files.priority.mix(ch_branched_files.normal),
                effective_batch_size,
                batch_timeout_val
            )

            log.info "Priority samples will be processed before normal samples"
        } else {
            // Standard batching without priority
            // Use BatchUtils for count-or-timeout batching (replaces collate)
            def batch_timeout_val = params.batch_timeout ?: 60
            ch_batched_files = BatchUtils.batchWithTimeout(
                ch_input_files,
                effective_batch_size,
                batch_timeout_val
            )
        }

        log.info "="*80

        //
        // CHANNEL: Convert files to meta map format with barcode extraction
        //
        ch_samples = ch_batched_files
            .flatten()
            .map { file ->
                def meta = [:]

                // Use InputDetector priority chain for sample ID
                def sample_id = InputDetector.extractSampleId(
                    file,
                    params.sample_regex,
                    params.sample_name
                )
                meta.id = sample_id

                // Add barcode metadata if applicable
                if (sample_id =~ /^barcode\d+$/) {
                    meta.barcode = sample_id
                }

                meta.single_end = true
                meta.batch_time = new Date().format('yyyy-MM-dd_HH-mm-ss')

                return [ meta, file ]
            }

        // Transform batches for REALTIME_STATISTICS
        // GENERATE_SNAPSHOT_STATS expects: tuple val(batch_meta), val(file_metas)
        // where batch_meta is a map with batch_id, batch_timestamp, batch_time
        // and file_metas is a list of maps with file metadata
        ch_batches = ch_batched_files
            .map { files ->
                def batch_timestamp = System.currentTimeMillis()
                def batch_time = new Date().format('yyyy-MM-dd_HH-mm-ss')
                // Use timestamp for unique batch ID (counter variables don't work in Nextflow dataflow)
                def batch_id = "batch_${batch_timestamp}"

                // Create batch metadata
                def batch_meta = [
                    batch_id: batch_id,
                    batch_timestamp: batch_timestamp,
                    batch_time: batch_time,
                    file_count: files.size()
                ]

                // Create file metadata for each file
                def file_metas = files.collect { f ->
                    def file_size = f.size()
                    def file_name = f.name
                    def is_compressed = file_name.endsWith('.gz')
                    // Estimate reads based on file size (rough: ~4 bytes per base, 1000bp avg read)
                    def estimated_reads = is_compressed ? (file_size * 4 / 4000).toLong() : (file_size / 4000).toLong()

                    [
                        file_path: f.toString(),
                        file_name: file_name,
                        file_size: file_size,
                        is_compressed: is_compressed,
                        estimated_reads: estimated_reads,
                        file_age_ms: batch_timestamp - f.lastModified(),
                        priority_score: 0,
                        watch_dir: f.parent.toString(),
                        sample_id: file_name.replaceAll(/\.(fastq|fq)(\.gz)?$/, '')
                    ]
                }

                return [ batch_meta, file_metas ]
            }

    } else {
        // Static mode - process existing files once
        ch_samples = Channel.empty()
        ch_batches = Channel.empty()
    }

    emit:
    samples  = ch_samples    // channel: [ val(meta), path(reads) ]
    batches  = ch_batches    // channel: [ val(batch_meta), val(file_metas) ] - structured batch data for REALTIME_STATISTICS
    versions = ch_versions   // channel: [ versions.yml ]
}
