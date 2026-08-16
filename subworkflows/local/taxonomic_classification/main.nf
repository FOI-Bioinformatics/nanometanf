/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: TAXONOMIC_CLASSIFICATION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Multi-tool taxonomic classification with taxpasta standardization

    Supported classifiers:
    - kraken2: Kraken2 k-mer based classification

    Features:
    - Tool-agnostic interface
    - Taxpasta standardization for consistent outputs
    - Easy addition of new classifiers
    - Scalable streaming architecture with per-sample parallelism (v1.5+)
----------------------------------------------------------------------------------------
*/

include { KRAKEN2_KRAKEN2                } from '../../../modules/nf-core/kraken2/kraken2/main'
include { KRAKEN2_OPTIMIZED              } from '../../../modules/local/kraken2_optimized/main'
include { KRAKEN2_INCREMENTAL_CLASSIFIER } from '../../../modules/local/kraken2_incremental_classifier/main'
include { KRAKEN2_DB_PRELOAD             } from '../../../modules/local/kraken2_db_preload/main'
include { KRAKEN2_OUTPUT_MERGER          } from '../../../modules/local/kraken2_output_merger/main'
include { KRAKEN2_REPORT_GENERATOR       } from '../../../modules/local/kraken2_report_generator/main'
include { KRAKEN2_FINAL_AGGREGATOR       } from '../../../modules/local/kraken2_final_aggregator/main'
include { EMIT_EMPTY_KRAKEN2_REPORT     } from '../../../modules/local/emit_empty_kraken2_report/main'
include { TAXPASTA_STANDARDISE           } from '../../../modules/nf-core/taxpasta/standardise/main'
include { CANONICAL_CLASSIFICATION_WRITER } from '../../../modules/local/canonical_classification_writer/main'

