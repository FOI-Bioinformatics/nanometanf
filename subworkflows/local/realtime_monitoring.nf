//
// Real-time file monitoring subworkflow using watchPath
//

workflow REALTIME_MONITORING {

    take:
    watch_dir      // val: directory to watch
    file_pattern   // val: file pattern to match
    batch_size     // val: number of files per batch
    batch_interval // val: time interval for batching

    main:
    
    //
    // CHANNEL: Watch for new FASTQ files using watchPath
    //
    if (params.realtime_mode) {
        log.info "Starting real-time monitoring of: ${watch_dir}"
        log.info "File pattern: ${file_pattern}"
        log.info "Batch size: ${batch_size}"
        log.info "Batch interval: ${batch_interval}"
        
        // Watch for files and limit if max_files is set
        def ch_watched = Channel.watchPath("${watch_dir}/${file_pattern}", 'create,modify')

        ch_input_files = params.max_files
            ? ch_watched.take(params.max_files.toInteger())
            : ch_watched
        
        //
        // CHANNEL: Create batches for processing
        //
        ch_batched_files = ch_input_files
            .buffer(size: batch_size, remainder: true)
            .mix(
                // Also emit batches on time interval
                Channel
                    .timer(batch_interval)
                    .combine(ch_input_files.collect())
                    .filter { timer, files -> files.size() > 0 }
                    .map { timer, files -> files }
            )
            .unique() // Remove duplicate batches
        
        //
        // CHANNEL: Convert files to meta map format
        //
        ch_samples = ch_batched_files
            .flatten()
            .map { file ->
                def meta = [:]
                meta.id = file.baseName.replaceAll(/\.(fastq|fq)(\.gz)?$/, '')
                meta.single_end = true // Assume single-end for nanopore
                meta.batch_time = new Date().format('yyyy-MM-dd_HH-mm-ss')
                return [ meta, file ]
            }
            
    } else {
        // Static mode - process existing files once
        ch_samples = Channel.empty()
    }

    emit:
    samples = ch_samples    // channel: [ val(meta), path(reads) ]
}