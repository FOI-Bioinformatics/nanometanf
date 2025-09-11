//
// Demultiplexing subworkflow for multiplexed nanopore samples
//

workflow DEMULTIPLEXING {

    take:
    ch_input     // channel: [ val(meta), path(reads) ]

    main:
    ch_versions = Channel.empty()
    
    //
    // BRANCH: Handle multiplexed vs pre-demultiplexed samples
    //
    ch_input
        .branch { meta, reads ->
            multiplexed: meta.barcode_kit && !meta.demultiplexed
            demultiplexed: !meta.barcode_kit || meta.demultiplexed
        }
        .set { ch_branched }
    
    //
    // PROCESS: Use dorado for demultiplexing if available and multiplexed
    //
    if (params.use_dorado && params.dorado_path) {
        ch_demux_with_dorado = ch_branched.multiplexed
            .map { meta, reads ->
                // Create dorado demux command
                def dorado_cmd = [
                    "${params.dorado_path}/dorado",
                    "demux",
                    "--emit-fastq",
                    reads
                ].join(" ")
                
                // Execute dorado demux and collect outputs
                def output_dir = "demux_${meta.id}"
                
                // Update meta for each barcode
                def demux_meta = meta.clone()
                demux_meta.demultiplexed = true
                demux_meta.demux_tool = "dorado"
                
                return [ demux_meta, reads, dorado_cmd, output_dir ]
            }
    } else {
        ch_demux_with_dorado = Channel.empty()
    }
    
    //
    // CHANNEL: Collect all demultiplexed samples
    //
    ch_demultiplexed_samples = ch_branched.demultiplexed
        .mix(ch_demux_with_dorado.map { meta, reads, cmd, dir -> [ meta, reads ] })
        .map { meta, reads ->
            // Ensure consistent sample naming
            def sample_meta = meta.clone()
            if (!sample_meta.id.contains('barcode') && meta.barcode) {
                sample_meta.id = "${meta.id}_${meta.barcode}"
            }
            return [ sample_meta, reads ]
        }

    emit:
    samples  = ch_demultiplexed_samples   // channel: [ val(meta), path(reads) ]
    versions = ch_versions                // channel: [ path(versions.yml) ]
}