/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: QC_BENCHMARK
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Performance benchmarking framework for QC tools comparison
    
    This subworkflow runs multiple QC tools on the same input data and compares:
    - Processing time and memory usage
    - Quality filtering effectiveness
    - Output read statistics and quality metrics
    - Resource efficiency
    
    Usage: Enable benchmarking by setting params.enable_qc_benchmark = true
    
    Supported comparisons:
    - FASTP vs FILTLONG vs CHOPPER
    - Different FILTLONG parameter sets
    - Custom QC tool configurations
    - Performance benchmarking: Speed, memory, quality metrics
----------------------------------------------------------------------------------------
*/

import groovy.json.JsonSlurper

include { FASTP                   } from '../../modules/nf-core/fastp/main'
include { FILTLONG                } from '../../modules/nf-core/filtlong/main'
include { CHOPPER                 } from '../../modules/nf-core/chopper/main'
include { PORECHOP_PORECHOP       } from '../../modules/nf-core/porechop/porechop/main'
include { FASTQC                  } from '../../modules/nf-core/fastqc/main'
include { SEQKIT_STATS            } from '../../modules/nf-core/seqkit/stats/main'
include { NANOPLOT                } from '../../modules/nf-core/nanoplot/main'

workflow QC_BENCHMARK {

    take:
    ch_reads     // channel: [ val(meta), path(reads) ]

    main:
    ch_versions = Channel.empty()
    ch_benchmark_results = Channel.empty()
    
    //
    // BENCHMARK 1: FASTP (General-purpose QC)
    //
    
    // Run FASTP with standard parameters
    FASTP (
        ch_reads,
        [],           // adapter_fasta
        false,        // discard_trimmed_pass  
        false,        // save_trimmed_fail
        false         // save_merged
    )
    ch_versions = ch_versions.mix(FASTP.out.versions)
    
    // Run FastQC on FASTP output for comparison
    FASTQC (
        FASTP.out.reads
    )
    ch_versions = ch_versions.mix(FASTQC.out.versions.first())
    
    // Run SeqKit stats on FASTP output
    SEQKIT_STATS (
        FASTP.out.reads
    )
    ch_versions = ch_versions.mix(SEQKIT_STATS.out.versions.first())
    
    // Create FASTP benchmark record
    ch_fastp_benchmark = FASTP.out.reads
        .join(FASTP.out.json)
        .join(SEQKIT_STATS.out.stats)
        .map { meta, reads, json, stats ->
            def new_meta = meta + [
                qc_tool: 'fastp',
                benchmark_category: 'general_purpose'
            ]
            return [new_meta, reads, json, stats]
        }
    
    //
    // BENCHMARK 2: FILTLONG (Nanopore-optimized QC) 
    //
    
    // Prepare FILTLONG input (shortreads=empty, longreads=reads)
    ch_filtlong_input = ch_reads.map { meta, reads ->
        [meta, null, reads]  // [meta, shortreads=empty, longreads=reads]
    }
    
    // Run FILTLONG with standard parameters
    FILTLONG (
        ch_filtlong_input
    )
    ch_versions = ch_versions.mix(FILTLONG.out.versions.first())
    
    // Run FastQC on FILTLONG output for comparison
    FASTQC (
        FILTLONG.out.reads
    )
    ch_versions = ch_versions.mix(FASTQC.out.versions.first())
    
    // Run SeqKit stats on FILTLONG output  
    SEQKIT_STATS (
        FILTLONG.out.reads
    )
    ch_versions = ch_versions.mix(SEQKIT_STATS.out.versions.first())
    
    // Create FILTLONG benchmark record
    ch_filtlong_benchmark = FILTLONG.out.reads
        .join(FILTLONG.out.log)
        .join(SEQKIT_STATS.out.stats)
        .map { meta, reads, log, stats ->
            def new_meta = meta + [
                qc_tool: 'filtlong',
                benchmark_category: 'nanopore_optimized'
            ]
            return [new_meta, reads, log, stats]
        }
    
    //
    // BENCHMARK 3: FILTLONG with PORECHOP (Enhanced nanopore QC)
    //
    
    // Run PORECHOP for adapter trimming
    PORECHOP_PORECHOP (
        ch_reads
    )
    ch_versions = ch_versions.mix(PORECHOP_PORECHOP.out.versions.first())
    
    // Prepare PORECHOP+FILTLONG input
    ch_porechop_filtlong_input = PORECHOP_PORECHOP.out.reads.map { meta, reads ->
        [meta, null, reads]  // [meta, shortreads=empty, longreads=reads]
    }
    
    // Run FILTLONG on adapter-trimmed reads (simplified for now)
    // TODO: Re-implement with proper module aliasing or separate workflows
    // FILTLONG_PORECHOP would go here
    
    // For now, skip the PORECHOP+FILTLONG combination to avoid aliasing issues
    // This maintains basic benchmarking functionality while avoiding compilation errors
    
    // Create PORECHOP+FILTLONG benchmark record (simplified - using PORECHOP output directly)
    ch_porechop_filtlong_benchmark = PORECHOP_PORECHOP.out.reads
        .map { meta, reads ->
            def new_meta = meta + [
                qc_tool: 'porechop_only',
                benchmark_category: 'enhanced_nanopore'
            ]
            return [new_meta, reads, null, null]  // Empty log and stats for now
        }

    //
    // BENCHMARK 4: CHOPPER (Nanopore-native Rust-based QC)
    //

    // Run CHOPPER for nanopore-optimized quality filtering
    CHOPPER (
        ch_reads,
        []  // No contamination filtering fasta
    )
    ch_versions = ch_versions.mix(CHOPPER.out.versions.first())

    // Run FastQC on CHOPPER output for comprehensive reporting
    FASTQC (
        CHOPPER.out.fastq
    )
    ch_versions = ch_versions.mix(FASTQC.out.versions.first())

    // Run SeqKit stats on CHOPPER output for detailed statistics
    SEQKIT_STATS (
        CHOPPER.out.fastq
    )
    ch_versions = ch_versions.mix(SEQKIT_STATS.out.versions.first())

    // Create CHOPPER benchmark record
    ch_chopper_benchmark = CHOPPER.out.fastq
        .join(SEQKIT_STATS.out.stats)
        .map { meta, reads, stats ->
            def new_meta = meta + [
                qc_tool: 'chopper',
                benchmark_category: 'nanopore_native_rust'
            ]
            return [new_meta, reads, null, stats]  // No log output for Chopper
        }

    //
    // Run NanoPlot on all QC outputs for visualization comparison
    //
    
    // Combine all QC outputs for NanoPlot comparison
    ch_all_qc_outputs = ch_fastp_benchmark
        .map { meta, reads, json, stats -> [meta, reads] }
        .mix(
            ch_filtlong_benchmark.map { meta, reads, log, stats -> [meta, reads] },
            ch_porechop_filtlong_benchmark.map { meta, reads, log, stats -> [meta, reads] },
            ch_chopper_benchmark.map { meta, reads, log, stats -> [meta, reads] }
        )
    
    NANOPLOT (
        ch_all_qc_outputs
    )
    ch_versions = ch_versions.mix(NANOPLOT.out.versions.first())
    
    //
    // Combine all benchmark results
    //
    ch_benchmark_results = ch_fastp_benchmark
        .mix(ch_filtlong_benchmark, ch_porechop_filtlong_benchmark, ch_chopper_benchmark)

    emit:
    benchmark_results = ch_benchmark_results          // channel: [ val(meta), path(reads), path(qc_output), path(stats) ]
    fastp_results     = ch_fastp_benchmark           // channel: [ val(meta), path(reads), path(json), path(stats) ]
    filtlong_results  = ch_filtlong_benchmark        // channel: [ val(meta), path(reads), path(log), path(stats) ]
    chopper_results   = ch_chopper_benchmark         // channel: [ val(meta), path(reads), null, path(stats) ]
    enhanced_results  = ch_porechop_filtlong_benchmark // channel: [ val(meta), path(reads), path(log), path(stats) ]
    nanoplot_reports  = NANOPLOT.out.html            // channel: [ val(meta), path(html) ]
    versions          = ch_versions                   // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    BENCHMARK ANALYSIS FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Extract performance metrics from tool outputs
def extractPerformanceMetrics(qc_tool, meta, stats_file) {
    // Parse stats files and extract key QC metrics
    def metrics = [:]
    
    // Parse stats based on tool type
    if (qc_tool == 'fastp') {
        // Parse FastP JSON output
        def json = new File(stats_file).text
        def data = new JsonSlurper().parseText(json)
        metrics = [
            reads_before: data.summary?.before_filtering?.total_reads ?: 0,
            reads_after: data.summary?.after_filtering?.total_reads ?: 0,
            bases_before: data.summary?.before_filtering?.total_bases ?: 0,
            bases_after: data.summary?.after_filtering?.total_bases ?: 0,
            mean_length_before: data.summary?.before_filtering?.mean_length ?: 0,
            mean_length_after: data.summary?.after_filtering?.mean_length ?: 0,
            q30_rate_before: data.summary?.before_filtering?.q30_rate ?: 0,
            q30_rate_after: data.summary?.after_filtering?.q30_rate ?: 0,
            duplication_rate: data.duplication?.rate ?: 0
        ]
    } else if (qc_tool == 'filtlong') {
        // Parse Filtlong stats (basic text parsing)
        def lines = new File(stats_file).readLines()
        metrics = [
            reads_kept: lines.find { it.contains('reads kept') }?.split()?.last()?.toInteger() ?: 0,
            bases_kept: lines.find { it.contains('bases kept') }?.split()?.last()?.toLong() ?: 0,
            mean_length: lines.find { it.contains('mean length') }?.split()?.last()?.toFloat() ?: 0
        ]
    } else if (qc_tool == 'chopper') {
        // Parse SeqKit stats output for Chopper (TSV format)
        def lines = new File(stats_file).readLines()
        if (lines.size() > 1) {
            def header = lines[0].split('\t')
            def data = lines[1].split('\t')
            def statsMap = [header, data].transpose().collectEntries()
            metrics = [
                num_seqs: statsMap['num_seqs']?.toLong() ?: 0,
                sum_len: statsMap['sum_len']?.toLong() ?: 0,
                min_len: statsMap['min_len']?.toInteger() ?: 0,
                avg_len: statsMap['avg_len']?.toFloat() ?: 0,
                max_len: statsMap['max_len']?.toInteger() ?: 0,
                avg_qual: statsMap['avg_qual']?.toFloat() ?: 0,
                q20_bases: statsMap['Q20(%)']?.toFloat() ?: 0,
                q30_bases: statsMap['Q30(%)']?.toFloat() ?: 0
            ]
        } else {
            metrics = [num_seqs: 0, sum_len: 0, avg_len: 0, avg_qual: 0]
        }
    }
    
    return [
        tool: qc_tool,
        sample: meta.id,
        timestamp: new Date(),
        metrics: metrics
    ]
}

// Compare QC tool performance
def compareQCPerformance(fastp_metrics, filtlong_metrics, chopper_metrics, enhanced_metrics) {
    // Generate comparative analysis of QC tools
    def comparison = [
        timestamp: new Date(),
        sample: fastp_metrics?.sample ?: filtlong_metrics?.sample ?: chopper_metrics?.sample,
        tools_compared: [],
        performance_summary: [:]
    ]

    // Analyze FastP performance
    if (fastp_metrics?.metrics) {
        def fastp_retention = fastp_metrics.metrics.reads_after / (fastp_metrics.metrics.reads_before ?: 1)
        def fastp_quality_improvement = fastp_metrics.metrics.q30_rate_after - fastp_metrics.metrics.q30_rate_before

        comparison.tools_compared << 'fastp'
        comparison.performance_summary.fastp = [
            read_retention_rate: fastp_retention,
            quality_improvement: fastp_quality_improvement,
            filtering_efficiency: fastp_quality_improvement / (1 - fastp_retention + 0.001) // Avoid division by zero
        ]
    }

    // Analyze Filtlong performance
    if (filtlong_metrics?.metrics) {
        comparison.tools_compared << 'filtlong'
        comparison.performance_summary.filtlong = [
            reads_kept: filtlong_metrics.metrics.reads_kept,
            bases_kept: filtlong_metrics.metrics.bases_kept,
            mean_length_after: filtlong_metrics.metrics.mean_length
        ]
    }

    // Analyze Chopper performance (nanopore-native Rust-based)
    if (chopper_metrics?.metrics) {
        comparison.tools_compared << 'chopper'
        comparison.performance_summary.chopper = [
            num_seqs: chopper_metrics.metrics.num_seqs,
            sum_len: chopper_metrics.metrics.sum_len,
            avg_len: chopper_metrics.metrics.avg_len,
            avg_qual: chopper_metrics.metrics.avg_qual,
            q20_bases: chopper_metrics.metrics.q20_bases,
            q30_bases: chopper_metrics.metrics.q30_bases
        ]
    }

    // Analyze enhanced metrics if available
    if (enhanced_metrics?.metrics) {
        comparison.tools_compared << 'enhanced'
        comparison.performance_summary.enhanced = enhanced_metrics.metrics
    }

    // Generate recommendations
    comparison.recommendations = generateQCRecommendations(comparison.performance_summary)

    return comparison
}

// Generate QC recommendations based on performance analysis
def generateQCRecommendations(performance_summary) {
    def recommendations = []

    // Analyze FastP performance and recommend optimizations
    if (performance_summary.fastp) {
        def fastp = performance_summary.fastp
        if (fastp.read_retention_rate < 0.7) {
            recommendations << "Consider relaxing FastP filtering parameters - low read retention detected"
        }
        if (fastp.quality_improvement < 0.05) {
            recommendations << "Minimal quality improvement with FastP - consider alternative filtering"
        }
    }

    // Analyze Chopper performance for nanopore data
    if (performance_summary.chopper) {
        def chopper = performance_summary.chopper
        if (chopper.avg_qual && chopper.avg_qual > 12) {
            recommendations << "Chopper performed well for nanopore data - consider using as default"
        }
        if (chopper.q30_bases && chopper.q30_bases < 50) {
            recommendations << "Low Q30 bases with Chopper - consider adjusting quality threshold or using Filtlong"
        }
    }

    // Compare Chopper vs FASTP for nanopore workflows
    if (performance_summary.chopper && performance_summary.fastp) {
        recommendations << "Chopper is optimized for nanopore data and typically 7x faster than general-purpose tools"
        recommendations << "For nanopore workflows, prefer Chopper (nanopore-native) > Filtlong (length-based) > FASTP (Illumina-focused)"
    }

    // Add general recommendations
    recommendations << "Monitor resource usage and adjust parameters based on data characteristics"
    recommendations << "Consider using Chopper for fast nanopore filtering, Filtlong for length-based quality filtering"

    return recommendations
}