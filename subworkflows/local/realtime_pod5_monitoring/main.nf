//
// Real-time POD5 file monitoring with Dorado basecalling
// - Supports flat POD5 directory structure
// - Supports barcode subdirectory structure (barcode01/, barcode02/, etc.)
// - Processes existing files on startup before watching for new files
//

// Note: BarcodeUtils class is auto-loaded from lib/ in Nextflow 25.x+

include { DORADO_BASECALLER } from "${projectDir}/modules/local/dorado_basecaller/main"

workflow REALTIME_POD5_MONITORING {

    take:
    watch_dir      // val: directory to watch for POD5 files
    file_pattern   // val: POD5 file pattern to match (e.g., "**/*.pod5")
    batch_size     // val: number of POD5 files per batch
    batch_interval // val: time interval for batching
    dorado_model   // val: Dorado basecalling model

    main:
    ch_versions = Channel.empty()

    //
    // CHANNEL: Watch for new POD5 files using watchPath
    //
    if (params.realtime_mode && params.use_dorado) {
        log.info "="*80
        log.info "Starting real-time POD5 monitoring of: ${watch_dir}"
        log.info "POD5 file pattern: ${file_pattern}"
        log.info "Batch size: ${batch_size}"
        log.info "Dorado model: ${dorado_model}"

        // Build file pattern - support both flat and barcode subdirectory structures
        def full_pattern = "${watch_dir}/${file_pattern}"

        // Find existing POD5 files (including in barcode subdirectories)
        def existing_files = file(full_pattern)
        def existing_list = []
        if (existing_files instanceof List) {
            existing_list = existing_files.findAll { it.exists() }
        } else if (existing_files != null && existing_files.exists()) {
            existing_list = [existing_files]
        }

        def existing_count = existing_list.size()

        if (existing_count > 0) {
            log.info "Found ${existing_count} existing POD5 files - will process immediately"
            existing_list.take(5).each { f -> log.info "  - ${f.name}" }
            if (existing_count > 5) {
                log.info "  ... and ${existing_count - 5} more"
            }
        } else {
            log.info "No existing POD5 files found - waiting for new files..."
        }

        // Create channel from existing files
        def ch_existing = existing_count > 0
            ? Channel.fromList(existing_list)
            : Channel.empty()

        // Watch for new files being created or modified
        def ch_new = Channel.watchPath(full_pattern, 'create,modify')

        // Combine existing files (processed first) with new files (watched continuously)
        def ch_all_files = ch_existing.mix(ch_new)

        log.info "="*80

        // Apply max_files limit if set
        ch_pod5_files = params.max_files
            ? ch_all_files.take(params.max_files.toInteger())
            : ch_all_files

        //
        // CHANNEL: Create batches of POD5 files for processing
        // STREAMING-FIX: Use collate instead of buffer for streaming compatibility
        // buffer(size: N, remainder: true) blocks until channel closes (never with watchPath)
        // collate(N, false) emits partial batches immediately without blocking
        //
        ch_batched_pod5 = ch_pod5_files
            .collate(batch_size, false)
            .unique() // Remove duplicate batches

        //
        // CHANNEL: Convert POD5 batches to meta map format for Dorado
        //
        ch_pod5_samples = ch_batched_pod5
            .map { files ->
                def meta = [:]
                meta.id = "realtime_batch_${new Date().format('yyyy-MM-dd_HH-mm-ss')}"
                meta.single_end = true
                meta.pod5_count = files.size()
                meta.batch_time = new Date().format('yyyy-MM-dd_HH-mm-ss')
                return [ meta, files ]
            }

        //
        // MODULE: Run Dorado basecalling on POD5 batches
        //
        DORADO_BASECALLER (
            ch_pod5_samples,
            dorado_model
        )
        ch_versions = ch_versions.mix(DORADO_BASECALLER.out.versions.first())

        //
        // CHANNEL: Convert basecalled FASTQ to standard sample format
        //
        ch_basecalled_samples = DORADO_BASECALLER.out.fastq
            .map { meta, fastq ->
                def new_meta = [:]
                new_meta.id = meta.id
                new_meta.single_end = true
                new_meta.basecalled = true
                new_meta.original_pod5_count = meta.pod5_count
                return [ new_meta, fastq ]
            }

        // Transform batches for REALTIME_STATISTICS
        // GENERATE_SNAPSHOT_STATS expects: tuple val(batch_meta), val(file_metas)
        ch_batches = ch_batched_pod5
            .map { files ->
                def batch_timestamp = System.currentTimeMillis()
                def batch_time = new Date().format('yyyy-MM-dd_HH-mm-ss')
                // Use timestamp for unique batch ID (counter variables don't work in Nextflow dataflow)
                def batch_id = "pod5_batch_${batch_timestamp}"

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

                    [
                        file_path: f.toString(),
                        file_name: file_name,
                        file_size: file_size,
                        is_compressed: false,
                        estimated_reads: (file_size / 10000).toLong(), // POD5 rough estimate
                        file_age_ms: batch_timestamp - f.lastModified(),
                        priority_score: 0,
                        watch_dir: f.parent.toString(),
                        sample_id: file_name.replaceAll(/\.pod5$/, '')
                    ]
                }

                return [ batch_meta, file_metas ]
            }

    } else {
        // Static mode or Dorado disabled - return empty channels
        ch_basecalled_samples = Channel.empty()
        ch_batches = Channel.empty()
    }

    emit:
    samples  = ch_basecalled_samples   // channel: [ val(meta), path(fastq) ]
    batches  = ch_batches              // channel: [ val(batch_meta), val(file_metas) ] - structured batch data for REALTIME_STATISTICS
    versions = ch_versions             // channel: [ versions.yml ]
}
