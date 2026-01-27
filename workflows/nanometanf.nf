/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { MULTIQC                    } from '../modules/nf-core/multiqc/main'
include { UNTAR                      } from '../modules/nf-core/untar/main'
include { paramsSummaryMap           } from 'plugin/nf-schema'
include { paramsSummaryMultiqc       } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML     } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText     } from '../subworkflows/local/utils_nfcore_nanometanf_pipeline'

// Import local subworkflows
include { REALTIME_MONITORING        } from '../subworkflows/local/realtime_monitoring'
include { REALTIME_POD5_MONITORING   } from '../subworkflows/local/realtime_pod5_monitoring'
include { DORADO_BASECALLING         } from '../subworkflows/local/dorado_basecalling'
include { BARCODE_DISCOVERY          } from '../subworkflows/local/barcode_discovery'
include { POD5_BARCODE_DISCOVERY    } from '../subworkflows/local/pod5_barcode_discovery'
include { DEMULTIPLEXING             } from '../subworkflows/local/demultiplexing'
include { QC_ANALYSIS                } from '../subworkflows/local/qc_analysis'
include { ASSEMBLY                   } from '../subworkflows/local/assembly'
include { TAXONOMIC_CLASSIFICATION   } from '../subworkflows/local/taxonomic_classification'
include { VALIDATION                 } from '../subworkflows/local/validation'
include { DYNAMIC_RESOURCE_ALLOCATION } from '../subworkflows/local/dynamic_resource_allocation'
include { NANOPLOT_COMPARE           } from '../modules/local/nanoplot_compare/main'