workflow TAXONOMIC_CLASSIFICATION {

    take:
    ch_reads     // channel: [ val(meta), path(reads) ] - streaming compatible (from watchPath or samplesheet)
    ch_db        // channel: [ path(db) ] - MUST be a value channel (use .first()) for streaming compatibility
                 // Queue channels are consumed after one emission, breaking streaming workflows

    main:
    ch_versions = Channel.empty()
    ch_classified_reads = Channel.empty()
    ch_unclassified_reads = Channel.empty()
    ch_reads_assignment = Channel.empty()
    ch_raw_reports = Channel.empty()
    ch_batch_reports = Channel.empty()
    ch_final_cumulative_output = Channel.empty()
    ch_final_cumulative_report = Channel.empty()

    // Set classifier and validate parameters
    def classifier = params.classifier ?: 'kraken2'
    def output_format = params.taxpasta_format ?: 'tsv'

    //
    // EMPTY-FASTQ GUARD
    //
    // Upstream QC (chopper, fastp) can legitimately produce an output FASTQ
    // with zero reads when every input read fails its quality or length
    // thresholds. Passing such a file to Kraken2 wastes scheduler cycles and
    // risks downstream failures in reporting tools that assume a non-empty
    // report. A gzipped FASTQ containing zero records is typically under 50
    // bytes (just the gzip framing), while a single minimal read gzips to
    // more than that. Filter those entries out here, log a warning so the
    // operator can see which sample was skipped, and let the channel
    // continue with the remaining samples.
    //
    // This guard is deliberately applied to the shared `ch_reads` input so
    // it covers all three classification paths (incremental, optimized,
    // standard) with a single check.
    //
    // Accept both channels (production wiring) and plain Lists (nf-test
    // compatibility). Tests pass three shapes:
    //   - []                           -> no samples
    //   - [meta, reads]                -> single sample tuple
    //   - [[meta, reads], [meta, ...]] -> list of sample tuples
    // Detect the single-tuple case by looking at the first element: a Map
    // indicates a meta dict, so the outer list IS the tuple; otherwise the
    // outer list is a collection of tuples.
    def ch_reads_input
    if (ch_reads instanceof List) {
        if (ch_reads.isEmpty()) {
            ch_reads_input = Channel.empty()
        } else if (ch_reads[0] instanceof Map) {
            ch_reads_input = Channel.of(ch_reads)
        } else {
            ch_reads_input = Channel.fromList(ch_reads)
        }
    } else {
        ch_reads_input = ch_reads
    }
    def empty_fastq_threshold = 50L
    // Upstream QC subworkflows attach `.ifEmpty([])` to their reads
    // channel so the top-level pipeline assertions see an emission even
    // when every CHOPPER / FASTP task failed. That synthetic `[]`
    // placeholder must be dropped before any tuple-destructuring closure
    // sees it -- otherwise `.branch { meta, reads -> ... }` raises
    // "Invalid method invocation `call` with arguments: [] (ArrayList)"
    // and aborts the whole streaming session. Mirrors the guard already
    // in place in qc_analysis (NanoPlot input) and the canonical writer.
    def ch_reads_tuples = ch_reads_input.filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map }
    // Split into two streams: samples with classifiable reads go to the
    // real Kraken2 path; samples whose post-QC FASTQ is empty (every
    // read filtered upstream) go to the placeholder path. The
    // placeholder still emits a well-formed Kraken2 report so MULTIQC,
    // TAXPASTA and the GUI loaders see all samples uniformly with a
    // 0-classified / 0-unclassified accounting -- previously these
    // samples vanished from every downstream channel.
    def ch_branched = ch_reads_tuples.branch { meta, reads ->
        def reads_list = reads instanceof List ? reads : [reads]
        def has_any = reads_list.any { f -> f != null && f.exists() && f.size() >= empty_fastq_threshold }
        if (!has_any) {
            log.warn "Empty post-QC FASTQ for sample '${meta.id}' - emitting placeholder Kraken2 report (0 reads, all unclassified)"
        }
        pass: has_any
        skip: !has_any
    }
    ch_reads = ch_branched.pass
    def ch_empty_samples = ch_branched.skip

    //
    // PHASE 2 OPTIMIZATION: Automatic database preloading in real-time mode
    //
    // Enable Kraken2 optimizations automatically for PromethION real-time processing
    // Memory-mapping enables OS-level database caching, eliminating redundant disk I/O across batches
    //
    def auto_enable_optimizations = params.realtime_mode && !params.kraken2_use_optimizations
    // Auto-disable memory-mapping on ARM (Apple Silicon / aarch64) where x86 emulation
    // via Rosetta can cause SIGSEGV crashes with memory-mapped Kraken2 databases.
    def is_arm = System.getProperty('os.arch')?.contains('aarch64') || System.getProperty('os.arch')?.contains('arm')
    def use_memory_mapping = is_arm ? false : params.kraken2_memory_mapping
    if (is_arm && params.kraken2_memory_mapping) {
        log.warn "ARM architecture detected - disabling Kraken2 memory-mapping to avoid SIGSEGV under emulation"
    }
    def use_optimizations = params.realtime_mode ? true : params.kraken2_use_optimizations

    if (auto_enable_optimizations && classifier == 'kraken2') {
        log.info "=== Phase 2: Database Preloading Enabled ==="
        log.info "Real-time mode detected - automatically enabling Kraken2 optimizations:"
        log.info "  - Memory-mapped database loading: ${use_memory_mapping ? 'ENABLED' : 'DISABLED (ARM Mac compatible mode)'}"
        if (use_memory_mapping) {
            log.info "  - Database cached in OS page cache for reuse across batches"
            log.info "  - Eliminates repeated database loading (30+ batches -> 1 load)"
            log.info "  - Estimated time savings: 1-3 minutes per batch after first load"
        } else {
            log.info "  - Note: Set --kraken2_memory_mapping true for faster performance on x86 systems"
        }
    }

    // Log scalable streaming architecture info
    if (params.kraken2_enable_incremental && params.realtime_mode) {
        log.info "=== Scalable Streaming Architecture ==="
        log.info "Per-sample parallel processing enabled:"
        log.info "  - Batch files stored separately (append-only, O(1) per batch)"
        log.info "  - Incremental taxid counting (no full file re-reads)"
        log.info "  - Concurrency limit: ${params.max_classification_forks ?: 8} parallel Kraken2 jobs"
        log.info "  - Final aggregation at end-of-session"
    }

    //
    // DATABASE PRELOAD: Load hash.k2d into OS page cache before classification
    // When memory-mapping is enabled, all Kraken2 forks share the cached pages.
    // The preloaded db channel ensures classification waits for preload completion.
    //
    if (use_memory_mapping && classifier == 'kraken2') {
        KRAKEN2_DB_PRELOAD(ch_db)
        ch_db_ready = KRAKEN2_DB_PRELOAD.out.db
        ch_versions = ch_versions.mix(KRAKEN2_DB_PRELOAD.out.versions)
    } else {
        ch_db_ready = ch_db
    }

    //
    // BRANCH: Route to appropriate classifier
    //
    if (classifier == 'kraken2') {
            //
            // MODULE: Run Kraken2 for taxonomic classification
            // Three modes: incremental (batch caching), optimized (memory-mapping), or standard
            //
            if (params.kraken2_enable_incremental == true || params.realtime_mode == true) {
                log.info "=== Phase 1.1: Incremental Kraken2 Classification ==="
                log.info "Using incremental Kraken2 processing with batch caching:"
                log.info "  - Classify only NEW reads per batch (O(n) vs O(n^2))"
                log.info "  - Raw outputs cached per batch for efficient merging"
                log.info "  - Cumulative reports generated from merged data"
                if (params.realtime_mode && !params.kraken2_enable_incremental) {
                    log.info "  - Automatically enabled by realtime mode for cumulative reporting"
                }
                log.info "  - Estimated time savings: 30-90 minutes for 30-batch runs"

                //
                // CHANNEL OPERATION: Add batch_id to metadata for incremental processing
                // STREAMING-COMPATIBLE: Uses stateful counter without channel completion
                // Works for real-time (streaming) and samplesheet (static) modes
                // Per-sample batch numbering: each sample gets sequential batch_id (0, 1, 2...)
                //
                // ARCHITECTURE FIX: Previous .collect() approach waited for channel completion,
                // incompatible with watchPath() which never closes in true streaming mode.
                // This stateful .map() assigns batch_id as files arrive without blocking.
                //
                def sample_batch_counters = [:].withDefault { 0 }

                ch_reads_with_batch = ch_reads
                    .map { meta, reads ->
                        def meta_with_batch = meta.clone()
                        def sample_id = meta.id

                        // Thread-safe counter increment per sample
                        // Ensures sequential batch numbering: 0, 1, 2... for each sample
                        // BatchUtils.withLock keeps `synchronized` out of the strict
                        // v2 grammar's reach (script scope rejects the keyword).
                        BatchUtils.withLock(sample_batch_counters) {
                            meta_with_batch.batch_id = sample_batch_counters[sample_id]
                            sample_batch_counters[sample_id] = sample_batch_counters[sample_id] + 1
                        }

                        return tuple(meta_with_batch, reads)
                    }

                //
                // MODULE: Incremental classification with caching
                //
                KRAKEN2_INCREMENTAL_CLASSIFIER (
                    ch_reads_with_batch,
                    ch_db_ready,
                    params.save_output_fastqs ?: false,
                    params.save_reads_assignment ?: false,
                    use_memory_mapping
                )
                ch_versions = ch_versions.mix(KRAKEN2_INCREMENTAL_CLASSIFIER.out.versions)

                //
                // SCALABLE STREAMING ARCHITECTURE (v1.5+)
                // Per-sample parallelism with append-only batch storage
                //
                // Architecture:
                // 1. Each batch is classified independently (parallel across samples)
                // 2. Batch output stored as separate file (O(1) write, no cumulative re-read)
                // 3. All processes are stateless (no shared filesystem state)
                // 4. Final aggregation at end-of-session collects batch files via channels
                //

                //
                // MODULE: Store batch output with append-only architecture
                // Stateless: writes only to work directory, no outdir reads
                //
                KRAKEN2_OUTPUT_MERGER (
                    KRAKEN2_INCREMENTAL_CLASSIFIER.out.classifier_output
                )
                ch_versions = ch_versions.mix(KRAKEN2_OUTPUT_MERGER.out.versions)

                //
                // MODULE: Process per-batch report (stateless, no cumulative state)
                //
                KRAKEN2_REPORT_GENERATOR (
                    KRAKEN2_OUTPUT_MERGER.out.merger_output
                )
                ch_versions = ch_versions.mix(KRAKEN2_REPORT_GENERATOR.out.versions)

                // Expose the per-batch reports (meta carries batch_id, file is
                // sample-unique) so downstream realtime validation can resolve
                // taxid->species names during the run, rather than waiting for
                // the end-of-session cumulative report (which a timeout-stopped
                // run may never produce).
                ch_batch_reports = KRAKEN2_REPORT_GENERATOR.out.report

                //
                // PROGRESSIVE CUMULATIVE REPORTING
                // Accumulates per-batch taxid counts in Groovy memory and writes
                // progressive cumulative kreports to outdir for Nanometa Live polling.
                // Runs in the Nextflow head process (single JVM) with synchronized
                // per-sample state -- no race conditions, no shared filesystem state.
                // This provides live cumulative reports during the run, while
                // FINAL_AGGREGATOR produces the definitive output at session end.
                //
                // MEMORY BOUNDING (audit P2.15):
                //  * Each per-sample taxa map grows with unique taxids and never
                //    shrinks during the run. On long high-diversity runs that
                //    map can reach tens or hundreds of thousands of entries
                //    (24 samples * 10k taxa * ~80 B per entry approaches 20 MB
                //    of long-lived heap inside the Nextflow head process).
                //  * Release each sample's state from the head-process map as
                //    soon as its final batch is written, so completed samples
                //    do not pin memory until session shutdown.
                //  * Periodically log the live state size so operators can
                //    detect runaway accumulation before it triggers OOM in the
                //    Nextflow driver JVM. The log interval is tied to the
                //    same write_interval that gates the report flush.
                //
                def cumulative_taxa_state = [:].withDefault { key ->
                    [total_reads: 0, classified_reads: 0, unclassified_reads: 0, taxa: [:]]
                }
                def batch_write_counter = [:].withDefault { 0 }
                def write_interval = params.report_write_interval ?: 5

                KRAKEN2_REPORT_GENERATOR.out.taxid_counts
                    .subscribe(onNext: { item ->
                        def sample_label = "unknown"
                        try {
                            def meta = item[0]
                            def taxid_file = item[1]
                            def sample_id = meta.id
                            sample_label = sample_id

                            BatchUtils.withLock(cumulative_taxa_state) {
                                def batch_counts = new groovy.json.JsonSlurper().parseText(taxid_file.text)
                                def state = cumulative_taxa_state[sample_id]

                                // Merge batch taxa into cumulative state.
                                // `parent` comes from KRAKEN2_REPORT_GENERATOR, which
                                // recovers it from the batch report's own row order and
                                // indentation. It is carried here because the cumulative
                                // report must be written depth first (see the write
                                // below); a taxa map alone cannot say where a row goes.
                                batch_counts.taxa.each { taxid, data ->
                                    if (!state.taxa.containsKey(taxid)) {
                                        state.taxa[taxid] = [
                                            reads: 0, cumul: 0,
                                            rank: data.rank, name: data.name,
                                            parent: data.parent
                                        ]
                                    } else if (state.taxa[taxid].parent == null && data.parent != null) {
                                        // A taxon can appear as a root in one batch and
                                        // with its lineage in a later, deeper one.
                                        state.taxa[taxid].parent = data.parent
                                    }
                                    state.taxa[taxid].reads += (data.reads as int)
                                    state.taxa[taxid].cumul += (data.cumul as int)
                                }
                                state.total_reads += (batch_counts.total_reads as int)
                                state.classified_reads += (batch_counts.classified_reads as int)
                                state.unclassified_reads += (batch_counts.unclassified_reads as int)

                                batch_write_counter[sample_id] = batch_write_counter[sample_id] + 1

                                // Write the live progressive report every N batches.
                                // A per-batch "final batch" flag is not knowable in a
                                // streaming watchPath run, so the definitive end-of-
                                // session report is produced by KRAKEN2_FINAL_AGGREGATOR
                                // (it writes the same kraken2/<id>.cumulative.kraken2.
                                // report.txt from the per-batch files on disk), and the
                                // in-memory state is released in onComplete below.
                                if (write_interval <= 0
                                    || batch_write_counter[sample_id] % write_interval == 0) {

                                    // Write progressive cumulative kreport for dashboard
                                    def outdir = new File("${params.outdir}/kraken2")
                                    outdir.mkdirs()
                                    def total = state.total_reads ?: 1

                                    // Depth first, NOT by descending cumulative reads.
                                    // The name column keeps its two-space-per-level
                                    // indentation, so an indent-stack reader resolves a
                                    // row's parent from the nearest preceding row with a
                                    // smaller indent. Sorting by abundance leaves that
                                    // indentation in place while destroying the order it
                                    // relies on, which silently re-parents taxa (a phylum
                                    // reads as a child of whichever domain now precedes
                                    // it). KreportTree keeps siblings in descending-cumul
                                    // order within the correct tree.
                                    def sb = new StringBuilder()
                                    KreportTree.depthFirstOrder(state.taxa).each { taxid ->
                                        def tdata = state.taxa[taxid]
                                        if (tdata == null) {
                                            return
                                        }
                                        def pct = String.format("%.2f", ((tdata.cumul as double) / total) * 100.0)
                                        sb.append("${pct}\t${tdata.cumul}\t${tdata.reads}\t${tdata.rank}\t${taxid}\t${tdata.name}\n")
                                    }

                                    // Atomic write: temp file then rename
                                    def temp = new File(outdir, "${sample_id}.cumulative.kraken2.report.txt.tmp")
                                    temp.text = sb.toString()
                                    def target = new File(outdir, "${sample_id}.cumulative.kraken2.report.txt")
                                    if (!temp.renameTo(target)) {
                                        // renameTo can fail silently; fall back to copy+delete
                                        target.text = temp.text
                                        temp.delete()
                                        log.debug "Progressive report: renameTo failed, used copy fallback for ${sample_id}"
                                    }

                                    log.debug "Progressive cumulative report updated for ${sample_id}: ${state.total_reads} reads, ${state.taxa.size()} taxa"

                                    // Memory diagnostic at every write: total live taxa across all in-flight samples
                                    def live_samples = cumulative_taxa_state.size()
                                    def live_taxa = cumulative_taxa_state.values().sum(0) { it.taxa.size() }
                                    log.info "[cumulative-state] ${live_samples} sample(s) in flight, ${live_taxa} total live taxa entries"
                                } // end write interval check
                            }
                        } catch (Exception e) {
                            log.warn "Progressive cumulative report failed for sample '${sample_label}': ${e.message}"
                        }
                    },
                    onComplete: {
                        // End of the real-time session (the watchPath closed via the
                        // inactivity timeout or max_files). Release the per-sample
                        // accumulator from the head-process heap. A per-batch "final
                        // batch" signal is not available in a streaming run, so channel
                        // closure is the correct end-of-session trigger; the definitive
                        // cumulative report is produced by KRAKEN2_FINAL_AGGREGATOR.
                        try {
                            BatchUtils.withLock(cumulative_taxa_state) {
                                def released = cumulative_taxa_state.size()
                                cumulative_taxa_state.clear()
                                batch_write_counter.clear()
                                log.info "[cumulative-state] end of session: released in-memory state for ${released} sample(s)"
                            }
                        } catch (Exception e) {
                            log.warn "End-of-session cumulative-state release failed: ${e.message}"
                        }
                    })

                //
                // END-OF-SESSION AGGREGATION
                // Collect all batch output and report files per sample via channels.
                // groupTuple waits for channel closure (end of real-time session or
                // static input complete), then passes collected files to aggregator.
                // This produces the definitive cumulative output from actual files.
                //

                // Collect batch output files per sample
                ch_sample_outputs = KRAKEN2_OUTPUT_MERGER.out.batch_output
                    .map { meta, output_file ->
                        return tuple(meta.id, output_file)
                    }
                    .groupTuple(by: 0, remainder: true)

                // Collect batch report files per sample
                ch_sample_reports = KRAKEN2_OUTPUT_MERGER.out.batch_report_copy
                    .map { meta, report_file ->
                        return tuple(meta.id, report_file)
                    }
                    .groupTuple(by: 0, remainder: true)

                // Join outputs and reports by sample_id, then run aggregation
                // Both channels come from the same OUTPUT_MERGER process, so cardinality
                // always matches. Use remainder:true to allow partial results if
                // errorStrategy permits some batch failures.
                ch_aggregator_input = ch_sample_outputs
                    .join(ch_sample_reports, by: 0, remainder: true)
                    .map { sample_id, outputs, reports ->
                        return tuple([id: sample_id, batch_count: outputs.size()], outputs, reports)
                    }

                KRAKEN2_FINAL_AGGREGATOR (
                    ch_aggregator_input
                )
                ch_versions = ch_versions.mix(KRAKEN2_FINAL_AGGREGATOR.out.versions)

                // Emit final cumulative outputs
                ch_final_cumulative_output = KRAKEN2_FINAL_AGGREGATOR.out.cumulative_output
                ch_final_cumulative_report = KRAKEN2_FINAL_AGGREGATOR.out.cumulative_report

                // Collect outputs from incremental path
                ch_classified_reads = KRAKEN2_INCREMENTAL_CLASSIFIER.out.classified_reads_fastq.ifEmpty([])
                ch_unclassified_reads = KRAKEN2_INCREMENTAL_CLASSIFIER.out.unclassified_reads_fastq.ifEmpty([])
                ch_reads_assignment = KRAKEN2_INCREMENTAL_CLASSIFIER.out.classified_reads_assignment.ifEmpty([])
                // Use final cumulative report for downstream (TAXPASTA, KRONA, MultiQC)
                // Per-batch reports would produce 720 files for 24 barcodes x 30 batches
                ch_raw_reports = KRAKEN2_FINAL_AGGREGATOR.out.cumulative_report
                ch_performance_metrics = KRAKEN2_REPORT_GENERATOR.out.stats

            } else if (use_optimizations == true) {
                log.info "Using optimized Kraken2 classification with:"
                log.info "  - Memory mapping: ${use_memory_mapping}"
                log.info "  - Confidence threshold: ${params.kraken2_confidence}"
                log.info "  - Minimum hit groups: ${params.kraken2_minimum_hit_groups}"

                KRAKEN2_OPTIMIZED (
                    ch_reads,
                    ch_db_ready,
                    params.save_output_fastqs ?: false,
                    params.save_reads_assignment ?: false,
                    use_memory_mapping,
                    params.kraken2_confidence ?: 0.0,
                    params.kraken2_minimum_hit_groups ?: 0
                )
                ch_versions = ch_versions.mix(KRAKEN2_OPTIMIZED.out.versions)

                // Collect outputs
                ch_classified_reads = KRAKEN2_OPTIMIZED.out.classified_reads_fastq.ifEmpty([])
                ch_unclassified_reads = KRAKEN2_OPTIMIZED.out.unclassified_reads_fastq.ifEmpty([])
                ch_reads_assignment = KRAKEN2_OPTIMIZED.out.classified_reads_assignment.ifEmpty([])
                ch_raw_reports = KRAKEN2_OPTIMIZED.out.report
                ch_performance_metrics = KRAKEN2_OPTIMIZED.out.performance_metrics.ifEmpty([])
            } else {
                KRAKEN2_KRAKEN2 (
                    ch_reads,
                    ch_db_ready,
                    params.save_output_fastqs ?: false,    // save_output_fastqs
                    params.save_reads_assignment ?: false  // save_reads_assignment
                )
                // KRAKEN2_KRAKEN2 uses topic: versions pattern - no .out.versions channel.
                // Versions are aggregated via Channel.topic('versions') in workflows/nanometanf.nf

                // Collect outputs
                ch_classified_reads = KRAKEN2_KRAKEN2.out.classified_reads_fastq.ifEmpty([])
                ch_unclassified_reads = KRAKEN2_KRAKEN2.out.unclassified_reads_fastq.ifEmpty([])
                ch_reads_assignment = KRAKEN2_KRAKEN2.out.classified_reads_assignment.ifEmpty([])
                ch_raw_reports = KRAKEN2_KRAKEN2.out.report
                ch_performance_metrics = Channel.empty()
            }
    } else {
        error "Unsupported classifier: ${classifier}. Currently supported: kraken2"
    }

    //
    // PLACEHOLDER REPORTS: synthesize a 0-read Kraken2 report for any
    // sample whose post-QC FASTQ was empty. Mixed into ch_raw_reports
    // after the classifier ran so MULTIQC, TAXPASTA and the Nanometa
    // Live GUI loaders see all samples uniformly. The TAXPASTA filter
    // below already drops zero-byte reports defensively, but the
    // GUI's per-sample table is now complete.
    //
    EMIT_EMPTY_KRAKEN2_REPORT(ch_empty_samples)
    ch_raw_reports = ch_raw_reports.mix(EMIT_EMPTY_KRAKEN2_REPORT.out.report)
    ch_versions = ch_versions.mix(EMIT_EMPTY_KRAKEN2_REPORT.out.versions)

    //
    // MODULE: Standardize classification reports with taxpasta
    //
    if (params.enable_taxpasta_standardization != false) {
        //
        // STREAMING-FIX: All non-streaming inputs must be value channels
        // Queue channels (default for file()) are consumed after one use
        // Value channels can be reused across multiple streaming emissions
        //
        def taxonomy_file = params.taxonomy_file ? file(params.taxonomy_file, checkIfExists: true) : []

        // Skip TAXPASTA for samples whose classifier report is absent,
        // empty, or the EMIT_EMPTY_KRAKEN2_REPORT placeholder. An
        // empty or placeholder report (for instance when every read
        // was filtered out upstream) causes taxpasta to abort the
        // pipeline. The placeholder is ~30 bytes (one unclassified
        // line); a genuine Kraken2 report carries at minimum the
        // root + cellular-organisms + domain rows for hundreds of
        // bytes even on a single classified read, so a 100-byte
        // floor cleanly separates real from placeholder without
        // requiring metadata flags.
        def ch_reports_for_taxpasta = ch_raw_reports.filter {
            it instanceof List && it.size() >= 2 && it[1] != null && it[1].size() > 100
        }

        TAXPASTA_STANDARDISE (
            ch_reports_for_taxpasta,
            Channel.value(classifier),
            Channel.value(output_format),
            Channel.value(taxonomy_file)
        )
        ch_versions = ch_versions.mix(TAXPASTA_STANDARDISE.out.versions)
        ch_standardized_reports = TAXPASTA_STANDARDISE.out.standardised_profile
    } else {
        ch_standardized_reports = ch_raw_reports
    }

    //
    // MODULE: Convert classification reports to canonical JSON format
    // Produces tool-agnostic output for frontend consumption
    //
    ch_canonical_classification = Channel.empty()
    if (params.write_canonical != false) {
        // Guard against empty input from failed upstream classification
        def ch_reports_filtered = ch_raw_reports.filter { it instanceof List && it.size() >= 2 && it[1] != null }

        CANONICAL_CLASSIFICATION_WRITER (
            ch_reports_filtered,
            Channel.value(classifier),
            Channel.value("auto")
        )
        ch_canonical_classification = CANONICAL_CLASSIFICATION_WRITER.out.canonical
        ch_versions = ch_versions.mix(CANONICAL_CLASSIFICATION_WRITER.out.versions)
    }

    emit:
    canonical_classification = ch_canonical_classification // channel: [ val(meta), path(json) ] - Canonical classification JSON
    classified_reads      = ch_classified_reads           // channel: [ val(meta), path(fastq) ]
    unclassified_reads    = ch_unclassified_reads         // channel: [ val(meta), path(fastq) ]
    reads_assignment      = ch_reads_assignment           // channel: [ val(meta), path(txt) ]
    report                = ch_raw_reports                // channel: [ val(meta), path(txt) ] - Original format for compatibility
    batch_reports         = ch_batch_reports              // channel: [ val(meta), path(txt) ] - Per-batch reports (realtime; meta has batch_id)
    standardized_report   = ch_standardized_reports       // channel: [ val(meta), path(tsv/csv/etc) ] - Standardized format
    final_output          = ch_final_cumulative_output    // channel: [ val(meta), path(txt) ] - End-of-session cumulative output
    final_report          = ch_final_cumulative_report    // channel: [ val(meta), path(txt) ] - End-of-session cumulative report
    performance_metrics   = ch_performance_metrics        // channel: [ path(json) ] - Performance metrics (when optimizations enabled)
    classifier_used       = Channel.value(classifier)     // channel: val(classifier_name)
    versions              = ch_versions                   // channel: [ path(versions.yml) ]
}
