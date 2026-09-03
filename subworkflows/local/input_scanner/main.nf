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
        // Per-sample subdirectory mode: one sample per direct subdirectory
        // that holds reads -- barcodeNN, unclassified, or a custom name such
        // as Turex/ (InputDetector.sampleSubdirs; the former barcode* glob
        // split custom-named folders into one sample per file).
        //
        ch_all_samples = Channel.fromList(
                InputDetector.sampleSubdirs(input_dir).collect { it.toPath() }
            )
            .map { sample_dir ->
                def sample_id = sample_dir.getName()
                def fastq_files = []
                sample_dir.eachFileMatch(~/[^.].*\.(fastq|fastq\.gz|fq|fq\.gz)$/) { f ->
                    fastq_files.add(f)
                }
                if (fastq_files.size() > 0) {
                    def meta = [
                        id: sample_id,
                        single_end: true,
                        demultiplexed: true,
                        demux_source: "input_scanner"
                    ]
                    if (sample_id =~ /^barcode\d+$/ || sample_id == 'unclassified') {
                        meta.barcode = sample_id
                    }
                    return [ meta, fastq_files ]
                }
                return null
            }
            .filter { it != null }

    } else {
        //
        // Flat directory mode: group by sample ID
        //
        // The extra filter drops hidden files: Java NIO globs match leading
        // dots, so macOS AppleDouble sidecars ("._sample.fastq.gz", written
        // beside every file on exFAT/USB media) were scanned as real FASTQ
        // inputs and failed CHOPPER with "not in gzip format" (2026-08-17).
        ch_all_samples = Channel.fromPath(["${input_dir}/*.{fastq,fastq.gz,fq,fq.gz}", "${input_dir}/**/*.{fastq,fastq.gz,fq,fq.gz}"])
            .filter { !it.name.startsWith('.') }
            .map { f ->
                def sample_id = InputDetector.extractSampleId(
                    f,
                    sample_regex,
                    params.sample_name,
                    input_dir
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

    // .ifEmpty returns a NEW channel; calling it without binding the result only
    // creates a dangling channel that nothing consumes, so the warning never
    // fired. .subscribe(onComplete:) observes the same condition on the channel
    // that is actually emitted.
    def saw_any_sample = new java.util.concurrent.atomic.AtomicBoolean(false)
    ch_all_samples.subscribe(
        onNext: { saw_any_sample.set(true) },
        onComplete: {
            if (!saw_any_sample.get()) {
                log.warn "WARNING: No FASTQ files found in input directory '${input_dir}'. Check the path and file extensions."
            }
        }
    )

    emit:
    samples  = ch_all_samples   // channel: [ val(meta), [path(reads)] ]
    versions = ch_versions      // channel: [ path(versions.yml) ]
}
