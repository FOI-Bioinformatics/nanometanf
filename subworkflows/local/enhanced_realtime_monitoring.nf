/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: ENHANCED_REALTIME_MONITORING
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Advanced event-driven real-time file monitoring for nanopore data
    
    Key improvements over legacy timer-based approach:
    - Event-driven batching (no timer dependencies)
    - Multi-directory monitoring support
    - File prioritization and intelligent batching
    - Adaptive batch sizing based on system load
    - Snapshot and cumulative statistics tracking
    
    Features:
    - Supports multiple watch directories
    - Priority-based file processing
    - Dynamic batch sizing
    - Real-time statistics generation
    - Memory-efficient file handling
----------------------------------------------------------------------------------------
*/

include { REALTIME_STATISTICS } from './realtime_statistics'

workflow ENHANCED_REALTIME_MONITORING {

    take:
    watch_dirs        // val: list of directories to watch (supports multiple)
    file_pattern      // val: file pattern to match (e.g., "**/*.fastq{,.gz}")
    batch_config      // val: batch configuration map
    stats_config      // val: statistics configuration map

    main:
    
    ch_versions = Channel.empty()
    
    //
    // Multi-directory file monitoring with priority handling
    //
    if (params.realtime_mode) {
        log.info "=== Enhanced Real-time Monitoring ==="
        log.info "Watch directories: ${watch_dirs}"
        log.info "File pattern: ${file_pattern}"
        log.info "Batch config: ${batch_config}"
        
        // Create separate monitoring channels for each directory
        ch_monitored_files = Channel.empty()
        
        // Handle single directory or multiple directories
        def directories = watch_dirs instanceof String ? [watch_dirs] : watch_dirs
        
        for (watch_dir in directories) {
            log.info "Starting monitoring for directory: ${watch_dir}"
            
            // Monitor each directory and add metadata
            def watched = Channel.watchPath("${watch_dir}/${file_pattern}", 'create,modify')

            def dir_channel = (params.max_files
                ? watched.take(params.max_files.toInteger())
                : watched
            ).map { file ->
                addFileMetadata(file, watch_dir)
            }
                
            ch_monitored_files = ch_monitored_files.mix(dir_channel)
        }
        
        //
        // Event-driven adaptive batching (replaces timer-based approach)
        //
        ch_prioritized_batches = ch_monitored_files
            .map { file_meta ->
                // Calculate file priority based on various factors
                calculateFilePriority(file_meta)
            }
            .buffer { file_meta ->
                // Dynamic batch sizing based on current system state
                calculateDynamicBatchSize(file_meta, batch_config)
            }
            .map { batch ->
                // Add batch metadata
                addBatchMetadata(batch, batch_config)
            }
        
        //
        // Convert to standard sample format with enhanced metadata
        //
        ch_samples = ch_prioritized_batches
            .flatMap { batch ->
                // Process each file in the batch
                batch.files.collect { file_meta ->
                    createSampleMetadata(file_meta, batch)
                }
            }
            .map { sample_meta ->
                [ sample_meta, sample_meta.file_path ]
            }
        
        //
        // Generate real-time statistics for each batch
        //
        REALTIME_STATISTICS (
            ch_prioritized_batches,
            stats_config
        )
        ch_versions = ch_versions.mix(REALTIME_STATISTICS.out.versions)
        
    } else {
        // Static mode - return empty channels
        ch_samples = Channel.empty()
        ch_prioritized_batches = Channel.empty()
    }

    emit:
    samples = ch_samples                              // channel: [ val(meta), path(reads) ]
    batches = ch_prioritized_batches                  // channel: [ val(batch_meta), [ file_metas ] ]
    snapshot_stats = REALTIME_STATISTICS.out.snapshot_stats.ifEmpty(Channel.empty())
    cumulative_stats = REALTIME_STATISTICS.out.cumulative_stats.ifEmpty(Channel.empty())
    versions = ch_versions                            // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    HELPER FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

def addFileMetadata(file, watch_dir) {
    /*
    Add comprehensive metadata to detected files
    */
    def file_size = file.size()
    def file_age = System.currentTimeMillis() - file.lastModified()
    def sample_id = extractSampleId(file.name)
    
    return [
        file_path: file,
        watch_dir: watch_dir,
        file_name: file.name,
        file_size: file_size,
        file_age_ms: file_age,
        detected_time: System.currentTimeMillis(),
        sample_id: sample_id,
        is_compressed: file.name.endsWith('.gz'),
        estimated_reads: estimateReadCount(file_size, file.name),
        priority_score: 0  // Will be calculated later
    ]
}

def calculateFilePriority(file_meta) {
    /*
    Calculate priority score for file processing
    Higher scores = higher priority
    */
    def priority = 0
    
    // Age-based priority (older files get higher priority)
    if (file_meta.file_age_ms > 300000) {        // > 5 minutes
        priority += 100
    } else if (file_meta.file_age_ms > 60000) {  // > 1 minute
        priority += 50
    }
    
    // Size-based priority (larger files might be complete)
    if (file_meta.file_size > 100000000) {      // > 100MB
        priority += 30
    } else if (file_meta.file_size > 10000000) { // > 10MB
        priority += 15
    }
    
    // Sample-specific priority (if configured)
    if (params.priority_samples && params.priority_samples.contains(file_meta.sample_id)) {
        priority += 200
    }
    
    // Compressed files might be complete
    if (file_meta.is_compressed) {
        priority += 25
    }
    
    file_meta.priority_score = priority
    return file_meta
}

def calculateDynamicBatchSize(file_meta, batch_config) {
    /*
    Calculate optimal batch size based on current conditions
    */
    def base_size = batch_config.base_size ?: 10
    def max_size = batch_config.max_size ?: 50
    def min_size = batch_config.min_size ?: 1
    
    // Adjust based on file size
    def size_factor = 1.0
    if (file_meta.file_size > 50000000) {       // Large files (>50MB)
        size_factor = 0.5                       // Smaller batches
    } else if (file_meta.file_size < 1000000) { // Small files (<1MB)
        size_factor = 2.0                       // Larger batches
    }
    
    // Adjust based on system load (simplified)
    def load_factor = 1.0
    def runtime = Runtime.getRuntime()
    def memory_usage = (runtime.totalMemory() - runtime.freeMemory()) / runtime.totalMemory()
    if (memory_usage > 0.8) {
        load_factor = 0.5  // Reduce batch size under high memory pressure
    }
    
    def calculated_size = Math.round(base_size * size_factor * load_factor)
    return Math.max(min_size, Math.min(max_size, calculated_size))
}

def addBatchMetadata(batch_files, batch_config) {
    /*
    Add metadata to the entire batch
    */
    def batch_id = "batch_${System.currentTimeMillis()}_${Math.random().toString().substring(2,8)}"
    def total_size = batch_files.sum { it.file_size }
    def avg_priority = batch_files.sum { it.priority_score } / batch_files.size()
    
    return [
        batch_id: batch_id,
        batch_time: new Date().format('yyyy-MM-dd_HH-mm-ss-SSS'),
        batch_timestamp: System.currentTimeMillis(),
        file_count: batch_files.size(),
        total_size_bytes: total_size,
        average_priority: avg_priority,
        estimated_total_reads: batch_files.sum { it.estimated_reads },
        watch_directories: batch_files.collect { it.watch_dir }.unique(),
        files: batch_files
    ]
}

def createSampleMetadata(file_meta, batch_meta) {
    /*
    Create standard sample metadata format
    */
    return [
        id: file_meta.sample_id,
        single_end: true,
        file_path: file_meta.file_path,
        file_size: file_meta.file_size,
        estimated_reads: file_meta.estimated_reads,
        priority_score: file_meta.priority_score,
        batch_id: batch_meta.batch_id,
        batch_time: batch_meta.batch_time,
        batch_file_count: batch_meta.file_count,
        watch_dir: file_meta.watch_dir,
        processing_mode: 'realtime',
        detected_time: file_meta.detected_time,
        is_compressed: file_meta.is_compressed
    ]
}

def extractSampleId(filename) {
    /*
    Extract sample ID from filename using common patterns
    */
    // Remove common extensions and extract base name
    def base_name = filename.replaceAll(/\.(fastq|fq)(\.gz)?$/, '')
    
    // Handle common naming patterns
    if (base_name.contains('_')) {
        return base_name.split('_')[0]
    } else if (base_name.contains('-')) {
        return base_name.split('-')[0]
    } else {
        return base_name
    }
}

def estimateReadCount(file_size, filename) {
    /*
    Estimate read count based on file size and type
    */
    def bytes_per_read = 1000  // Conservative estimate for nanopore reads
    
    // Adjust for compression
    if (filename.endsWith('.gz')) {
        bytes_per_read = 300  // Compressed reads are ~3x smaller
    }
    
    return Math.max(1, (file_size / bytes_per_read).toInteger())
}

def getProcessedFileCount() {
    /*
    Get current count of processed files (placeholder)
    In a real implementation, this would track processed files
    */
    return 0
}