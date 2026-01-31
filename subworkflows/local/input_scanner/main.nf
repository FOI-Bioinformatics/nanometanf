//
// Unified input directory scanner
// Auto-detects folder structure and groups files by sample
//

workflow INPUT_SCANNER {

    take:
    input_dir      // val: path to input directory
    sample_regex   // val: optional regex for sample ID extraction (null if not set)

    main:
    ch_versions = Channel.empty()

    def structure = InputDetector.detectStructure(input_dir)
    log.info "Input directory structure detected: ${structure}"

    if (structure == 'barcode_subdirs') {
        //
        // Barcode subdirectory mode: one sample per barcode dir
        //
        ch_samples = Channel.fromPath("${input_dir}/barcode*", type: 'dir')
            .filter { it.isDirectory() }
            .map { barcode_dir ->
                def barcode = barcode_dir.getName()
                def fastq_files = []
                barcode_dir.eachFileMatch(~/.+\.(fastq|fastq\.gz|fq|fq\.gz)$/) { f ->
                    fastq_files.add(f)
                }
                if (fastq_files.size() > 0) {
                    def meta = [
                        id: barcode,
                        barcode: barcode,
                        single_end: true,
                        demultiplexed: true,
                        demux_source: "input_scanner"
                    ]
                    return [ meta, fastq_files ]
                }
                return null
            }
            .filter { it != null }

        // Also pick up unclassified directory
        ch_unclassified = Channel.fromPath("${input_dir}/unclassified", type: 'dir')
            .filter { it.isDirectory() }
            .map { unclass_dir ->
                def fastq_files = []
                unclass_dir.eachFileMatch(~/.+\.(fastq|fastq\.gz|fq|fq\.gz)$/) { f ->
                    fastq_files.add(f)
                }
                if (fastq_files.size() > 0) {
                    def meta = [
                        id: "unclassified",
                        barcode: "unclassified",
                        single_end: true,
                        demultiplexed: true,
                        demux_source: "input_scanner"
                    ]
                    return [ meta, fastq_files ]
                }
                return null
            }
            .filter { it != null }

        ch_all_samples = ch_samples.mix(ch_unclassified)

    } else {
        //
        // Flat directory mode: group by sample ID
        //
        ch_all_samples = Channel.fromPath(["${input_dir}/*.{fastq,fastq.gz,fq,fq.gz}", "${input_dir}/**/*.{fastq,fastq.gz,fq,fq.gz}"])
            .map { f ->
                def sample_id = InputDetector.extractSampleId(
                    f,
                    sample_regex,
                    params.sample_name
                )
                def meta = [
                    id: sample_id,
                    single_end: true,
                    demux_source: "input_scanner"
                ]
                // Add barcode to meta if sample_id looks like a barcode
                if (sample_id =~ /^barcode\d+$/) {
                    meta.barcode = sample_id
                    meta.demultiplexed = true
                }
                return [ meta, f ]
            }
            .groupTuple(by: 0)
            .map { meta, files ->
                // groupTuple wraps files in extra list; flatten
                [ meta, files.flatten() ]
            }
    }

    emit:
    samples  = ch_all_samples   // channel: [ val(meta), [path(reads)] ]
    versions = ch_versions      // channel: [ path(versions.yml) ]
}
