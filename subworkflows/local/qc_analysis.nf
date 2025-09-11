//
// Quality control analysis subworkflow
//

include { FASTP                   } from '../../modules/nf-core/fastp/main'
include { NANOPLOT                } from '../../modules/nf-core/nanoplot/main'

workflow QC_ANALYSIS {

    take:
    ch_reads     // channel: [ val(meta), path(reads) ]

    main:
    ch_versions = Channel.empty()
    
    //
    // MODULE: Run fastp for quality filtering and QC
    //
    FASTP (
        ch_reads,
        [],           // adapter_fasta
        false,        // discard_trimmed_pass  
        false,        // save_trimmed_fail
        false         // save_merged
    )
    ch_versions = ch_versions.mix(FASTP.out.versions)
    
    //
    // MODULE: Run NanoPlot for nanopore-specific QC visualization
    //
    NANOPLOT (
        FASTP.out.reads.ifEmpty(ch_reads)
    )
    ch_versions = ch_versions.mix(NANOPLOT.out.versions)

    emit:
    reads        = FASTP.out.reads        // channel: [ val(meta), path(reads) ]
    fastp_json   = FASTP.out.json         // channel: [ val(meta), path(json) ]
    fastp_html   = FASTP.out.html         // channel: [ val(meta), path(html) ]
    fastp_log    = FASTP.out.log          // channel: [ val(meta), path(log) ]
    nanoplot     = NANOPLOT.out.html      // channel: [ val(meta), path(html) ]
    versions     = ch_versions            // channel: [ path(versions.yml) ]
}