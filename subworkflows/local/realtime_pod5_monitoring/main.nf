//
// Real-time POD5 file monitoring with Dorado basecalling
//

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
        log.info "Starting real-time POD5 monitoring of: ${watch_dir}"
        log.info "POD5 file pattern: ${file_pattern}"
        log.info "Batch size: ${batch_size}"
        log.info "Dorado model: ${dorado_model}"
        
        // Watch for POD5 files and limit if max_files is set
        def ch_watched = Channel.watchPath("${watch_dir}/${file_pattern}", 'create,modify')

        ch_pod5_files = params.max_files
            ? ch_watched.take(params.max_files.toInteger())
            : ch_watched
        
        //
        // CHANNEL: Create batches of POD5 files for processing
        //
        ch_batched_pod5 = ch_pod5_files
            .buffer(size: batch_size, remainder: true)
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
            
    } else {
        // Static mode or Dorado disabled - return empty channel
        ch_basecalled_samples = Channel.empty()
    }

    emit:
    samples = ch_basecalled_samples    // channel: [ val(meta), path(fastq) ]
    versions = ch_versions              // channel: [ versions.yml ]
}