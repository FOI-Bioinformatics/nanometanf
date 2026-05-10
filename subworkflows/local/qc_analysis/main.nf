/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: QC_ANALYSIS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Multi-tool quality control analysis with nanopore optimization

    Supported QC tools:
    - chopper: Nanopore-native Rust-based filtering (7x faster than NanoFilt)
    - fastp: General-purpose QC with rich reporting
    - filtlong: Nanopore-optimized length-weighted quality filtering

    Features:
    - Tool-agnostic interface
    - Nanopore-specific optimizations
    - Consistent output standardization
    - Easy addition of new QC tools
----------------------------------------------------------------------------------------
*/

include { FASTP                   } from '../../../modules/nf-core/fastp/main'
include { FASTP_STREAMING         } from '../../../modules/local/fastp_streaming/main'
include { FILTLONG                } from '../../../modules/nf-core/filtlong/main'
include { CHOPPER                 } from '../../../modules/nf-core/chopper/main'
include { PORECHOP_PORECHOP       } from '../../../modules/nf-core/porechop/porechop/main'
include { NANOPLOT                } from '../../../modules/nf-core/nanoplot/main'
include { FASTQC                  } from '../../../modules/nf-core/fastqc/main'
include { SEQKIT_STATS            } from '../../../modules/nf-core/seqkit/stats/main'
include { SEQKIT_MERGE_STATS      } from '../../../modules/local/seqkit_merge_stats/main'
include { CANONICAL_QC_WRITER    } from '../../../modules/local/canonical_qc_writer/main'

