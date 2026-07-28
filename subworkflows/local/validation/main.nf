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
include { CONSENSUS_VALIDATION          } from '../../../modules/local/consensus_validation/main'
include { AGGREGATE_VALIDATION_RESULTS  } from '../../../modules/local/aggregate_validation_results/main'
include { AGGREGATE_VALIDATION_RESULTS as AGGREGATE_VALIDATION_LIVE } from '../../../modules/local/aggregate_validation_results/main'
include { CANONICAL_VALIDATION_WRITER  } from '../../../modules/local/canonical_validation_writer/main'
include { VALIDATION_CUMULATIVE_AGGREGATOR as MINIMAP2_CUMULATIVE_AGGREGATOR } from '../../../modules/local/validation_cumulative_aggregator/main'
include { VALIDATION_CUMULATIVE_AGGREGATOR as BLAST_CUMULATIVE_AGGREGATOR    } from '../../../modules/local/validation_cumulative_aggregator/main'

workflow VALIDATION {

    take:
    ch_classified_reads    // channel: [ val(meta), path(fastq) ] - from TAXONOMIC_CLASSIFICATION
    ch_kraken_output       // channel: [ val(meta), path(txt) ] - Kraken2 raw output (C/U lines)
    ch_kraken_reports      // channel: [ val(meta), path(txt) ] - Kraken2 reports (for read counts)
    pathogen_genomes       // val(path) - Path to genomes JSON file
    taxids_to_validate     // val(string) - 'auto', 'all', or comma-separated taxid list
    validation_method      // val(string) - 'blast', 'minimap2', or 'both'
    min_batch_reads_for_validation  // val(integer) - per-batch exact-taxid read floor; a (sample, taxid) pair is only extracted when this many reads are classified to the taxid IN THAT BATCH (per-batch gate, not a cumulative threshold; default 1 skips only zero-read taxids)

    main:
    ch_versions = Channel.empty()

    // The classification subworkflow attaches `.ifEmpty([])` sentinels to these
    // channels, so a sample with no classified reads (e.g. a negative control,
    // or the EMIT_EMPTY_KRAKEN2_REPORT placeholder) emits the `[]` sentinel.
    // The joins/combines and `{ meta, ... -> }` maps below would then be called
    // with `[]` and abort the run with MissingMethodException. Drop the sentinel
    // at the boundary so an empty sample simply yields no validation tasks; the
    // aggregator already tolerates an empty result via `.collect().ifEmpty([])`.
    ch_classified_reads = ch_classified_reads
        .filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map }
    ch_kraken_output = ch_kraken_output
        .filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map }
    ch_kraken_reports = ch_kraken_reports
        .filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map }

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
                // Each value must be a path string. Nanometa Live writes two
                // similar JSON files -- genome_metadata.json, whose values are
                // per-genome objects, and pathogen_genomes.json, whose values
                // are bare paths -- and only the latter belongs here. Pointing
                // at the former used to reach .startsWith() with a LazyMap and
                // fail as "Unknown method invocation `startsWith` on LazyMap
                // type", which names neither the file nor the real problem.
                if (!(genome_path instanceof CharSequence)) {
                    throw new IllegalArgumentException(
                        "Invalid --pathogen_genomes file '${json_file}': the entry " +
                        "for taxid ${taxid} is a ${genome_path.getClass().simpleName}, " +
                        "expected a path string. This file must map taxid to genome " +
                        "path, e.g. {\"263\": \"/path/to/263.fasta\"}. If you passed " +
                        "genome_metadata.json, use pathogen_genomes.json instead."
                    )
                }

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
    // Coerce to string before .split(): Nextflow's CLI parser auto-
    // promotes ``--taxids_to_validate 9606`` to Integer when the value
    // is all-digit, even though the schema declares it as string. Once
    // it lands here as Integer, .split(',') throws "Unknown method
    // invocation `split` on Integer type". The .toString() guard makes
    // this robust to both single-taxid and comma-list invocations,
    // including the GUI's nextflow run -resume on-demand path.
    ch_filtered_genomes = ch_genome_mapping
        .filter { taxid, genome ->
            def t = taxids_to_validate.toString()
            if (t == 'auto' || t == 'all') {
                return true  // Include all taxids from JSON
            } else {
                // Only include requested taxids
                def requested = t.split(',').collect { it.trim() }
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
    // Pre-extraction taxid gate (issue #6 scalability fix)
    //
    // Without this gate every (sample, taxid) pair launches EXTRACT_READS_BY_TAXID
    // each batch, including taxids absent from the batch -- the bulk of the
    // per-batch x per-taxid task explosion (a 20-file realtime run scheduled 665
    // extractions, almost all on zero-read taxids). Here the per-read Kraken2
    // assignment file is histogrammed once per (sample, batch) into an exact-taxid
    // read count, using the same '$1 == "C" && $3 == taxid' rule that
    // EXTRACT_READS_BY_TAXID applies, so the gate count equals what extraction
    // would find. A (sample, taxid) pair is only kept when its count meets the
    // floor (at least 1 -- extracting zero reads yields nothing). The histogram is
    // built once per batch in the head process, O(reads in this batch), replacing
    // N per-taxid process launches with a single parse.
    //
    def reads_floor = Math.max(1, (min_batch_reads_for_validation ?: 1) as int)
    ch_sample_with_hist = ch_sample_data
        .map { meta, reads, kraken_output ->
            // Exact-taxid read histogram for this batch, matching EXTRACT's rule.
            [ meta, reads, kraken_output, BatchUtils.exactTaxidReadCounts(kraken_output) ]
        }

    //
    // Combine each sample with each taxid that has a genome available, gating on
    // the per-batch read count, then drop the histogram.
    // Result: [ meta_with_taxid, reads, kraken_output, taxid, genome ]
    //
    ch_validation_tasks = ch_sample_with_hist
        .combine(ch_filtered_genomes)
        .filter { meta, reads, kraken_output, hist, taxid, genome ->
            def n = (hist[taxid.toString()] ?: 0)
            def keep = n >= reads_floor
            if (!keep) {
                log.debug "Validation gate: sample '${meta.id}' taxid '${taxid}' has ${n} classified read(s) (< ${reads_floor}) -- skipping extraction this batch"
            }
            return keep
        }
        .map { meta, reads, kraken_output, hist, taxid, genome ->
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
    // Use .first() to collapse the per-taxid scatter to a single versions
    // entry. Do NOT add .ifEmpty([]) -- a skipped process (e.g. a cumulative
    // aggregator in batch mode) would then inject an empty list `[]` into
    // ch_versions, and the nf-core softwareVersionsToYAML helper calls
    // Yaml.load() on each item, which throws MethodSelectionException on a
    // List. An empty channel mixed in contributes nothing, which is correct.
    ch_versions = ch_versions.mix(EXTRACT_READS_BY_TAXID.out.versions.first())

    //
    // Prepare validation input by combining extracted reads with genome references
    // Key by meta (which includes taxid) to properly join
    //
    // Use tuple keys [sample_id, taxid] for robust joining (avoids issues if sample_id contains underscores)
    // ``remainder: true`` lets either side flow through unmatched so the
    // join cannot deadlock; the downstream filter then drops half-tuples,
    // but a log.warn first records the drop so operators can trace why a
    // sample/taxid validation went missing rather than silently see it
    // disappear from the report.
    ch_extracted_with_genome = EXTRACT_READS_BY_TAXID.out.reads
        .map { meta, reads -> [ [meta.id, meta.taxid.toString()], meta, reads ] }
        .join(
            ch_validation_tasks.map { meta, reads, kraken_output, taxid, genome ->
                [ [meta.id, taxid.toString()], genome ]
            },
            by: [0],
            remainder: true
        )
        .map { row ->
            // A single-argument closure is required here because the remainder
            // join emits tuples of varying arity. EXTRACT_READS_BY_TAXID.out.reads
            // is an optional output (zero-read taxids emit no FASTQ), so a taxid
            // present only on the right (a validation task with no extracted reads)
            // arrives as a 3-element [key, null, genome] rather than the 4-element
            // [key, meta, reads, genome] of a matched key. A fixed 4-parameter
            // closure cannot bind the 3-element case and throws MissingMethodException.
            // The right side contributes the genome last in every case, so it is
            // addressed positionally; reads/meta are only present in the matched
            // 4-wide tuple.
            def key = row[0]
            def genome = row[-1]
            def reads = row.size() >= 4 ? row[2] : null
            def meta = row.size() >= 4 ? row[1] : null
            if (reads == null) {
                // Expected in realtime: a taxid with zero reads in this batch
                // emits no FASTQ from EXTRACT_READS_BY_TAXID (optional output),
                // so it is intentionally skipped here. Debug, not warn -- most
                // watchlist taxids are absent from any given batch.
                log.debug "Validation: no extracted reads for sample '${key[0]}' taxid '${key[1]}' -- skipping (no reads in this batch)"
                return null
            }
            if (genome == null) {
                log.warn "Validation join: no reference genome for sample '${key[0]}' taxid '${key[1]}' -- skipping validation for this pair"
                return null
            }
            return [ meta, reads, genome ]
        }
        .filter { it != null }

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
        ch_versions = ch_versions.mix(BLASTN_VALIDATION.out.versions.first())

        // Realtime only: maintain a run-so-far cumulative BLAST table + stats per
        // (sample, taxid). Pair this batch's table with its stats (for the
        // per-batch read count) and the prior cumulative files from the outdir;
        // the aggregator merges + recomputes. The ext.when guard plus this
        // filter keep it a no-op in batch mode.
        ch_blast_cumulative_input = BLASTN_VALIDATION.out.results
            .join(BLASTN_VALIDATION.out.stats)
            .filter { meta, tsv, stats -> meta.batch_id != null }
            .map { meta, tsv, stats ->
                def base = "${params.outdir}/validation/blast/${meta.id}_taxid${meta.taxid}"
                def prior_tsv = file("${base}.blast.tsv")
                def prior_stats = file("${base}.blast_stats.json")
                [ meta, meta.taxid, tsv, stats,
                  prior_tsv.exists() ? prior_tsv : [],
                  prior_stats.exists() ? prior_stats : [] ]
            }
        BLAST_CUMULATIVE_AGGREGATOR(ch_blast_cumulative_input, 'blast')
        ch_versions = ch_versions.mix(BLAST_CUMULATIVE_AGGREGATOR.out.versions.first())
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
        ch_versions = ch_versions.mix(MINIMAP2_VALIDATION.out.versions.first())

        // Realtime only: maintain a run-so-far cumulative PAF + stats per
        // (sample, taxid). See the BLAST branch above for the rationale.
        ch_minimap2_cumulative_input = MINIMAP2_VALIDATION.out.alignments
            .join(MINIMAP2_VALIDATION.out.stats)
            .filter { meta, paf, stats -> meta.batch_id != null }
            .map { meta, paf, stats ->
                def base = "${params.outdir}/validation/minimap2/${meta.id}_taxid${meta.taxid}"
                def prior_paf = file("${base}.paf")
                def prior_stats = file("${base}.minimap2_stats.json")
                [ meta, meta.taxid, paf, stats,
                  prior_paf.exists() ? prior_paf : [],
                  prior_stats.exists() ? prior_stats : [] ]
            }
        MINIMAP2_CUMULATIVE_AGGREGATOR(ch_minimap2_cumulative_input, 'minimap2')
        ch_versions = ch_versions.mix(MINIMAP2_CUMULATIVE_AGGREGATOR.out.versions.first())
    }

    //
    // MODULE: Generate a consensus sequence per (sample, taxid) from read
    // mapping. Opt-in via params.generate_consensus, independent of
    // validation_method so it can run alongside BLAST-only or minimap2-only
    // validation. Reuses ch_extracted_with_genome ([meta, reads, genome]).
    //
    ch_consensus = Channel.empty()
    ch_consensus_stats = Channel.empty()

    if (params.generate_consensus) {
        CONSENSUS_VALIDATION(
            ch_extracted_with_genome,
            params.minimap2_preset ?: "map-ont",
            params.consensus_min_depth ?: 10
        )
        ch_consensus = CONSENSUS_VALIDATION.out.consensus
        ch_consensus_stats = CONSENSUS_VALIDATION.out.stats
        ch_versions = ch_versions.mix(CONSENSUS_VALIDATION.out.versions.first())
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

        // ch_blast_results / ch_minimap2_results carry an `.ifEmpty([])`
        // sentinel (set above), so when validation produced no alignments they
        // emit `[]`. Filter the sentinel before the `{ meta, f -> ... }` map, or
        // the closure is called with `[]` and the run aborts. The post-mix
        // filter below only guards the downstream consumer, not these maps.
        if (validation_method == 'blast' || validation_method == 'both') {
            ch_for_canonical = ch_for_canonical.mix(
                ch_blast_results
                    .filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map }
                    .map { meta, f -> [meta, f, "blast", "blast"] }
            )
        }
        if (validation_method == 'minimap2' || validation_method == 'both') {
            ch_for_canonical = ch_for_canonical.mix(
                ch_minimap2_results
                    .filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map }
                    .map { meta, f -> [meta, f, "minimap2", "paf"] }
            )
        }

        // Guard against empty input from failed upstream validation
        def ch_for_canonical_filtered = ch_for_canonical.filter { it instanceof List && it.size() >= 2 && it[1] != null }

        CANONICAL_VALIDATION_WRITER (
            ch_for_canonical_filtered
        )
        ch_canonical_alignments = CANONICAL_VALIDATION_WRITER.out.canonical
        ch_versions = ch_versions.mix(CANONICAL_VALIDATION_WRITER.out.versions)
    }

    //
    // MODULE: Aggregate validation results into the Nanometa Live JSON.
    //
    // Two cadences share one aggregator module:
    //
    //  * Batch mode (no meta.batch_id): the source channels close at end of run,
    //    so a single .collect() gathers every per-batch stats file and one
    //    aggregation writes the final validation_results.json. Unchanged.
    //
    //  * Realtime mode (watchPath): the source channels never close until the
    //    timeout fires, so a .collect() barrier would defer the JSON to end of
    //    run. Instead we re-aggregate from the per-(sample, taxid) CUMULATIVE
    //    stats files, which VALIDATION_CUMULATIVE_AGGREGATOR already rebuilds
    //    each batch. A running snapshot keeps the latest file per key and
    //    re-emits the full current set on each update; every emission therefore
    //    rebuilds a complete, run-so-far JSON. The aggregator reads its work
    //    directory by filename suffix, so the combined snapshot is passed as the
    //    first path input and the remaining inputs are empty.
    //
    ch_validation_json = Channel.empty()
    ch_validation_summary = Channel.empty()

    if (params.realtime_mode) {
        def interval = (params.validation_aggregate_interval ?: 1) as int

        def ch_blast_cumulative_stats = (validation_method == 'blast' || validation_method == 'both') ?
            BLAST_CUMULATIVE_AGGREGATOR.out.stats.map { meta, taxid, f -> ["blast|${meta.id}|${taxid}", f] } :
            Channel.empty()
        def ch_minimap2_cumulative_stats = (validation_method == 'minimap2' || validation_method == 'both') ?
            MINIMAP2_CUMULATIVE_AGGREGATOR.out.stats.map { meta, taxid, f -> ["mm2|${meta.id}|${taxid}", f] } :
            Channel.empty()

        // Tag every upstream update with whether it is a per-batch BOUNDARY (a
        // Kraken2 report -- one per batch) or just a stat refresh. The .map
        // closures here are pure (they only relabel the tuple); all cross-emission
        // state lives in the ValidationSnapshotAccumulator below.
        def ch_tagged = ch_blast_cumulative_stats.map { k, f -> [k, f, false] }
            .mix(ch_minimap2_cumulative_stats.map { k, f -> [k, f, false] })
            .mix(
                EXTRACT_READS_BY_TAXID.out.stats
                    .filter { meta, f -> meta.batch_id != null }
                    .map { meta, f -> ["ext|${meta.id}|${meta.taxid}", f, false] }
            )
            .mix(
                // Kraken2 reports carry the taxid->species names the aggregator
                // needs and arrive one per batch, so they double as the per-batch
                // aggregation heartbeat (tagged true). ch_kraken_reports delivers
                // the per-batch reports (meta has batch_id) plus the end-of-session
                // cumulative report (no batch_id); key each uniquely with an
                // explicit null check so batch_id 0 is not mistaken for the
                // cumulative, so the snapshot accumulates every report.
                ch_kraken_reports
                    .map { meta, r ->
                        def tag = meta.batch_id != null ? meta.batch_id : 'final'
                        ["krak|${meta.id}|${tag}", r, true]
                    }
            )

        // Running snapshot: remember the latest file per key and re-emit the full
        // current set on each update, tagged with whether this emission should
        // trigger an aggregation. The accumulator owns all the state, so the
        // operators below stay pure.
        //
        // Issue #29: aggregating on every store update -- for a single barcode of
        // 8 files that was ~366 AGGREGATE_VALIDATION_LIVE runs. That process is
        // maxForks=1 (serialised) and each run does a conda activation; under that
        // load a single flaky `conda info --json` activation hung the one allowed
        // slot and, because every later aggregation and the .last() final queue
        // behind it, the whole realtime run wedged (0 running, ~1000 pending).
        // Triggering once per batch boundary (thinned by interval) cuts the count
        // ~40x, so the live JSON stays fresh while the maxForks=1 slot is no longer
        // hammered. The per-batch result lags stat updates by at most one batch;
        // the final snapshot below is always complete.
        def snapshotter = new ValidationSnapshotAccumulator(interval)
        def ch_snapshots = ch_tagged.map { key, f, isBoundary ->
            snapshotter.update(key, f, isBoundary)
        }

        // Pure filter/map: aggregate when the accumulator flagged a boundary.
        def ch_periodic = ch_snapshots
            .filter { shouldAggregate, files -> shouldAggregate }
            .map { shouldAggregate, files -> files }

        // Final-snapshot guarantee: the terminal emission may be a stat update
        // (not a boundary), so always re-emit the last snapshot to publish the
        // complete final set. A duplicate final aggregation is harmless --
        // AGGREGATE_VALIDATION_LIVE rebuilds the full JSON and maxForks=1
        // serialises the writes, so it overwrites with identical content.
        def ch_final = ch_snapshots
            .last()
            .map { shouldAggregate, files -> files }

        def ch_live_input = ch_periodic.mix(ch_final)

        AGGREGATE_VALIDATION_LIVE(
            ch_live_input,
            [],
            [],
            [],
            validation_method,
            params.validation_hit_rate_threshold ?: 0.5,
            params.validation_identity_threshold ?: 90.0
        )
        ch_validation_json = AGGREGATE_VALIDATION_LIVE.out.json
        ch_validation_summary = AGGREGATE_VALIDATION_LIVE.out.summary
        // The live aggregator re-runs each batch; collapse its repeated version
        // emissions to one so ch_versions is not flooded with duplicates.
        ch_versions = ch_versions.mix(AGGREGATE_VALIDATION_LIVE.out.versions.first())
    } else {
        AGGREGATE_VALIDATION_RESULTS(
            ch_blast_stats.collect().ifEmpty([]),
            ch_minimap2_stats.collect().ifEmpty([]),
            ch_extraction_stats.collect().ifEmpty([]),
            ch_kraken_report_files.collect().ifEmpty([]),
            validation_method,
            params.validation_hit_rate_threshold ?: 0.5,
            params.validation_identity_threshold ?: 90.0
        )
        ch_validation_json = AGGREGATE_VALIDATION_RESULTS.out.json
        ch_validation_summary = AGGREGATE_VALIDATION_RESULTS.out.summary
        ch_versions = ch_versions.mix(AGGREGATE_VALIDATION_RESULTS.out.versions)
    }

    emit:
    validation_json        = ch_validation_json                         // path: validation_results.json
    validation_summary     = ch_validation_summary                      // path: validation_summary.tsv
    extraction_stats       = EXTRACT_READS_BY_TAXID.out.stats           // channel: [ val(meta), path(json) ]
    blast_results          = ch_blast_results                           // channel: [ val(meta), path(tsv) ]
    minimap2_results       = ch_minimap2_results                        // channel: [ val(meta), path(paf) ]
    consensus              = ch_consensus                               // channel: [ val(meta), path(fasta) ]
    consensus_stats        = ch_consensus_stats                         // channel: [ val(meta), path(json) ]
    canonical_alignments   = ch_canonical_alignments                    // channel: [ val(meta), path(tsv) ] - Canonical alignment TSV
    versions               = ch_versions                                // channel: [ path(versions.yml) ]
}