// Experimental feature imports (v1.5 planned)
include { QC_BENCHMARK               } from '../subworkflows/local/qc_benchmark'
include { REALTIME_STATISTICS        } from '../subworkflows/local/realtime_statistics'
include { KRONA_KRAKEN2              } from '../modules/local/krona_kraken2/main'
include { MULTIQC_NANOPORE_STATS     } from '../modules/local/multiqc_nanopore_stats/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    HELPER FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Detect POD5 directory structure: 'flat' or 'barcode_subdirs'
// - flat: POD5 files directly in the directory (e.g., pod5_dir/*.pod5)
// - barcode_subdirs: POD5 files in barcode subdirectories (e.g., pod5_dir/barcode01/*.pod5)
//
def detectPod5Structure(pod5_dir) {
    def dir = file(pod5_dir)
    def hasBarcodeDirs = false

    // Check for barcode*/ subdirectories containing POD5 files
    dir.eachFile { f ->
        if (f.isDirectory() && f.name.startsWith('barcode')) {
            def hasPod5 = false
            f.eachFileMatch(~/.+\.pod5$/) { hasPod5 = true }
            if (hasPod5) {
                hasBarcodeDirs = true
            }
        }
    }

    return hasBarcodeDirs ? 'barcode_subdirs' : 'flat'
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow NANOMETANF {

    take:
    ch_samplesheet // channel: samplesheet read in from --input
    
    main:
    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    //
    // BACKWARD COMPATIBILITY: Handle deprecated parameters
    // Map old parameter names to new ones with deprecation warnings
    //
    def run_validation_effective = params.run_validation
    if (params.blast_validation && !params.run_validation) {
        log.warn "DEPRECATED: Parameter 'blast_validation' is deprecated. Please use 'run_validation' instead."
        log.warn "  Enabling validation due to blast_validation=true"
        run_validation_effective = true
    }
    if (params.blast_db && !params.pathogen_genomes) {
        log.warn "DEPRECATED: Parameter 'blast_db' is deprecated. Please use 'pathogen_genomes' instead."
    }
    if (params.validation_taxa && !params.taxids_to_validate) {
        log.warn "DEPRECATED: Parameter 'validation_taxa' is deprecated. Please use 'taxids_to_validate' instead."
    }

    //
    // WORKFLOW ROUTING: Determine if this is POD5 or FASTQ workflow
    //
    def is_pod5_workflow = (params.pod5_input_dir && params.use_dorado) || 
                          (params.realtime_mode && params.file_pattern?.contains('.pod5'))
    def is_barcode_discovery = params.barcode_input_dir
    
    if (is_pod5_workflow) {
        //
        // POD5 WORKFLOW PATH
        //
        if (params.realtime_mode) {
            // Real-time POD5 monitoring with Dorado basecalling
            REALTIME_POD5_MONITORING (
                params.pod5_input_dir,
                "*.pod5",  // POD5 files in watch_dir (not subdirectories)
                params.batch_size ?: 10,
                params.batch_interval ?: "5min",
                params.dorado_model
            )
            ch_processed_samples = REALTIME_POD5_MONITORING.out.samples
            ch_versions = ch_versions.mix(REALTIME_POD5_MONITORING.out.versions.ifEmpty([]))

            // Real-time statistics generation (optional)
            if (params.enable_realtime_stats) {
                def stats_config = [
                    enable_quality_indicators: true,
                    enable_source_analysis: true,
                    enable_timing_analysis: true,
                    quality_threshold_warnings: true,
                    stats_interval: params.realtime_report_interval ?: 30000,
                    report_format: 'html,json'
                ]

                REALTIME_STATISTICS (
                    REALTIME_POD5_MONITORING.out.batches,
                    stats_config
                )
                ch_versions = ch_versions.mix(REALTIME_STATISTICS.out.versions)
                ch_realtime_stats = REALTIME_STATISTICS.out.realtime_reports
            } else {
                ch_realtime_stats = Channel.empty()
            }

        } else {
            // Static POD5 basecalling
            if (!params.pod5_input_dir) {
                error "POD5 input directory is required when use_dorado is true and not in realtime mode"
            }

            // Auto-detect POD5 directory structure
            def pod5_structure = detectPod5Structure(params.pod5_input_dir)
            log.info "POD5 directory structure detected: ${pod5_structure}"

            if (pod5_structure == 'barcode_subdirs') {
                //
                // PRE-DEMULTIPLEXED POD5: barcode subdirectories with POD5 files
                // Each barcode is processed as a separate sample, demultiplexing is skipped
                //
                log.info "Processing pre-demultiplexed POD5 barcode directories"

                POD5_BARCODE_DISCOVERY (
                    params.pod5_input_dir
                )

                // Run basecalling for each barcode sample
                DORADO_BASECALLING (
                    POD5_BARCODE_DISCOVERY.out.samples,
                    params.dorado_model
                )

                // Skip demultiplexing - samples are already per-barcode
                ch_processed_samples = DORADO_BASECALLING.out.fastq
                ch_versions = ch_versions.mix(DORADO_BASECALLING.out.versions)
                ch_versions = ch_versions.mix(POD5_BARCODE_DISCOVERY.out.versions)

            } else {
                //
                // FLAT POD5: all POD5 files in a single directory
                // Process as single sample, optionally demultiplex after basecalling
                //
                log.info "Processing flat POD5 directory"

                ch_pod5_files = Channel.fromPath("${params.pod5_input_dir}/*.pod5", checkIfExists: true)
                    .collect()
                    .map { files ->
                        def meta = [
                            id: 'pod5_sample',
                            single_end: true,
                            barcode_kit: params.barcode_kit ?: null
                        ]
                        [ meta, files ]
                    }

                DORADO_BASECALLING (
                    ch_pod5_files,
                    params.dorado_model
                )
                ch_processed_samples = DORADO_BASECALLING.out.fastq
                ch_versions = ch_versions.mix(DORADO_BASECALLING.out.versions)
            }
        }
        
    } else if (is_barcode_discovery) {
        //
        // PRE-DEMULTIPLEXED BARCODE DIRECTORIES
        //
        BARCODE_DISCOVERY (
            params.barcode_input_dir
        )
        ch_processed_samples = BARCODE_DISCOVERY.out.samples
        ch_versions = ch_versions.mix(BARCODE_DISCOVERY.out.versions)
        
    } else {
        //
        // FASTQ WORKFLOW PATH
        //
        if (params.realtime_mode) {
            // Real-time FASTQ monitoring
            REALTIME_MONITORING (
                params.nanopore_output_dir,
                params.file_pattern ?: "**/*.fastq{,.gz}",
                params.batch_size ?: 10,
                params.batch_interval ?: "5min"
            )
            ch_processed_samples = REALTIME_MONITORING.out.samples

            // Real-time statistics generation (optional)
            if (params.enable_realtime_stats) {
                def stats_config = [
                    enable_quality_indicators: true,
                    enable_source_analysis: true,
                    enable_timing_analysis: true,
                    quality_threshold_warnings: true,
                    stats_interval: params.realtime_report_interval ?: 30000,
                    report_format: 'html,json'
                ]

                REALTIME_STATISTICS (
                    REALTIME_MONITORING.out.batches,
                    stats_config
                )
                ch_versions = ch_versions.mix(REALTIME_STATISTICS.out.versions)
                ch_realtime_stats = REALTIME_STATISTICS.out.realtime_reports
            } else {
                ch_realtime_stats = Channel.empty()
            }
        } else {
            // Standard samplesheet input - detect and handle POD5 files
            ch_samplesheet
                .branch { meta, reads ->
                    // Extract first file if reads is a list (from samplesheet parser)
                    def fileToCheck = reads instanceof List ? reads[0] : reads
                    // Get filename
                    def fileName = fileToCheck instanceof java.nio.file.Path ? fileToCheck.getName() : fileToCheck.toString()
                    // Check if it's a POD5 file
                    pod5: fileName.endsWith('.pod5')
                        return [meta, reads]
                    fastq: true
                        return [meta, reads]
                }
                .set { ch_branched_input }

            // If POD5 files detected and Dorado enabled, basecall them
            if (params.use_dorado) {
                log.info "Checking for POD5 files in samplesheet for Dorado basecalling..."

                DORADO_BASECALLING (
                    ch_branched_input.pod5,
                    params.dorado_model
                )
                ch_basecalled_pod5 = DORADO_BASECALLING.out.fastq
                ch_versions = ch_versions.mix(DORADO_BASECALLING.out.versions)

                // Combine basecalled POD5 samples with FASTQ samples
                ch_processed_samples = ch_branched_input.fastq.mix(ch_basecalled_pod5)
            } else {
                // No basecalling - use samplesheet as-is
                // POD5 files without use_dorado will fail downstream (expected)
                ch_processed_samples = ch_samplesheet
            }
        }
    }
    
    //
    // SUBWORKFLOW: Dynamic resource allocation for optimal performance
    //
    if (params.enable_dynamic_resources) {
        log.info "=== Enabling Dynamic Resource Allocation ==="
        
        // Prepare resource configuration
        def resource_config = [
            'optimization_profile': params.optimization_profile ?: 'auto',
            'safety_factor': params.resource_safety_factor ?: 0.8,
            'priority_samples': params.priority_samples ?: [],
            'max_parallel_jobs': params.max_parallel_jobs ?: 4,
            'enable_gpu_optimization': params.enable_gpu_optimization ?: true,
            'realtime_mode': params.realtime_mode ?: false
        ]
        
        // System configuration
        def system_config = [
            'monitoring_interval': params.resource_monitoring_interval ?: 30,
            'enable_performance_logging': params.enable_performance_logging ?: true
        ]
        
        // Create input for resource allocation - combine samples with tool context
        ch_resource_inputs = ch_processed_samples
            .map { meta, files ->
                def tool_context = [
                    'tool_name': 'preprocessing',  // Will be updated per process
                    'workflow_stage': 'initial_processing'
                ]
                [ meta, files, tool_context ]
            }
        
        DYNAMIC_RESOURCE_ALLOCATION (
            ch_resource_inputs,
            resource_config,
            system_config
        )
        ch_versions = ch_versions.mix(DYNAMIC_RESOURCE_ALLOCATION.out.versions)

        // Extract resource configurations for later use
        ch_resource_configs = DYNAMIC_RESOURCE_ALLOCATION.out.resource_configs
        ch_optimal_allocations = DYNAMIC_RESOURCE_ALLOCATION.out.optimal_allocations
        
        log.info "Dynamic resource allocation configured successfully"
    } else {
        ch_resource_configs = Channel.empty()
        ch_optimal_allocations = Channel.empty()
    }
    
    //
    // SUBWORKFLOW: Demultiplexing (handle multiplexed samples)
    //
    DEMULTIPLEXING (
        ch_processed_samples
    )
    ch_versions = ch_versions.mix(DEMULTIPLEXING.out.versions)
    
    //
    // SUBWORKFLOW: Quality control analysis
    //
    if (!params.skip_fastp || !params.skip_nanoplot) {
        QC_ANALYSIS (
            DEMULTIPLEXING.out.samples
        )
        ch_versions = ch_versions.mix(QC_ANALYSIS.out.versions)

        // Collect QC outputs for MultiQC (tool-agnostic)
        ch_multiqc_files = ch_multiqc_files.mix(QC_ANALYSIS.out.qc_json.collect{it[1]})

        // Add NanoPlot summary statistics to MultiQC (NanoStats.txt)
        if (!params.skip_nanoplot) {
            ch_multiqc_files = ch_multiqc_files.mix(QC_ANALYSIS.out.nanoplot_txt.collect{it[1]})
        }

        ch_qc_reads = QC_ANALYSIS.out.reads
        ch_qc_reports = QC_ANALYSIS.out.qc_reports  // Tool-agnostic QC reports (FASTP HTML, FastQC HTML, or tool-specific)
        ch_nanoplot_reports = QC_ANALYSIS.out.nanoplot

        //
        // MODULE: Multi-sample NanoPlot comparison (optional)
        //
        if (params.enable_nanoplot_comparison && !params.skip_nanoplot) {
            // Collect all QC'd reads for comparative analysis
            ch_comparison_reads = ch_qc_reads.map { meta, reads -> reads }.collect()

            NANOPLOT_COMPARE (
                ch_comparison_reads,
                "multisample_comparison"
            )
            ch_versions = ch_versions.mix(NANOPLOT_COMPARE.out.versions)

            // Add comparison stats to MultiQC
            ch_multiqc_files = ch_multiqc_files.mix(NANOPLOT_COMPARE.out.txt.collect())

            ch_nanoplot_comparison = NANOPLOT_COMPARE.out.comparison_dir
        } else {
            ch_nanoplot_comparison = Channel.empty()
        }

        //
        // SUBWORKFLOW: QC tool benchmarking (optional)
        // Compare performance of FASTP, FILTLONG, CHOPPER on same input
        //
        if (params.enable_qc_benchmark) {
            log.info "=== QC Tool Benchmarking Enabled ==="

            QC_BENCHMARK (
                DEMULTIPLEXING.out.samples
            )
            ch_versions = ch_versions.mix(QC_BENCHMARK.out.versions)
            ch_qc_benchmark_results = QC_BENCHMARK.out.benchmark_results
        } else {
            ch_qc_benchmark_results = Channel.empty()
        }
    } else {
        // If QC is skipped, pass through original reads
        log.info "Skipping QC analysis - using original reads"
        ch_qc_reads = DEMULTIPLEXING.out.samples
        ch_qc_reports = Channel.empty()
        ch_nanoplot_reports = Channel.empty()
        ch_qc_benchmark_results = Channel.empty()
    }
    
    //
    // SUBWORKFLOW: Multi-tool genome assembly for long-read data
    //
    if (params.enable_assembly) {
        ASSEMBLY (
            ch_qc_reads
        )
        ch_versions = ch_versions.mix(ASSEMBLY.out.versions)
    }
    
    //
    // SUBWORKFLOW: Multi-tool taxonomic classification with taxpasta standardization
    //
    if (params.kraken2_db) {
        //
        // PREPARE DATABASE: Handle both directory and tar.gz inputs
        // Supports: local directories, local tar.gz files, and remote tar.gz URLs
        //
        def db_path = params.kraken2_db
        def is_archive = db_path.toString().endsWith('.tar.gz') || db_path.toString().endsWith('.tgz')

        if (is_archive) {
            // Extract tar.gz archive using UNTAR module
            ch_db_archive = Channel.of([ [id: 'kraken2_db'], file(db_path, checkIfExists: true) ])
            UNTAR ( ch_db_archive )
            // STREAMING-FIX: Use .first() to convert queue channel to value channel
            // Queue channels are consumed after one emission, breaking streaming workflows
            // Value channels can be reused across multiple emissions (required for watchPath)
            ch_classification_db = UNTAR.out.untar.map { meta, db -> db }.first()
            ch_versions = ch_versions.mix(UNTAR.out.versions)
        } else {
            // Use directory path directly
            // STREAMING-FIX: Use .first() to convert queue channel to value channel
            // This ensures the database path can be reused for each streaming batch
            // Without .first(), only the first batch would receive the database
            ch_classification_db = Channel.fromPath(db_path, checkIfExists: true).first()
        }

        TAXONOMIC_CLASSIFICATION (
            ch_qc_reads,
            ch_classification_db
        )
        ch_versions = ch_versions.mix(TAXONOMIC_CLASSIFICATION.out.versions)
        ch_multiqc_files = ch_multiqc_files.mix(TAXONOMIC_CLASSIFICATION.out.report.collect{it[1]})

        //
        // MODULE: Krona interactive visualization of taxonomic results
        // Note: skip_krona parameter for ARM Mac compatibility (Krona container has permission issues)
        //
        if (params.enable_krona_plots && !params.skip_krona) {
            log.info "Generating Krona interactive visualization"

            KRONA_KRAKEN2 (
                TAXONOMIC_CLASSIFICATION.out.report
            )
            ch_versions = ch_versions.mix(KRONA_KRAKEN2.out.versions)
            ch_krona_reports = KRONA_KRAKEN2.out.html
        } else {
            ch_krona_reports = Channel.empty()
        }

        //
        // SUBWORKFLOW: Pathogen validation via BLAST and/or minimap2
        // Validates Kraken2 classifications against reference genomes
        // Output: validation_results.json for Nanometa Live dashboard
        //
        // REQUIREMENT: save_reads_assignment must be true for validation to work
        // The Kraken2 output file (per-read classifications) is needed to extract reads by taxid
        //
        if (run_validation_effective && params.pathogen_genomes) {
            // Check that save_reads_assignment is enabled
            if (!params.save_reads_assignment) {
                error """
                    ===============================================================================
                    ERROR: Pathogen validation requires --save_reads_assignment true

                    The validation workflow needs the Kraken2 per-read classification output
                    to extract reads for specific taxids. Please add this parameter:

                        --save_reads_assignment true

                    Or disable validation:

                        --run_validation false (or --blast_validation false for legacy)
                    ===============================================================================
                    """.stripIndent()
            }

            // Check that pathogen_genomes file exists and is JSON
            def genomes_file = file(params.pathogen_genomes, checkIfExists: true)
            if (!genomes_file.name.endsWith('.json')) {
                log.warn "WARNING: pathogen_genomes file '${params.pathogen_genomes}' does not have .json extension"
            }

            log.info "Running pathogen validation using ${params.validation_method} method"
            log.info "  Genomes file: ${params.pathogen_genomes}"
            log.info "  Taxids to validate: ${params.taxids_to_validate}"

            VALIDATION (
                TAXONOMIC_CLASSIFICATION.out.classified_reads,
                TAXONOMIC_CLASSIFICATION.out.reads_assignment,
                TAXONOMIC_CLASSIFICATION.out.report,
                params.pathogen_genomes,
                params.taxids_to_validate,
                params.validation_method
            )
            ch_versions = ch_versions.mix(VALIDATION.out.versions)

            // Log validation completion
            VALIDATION.out.validation_json.subscribe {
                log.info "Validation results written to: ${params.outdir}/validation/validation_results.json"
            }
        }
    }

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:  'nanometanf_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }

    //
    // MODULE: Generate nanopore-specific MultiQC custom content (optional)
    //
    if (params.enable_nanopore_stats_mqc) {
        // Collect sample statistics from QC outputs
        ch_sample_stats = ch_qc_reports
            .map { meta, report ->
                [
                    sample_id: meta.id,
                    barcode: meta.barcode ?: 'unclassified',
                    report_path: report.toString()
                ]
            }
            .collect()

        MULTIQC_NANOPORE_STATS (
            ch_sample_stats,
            'nanometanf'
        )
        ch_versions = ch_versions.mix(MULTIQC_NANOPORE_STATS.out.versions)
        ch_multiqc_files = ch_multiqc_files.mix(MULTIQC_NANOPORE_STATS.out.multiqc_files)
    }

    //
    // MODULE: MultiQC - Comprehensive quality control report
    //
    // Real-time mode optimization (PromethION):
    // - The .collect() operator naturally defers MultiQC execution until ALL input files are emitted
    // - This means MultiQC runs once at the end, avoiding re-parsing intermediate batch files
    // - No additional logic needed - .collect() implements deferred execution automatically
    // - Controlled by: params.multiqc_realtime_final_only (default: true)
    //
    ch_multiqc_config        = Channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        Channel.fromPath(params.multiqc_config, checkIfExists: true) :
        Channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        Channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        Channel.empty()

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    if (!params.skip_multiqc) {
        // Log real-time mode optimization
        if (params.realtime_mode && params.multiqc_realtime_final_only) {
            log.info "Real-time mode: MultiQC will run once at the end (deferred execution via .collect())"
        }

        MULTIQC (
            ch_multiqc_files.collect(),
            ch_multiqc_config.toList(),
            ch_multiqc_custom_config.toList(),
            ch_multiqc_logo.toList(),
            [],
            []
        )
        ch_multiqc_report = MULTIQC.out.report.toList()
    } else {
        log.info "Skipping MultiQC report generation"
        ch_multiqc_report = Channel.empty()
    }

    emit:
    multiqc_report         = ch_multiqc_report                              // channel: /path/to/multiqc_report.html
    qc_reports             = ch_qc_reports                                  // channel: [ val(meta), path(html) ]
    nanoplot_reports       = ch_nanoplot_reports                            // channel: [ val(meta), path(html) ]
    nanoplot_comparison    = params.enable_nanoplot_comparison && !params.skip_nanoplot ? ch_nanoplot_comparison : Channel.empty()  // channel: path(dir) - Multi-sample comparison
    assemblies             = params.enable_assembly ? ASSEMBLY.out.assembly : Channel.empty()          // channel: [ val(meta), path(fasta.gz) ] - Genome assemblies
    assembly_graphs        = params.enable_assembly ? ASSEMBLY.out.assembly_graph : Channel.empty()    // channel: [ val(meta), path(gfa.gz) ] - Assembly graphs
    assembly_info          = params.enable_assembly ? ASSEMBLY.out.assembly_info : Channel.empty()     // channel: [ val(meta), path(txt) ] - Assembly statistics
    assembler_used         = params.enable_assembly ? ASSEMBLY.out.assembler_used : Channel.empty()    // channel: val(assembler_name)
    classification_reports = params.kraken2_db ? TAXONOMIC_CLASSIFICATION.out.report : Channel.empty() // channel: [ val(meta), path(txt) ] - Original format
    standardized_reports   = params.kraken2_db ? TAXONOMIC_CLASSIFICATION.out.standardized_report : Channel.empty() // channel: [ val(meta), path(tsv/csv/etc) ] - Taxpasta format
    classifier_used        = params.kraken2_db ? TAXONOMIC_CLASSIFICATION.out.classifier_used : Channel.empty() // channel: val(classifier_name)
    blast_results          = run_validation_effective ? VALIDATION.out.blast_results : Channel.empty()  // channel: [ val(meta), path(txt) ]
    versions               = ch_versions                                     // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
