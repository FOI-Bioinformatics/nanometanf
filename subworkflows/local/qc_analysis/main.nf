/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: QC_ANALYSIS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Multi-tool quality control analysis with nanopore optimization

    Supported QC tools:
    - chopper: Nanopore-native Rust-based filtering (7x faster than NanoFilt)
    - fastp: General-purpose QC with rich reporting
    - filtlong: Nanopore-optimized length-weighted quality filtering

    Future QC tools (ready to implement):
    - nanoq: Nanopore quality assessment

    Features:
    - Tool-agnostic interface
    - Nanopore-specific optimizations
    - Consistent output standardization
    - Easy addition of new QC tools
----------------------------------------------------------------------------------------
*/

include { FASTP                   } from "${projectDir}/modules/nf-core/fastp/main"
include { FILTLONG                } from "${projectDir}/modules/nf-core/filtlong/main"
include { CHOPPER                 } from "${projectDir}/modules/nf-core/chopper/main"
include { PORECHOP_PORECHOP       } from "${projectDir}/modules/nf-core/porechop/porechop/main"
include { NANOPLOT                } from "${projectDir}/modules/nf-core/nanoplot/main"
include { FASTQC                  } from "${projectDir}/modules/nf-core/fastqc/main"
include { SEQKIT_STATS            } from "${projectDir}/modules/nf-core/seqkit/stats/main"
include { SEQKIT_MERGE_STATS      } from "${projectDir}/modules/local/seqkit_merge_stats/main"

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
    
    // Set QC tool and validate parameters
    def qc_tool = params.qc_tool ?: 'fastp'
    def enable_adapter_trimming = params.enable_adapter_trimming ?: false
    
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
    switch(qc_tool) {
        case 'fastp':
            //
            // MODULE: Run FASTP for general-purpose quality filtering and QC
            //
            FASTP (
                ch_adapter_trimmed,
                [],           // adapter_fasta
                false,        // discard_trimmed_pass  
                false,        // save_trimmed_fail
                false         // save_merged
            )
            ch_versions = ch_versions.mix(FASTP.out.versions)
            
            // Collect standardized outputs
            ch_qc_reads = FASTP.out.reads
            ch_qc_reports = FASTP.out.html
            ch_qc_logs = FASTP.out.log
            ch_qc_json = FASTP.out.json
            break
            
        case 'filtlong':
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
            ch_versions = ch_versions.mix(FILTLONG.out.versions)
            
            //
            // Enhanced reporting for FILTLONG: Add FastQC and SeqKit stats
            //
            
            // MODULE: Run FastQC on filtered reads for comprehensive HTML reporting
            FASTQC (
                FILTLONG.out.reads
            )
            ch_versions = ch_versions.mix(FASTQC.out.versions)
            ch_fastqc_html = FASTQC.out.html
            
            // MODULE: Run SeqKit stats for detailed sequence statistics  
            SEQKIT_STATS (
                FILTLONG.out.reads
            )
            ch_versions = ch_versions.mix(SEQKIT_STATS.out.versions)
            ch_seqkit_stats = SEQKIT_STATS.out.stats
            
            // Collect standardized outputs
            ch_qc_reads = FILTLONG.out.reads
            ch_qc_reports = ch_fastqc_html              // Use FastQC HTML reports for FILTLONG
            ch_qc_logs = FILTLONG.out.log
            ch_qc_json = ch_seqkit_stats                // Use SeqKit stats as JSON-like structured output
            break

        case 'chopper':
            //
            // MODULE: Run CHOPPER for nanopore-native quality filtering
            //
            // CHOPPER is Rust-based, 7x faster than NanoFilt, optimized for nanopore data
            CHOPPER (
                ch_adapter_trimmed,
                []  // No contamination filtering fasta
            )
            ch_versions = ch_versions.mix(CHOPPER.out.versions)

            //
            // Enhanced reporting for CHOPPER: Add FastQC and SeqKit stats
            //

            // MODULE: Run FastQC on filtered reads for comprehensive HTML reporting
            FASTQC (
                CHOPPER.out.fastq
            )
            ch_versions = ch_versions.mix(FASTQC.out.versions)
            ch_fastqc_html = FASTQC.out.html

            // MODULE: Run SeqKit stats for detailed sequence statistics
            SEQKIT_STATS (
                CHOPPER.out.fastq
            )
            ch_versions = ch_versions.mix(SEQKIT_STATS.out.versions)
            ch_seqkit_stats = SEQKIT_STATS.out.stats

            // Collect standardized outputs
            ch_qc_reads = CHOPPER.out.fastq
            ch_qc_reports = ch_fastqc_html              // Use FastQC HTML reports for CHOPPER
            ch_qc_logs = Channel.empty()                // CHOPPER has no log output
            ch_qc_json = ch_seqkit_stats                // Use SeqKit stats as JSON-like structured output
            break

        // Future QC tools to be added here:
        // case 'nanoq':
        //     NANOQ(ch_adapter_trimmed)
        //     break

        default:
            error "Unsupported QC tool: ${qc_tool}. Currently supported: fastp, filtlong, chopper"
    }

    //
    // OPTIONAL: Incremental QC statistics aggregation (PromethION optimization)
    //
    // For tools that use SEQKIT_STATS (chopper, filtlong), aggregate batch-level stats
    // into cumulative statistics when incremental mode is enabled
    //
    def enable_incremental = params.qc_enable_incremental ?: false
    def ch_final_seqkit_stats = ch_seqkit_stats

    if (enable_incremental && (qc_tool == 'chopper' || qc_tool == 'filtlong')) {
        log.info "Using incremental QC statistics aggregation for ${qc_tool}"

        // Group batch-level seqkit stats by sample ID
        def ch_grouped_batch_stats = ch_seqkit_stats.groupTuple(by: 0)

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

    def ch_nanoplot_input = ch_qc_reads
    def ch_nanoplot_html = Channel.empty()
    def ch_nanoplot_txt = Channel.empty()
    def ch_nanoplot_png = Channel.empty()

    if (!skip_nanoplot) {
        // Apply real-time optimizations
        if (is_realtime && skip_intermediate) {
            log.info "Real-time mode: NanoPlot will run every ${batch_interval} batches and on final batch"

            // Filter channel to only include samples that should run NanoPlot
            ch_nanoplot_input = ch_qc_reads.filter { meta, reads ->
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

        // Run NanoPlot on filtered samples
        NANOPLOT (
            ch_nanoplot_input
        )
        ch_versions = ch_versions.mix(NANOPLOT.out.versions)
        ch_nanoplot_html = NANOPLOT.out.html
        ch_nanoplot_txt = NANOPLOT.out.txt
        ch_nanoplot_png = NANOPLOT.out.png
    } else {
        log.info "NanoPlot is disabled (skip_nanoplot = true)"
    }

    emit:
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