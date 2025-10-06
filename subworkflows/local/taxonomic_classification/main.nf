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

include { KRAKEN2_KRAKEN2         } from '../../modules/nf-core/kraken2/kraken2/main'
include { KRAKEN2_OPTIMIZED       } from '../../../modules/local/kraken2_optimized/main'
include { TAXPASTA_STANDARDISE    } from '../../modules/nf-core/taxpasta/standardise/main'

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
    // BRANCH: Route to appropriate classifier
    //
    switch(classifier) {
        case 'kraken2':
            //
            // MODULE: Run Kraken2 for taxonomic classification
            // Use optimized module if kraken2_use_optimizations is enabled
            //
            if (params.kraken2_use_optimizations == true) {
                log.info "Using optimized Kraken2 classification with:"
                log.info "  - Memory mapping: ${params.kraken2_memory_mapping}"
                log.info "  - Confidence threshold: ${params.kraken2_confidence}"
                log.info "  - Minimum hit groups: ${params.kraken2_minimum_hit_groups}"

                KRAKEN2_OPTIMIZED (
                    ch_reads,
                    ch_db,
                    params.save_output_fastqs ?: false,
                    params.save_reads_assignment ?: false,
                    params.kraken2_memory_mapping ?: false,
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