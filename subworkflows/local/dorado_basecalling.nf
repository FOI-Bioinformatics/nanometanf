/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: DORADO_BASECALLING
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Dorado basecalling and optional demultiplexing for nanopore sequencing data
----------------------------------------------------------------------------------------
*/

include { DORADO_BASECALLER      } from '../../modules/local/dorado_basecaller'
include { DORADO_DEMUX           } from '../../modules/local/dorado_demux'

workflow DORADO_BASECALLING {
    
    take:
    pod5_files    // channel: [ val(meta), path(pod5_files) ]
    dorado_model  // val: dorado model name
    
    main:
    
    ch_versions = Channel.empty()
    ch_fastq    = Channel.empty()
    
    // Basecalling with Dorado
    DORADO_BASECALLER (
        pod5_files,
        dorado_model
    )
    ch_versions = ch_versions.mix(DORADO_BASECALLER.out.versions)
    
    // Branch based on demultiplexing requirement
    DORADO_BASECALLER.out.fastq.branch { meta, fastq ->
        demux: params.demultiplex && params.barcode_kit
        single: true
    }.set { ch_basecalled }
    
    // Demultiplexing if enabled
    if (params.demultiplex && params.barcode_kit) {
        DORADO_DEMUX (
            ch_basecalled.demux,
            params.barcode_kit
        )
        ch_versions = ch_versions.mix(DORADO_DEMUX.out.versions)
        
        // Combine single sample and demultiplexed samples
        ch_fastq = ch_basecalled.single.mix(DORADO_DEMUX.out.fastq)
    } else {
        // Use basecalled fastq directly for single samples
        ch_fastq = ch_basecalled.single
    }
    
    emit:
    fastq    = ch_fastq     // channel: [ val(meta), path(fastq) ]
    summary  = DORADO_BASECALLER.out.summary  // channel: [ val(meta), path(summary) ]
    versions = ch_versions  // channel: [ versions.yml ]
}