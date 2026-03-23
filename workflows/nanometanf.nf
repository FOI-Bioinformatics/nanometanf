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
include { INPUT_SCANNER              } from '../subworkflows/local/input_scanner'
include { POD5_BARCODE_DISCOVERY    } from '../subworkflows/local/pod5_barcode_discovery'
include { DEMULTIPLEXING             } from '../subworkflows/local/demultiplexing'
include { QC_ANALYSIS                } from '../subworkflows/local/qc_analysis'
include { ASSEMBLY                   } from '../subworkflows/local/assembly'
include { TAXONOMIC_CLASSIFICATION   } from '../subworkflows/local/taxonomic_classification'
include { VALIDATION                 } from '../subworkflows/local/validation'
include { NANOPLOT_COMPARE           } from '../modules/local/nanoplot_compare/main'
include { MANIFEST_WRITER           } from '../modules/local/manifest_writer/main'

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
    // INPUT VALIDATION: Check for conflicting or missing parameters
    //
    def input_modes = []
    if (params.input) input_modes << '--input'
    if (params.input_dir) input_modes << '--input_dir'
    if (params.barcode_input_dir) input_modes << '--barcode_input_dir'
    if (params.pod5_input_dir && params.use_dorado) input_modes << '--pod5_input_dir'
    if (params.realtime_mode && params.nanopore_output_dir) input_modes << '--realtime_mode'

    if (input_modes.size() > 1 && !params.realtime_mode) {
        log.warn "========================================================================="
        log.warn "  WARNING: Multiple input modes specified: ${input_modes.join(', ')}"
        log.warn "  Only one input mode should be used. The pipeline will use the first detected."
        log.warn "========================================================================="
    }

    if (input_modes.size() == 0 && !params.realtime_mode) {
        log.error "========================================================================="
        log.error "  ERROR: No input specified!"
        log.error ""
        log.error "  Please provide one of:"
        log.error "    --input samplesheet.csv"
        log.error "    --input_dir /path/to/barcode/folders"
        log.error "    --pod5_input_dir /path/to/pod5 --use_dorado"
        log.error "    --realtime_mode --nanopore_output_dir /path/to/monitor"
        log.error "========================================================================="
        error "No input data specified. See above for options."
    }

    // Realtime safeguard: warn if no termination condition is set
    if (params.realtime_mode && params.max_files == null && params.realtime_timeout_minutes == null) {
        log.warn "========================================================================="
        log.warn "  WARNING: Real-time mode is enabled without a termination condition."
        log.warn "  Neither --max_files nor --realtime_timeout_minutes is set."
        log.warn "  The pipeline will run indefinitely until manually stopped."
        log.warn ""
        log.warn "  Consider setting one of:"
        log.warn "    --max_files <N>                     Stop after N files processed"
        log.warn "    --realtime_timeout_minutes <N>      Stop after N minutes of inactivity"
        log.warn "========================================================================="
    }

    //
    // INPUT VALIDATION: Verify external resources before pipeline execution
    //

    // Validate Kraken2 database when classification is enabled
    if (!params.skip_kraken2) {
        if (!params.kraken2_db) {
            error "Kraken2 classification is enabled but params.kraken2_db is not set. " +
                  "Provide a database path with --kraken2_db or set --skip_kraken2 true."
        }
        def kraken2_db_dir = file(params.kraken2_db)
        if (!kraken2_db_dir.exists()) {
            error "Kraken2 database directory does not exist: ${params.kraken2_db}"
        }
        def has_hash = file("${params.kraken2_db}/hash.k2d").exists()
        def has_taxo = file("${params.kraken2_db}/taxo.k2d").exists()
        if (!has_hash || !has_taxo) {
            error "Kraken2 database at ${params.kraken2_db} appears incomplete. " +
                  "Expected hash.k2d and taxo.k2d inside the directory."
        }
    }

    // Validate output directory is writable
    def outdir = file(params.outdir)
    if (!outdir.mkdirs() && !outdir.exists()) {
        error "Unable to create or access output directory: ${params.outdir}. " +
              "Check that the path is writable."
    }

    // Validate sample_regex if provided
    if (params.sample_regex) {
        try {
            java.util.regex.Pattern.compile(params.sample_regex)
        } catch (e) {
            error "Invalid regular expression in params.sample_regex: '${params.sample_regex}'. " +
                  "Pattern compilation failed: ${e.message}"
        }
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

    } else if (params.input_dir || is_barcode_discovery) {
        //
        // UNIFIED DIRECTORY SCAN (replaces BARCODE_DISCOVERY)
        //
        def effective_input_dir = params.input_dir ?: params.barcode_input_dir
        if (params.barcode_input_dir && !params.input_dir) {
            log.warn "DEPRECATED: --barcode_input_dir is deprecated. Use --input_dir instead."
        }
        INPUT_SCANNER (
            effective_input_dir,
            params.sample_regex
        )
        ch_processed_samples = INPUT_SCANNER.out.samples
        ch_versions = ch_versions.mix(INPUT_SCANNER.out.versions)

    } else {
        //
        // FASTQ WORKFLOW PATH
        //
        if (params.realtime_mode) {
            // Real-time FASTQ monitoring
            REALTIME_MONITORING (
                params.nanopore_output_dir,
                params.file_pattern ?: "**.fastq{,.gz}",
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
        // NOTE: The .collect() below waits for all items in the channel before emitting,
        // which blocks until the entire real-time session completes. This is acceptable
        // because enable_nanoplot_comparison defaults to false and is intended for
        // post-run batch analysis, not streaming use. In streaming mode, per-sample
        // NanoPlot runs are handled by QC_ANALYSIS with interval-based gating instead.
        //
        if (params.enable_nanoplot_comparison && !params.skip_nanoplot) {
            log.info "NanoPlot multi-sample comparison enabled -- this defers until all samples complete"
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
    if (params.skip_kraken2) {
        log.info "Taxonomic classification skipped (--skip_kraken2 is true)"
    } else if (!params.kraken2_db) {
        log.warn "========================================================================="
        log.warn "  WARNING: No Kraken2 database provided (--kraken2_db)"
        log.warn "  Taxonomic classification will be SKIPPED."
        log.warn ""
        log.warn "  To enable classification, provide a database path:"
        log.warn "    --kraken2_db /path/to/kraken2_db"
        log.warn ""
        log.warn "  Or download a pre-built database from:"
        log.warn "    https://benlangmead.github.io/aws-indexes/k2"
        log.warn ""
        log.warn "  To silence this warning, use: --skip_kraken2 true"
        log.warn "========================================================================="
    }

    if (params.kraken2_db && !params.skip_kraken2) {
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
            // Auto-enable save_reads_assignment when validation is active
            if (!params.save_reads_assignment) {
                log.warn "Validation requires per-read Kraken2 output. Automatically enabling save_reads_assignment."
                params.save_reads_assignment = true
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
    // MODULE: Write canonical run manifest
    // Collects tool identity and sample list for frontend discovery
    //
    if (params.write_canonical != false) {
        // Collect sample IDs from processed samples
        def ch_sample_ids = DEMULTIPLEXING.out.samples
            .map { meta, reads -> meta.id }
            .collect()

        def effective_classifier = (params.kraken2_db && !params.skip_kraken2) ? (params.classifier ?: 'kraken2') : ""
        def effective_qc_tool = (!params.skip_fastp || !params.skip_nanoplot) ? (params.qc_tool ?: 'chopper') : ""
        def effective_assembler = params.enable_assembly ? (params.assembler ?: 'flye') : ""
        def effective_validation = (run_validation_effective && params.pathogen_genomes) ? (params.validation_method ?: 'blast') : ""
        def effective_mode = params.realtime_mode ? "realtime" : "batch"

        MANIFEST_WRITER (
            Channel.value(effective_classifier),
            Channel.value(effective_qc_tool),
            Channel.value(effective_assembler),
            Channel.value(effective_validation),
            ch_sample_ids,
            Channel.value(effective_mode)
        )
        ch_versions = ch_versions.mix(MANIFEST_WRITER.out.versions)
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

        // Build MULTIQC input tuple
        // New API: tuple val(meta), path(multiqc_files), path(multiqc_config), path(multiqc_logo), path(replace_names), path(sample_names)
        //
        // Each channel is collected independently. The .map{[it]} wrapper prevents
        // .combine() from flattening the inner lists into the result tuple.
        ch_multiqc_input = ch_multiqc_files
            .collect().map { [it] }
            .combine(
                ch_multiqc_config
                    .mix(ch_multiqc_custom_config)
                    .collect().map { [it] }
            )
            .combine(
                ch_multiqc_logo
                    .toList().map { it.size() > 0 ? [it] : [[]] }
            )
            .map { files, configs, logo ->
                [ [id: 'multiqc'], files, configs, logo, [], [] ]
            }

        MULTIQC ( ch_multiqc_input )
        ch_multiqc_report = MULTIQC.out.report.map { meta, report -> report }.toList()
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
    blast_results          = (run_validation_effective && params.pathogen_genomes) ? VALIDATION.out.blast_results : Channel.empty()  // channel: [ val(meta), path(txt) ]
    versions               = ch_versions                                     // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
