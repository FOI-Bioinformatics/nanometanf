//
// Barcode discovery subworkflow for pre-demultiplexed samples
//

workflow BARCODE_DISCOVERY {

    take:
    input_dir    // path: directory containing barcode subdirectories
    
    main:
    ch_versions = Channel.empty()
    
    //
    // DISCOVERY: Find barcode directories and FASTQ files
    //
    ch_barcode_samples = Channel.fromPath("${input_dir}/barcode*", type: 'dir')
        .filter { it.isDirectory() }
        .map { barcode_dir ->
            def barcode = barcode_dir.getName()
            def fastq_files = []
            
            // Find FASTQ files in barcode directory
            barcode_dir.eachFileMatch(~/.+\.(fastq|fastq\.gz|fq|fq\.gz)$/) { file ->
                fastq_files.add(file)
            }
            
            if (fastq_files.size() > 0) {
                def meta = [
                    id: barcode,
                    barcode: barcode,
                    single_end: true,
                    demultiplexed: true,
                    demux_source: "pre_demultiplexed"
                ]
                return [ meta, fastq_files ]
            } else {
                return null
            }
        }
        .filter { it != null }  // Remove empty directories
    
    //
    // DISCOVERY: Also check for 'unclassified' directory
    //
    ch_unclassified = Channel.fromPath("${input_dir}/unclassified", type: 'dir')
        .filter { it.isDirectory() }
        .map { unclass_dir ->
            def fastq_files = []
            
            unclass_dir.eachFileMatch(~/.+\.(fastq|fastq\.gz|fq|fq\.gz)$/) { file ->
                fastq_files.add(file)
            }
            
            if (fastq_files.size() > 0) {
                def meta = [
                    id: "unclassified",
                    barcode: "unclassified", 
                    single_end: true,
                    demultiplexed: true,
                    demux_source: "pre_demultiplexed"
                ]
                return [ meta, fastq_files ]
            } else {
                return null
            }
        }
        .filter { it != null }
        .ifEmpty([])  // Make optional
    
    //
    // COMBINE: Mix barcode and unclassified samples
    //
    ch_all_samples = ch_barcode_samples.mix(ch_unclassified)

    emit:
    samples  = ch_all_samples    // channel: [ val(meta), path(reads) ]
    versions = ch_versions       // channel: [ path(versions.yml) ]
}