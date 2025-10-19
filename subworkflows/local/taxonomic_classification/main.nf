/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: TAXONOMIC_CLASSIFICATION  
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Multi-tool taxonomic classification with taxpasta standardization
    
    Supported classifiers:
    - kraken2: Kraken2 k-mer based classification
    
    Future classifiers (ready to implement):
    - centrifuge: Centrifuge classification
    - metaphlan: MetaPhlAn4 marker-based profiling
    - kaiju: Kaiju protein-level classification
    
    Features:
    - Tool-agnostic interface
    - Taxpasta standardization for consistent outputs
    - Easy addition of new classifiers
----------------------------------------------------------------------------------------
*/

include { KRAKEN2_KRAKEN2                } from "${projectDir}/modules/nf-core/kraken2/kraken2/main"
include { KRAKEN2_OPTIMIZED              } from "${projectDir}/modules/local/kraken2_optimized/main"
// NOTE: Incremental classification feature disabled - modules not implemented
// include { KRAKEN2_INCREMENTAL_CLASSIFIER } from "${projectDir}/modules/local/kraken2_incremental_classifier/main"
// include { KRAKEN2_OUTPUT_MERGER          } from "${projectDir}/modules/local/kraken2_output_merger/main"
// include { KRAKEN2_REPORT_GENERATOR       } from "${projectDir}/modules/local/kraken2_report_generator/main"
include { TAXPASTA_STANDARDISE           } from "${projectDir}/modules/nf-core/taxpasta/standardise/main"

