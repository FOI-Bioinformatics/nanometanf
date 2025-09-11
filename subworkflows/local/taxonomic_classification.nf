//
// Taxonomic classification subworkflow
//

include { KRAKEN2_KRAKEN2         } from '../../modules/nf-core/kraken2/kraken2/main'

workflow TAXONOMIC_CLASSIFICATION {

    take:
    ch_reads     // channel: [ val(meta), path(reads) ]
    ch_db        // channel: [ path(kraken2_db) ]

    main:
    ch_versions = Channel.empty()
    
    //
    // MODULE: Run Kraken2 for taxonomic classification
    //
    KRAKEN2_KRAKEN2 (
        ch_reads,
        ch_db,
        params.save_output_fastqs ?: false,    // save_output_fastqs
        params.save_reads_assignment ?: false  // save_reads_assignment
    )
    ch_versions = ch_versions.mix(KRAKEN2_KRAKEN2.out.versions)

    emit:
    classified_reads      = KRAKEN2_KRAKEN2.out.classified_reads_fastq     // channel: [ val(meta), path(fastq) ]
    unclassified_reads    = KRAKEN2_KRAKEN2.out.unclassified_reads_fastq   // channel: [ val(meta), path(fastq) ]
    reads_assignment      = KRAKEN2_KRAKEN2.out.classified_reads_assignment // channel: [ val(meta), path(txt) ]
    report                = KRAKEN2_KRAKEN2.out.report                      // channel: [ val(meta), path(txt) ]
    versions              = ch_versions                                     // channel: [ path(versions.yml) ]
}