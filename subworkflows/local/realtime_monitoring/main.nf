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
        //
        // ``max_classification_forks`` is enforced by ``maxForks`` on
        // the KRAKEN2_INCREMENTAL_CLASSIFIER / KRAKEN2_OPTIMIZED /
        // KRAKEN2_KRAKEN2 process declarations in conf/modules.config.
        // It is a *global* fork cap across all in-flight classification
        // tasks, regardless of which barcode emitted them.
        //
        // ``max_concurrent_batches`` is currently *advisory only*. The
        // intent (one barcode cannot occupy more than N classifier
        // slots) cannot be expressed cleanly in Nextflow DSL2 because
        // ``maxForks`` is per-process, not per-key. The audit P2.9
        // item tracks the work to add a per-key throttle (likely a
        // custom Groovy operator in lib/BatchUtils.groovy that wraps
        // a per-sample semaphore over the batches channel). Until then,
        // operators who see a single slow barcode starve others should
        // raise ``--max_classification_forks`` proportionally to the
        // number of barcodes -- e.g. on a 24-plex run set forks to at
        // least 6 so every barcode can land at least one classifier
        // slot in steady state.
        //
        def max_classification_forks = params.max_classification_forks ?: 8
        def batch_timeout = params.batch_timeout ?: 60
        log.info "Backpressure: classifier maxForks = ${max_classification_forks} (global cap, not per-barcode)"
        log.info "Batch timeout: ${batch_timeout} seconds"
        if (params.max_concurrent_batches != null) {
            log.info "NOTE: ``--max_concurrent_batches ${params.max_concurrent_batches}`` is currently advisory; see audit P2.9 for the planned per-barcode throttle"
        }

        //
        // RUNTIME METRICS SNAPSHOTS (audit V5)
        //
        // Audit V5 asked for "live or simulated 24-barcode run with
        // executor queue-depth metrics collected from .nextflow.log to
        // confirm backpressure behaviour". Two complementary streams
        // satisfy that request without instrumenting Nextflow internals:
        //   1. ``trace.fields`` in nextflow.config now exports submit /
        //      start / complete / queue, so post-hoc analysis can chart
        //      per-task waiting time directly from
        //      ``execution_trace_<ts>.txt``.
        //   2. This block runs a daemon Timer that periodically emits a
        //      structured ``[runtime-metrics]`` log line with the live
        //      counters (files seen, batches emitted, per-barcode batch
        //      counts). Operators can grep ``.nextflow.log`` for
        //      ``[runtime-metrics]`` and pipe through ``jq`` / ``awk``.
        //
        // The interval is controlled by ``params.runtime_metrics_interval_seconds``.
        // Default 0 (disabled) keeps batch-mode runs silent; field
        // operators set e.g. ``--runtime_metrics_interval_seconds 60``
        // when collecting V5 evidence on a 24-barcode run.
        //
        def metrics_interval_s = (params.runtime_metrics_interval_seconds ?: 0) as int
        def files_seen = new java.util.concurrent.atomic.AtomicLong(0L)
        def batches_emitted = new java.util.concurrent.atomic.AtomicLong(0L)
        def per_barcode_batches = new java.util.concurrent.ConcurrentHashMap<String, java.util.concurrent.atomic.AtomicLong>()
        if (metrics_interval_s > 0) {
            log.info "[runtime-metrics] periodic snapshot enabled, interval = ${metrics_interval_s}s"
            def started_at = System.currentTimeMillis()
            def period_ms = metrics_interval_s * 1000L
            def metrics_timer = new java.util.Timer('runtime-metrics-snapshot', /* daemon */ true)
            metrics_timer.scheduleAtFixedRate({
                try {
                    long elapsed_s = (System.currentTimeMillis() - started_at) / 1000L
                    long files = files_seen.get()
                    long batches = batches_emitted.get()
                    long sample_count = per_barcode_batches.size()
                    long max_per_sample = per_barcode_batches.values()
                        .collect { it.get() }
                        .max() ?: 0L
                    long min_per_sample = per_barcode_batches.values()
                        .collect { it.get() }
                        .min() ?: 0L
                    log.info "[runtime-metrics] elapsed_s=${elapsed_s} files=${files} batches=${batches} barcodes=${sample_count} batches_per_barcode_min=${min_per_sample} batches_per_barcode_max=${max_per_sample}"
                } catch (Exception e) {
                    log.debug "[runtime-metrics] snapshot failed: ${e.message}"
                }
            } as java.util.TimerTask, period_ms, period_ms)
        }

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
        // Hidden files are never sequencing output. macOS writes AppleDouble
        // "._*" sidecars beside every file on exFAT/USB media, the glob above
        // matches them, and gzip then fails the QC process (2026-08-17).
        existing_list = existing_list.findAll { !it.name.startsWith('.') }

        // Round-robin interleave existing files by parent (barcode) directory so
        // take(max_files) selects fairly across all barcodes rather than in
        // filesystem order. See BatchUtils.interleaveFilesByParentDir.
        existing_list = BatchUtils.interleaveFilesByParentDir(existing_list)

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

        // Watch for new files being created or modified.
        //
        // ch_new must stay the RAW watchPath queue: the timeout timer
        // terminates the stream by binding a PoisonPill into it (see
        // below), and rebinding this name to an operator's output channel
        // makes that bind fail into its catch-all -- the stream then never
        // closes and the run hangs until an external timeout (observed as
        // a 60-minute CI cancel, 2026-08-17). The hidden-file exclusion is
        // therefore applied downstream, after the mix.
        def ch_new = Channel.watchPath(full_pattern, 'create,modify')

        // Combine existing files (processed first) with new files (watched
        // continuously). Hidden files are excluded here: macOS writes
        // AppleDouble "._name.fastq.gz" sidecars beside every file on
        // exFAT/USB media and the glob matches them (gzip then fails the
        // QC process). The PoisonPill never reaches the filter closure --
        // operators terminate on it without invoking user code.
        def ch_watched = ch_existing.mix(ch_new)
            .filter { !it.name.startsWith('.') }

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

        // Apply timeout and/or max_files limits.
        //
        // Both bounds are independent and either may fire first:
        //   - max_files: enforced via .take(N) on the file stream.
        //   - realtime_timeout_minutes (+ realtime_processing_grace_period):
        //     enforced by mixing a sentinel into the stream that is emitted
        //     by Channel.interval after the total timeout, then using
        //     .until { ... } to stop the stream when the sentinel arrives.
        //
        // Earlier revisions computed total_timeout_ms but never applied it,
        // so .take(max_files) silently dominated and operators who set a
        // generous max_files (defensive cap) lost timeout-based auto-stop.
        // With both bounds wired in, whichever predicate is satisfied first
        // terminates the channel; downstream batching then drains naturally.
        def TIMEOUT_SENTINEL = '__REALTIME_TIMEOUT_SENTINEL__'

        // Issue #22: realtime termination needs to close all inputs the
        // workflow session waits on, not just the downstream stream.
        // Hoist nullable references so both the timeout-fires path and
        // the max_files-fires path can close them in either order.
        groovyx.gpars.dataflow.DataflowQueue ch_timeout = null
        Timer realtime_timer = null

        // Count every file seen, regardless of whether it survives the
        // timeout or max_files cuts below. The tap is a side-effect-only
        // ``.map`` so it does not change the channel shape; the counter
        // feeds the periodic ``[runtime-metrics]`` snapshot above.
        if (metrics_interval_s > 0) {
            ch_all_files = ch_all_files.map { f ->
                files_seen.incrementAndGet()
                return f
            }
        }
        ch_input_files = ch_all_files

        if (params.realtime_timeout_minutes) {
            def grace = (params.realtime_processing_grace_period ?: 0) as Integer
            def total_timeout_ms = (params.realtime_timeout_minutes.toInteger() + grace) * 60L * 1000L

            log.info "Real-time timeout enabled: stop after ${params.realtime_timeout_minutes} minutes (idle) plus ${grace} minute grace period"
            log.info "Total wall-clock budget: ${total_timeout_ms} ms"

            // Schedule a one-shot sentinel emission on a Java daemon
            // Timer. We intentionally avoid Channel.interval here: that
            // factory keeps emitting on its scheduler until the JVM
            // exits and is awkward to cancel cleanly when .take(N)
            // satisfies the cap first. A daemon Timer is GC-collected
            // along with its queue when no consumers remain, so a
            // cap-fires-first run does not pin the JVM open waiting
            // for a sentinel that no one is reading.
            //
            // The sentinel is delivered by binding values into a GPars
            // DataflowQueue (the type that backs every Nextflow channel)
            // from the timer task. The queue is mixed with the file
            // stream and consumed by .until so that whichever predicate
            // is satisfied first terminates the merged channel. After
            // emitting the sentinel, the timer also binds a PoisonPill
            // so the queue closes for downstream operators that look at
            // channel completion.
            ch_timeout = new groovyx.gpars.dataflow.DataflowQueue()
            realtime_timer = new Timer('realtime-timeout', /* isDaemon */ true)
            realtime_timer.schedule({
                try {
                    ch_timeout.bind(TIMEOUT_SENTINEL)
                    ch_timeout.bind(groovyx.gpars.dataflow.operator.PoisonPill.instance)
                    // Issue #22: also send a PoisonPill into the underlying
                    // watchPath queue. ``.until { sentinel }`` only closes
                    // the merged downstream channel; the Nextflow session
                    // waits for every upstream queue (including ch_new) to
                    // close before reporting "Pipeline completed". Without
                    // this, realtime runs hang indefinitely after MULTIQC
                    // even when the realtime-timeout sentinel has fired.
                    try {
                        ch_new.bind(groovyx.gpars.dataflow.operator.PoisonPill.instance)
                    } catch (Exception inner) {
                        // ch_new already closed by an earlier termination path
                    }
                    log.info "Real-time timeout fired after ${total_timeout_ms} ms"
                } catch (Exception e) {
                    // Queue already closed by an earlier termination path.
                }
                realtime_timer.cancel()
            } as TimerTask, total_timeout_ms)

            ch_input_files = ch_input_files
                .mix(ch_timeout)
                .until { it == TIMEOUT_SENTINEL }
        }

        if (params.max_files) {
            def max_files_limit = params.max_files.toInteger()
            log.info "Max files limit: ${max_files_limit}"
            // Issue #22: the same channel-close requirement that applies
            // to the realtime-timeout path applies here. ``.take(N)``
            // closes its downstream output after N emissions but does
            // not propagate a PoisonPill into the upstream watchPath
            // queue (ch_new), nor into the ch_timeout queue that the
            // ``.mix(ch_timeout).until`` chain is also waiting on. The
            // tap below counts emissions and on hitting the cap closes
            // all the upstream queues the session waits on so the
            // workflow can terminate.
            def file_counter = new java.util.concurrent.atomic.AtomicLong(0L)
            ch_input_files = ch_input_files
                .map { f ->
                    if (file_counter.incrementAndGet() >= max_files_limit) {
                        try {
                            ch_new.bind(groovyx.gpars.dataflow.operator.PoisonPill.instance)
                        } catch (Exception inner) {
                            // ch_new already closed by an earlier termination path
                        }
                        if (ch_timeout != null) {
                            try {
                                ch_timeout.bind(TIMEOUT_SENTINEL)
                                ch_timeout.bind(groovyx.gpars.dataflow.operator.PoisonPill.instance)
                            } catch (Exception inner) {
                                // ch_timeout already closed
                            }
                            realtime_timer?.cancel()
                        }
                    }
                    return f
                }
                .take(max_files_limit)
        }

        if (!params.realtime_timeout_minutes && !params.max_files) {
            log.warn "WARNING: No timeout or max_files set - pipeline will run indefinitely!"
            log.warn "Consider setting --realtime_timeout_minutes or --max_files"
        }
        log.info "="*80

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

        // Tap each batch into the runtime-metrics counters before it
        // flows into the meta-map conversion. ``per_barcode_batches``
        // is keyed by the parent-directory name (typically the barcode
        // folder), so the snapshot can report which barcode is moving
        // and which is starving.
        if (metrics_interval_s > 0) {
            ch_batched_files = ch_batched_files.map { batch ->
                batches_emitted.incrementAndGet()
                def files = batch instanceof List ? batch : [batch]
                files.each { f ->
                    def key = f?.parent?.name ?: 'unknown'
                    def counter = per_barcode_batches.computeIfAbsent(key, { new java.util.concurrent.atomic.AtomicLong(0L) })
                    counter.incrementAndGet()
                }
                return batch
            }
        }

        //
        // CHANNEL: Convert files to meta map format with barcode extraction
        //
        // One interleaver instance for the whole run: it keeps a cumulative
        // served-count per barcode across batches, so a barcode that fell behind
        // in earlier batches is drained first in later ones. This carries the
        // round-robin fairness ACROSS batch boundaries -- the stateless per-batch
        // interleave could not, because it ordered each batch independently and so
        // a fast barcode that kept filling batches stayed ahead all run (audit
        // P2.9). Still feedback-free: it only reorders files already in a batch, so
        // nothing is held back and termination is unaffected.
        def cross_batch_interleaver = new CrossBatchInterleaver()
        ch_samples = ch_batched_files
            .map { batch -> cross_batch_interleaver.interleave(batch instanceof List ? batch : [batch]) }
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

                // Add barcode metadata if applicable; the unclassified bin
                // carries it too, matching the scan-mode input_scanner.
                if (sample_id =~ /^barcode\d+$/ || sample_id == 'unclassified') {
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