workflow TAXONOMIC_CLASSIFICATION {

    take:
    ch_reads     // channel: [ val(meta), path(reads) ]
    ch_db        // channel: [ path(db) ]

    main:
    ch_versions = Channel.empty()
    ch_classified_reads = Channel.empty()
    ch_unclassified_reads = Channel.empty()
    ch_reads_assignment = Channel.empty()
    ch_raw_reports = Channel.empty()

    // Set classifier and validate parameters
    def classifier = params.classifier ?: 'kraken2'
    def output_format = params.taxpasta_format ?: 'tsv'

    //
    // PHASE 2 OPTIMIZATION: Automatic database preloading in real-time mode
    //
    // Enable Kraken2 optimizations automatically for PromethION real-time processing
    // Memory-mapping enables OS-level database caching, eliminating redundant disk I/O across batches
    //
    def auto_enable_optimizations = params.realtime_mode && !params.kraken2_use_optimizations
    def use_memory_mapping = params.realtime_mode ? true : params.kraken2_memory_mapping
    def use_optimizations = params.realtime_mode ? true : params.kraken2_use_optimizations

    if (auto_enable_optimizations && classifier == 'kraken2') {
        log.info "=== Phase 2: Database Preloading Enabled ==="
        log.info "Real-time mode detected - automatically enabling Kraken2 optimizations:"
        log.info "  - Memory-mapped database loading: ENABLED"
        log.info "  - Database cached in OS page cache for reuse across batches"
        log.info "  - Eliminates repeated database loading (30+ batches → 1 load)"
        log.info "  - Estimated time savings: 1-3 minutes per batch after first load"
    }
    
    //
    // BRANCH: Route to appropriate classifier
    //
    switch(classifier) {
        case 'kraken2':
            //
            // MODULE: Run Kraken2 for taxonomic classification
            // Two modes: optimized or standard (incremental disabled - modules not implemented)
            //
            if (false && params.kraken2_enable_incremental == true) {  // Incremental mode disabled
                log.info "Using incremental Kraken2 processing with batch caching"
                log.info "  - Raw outputs cached per batch for efficient merging"
                log.info "  - Cumulative reports generated from merged data"

                //
                // MODULE: Incremental classification with caching
                //
                KRAKEN2_INCREMENTAL_CLASSIFIER (
                    ch_reads,
                    ch_db,
                    params.save_output_fastqs ?: false,
                    params.save_reads_assignment ?: false,
                    params.kraken2_cache_dir ?: "${params.outdir}/cache/kraken2"
                )
                ch_versions = ch_versions.mix(KRAKEN2_INCREMENTAL_CLASSIFIER.out.versions)

                // Collect batch outputs per sample/barcode
                ch_raw_kraken2_outputs = KRAKEN2_INCREMENTAL_CLASSIFIER.out.raw_kraken2_output
                    .groupTuple(by: 0)  // Group by meta

                ch_batch_reports = KRAKEN2_INCREMENTAL_CLASSIFIER.out.report
                    .groupTuple(by: 0)  // Group by meta

                ch_batch_metadata = KRAKEN2_INCREMENTAL_CLASSIFIER.out.batch_metadata
                    .groupTuple(by: 0)  // Group by meta
                    .map{ meta, files -> files }  // Extract just the metadata files (remove meta)

                //
                // MODULE: Merge batch outputs
                //
                KRAKEN2_OUTPUT_MERGER (
                    ch_raw_kraken2_outputs,
                    ch_batch_metadata
                )
                ch_versions = ch_versions.mix(KRAKEN2_OUTPUT_MERGER.out.versions)

                //
                // MODULE: Generate cumulative report
                //
                KRAKEN2_REPORT_GENERATOR (
                    KRAKEN2_OUTPUT_MERGER.out.cumulative_output,
                    ch_batch_reports,
                    ch_db
                )
                ch_versions = ch_versions.mix(KRAKEN2_REPORT_GENERATOR.out.versions)

                // Collect outputs from incremental path
                ch_classified_reads = KRAKEN2_INCREMENTAL_CLASSIFIER.out.classified_reads_fastq
                ch_unclassified_reads = KRAKEN2_INCREMENTAL_CLASSIFIER.out.unclassified_reads_fastq
                ch_reads_assignment = KRAKEN2_INCREMENTAL_CLASSIFIER.out.classified_reads_assignment
                ch_raw_reports = KRAKEN2_REPORT_GENERATOR.out.report
                ch_performance_metrics = KRAKEN2_REPORT_GENERATOR.out.stats

            } else if (use_optimizations == true) {
                log.info "Using optimized Kraken2 classification with:"
                log.info "  - Memory mapping: ${use_memory_mapping}"
                log.info "  - Confidence threshold: ${params.kraken2_confidence}"
                log.info "  - Minimum hit groups: ${params.kraken2_minimum_hit_groups}"

                KRAKEN2_OPTIMIZED (
                    ch_reads,
                    ch_db,
                    params.save_output_fastqs ?: false,
                    params.save_reads_assignment ?: false,
                    use_memory_mapping,
                    params.kraken2_confidence ?: 0.0,
                    params.kraken2_minimum_hit_groups ?: 0
                )
                ch_versions = ch_versions.mix(KRAKEN2_OPTIMIZED.out.versions)

                // Collect outputs
                ch_classified_reads = KRAKEN2_OPTIMIZED.out.classified_reads_fastq
                ch_unclassified_reads = KRAKEN2_OPTIMIZED.out.unclassified_reads_fastq
                ch_reads_assignment = KRAKEN2_OPTIMIZED.out.classified_reads_assignment
                ch_raw_reports = KRAKEN2_OPTIMIZED.out.report
                ch_performance_metrics = KRAKEN2_OPTIMIZED.out.performance_metrics
            } else {
                KRAKEN2_KRAKEN2 (
                    ch_reads,
                    ch_db,
                    params.save_output_fastqs ?: false,    // save_output_fastqs
                    params.save_reads_assignment ?: false  // save_reads_assignment
                )
                ch_versions = ch_versions.mix(KRAKEN2_KRAKEN2.out.versions)

                // Collect outputs
                ch_classified_reads = KRAKEN2_KRAKEN2.out.classified_reads_fastq
                ch_unclassified_reads = KRAKEN2_KRAKEN2.out.unclassified_reads_fastq
                ch_reads_assignment = KRAKEN2_KRAKEN2.out.classified_reads_assignment
                ch_raw_reports = KRAKEN2_KRAKEN2.out.report
                ch_performance_metrics = Channel.empty()
            }
            break
            
        // Future classifiers to be added here:
        // case 'centrifuge':
        //     CENTRIFUGE_CENTRIFUGE(...)
        //     break
        // case 'metaphlan':
        //     METAPHLAN4_METAPHLAN4(...)
        //     break
        
        default:
            error "Unsupported classifier: ${classifier}. Currently supported: kraken2"
    }
    
    //
    // MODULE: Standardize classification reports with taxpasta
    //
    if (params.enable_taxpasta_standardization != false) {
        TAXPASTA_STANDARDISE (
            ch_raw_reports,
            classifier,
            output_format,
            params.taxonomy_file ? file(params.taxonomy_file, checkIfExists: true) : []
        )
        ch_versions = ch_versions.mix(TAXPASTA_STANDARDISE.out.versions)
        ch_standardized_reports = TAXPASTA_STANDARDISE.out.standardised_profile
    } else {
        ch_standardized_reports = ch_raw_reports
    }

    emit:
    classified_reads      = ch_classified_reads      // channel: [ val(meta), path(fastq) ]
    unclassified_reads    = ch_unclassified_reads    // channel: [ val(meta), path(fastq) ]
    reads_assignment      = ch_reads_assignment      // channel: [ val(meta), path(txt) ]
    report                = ch_raw_reports           // channel: [ val(meta), path(txt) ] - Original format for compatibility
    standardized_report   = ch_standardized_reports  // channel: [ val(meta), path(tsv/csv/etc) ] - Standardized format
    performance_metrics   = ch_performance_metrics   // channel: [ path(json) ] - Performance metrics (when optimizations enabled)
    classifier_used       = Channel.value(classifier) // channel: val(classifier_name)
    versions              = ch_versions              // channel: [ path(versions.yml) ]
}