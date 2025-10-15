//
// Demultiplexing subworkflow for multiplexed nanopore samples
//

include { DORADO_DEMUX } from "${projectDir}/modules/local/dorado_demux/main"

workflow DEMULTIPLEXING {

    take:
    ch_input     // channel: [ val(meta), path(reads) ]

    main:
    ch_versions = Channel.empty()
    ch_all_samples = Channel.empty()

    // Convert input to channel if needed (for nf-test compatibility with ArrayList inputs)
    def input_channel = ch_input instanceof List ? Channel.fromList(ch_input) : ch_input

    //
    // BRANCH: Handle multiplexed vs pre-demultiplexed samples
    //
    input_channel
        .branch { meta, reads ->
            needs_demux: meta.barcode_kit && !meta.demultiplexed
            already_demuxed: !meta.barcode_kit || meta.demultiplexed
        }
        .set { ch_branched }
    
    //
    // PROCESS: Dorado demultiplexing for multiplexed samples
    //
    if (params.use_dorado && params.barcode_kit) {
        DORADO_DEMUX (
            ch_branched.needs_demux,
            params.barcode_kit ?: 'SQK-NBD114-24'  // Default barcode kit
        )
        ch_versions = ch_versions.mix(DORADO_DEMUX.out.versions)

        // Flatten demuxed reads into individual samples
        ch_demuxed_samples = DORADO_DEMUX.out.demuxed_reads
            .transpose()
            .map { meta, reads ->
                // Extract barcode from path (e.g., demux_output/barcode01/reads.fastq)
                def barcode = reads.getParent().getName()
                def new_meta = meta.clone()
                new_meta.id = "${meta.id}_${barcode}"
                new_meta.barcode = barcode
                new_meta.demultiplexed = true
                new_meta.demux_tool = "dorado"
                return [ new_meta, reads ]
            }

        ch_all_samples = ch_all_samples.mix(ch_demuxed_samples)
    } else {
        // If demuxing is disabled, pass through samples that need demux unchanged
        // This allows downstream processes to handle them or skip them as needed
        ch_all_samples = ch_all_samples.mix(ch_branched.needs_demux)
    }

    //
    // CHANNEL: Add already demultiplexed samples
    //
    ch_all_samples = ch_all_samples.mix(ch_branched.already_demuxed)

    emit:
    samples  = ch_all_samples    // channel: [ val(meta), path(reads) ]
    versions = ch_versions       // channel: [ path(versions.yml) ]
}