workflow QC_ANALYSIS {

    take:
    ch_reads     // channel: [ val(meta), path(reads) ]

    main:
    ch_versions = Channel.empty()
    ch_qc_reads = Channel.empty()
    ch_qc_reports = Channel.empty()
    ch_qc_logs = Channel.empty()
    ch_qc_json = Channel.empty()
    ch_fastqc_html = Channel.empty()
    ch_seqkit_stats = Channel.empty()

    //
    // INPUT NORMALISATION: accept plain Lists alongside Channels.
    //
    // nf-test cases pass three shapes for a workflow input:
    //   - []                            -> no samples
    //   - [meta, reads]                 -> single sample tuple
    //   - [[meta, reads], [meta, ...]]  -> list of sample tuples
    // Under Nextflow 25.10 a downstream `.map { meta, reads -> ... }` call
    // on a literal ArrayList raises "Missing process or function map(...)".
    // Detect the single-tuple case by looking at the first element: a Map
    // indicates a meta dict, so the outer list IS the tuple; otherwise the
    // outer list is a collection of tuples and is best dispatched through
    // Channel.fromList. This mirrors the guard already in
    // TAXONOMIC_CLASSIFICATION (commit 72a5702) and keeps the production
    // wiring untouched, since real callers always pass a Channel.
    //
    if (ch_reads instanceof List) {
        if (ch_reads.isEmpty()) {
            ch_reads = Channel.empty()
        } else if (ch_reads[0] instanceof Map) {
            ch_reads = Channel.of(ch_reads)
        } else {
            ch_reads = Channel.fromList(ch_reads)
        }
    }

    // Set QC tool and validate parameters
    def qc_tool = (params.qc_tool ?: 'chopper').toLowerCase()
    def enable_adapter_trimming = params.enable_adapter_trimming ?: false
    def run_fastqc = !(params.realtime_mode && params.skip_fastqc_realtime)

    //
    // OPTIONAL: Adapter trimming with PORECHOP (nanopore-specific)
    //
    if (enable_adapter_trimming && qc_tool == 'filtlong') {
        PORECHOP_PORECHOP (
            ch_reads
        )
        ch_versions = ch_versions.mix(PORECHOP_PORECHOP.out.versions)
        ch_adapter_trimmed = PORECHOP_PORECHOP.out.reads
    } else {
        ch_adapter_trimmed = ch_reads
    }

    //
    // BRANCH: Route to appropriate QC tool
    //
    if (qc_tool == 'fastp') {
            //
            // MODULE: Run FASTP for general-purpose quality filtering and QC
            //
            // In realtime (streaming) mode, reads arrive as multiple files per batch cycle.
            // FASTP_STREAMING handles multi-file concatenation before calling fastp.
            // In standard batch mode, use the unmodified upstream nf-core/fastp module.
            ch_fastp_input = ch_adapter_trimmed.map { meta, reads ->
                [ meta, reads, [] ]  // adapter_fasta: empty list
            }

            def is_streaming = params.realtime_mode ?: false

            if (is_streaming) {
                FASTP_STREAMING (
                    ch_fastp_input,
                    false,        // discard_trimmed_pass
                    false,        // save_trimmed_fail
                    false         // save_merged
                )
                // FASTP_STREAMING is a local module that still emits versions.yml
                ch_versions = ch_versions.mix(FASTP_STREAMING.out.versions.ifEmpty([]))
                ch_qc_reads = FASTP_STREAMING.out.reads.ifEmpty([])
                ch_qc_reports = FASTP_STREAMING.out.html.ifEmpty([])
                ch_qc_logs = FASTP_STREAMING.out.log.ifEmpty([])
                ch_qc_json = FASTP_STREAMING.out.json.ifEmpty([])
            } else {
                FASTP (
                    ch_fastp_input,
                    false,        // discard_trimmed_pass
                    false,        // save_trimmed_fail
                    false         // save_merged
                )
                // FASTP uses topic: versions pattern - no .out.versions channel.
                // Versions are aggregated via Channel.topic('versions') in workflows/nanometanf.nf
                ch_qc_reads = FASTP.out.reads.ifEmpty([])
                ch_qc_reports = FASTP.out.html.ifEmpty([])
                ch_qc_logs = FASTP.out.log.ifEmpty([])
                ch_qc_json = FASTP.out.json.ifEmpty([])
            }
    } else if (qc_tool == 'filtlong') {
            //
            // MODULE: Run FILTLONG for nanopore-optimized quality filtering
            //
            // FILTLONG expects shortreads and longreads, for nanopore-only we pass empty for shortreads
            ch_filtlong_input = ch_adapter_trimmed.map { meta, reads ->
                [meta, [], reads]  // [meta, shortreads=empty, longreads=reads]
            }

            FILTLONG (
                ch_filtlong_input
            )
            ch_versions = ch_versions.mix(FILTLONG.out.versions.ifEmpty([]))

            //
            // Enhanced reporting for FILTLONG: Add FastQC and SeqKit stats
            //

            // MODULE: Run FastQC on filtered reads for comprehensive HTML reporting
            if (run_fastqc) {
                FASTQC (
                    FILTLONG.out.reads
                )
                // FASTQC uses topic: versions pattern - no .out.versions channel
                ch_fastqc_html = FASTQC.out.html.ifEmpty([])
            }

            // MODULE: Run SeqKit stats for detailed sequence statistics
            SEQKIT_STATS (
                FILTLONG.out.reads
            )
            // SEQKIT_STATS uses topic: versions pattern - no .out.versions channel
            ch_seqkit_stats = SEQKIT_STATS.out.stats.ifEmpty([])

            // Collect standardized outputs
            ch_qc_reads = FILTLONG.out.reads.ifEmpty([])
            ch_qc_reports = ch_fastqc_html              // Use FastQC HTML reports for FILTLONG
            ch_qc_logs = FILTLONG.out.log.ifEmpty([])
            ch_qc_json = ch_seqkit_stats                // Use SeqKit stats as JSON-like structured output
    } else if (qc_tool == 'chopper') {
            //
            // MODULE: Run CHOPPER for nanopore-native quality filtering
            //
            // CHOPPER is Rust-based, 7x faster than NanoFilt, optimized for nanopore data
            CHOPPER (
                ch_adapter_trimmed,
                []  // No contamination filtering fasta
            )
            // CHOPPER uses topic: versions pattern - no .out.versions channel.
            // Versions are aggregated via Channel.topic('versions') in workflows/nanometanf.nf

            //
            // Enhanced reporting for CHOPPER: Add FastQC and SeqKit stats
            //

            // MODULE: Run FastQC on filtered reads for comprehensive HTML reporting
            if (run_fastqc) {
                FASTQC (
                    CHOPPER.out.fastq
                )
                // FASTQC uses topic: versions pattern - no .out.versions channel
                ch_fastqc_html = FASTQC.out.html.ifEmpty([])
            }

            // MODULE: Run SeqKit stats for detailed sequence statistics
            SEQKIT_STATS (
                CHOPPER.out.fastq
            )
            // SEQKIT_STATS uses topic: versions pattern - no .out.versions channel
            ch_seqkit_stats = SEQKIT_STATS.out.stats.ifEmpty([])

            // Collect standardized outputs
            ch_qc_reads = CHOPPER.out.fastq.ifEmpty([])
            ch_qc_reports = ch_fastqc_html              // Use FastQC HTML reports for CHOPPER
            ch_qc_logs = Channel.empty()                // CHOPPER has no log output
            ch_qc_json = ch_seqkit_stats                // Use SeqKit stats as JSON-like structured output
    } else {
        error "Unsupported QC tool: ${qc_tool}. Currently supported: fastp, filtlong, chopper"
    }

    //
    // OPTIONAL: Incremental QC statistics aggregation (PromethION optimization)
    //
    // For tools that use SEQKIT_STATS (chopper, filtlong), aggregate batch-level
    // stats into cumulative statistics when incremental mode is enabled.
    //
    // The realtime path closes the watchPath channel via the
    // realtime_timeout_minutes idle timeout (see F12), at which point
    // groupTuple(remainder: true) flushes the partial group and
    // SEQKIT_MERGE_STATS fires once per sample. Auto-promote
    // qc_enable_incremental when realtime_mode + kraken2_enable_incremental are
    // both on -- without aggregation the per-batch SEQKIT_STATS overwrite
    // each other on publish (default tokenizer publishDir, fixed filename
    // ${meta.id}.tsv) and the published seqkit/{sample}.tsv ends up holding
    // only the last batch's read count. This mirrors the cumulative kraken2
    // report contract that the dashboard already relies on.
    //
    def is_realtime_mode = params.realtime_mode ?: false
    def auto_qc_incremental = is_realtime_mode && (params.kraken2_enable_incremental ?: false)
    def enable_incremental = (params.qc_enable_incremental ?: false) || auto_qc_incremental
    if (auto_qc_incremental && !(params.qc_enable_incremental ?: false)) {
        log.info "Realtime mode with kraken2_enable_incremental: auto-enabling QC stats aggregation"
    }
    def ch_final_seqkit_stats = ch_seqkit_stats

    if (enable_incremental && (qc_tool == 'chopper' || qc_tool == 'filtlong')) {
        log.info "Using incremental QC statistics aggregation for ${qc_tool}"

        // Group batch-level seqkit stats by sample id. The full meta map
        // carries a per-batch batch_time stamp set in REALTIME_MONITORING
        // (line 285), so two batches for the same sample compare unequal
        // and groupTuple(by: 0) on the raw meta would never collapse them.
        // Re-key by meta.id, then rebuild a stable sample-level meta from
        // the first emitted item (id, single_end, optional barcode) so
        // SEQKIT_MERGE_STATS receives the canonical per-sample tuple it
        // expects. remainder: true flushes the partial group when the
        // upstream watchPath channel finally closes.
        def ch_grouped_batch_stats = ch_seqkit_stats
            .map { meta, stats -> tuple(meta.id, meta, stats) }
            .groupTuple(by: 0, remainder: true)
            .map { sample_id, metas, stats_list ->
                def base = metas[0] ?: [:]
                def cumulative_meta = [
                    id: sample_id,
                    single_end: base.single_end != null ? base.single_end : true
                ]
                if (base.barcode) {
                    cumulative_meta.barcode = base.barcode
                }
                tuple(cumulative_meta, stats_list)
            }

        // Merge batch statistics into cumulative statistics
        SEQKIT_MERGE_STATS(
            ch_grouped_batch_stats
        )
        ch_versions = ch_versions.mix(SEQKIT_MERGE_STATS.out.versions)

        // Use cumulative stats instead of batch stats
        ch_final_seqkit_stats = SEQKIT_MERGE_STATS.out.cumulative_stats
    }

    //
    // MODULE: Run NanoPlot for nanopore-specific QC visualization (conditional in real-time mode)
    //
    // NanoPlot optimization for real-time processing:
    // - Skip intermediate batches if nanoplot_realtime_skip_intermediate = true
    // - Run every N batches if nanoplot_batch_interval is set
    // - Always run on final batch (when is_final_batch = true in meta)
    //
    def skip_nanoplot = params.skip_nanoplot ?: false
    def is_realtime = params.realtime_mode ?: false
    def skip_intermediate = params.nanoplot_realtime_skip_intermediate ?: true
    def batch_interval = params.nanoplot_batch_interval ?: 10

    // The QC tool branches above attach `.ifEmpty([])` to ch_qc_reads so that
    // top-level `assert workflow.out.reads` checks see an emission even when
    // upstream produced none. That synthetic `[]` placeholder is shaped like
    // a single ArrayList rather than a [meta, reads] tuple, and the
    // downstream NanoPlot filters destructure their input into (meta, reads)
    // -- on an empty list this raises "Invalid method invocation `call` with
    // arguments: [] (java.util.ArrayList)" and aborts the run. Drop the
    // placeholder before any tuple-destructuring filter sees it; real tuples
    // pass through unchanged. Mirrors the guard already in place for the
    // canonical writer below (line 377).
    def ch_qc_reads_tuples = ch_qc_reads.filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map }
    def ch_nanoplot_input = ch_qc_reads_tuples
    def ch_nanoplot_html = Channel.empty()
    def ch_nanoplot_txt = Channel.empty()
    def ch_nanoplot_png = Channel.empty()

    if (!skip_nanoplot) {
        // Apply real-time optimizations
        if (is_realtime && skip_intermediate) {
            log.info "Real-time mode: NanoPlot will run every ${batch_interval} batches and on final batch"

            // Filter channel to only include samples that should run NanoPlot
            ch_nanoplot_input = ch_qc_reads_tuples.filter { meta, reads ->
                // Always run on final batch
                if (meta.is_final_batch == true) {
                    log.info "Running NanoPlot for ${meta.id} (final batch)"
                    return true
                }

                // Run every N batches based on batch_id
                if (meta.batch_id != null) {
                    def batch_num = meta.batch_id instanceof String ?
                        Integer.parseInt(meta.batch_id.replaceAll(/\D/, '')) : meta.batch_id

                    if (batch_num % batch_interval == 0) {
                        log.info "Running NanoPlot for ${meta.id} (batch ${batch_num} - interval milestone)"
                        return true
                    }
                }

                // Skip this batch
                log.debug "Skipping NanoPlot for ${meta.id} (intermediate batch)"
                return false
            }
        }

        // Skip NanoPlot for samples whose post-QC FASTQ has no reads.
        //
        // NanoPlot exits non-zero ("Fatal: No reads found in input") on a
        // zero-read FASTQ, which would otherwise abort the whole pipeline.
        // An earlier guard relied on `size() > 0`, but Chopper and fastp
        // can legitimately emit a gzipped FASTQ that contains only the
        // gzip framing (typically under 50 bytes) when every input read
        // fails the quality or length thresholds. Such files pass the
        // size > 0 check but still cause NanoPlot to fail.
        //
        // The 50-byte threshold matches the equivalent guard at the
        // entry of TAXONOMIC_CLASSIFICATION (commit e8b8dfe). It sits
        // comfortably above an empty gzip stream and below a single
        // minimal FASTQ record, so it skips empty samples without
        // dropping any sample that contains real reads. Skipped samples
        // continue through the rest of the pipeline; only NanoPlot is
        // bypassed for them.
        def empty_fastq_threshold = 50L
        def ch_nanoplot_nonempty = ch_nanoplot_input.filter { meta, reads ->
            def reads_list = reads instanceof List ? reads : [reads]
            def has_any = reads_list.any { f ->
                f != null && f.exists() && f.size() >= empty_fastq_threshold
            }
            if (!has_any) {
                log.warn "Skipping NanoPlot for sample '${meta.id}' - post-QC FASTQ contains no reads (size below ${empty_fastq_threshold} bytes)"
            }
            return has_any
        }

        // Run NanoPlot on filtered samples
        NANOPLOT (
            ch_nanoplot_nonempty
        )
        ch_versions = ch_versions.mix(NANOPLOT.out.versions)
        ch_nanoplot_html = NANOPLOT.out.html
        ch_nanoplot_txt = NANOPLOT.out.txt
        ch_nanoplot_png = NANOPLOT.out.png
    } else {
        log.info "NanoPlot is disabled (skip_nanoplot = true)"
    }

    //
    // MODULE: Convert QC statistics to canonical JSON format
    // Produces tool-agnostic output for frontend consumption
    //
    ch_canonical_qc = Channel.empty()
    if (params.write_canonical != false) {
        // Use fastp JSON when available, otherwise seqkit stats
        def ch_qc_input = qc_tool == 'fastp' ? ch_qc_json : ch_final_seqkit_stats

        // Guard against empty input from failed upstream QC processes
        def ch_qc_filtered = ch_qc_input.filter { it instanceof List && it.size() >= 2 && it[1] != null }

        CANONICAL_QC_WRITER (
            ch_qc_filtered,
            Channel.value(qc_tool),
            Channel.value("auto")
        )
        ch_canonical_qc = CANONICAL_QC_WRITER.out.canonical
        ch_versions = ch_versions.mix(CANONICAL_QC_WRITER.out.versions)
    }

    emit:
    canonical_qc = ch_canonical_qc        // channel: [ val(meta), path(json) ] - Canonical QC JSON
    reads        = ch_qc_reads            // channel: [ val(meta), path(reads) ] - QC'd reads
    qc_reports   = ch_qc_reports          // channel: [ val(meta), path(html) ] - QC HTML reports (tool-specific)
    qc_logs      = ch_qc_logs             // channel: [ val(meta), path(log) ] - QC log files
    qc_json      = ch_qc_json             // channel: [ val(meta), path(json) ] - QC JSON reports (if available)
    nanoplot     = ch_nanoplot_html       // channel: [ val(meta), path(html) ] - NanoPlot visualization (conditional in real-time mode)
    nanoplot_txt = ch_nanoplot_txt        // channel: [ val(meta), path(txt) ] - NanoPlot summary stats (conditional, for MultiQC)
    nanoplot_png = ch_nanoplot_png        // channel: [ val(meta), path(png) ] - NanoPlot plots (conditional)
    qc_tool_used = Channel.value(qc_tool) // channel: val(qc_tool_name) - Tool identification
    versions     = ch_versions            // channel: [ path(versions.yml) ]

    // Enhanced reporting outputs
    fastqc_html  = ch_fastqc_html         // channel: [ val(meta), path(html) ] - FastQC HTML reports (FILTLONG/CHOPPER enhancement)
    seqkit_stats = ch_final_seqkit_stats  // channel: [ val(meta), path(txt) ] - SeqKit detailed statistics (cumulative if incremental mode)

    // Legacy outputs for backward compatibility
    fastp_json   = qc_tool == 'fastp' ? ch_qc_json : Channel.empty()     // channel: [ val(meta), path(json) ]
    fastp_html   = qc_tool == 'fastp' ? ch_qc_reports : Channel.empty()  // channel: [ val(meta), path(html) ]
    fastp_log    = qc_tool == 'fastp' ? ch_qc_logs : Channel.empty()     // channel: [ val(meta), path(log) ]
}
