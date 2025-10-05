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

include { FASTP                   } from '../../modules/nf-core/fastp/main'
include { FILTLONG                } from '../../modules/nf-core/filtlong/main'
include { CHOPPER                 } from '../../modules/nf-core/chopper/main'
include { PORECHOP_PORECHOP       } from '../../modules/nf-core/porechop/porechop/main'
include { NANOPLOT                } from '../../modules/nf-core/nanoplot/main'
include { FASTQC                  } from '../../modules/nf-core/fastqc/main'
include { SEQKIT_STATS            } from '../../modules/nf-core/seqkit/stats/main'

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
    // MODULE: Run NanoPlot for nanopore-specific QC visualization (always run)
    //
    NANOPLOT (
        ch_qc_reads.ifEmpty(ch_reads)
    )
    ch_versions = ch_versions.mix(NANOPLOT.out.versions)

    emit:
    reads        = ch_qc_reads            // channel: [ val(meta), path(reads) ] - QC'd reads
    qc_reports   = ch_qc_reports          // channel: [ val(meta), path(html) ] - QC HTML reports (tool-specific)
    qc_logs      = ch_qc_logs             // channel: [ val(meta), path(log) ] - QC log files
    qc_json      = ch_qc_json             // channel: [ val(meta), path(json) ] - QC JSON reports (if available)
    nanoplot     = NANOPLOT.out.html      // channel: [ val(meta), path(html) ] - NanoPlot visualization
    qc_tool_used = Channel.value(qc_tool) // channel: val(qc_tool_name) - Tool identification
    versions     = ch_versions            // channel: [ path(versions.yml) ]
    
    // Enhanced reporting outputs
    fastqc_html  = ch_fastqc_html         // channel: [ val(meta), path(html) ] - FastQC HTML reports (FILTLONG enhancement)
    seqkit_stats = ch_seqkit_stats        // channel: [ val(meta), path(txt) ] - SeqKit detailed statistics
    
    // Legacy outputs for backward compatibility
    fastp_json   = qc_tool == 'fastp' ? ch_qc_json : Channel.empty()     // channel: [ val(meta), path(json) ]
    fastp_html   = qc_tool == 'fastp' ? ch_qc_reports : Channel.empty()  // channel: [ val(meta), path(html) ]
    fastp_log    = qc_tool == 'fastp' ? ch_qc_logs : Channel.empty()     // channel: [ val(meta), path(log) ]
}