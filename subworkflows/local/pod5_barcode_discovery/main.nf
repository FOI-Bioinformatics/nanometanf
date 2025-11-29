//
// POD5 Barcode discovery subworkflow for pre-demultiplexed POD5 samples
//
// Discovers barcode subdirectories containing POD5 files for basecalling.
// Each barcode directory becomes a separate sample for parallel processing.
//

workflow POD5_BARCODE_DISCOVERY {

    take:
    input_dir    // path: directory containing barcode subdirectories with POD5 files

    main:
    ch_versions = Channel.empty()

    //
    // DISCOVERY: Find barcode directories containing POD5 files
    //
    ch_barcode_samples = Channel.fromPath("${input_dir}/barcode*", type: 'dir')
        .filter { it.isDirectory() }
        .map { barcode_dir ->
            def barcode = barcode_dir.getName()
            def pod5_files = []

            // Find POD5 files in barcode directory
            barcode_dir.eachFileMatch(~/.+\.pod5$/) { file ->
                pod5_files.add(file)
            }

            if (pod5_files.size() > 0) {
                def meta = [
                    id: barcode,
                    barcode: barcode,
                    single_end: true,
                    demultiplexed: true,
                    demux_source: "pre_demultiplexed_pod5"
                ]
                return [ meta, pod5_files ]
            } else {
                return null
            }
        }
        .filter { it != null }  // Remove empty directories

    emit:
    samples  = ch_barcode_samples    // channel: [ val(meta), path(pod5_files) ]
    versions = ch_versions           // channel: [ path(versions.yml) ]
}
