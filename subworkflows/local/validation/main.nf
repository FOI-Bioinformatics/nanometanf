//
// Enhanced validation subworkflow for pathogen confirmation
// Supports BLAST and minimap2 validation against reference genomes
//
// REQUIREMENT: params.save_reads_assignment must be true for this subworkflow to work
// The Kraken2 output file (per-read classifications) is needed to extract reads by taxid
//

include { EXTRACT_READS_BY_TAXID        } from '../../../modules/local/extract_reads_by_taxid/main'
include { BLASTN_VALIDATION             } from '../../../modules/local/blastn_validation/main'
include { MINIMAP2_VALIDATION           } from '../../../modules/local/minimap2_validation/main'
include { AGGREGATE_VALIDATION_RESULTS  } from '../../../modules/local/aggregate_validation_results/main'
include { CANONICAL_VALIDATION_WRITER  } from '../../../modules/local/canonical_validation_writer/main'

workflow VALIDATION {

    take:
    ch_classified_reads    // channel: [ val(meta), path(fastq) ] - from TAXONOMIC_CLASSIFICATION
    ch_kraken_output       // channel: [ val(meta), path(txt) ] - Kraken2 raw output (C/U lines)
    ch_kraken_reports      // channel: [ val(meta), path(txt) ] - Kraken2 reports (for read counts)
    pathogen_genomes       // val(path) - Path to genomes JSON file
    taxids_to_validate     // val(string) - 'auto', 'all', or comma-separated taxid list
    validation_method      // val(string) - 'blast', 'minimap2', or 'both'

    main:
    ch_versions = Channel.empty()

    //
    // Parse pathogen genomes JSON to get taxid -> genome/database path mapping
    // JSON format: { "taxid": "/path/to/genome.fasta", ... }
    //
    // Read the JSON file and parse it to create a channel of [taxid, genome_path] tuples
    // Relative paths are resolved from the JSON file's parent directory
    //
    ch_genome_mapping = Channel.fromPath(pathogen_genomes, checkIfExists: true)
        .map { json_file ->
            def json_text = json_file.text
            def slurper = new groovy.json.JsonSlurper()
            def genome_map
            try {
                genome_map = slurper.parseText(json_text)
            } catch (Exception e) {
                log.error "Failed to parse pathogen genomes JSON file: ${json_file}"
                log.error "Error: ${e.message}"
                log.error "Please ensure the file contains valid JSON format: {\"taxid\": \"/path/to/genome.fasta\", ...}"
                throw new RuntimeException("Invalid pathogen genomes JSON: ${e.message}")
            }

            // Check for empty genome map
            if (!genome_map || genome_map.isEmpty()) {
                log.warn "Pathogen genomes JSON file is empty: ${json_file}"
                log.warn "No validation tasks will be performed. Add taxid->genome mappings to enable validation."
                return []
            }

            def json_parent = json_file.parent
            return genome_map.collect { taxid, genome_path ->
                // Resolve relative paths from JSON file's parent directory
                def genome_file
                // Check for absolute paths (Unix or Windows style)
                if (genome_path.startsWith('/') || (genome_path.length() > 1 && genome_path.charAt(1) == ':')) {
                    // Absolute path
                    genome_file = file(genome_path, checkIfExists: true)
                } else {
                    // Relative path - resolve from JSON file's location
                    genome_file = file("${json_parent}/${genome_path}", checkIfExists: true)
                }
                [ taxid.toString(), genome_file ]
            }
        }
        .flatMap { it }  // Flatten the list of tuples into individual emissions

    //
    // Filter genome mapping based on taxids_to_validate parameter
    //
    ch_filtered_genomes = ch_genome_mapping
        .filter { taxid, genome ->
            if (taxids_to_validate == 'auto' || taxids_to_validate == 'all') {
                return true  // Include all taxids from JSON
            } else {
                // Only include requested taxids
                def requested = taxids_to_validate.split(',').collect { it.trim() }
                return requested.contains(taxid)
            }
        }

    //
    // Create validation tasks by combining samples with taxids
    // First join classified reads with kraken output by meta.id
    //
    ch_sample_data = ch_classified_reads
        .join(ch_kraken_output, by: [0], remainder: true)  // Join on meta

    //
    // Combine each sample with each taxid that has a genome available
    // Result: [ meta_with_taxid, reads, kraken_output, taxid, genome ]
    //
    ch_validation_tasks = ch_sample_data
        .combine(ch_filtered_genomes)
        .map { meta, reads, kraken_output, taxid, genome ->
            def new_meta = meta.clone()
            new_meta.taxid = taxid.toInteger()
            [ new_meta, reads, kraken_output, taxid, genome ]
        }

    //
    // MODULE: Extract reads classified as each target taxid
    // Input: combined tuple [ meta, reads, kraken_output, taxid ]
    //
    ch_extraction_input = ch_validation_tasks.map { meta, reads, kraken_output, taxid, genome ->
        [ meta, reads, kraken_output, taxid ]
    }

    EXTRACT_READS_BY_TAXID(ch_extraction_input)
    ch_versions = ch_versions.mix(EXTRACT_READS_BY_TAXID.out.versions.first().ifEmpty([]))

    //
    // Prepare validation input by combining extracted reads with genome references
    // Key by meta (which includes taxid) to properly join
    //
    // Use tuple keys [sample_id, taxid] for robust joining (avoids issues if sample_id contains underscores)
    ch_extracted_with_genome = EXTRACT_READS_BY_TAXID.out.reads
        .map { meta, reads -> [ [meta.id, meta.taxid.toString()], meta, reads ] }
        .join(
            ch_validation_tasks.map { meta, reads, kraken_output, taxid, genome ->
                [ [meta.id, taxid.toString()], genome ]
            },
            by: [0],
            remainder: true
        )
        .map { key, meta, reads, genome ->
            [ meta, reads, genome ]
        }

    //
    // MODULE: Run BLAST validation (if enabled)
    //
    ch_blast_stats = Channel.empty()
    ch_blast_results = Channel.empty()

    if (validation_method == 'blast' || validation_method == 'both') {
        BLASTN_VALIDATION(
            ch_extracted_with_genome,
            params.blast_evalue ?: "1e-10",
            params.blast_perc_identity ?: 90,
            params.blast_max_target_seqs ?: 1,
            params.validation_hit_rate_threshold ?: 0.5,
            params.validation_identity_threshold ?: 90.0
        )
        ch_blast_stats = BLASTN_VALIDATION.out.stats.map { meta, stats -> stats }.ifEmpty([])
        ch_blast_results = BLASTN_VALIDATION.out.results.ifEmpty([])
        ch_versions = ch_versions.mix(BLASTN_VALIDATION.out.versions.first().ifEmpty([]))
    }

    //
    // MODULE: Run minimap2 validation (if enabled)
    //
    ch_minimap2_stats = Channel.empty()
    ch_minimap2_results = Channel.empty()

    if (validation_method == 'minimap2' || validation_method == 'both') {
        MINIMAP2_VALIDATION(
            ch_extracted_with_genome,
            params.minimap2_preset ?: "map-ont",
            params.minimap2_min_mapq ?: 10,
            params.validation_hit_rate_threshold ?: 0.5,
            params.validation_identity_threshold ?: 90.0
        )
        ch_minimap2_stats = MINIMAP2_VALIDATION.out.stats.map { meta, stats -> stats }.ifEmpty([])
        ch_minimap2_results = MINIMAP2_VALIDATION.out.alignments.ifEmpty([])
        ch_versions = ch_versions.mix(MINIMAP2_VALIDATION.out.versions.first().ifEmpty([]))
    }

    //
    // MODULE: Aggregate all validation results into Nanometa Live JSON format
    //
    ch_extraction_stats = EXTRACT_READS_BY_TAXID.out.stats.map { meta, stats -> stats }

    // Collect Kraken2 reports for species name lookup
    ch_kraken_report_files = ch_kraken_reports.map { meta, report -> report }

    //
    // MODULE: Convert alignment results to canonical TSV format
    // Produces tool-agnostic output with named columns
    //
    // Build a unified channel of [meta, file, tool_name, format] from whichever
    // validation methods are active. A single process invocation handles all items.
    //
    ch_canonical_alignments = Channel.empty()
    if (params.write_canonical != false) {
        def ch_for_canonical = Channel.empty()

        if (validation_method == 'blast' || validation_method == 'both') {
            ch_for_canonical = ch_for_canonical.mix(
                ch_blast_results.map { meta, f -> [meta, f, "blast", "blast"] }
            )
        }
        if (validation_method == 'minimap2' || validation_method == 'both') {
            ch_for_canonical = ch_for_canonical.mix(
                ch_minimap2_results.map { meta, f -> [meta, f, "minimap2", "paf"] }
            )
        }

        CANONICAL_VALIDATION_WRITER (
            ch_for_canonical
        )
        ch_canonical_alignments = CANONICAL_VALIDATION_WRITER.out.canonical
        ch_versions = ch_versions.mix(CANONICAL_VALIDATION_WRITER.out.versions)
    }

    //
    // INTERMEDIATE VALIDATION: Progressive aggregation for real-time dashboard
    // Uses .tap() to fork channels and .subscribe to accumulate validation stats
    // in JVM memory, writing periodic intermediate JSON to outdir for dashboard polling.
    //
    def val_interval = params.validation_aggregate_interval ?: 0
    if (val_interval > 0) {
        // Fork channels for intermediate aggregation
        def ch_blast_for_intermediate = Channel.create()
        def ch_minimap2_for_intermediate = Channel.create()

        ch_blast_stats = ch_blast_stats.tap(ch_blast_for_intermediate)
        ch_minimap2_stats = ch_minimap2_stats.tap(ch_minimap2_for_intermediate)

        def intermediate_results = [].asSynchronized()
        def val_counter = new java.util.concurrent.atomic.AtomicInteger(0)

        ch_blast_for_intermediate.mix(ch_minimap2_for_intermediate).subscribe { stats_file ->
            try {
                def data = new groovy.json.JsonSlurper().parseText(stats_file.text)
                intermediate_results.add(data)
                def count = val_counter.incrementAndGet()

                if (count % val_interval == 0) {
                    def outdir = new File("${params.outdir}/validation")
                    outdir.mkdirs()
                    def json_text = new groovy.json.JsonBuilder(intermediate_results.collect()).toPrettyString()
                    def temp = new File(outdir, "intermediate_validation.json.tmp")
                    temp.text = json_text
                    def target = new File(outdir, "intermediate_validation.json")
                    if (!temp.renameTo(target)) {
                        target.text = temp.text
                        temp.delete()
                    }
                    log.debug "Intermediate validation updated: ${intermediate_results.size()} results"
                }
            } catch (Exception e) {
                log.warn "Intermediate validation aggregation failed: ${e.message}"
            }
        }
    }

    AGGREGATE_VALIDATION_RESULTS(
        ch_blast_stats.collect().ifEmpty([]),
        ch_minimap2_stats.collect().ifEmpty([]),
        ch_extraction_stats.collect().ifEmpty([]),
        ch_kraken_report_files.collect().ifEmpty([]),
        validation_method,
        params.validation_hit_rate_threshold ?: 0.5,
        params.validation_identity_threshold ?: 90.0
    )
    ch_versions = ch_versions.mix(AGGREGATE_VALIDATION_RESULTS.out.versions)

    emit:
    validation_json        = AGGREGATE_VALIDATION_RESULTS.out.json      // path: validation_results.json
    validation_summary     = AGGREGATE_VALIDATION_RESULTS.out.summary   // path: validation_summary.tsv
    extraction_stats       = EXTRACT_READS_BY_TAXID.out.stats           // channel: [ val(meta), path(json) ]
    blast_results          = ch_blast_results                           // channel: [ val(meta), path(tsv) ]
    minimap2_results       = ch_minimap2_results                        // channel: [ val(meta), path(paf) ]
    canonical_alignments   = ch_canonical_alignments                    // channel: [ val(meta), path(tsv) ] - Canonical alignment TSV
    versions               = ch_versions                                // channel: [ path(versions.yml) ]
}
