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
include { INPUT_SCANNER              } from '../subworkflows/local/input_scanner'
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
include { MULTIQC_NANOPORE_STATS     } from '../modules/local/multiqc_nanopore_stats/main'

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
    // Validation extracts reads by taxid from the PER-READ Kraken2 output, so
    // save_reads_assignment must be true. This used to "auto-enable" it:
    //
    //     params.save_reads_assignment = true
    //
    // That has never worked under Nextflow 26, which treats params as
    // write-once and reports
    //
    //     WARN: `params.x` is defined multiple times --
    //           Assignments following the first are ignored
    //
    // while leaving the value at false. The Kraken2 process was therefore
    // built with --output /dev/null, no per-read file was written, no reads
    // could be extracted, every validation stage was skipped, and the
    // aggregator wrote an empty validation_results.json -- with the run
    // reporting SUCCESS. On a real sample that is a false negative on a
    // select agent, announced as a clean result.
    //
    // Moving the assignment earlier does not help: the mechanism itself is
    // gone. Since the pipeline cannot fix this for the operator, it must
    // refuse to pretend it has. Fail immediately, naming the flag to set.
    //
    // Two separate Kraken2 outputs are needed, behind two separate flags:
    //   save_reads_assignment -> the per-read taxid assignments, which say
    //                            WHICH reads belong to a target taxid
    //   save_output_fastqs    -> the classified-reads FASTQ, which is the
    //                            sequence data those reads are extracted from
    // Missing either one leaves VALIDATION's input channel empty.
    if (run_validation_effective && params.pathogen_genomes) {
        def missing = []
        if (!params.save_reads_assignment) missing << 'save_reads_assignment'
        if (!params.save_output_fastqs)    missing << 'save_output_fastqs'

        if (missing) {
            log.error "========================================================================="
            log.error "  ERROR: Validation requires Kraken2 read-level output."
            log.error ""
            log.error "  Validation aligns the reads assigned to each target taxid back to a"
            log.error "  reference genome. That needs the per-read assignments to say which"
            log.error "  reads to take, and the classified FASTQ to take them from."
            log.error ""
            log.error "  Missing: ${missing.join(', ')}"
            log.error ""
            log.error "  Re-run with:"
            missing.each { log.error "    --${it} true" }
            log.error ""
            log.error "  These cannot be enabled automatically: Nextflow ignores assignments"
            log.error "  to params after the first, so the pipeline would run to completion"
            log.error "  and report success having validated nothing."
            log.error "========================================================================="
            error "Validation requires: ${missing.collect { "--${it} true" }.join(' ')}"
        }
    }

    //
    // INPUT VALIDATION: Check for conflicting or missing parameters
    //
    def input_modes = []
    if (params.input) input_modes << '--input'
    if (params.input_dir) input_modes << '--input_dir'
    if (params.barcode_input_dir) input_modes << '--barcode_input_dir'
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
        log.error "    --realtime_mode --nanopore_output_dir /path/to/monitor"
        log.error "========================================================================="
        error "No input data specified. See above for options."
    }

    // Realtime safeguard: fail fast on a missing watch directory.
    // A watchPath on a non-existent directory does NOT error -- it keeps the
    // watch queue open and the run hangs until killed (max_time is per-task and
    // there are no tasks). Reject it up front with a clear message instead.
    if (params.realtime_mode) {
        if (!params.nanopore_output_dir) {
            log.error "========================================================================="
            log.error "  ERROR: Real-time mode requires a directory to monitor."
            log.error "  Set --nanopore_output_dir /path/to/monitor"
            log.error "========================================================================="
            error "Real-time mode enabled but --nanopore_output_dir was not provided."
        }
        if (!file(params.nanopore_output_dir).exists()) {
            log.error "========================================================================="
            log.error "  ERROR: Real-time watch directory does not exist:"
            log.error "    ${params.nanopore_output_dir}"
            log.error "  Create it (or point --nanopore_output_dir at an existing directory)"
            log.error "  before starting real-time monitoring."
            log.error "========================================================================="
            error "Real-time watch directory does not exist: ${params.nanopore_output_dir}"
        }
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

    // Kraken2 database validation lives in WorkflowNanometanf.validateKraken2Database,
    // called from PIPELINE_INITIALISATION before this workflow runs. A second copy
    // used to sit here and it only ever did harm: it asserted hash.k2d and taxo.k2d
    // inside the path unconditionally, which is false for the two forms the lib
    // validator accepts and the workflow below implements -- a .tar.gz/.tgz archive
    // (extracted by UNTAR further down) and a remote URL (fetched at runtime).
    // conf/test.config sets exactly such a URL, so `-profile test,docker` could not
    // reach classification at all. The lib validator is also the stricter of the two
    // on real directories (it checks opts.k2d as well) and the only one the failure
    // paths tests observe, because it runs first.

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
    // WORKFLOW ROUTING: FASTQ-only pipeline
    //
    def is_barcode_discovery = params.barcode_input_dir

    if (params.input_dir || is_barcode_discovery) {
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
            // Standard samplesheet input - FASTQ only
            ch_processed_samples = ch_samplesheet
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

        // Collect QC outputs for MultiQC (tool-agnostic). The upstream
        // FASTP / FASTP_STREAMING channels carry `.ifEmpty([])` sentinels
        // (see qc_analysis), which would crash this destructuring closure
        // when every QC task failed. Drop the sentinel before `it[1]`.
        ch_multiqc_files = ch_multiqc_files.mix(
            QC_ANALYSIS.out.qc_json
                .filter { it instanceof List && it.size() >= 2 && it[1] != null }
                .collect { it[1] }
        )

        // Add NanoPlot summary statistics to MultiQC (NanoStats.txt)
        if (!params.skip_nanoplot) {
            ch_multiqc_files = ch_multiqc_files.mix(
                QC_ANALYSIS.out.nanoplot_txt
                    .filter { it instanceof List && it.size() >= 2 && it[1] != null }
                    .collect { it[1] }
            )
        }

        ch_qc_reads = QC_ANALYSIS.out.reads
        ch_qc_reports = QC_ANALYSIS.out.qc_reports  // Tool-agnostic QC reports (FASTP HTML, FastQC HTML, or tool-specific)
        ch_nanoplot_reports = QC_ANALYSIS.out.nanoplot
        ch_qc_json = QC_ANALYSIS.out.qc_json

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
        ch_qc_json = Channel.empty()
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
            // The nf-core UNTAR module reports its version through the
            // topic-style emit (versions_untar, topic: versions); it has no
            // plain `versions` emit, and mixing the eval-tuple into the
            // yml-based ch_versions would break softwareVersionsToYAML.
            // Referencing UNTAR.out.versions crashed EVERY tar.gz-database
            // run at wiring time (2026-08-27), so no version line for tar
            // is the accepted trade-off.
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
        ch_multiqc_files = ch_multiqc_files.mix(
            TAXONOMIC_CLASSIFICATION.out.report
                .filter { it instanceof List && it.size() >= 2 && it[1] != null }
                .collect { it[1] }
        )

        //
        // SUBWORKFLOW: Pathogen validation via BLAST and/or minimap2
        // Validates Kraken2 classifications against reference genomes
        // Output: validation_results.json for Nanometa Live dashboard
        //
        // REQUIREMENT: save_reads_assignment must be true for validation to work
        // The Kraken2 output file (per-read classifications) is needed to extract reads by taxid
        //
        if (run_validation_effective && params.pathogen_genomes) {
            // save_reads_assignment was enabled near the top of this workflow,
            // before TAXONOMIC_CLASSIFICATION was constructed. Doing it here
            // would be too late to affect the Kraken2 process.

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
                // Mix the per-batch reports (realtime; empty in batch mode) into
                // the report stream so realtime validation can resolve species
                // names each batch instead of only from the end-of-session
                // cumulative report.
                TAXONOMIC_CLASSIFICATION.out.report.mix(TAXONOMIC_CLASSIFICATION.out.batch_reports),
                params.pathogen_genomes,
                params.taxids_to_validate,
                params.validation_method,
                params.min_batch_reads_for_validation
            )
            ch_versions = ch_versions.mix(VALIDATION.out.versions)

            // Log validation completion
            VALIDATION.out.validation_json.subscribe {
                log.info "Validation results written to: ${params.outdir}/validation/validation_results.json"
            }
        }
    }

    //
    // SUBWORKFLOW: Multi-tool genome assembly for long-read data
    //
    // Invoked AFTER validation, not before, because targeted assembly reuses
    // the per-organism reads validation already extracts -- one extraction
    // path, not two. Nextflow orders by data dependency, not by position, so
    // this changes nothing about when the whole-sample assembly runs.
    if (params.enable_assembly) {
        // The reads of an organism the run detected, paired with the
        // reference its depth is judged against. Extraction is keyed on the
        // taxid, so the reference comes from the same pathogen_genomes map
        // validation resolved.
        ch_assembly_targeted = Channel.empty()
        if (params.assembly_scope in ['targeted', 'both']) {
            if (run_validation_effective && params.pathogen_genomes) {
                ch_assembly_targeted = VALIDATION.out.extracted_reads
            } else {
                log.warn "assembly_scope '${params.assembly_scope}' asks for targeted assembly, " +
                    "but confirmation testing is not running, so there are no per-organism " +
                    "read sets to assemble. Only the whole-sample assembly will run."
            }
        }

        ASSEMBLY ( ch_qc_reads, ch_assembly_targeted )
        ch_versions = ch_versions.mix(ASSEMBLY.out.versions)
    }

    //
    // MODULE: Write canonical run manifest
    // Collects tool identity and sample list for frontend discovery
    //
    if (params.write_canonical != false) {
        // Collect unique sample IDs (realtime mode emits duplicates per batch).
        // .ifEmpty([]) so a run that detected no samples at all still reaches
        // MANIFEST_WRITER: .collect() on an empty channel emits nothing, which
        // leaves the process unscheduled and the run finishing with no manifest
        // -- the one artifact a consumer would read to find out that nothing was
        // processed.
        def ch_sample_ids = DEMULTIPLEXING.out.samples
            .map { meta, reads -> meta.id }
            .unique()
            .collect()
            .ifEmpty([])

        // Samples that actually emitted QC output. A sample whose QC task
        // failed is absorbed by conf/error_isolation.config so the other
        // barcodes continue, and never reaches this channel; the difference
        // from ch_sample_ids is what the manifest records as failed_samples.
        //
        // The .filter is load-bearing, not defensive. QC_ANALYSIS attaches
        // `.ifEmpty([])` to ch_qc_reads (qc_analysis/main.nf:204 and friends),
        // so a sample that produced nothing puts the bare `[]` sentinel on this
        // channel. Destructuring that in the map below aborts the run --
        // which is exactly what a first version of this code did, converting an
        // isolated QC failure into a whole-pipeline failure and defeating the
        // isolation this feature exists to report on. Same guard VALIDATION
        // applies at its own boundary (validation/main.nf:41).
        //
        // Read ch_qc_reads, not QC_ANALYSIS.out.reads: with QC fully skipped
        // (skip_fastp + skip_nanoplot) QC_ANALYSIS is never invoked and
        // touching its .out aborts the run with "Access to 'QC_ANALYSIS.out'
        // is undefined". ch_qc_reads is assigned in both branches -- it falls
        // back to DEMULTIPLEXING.out.samples -- so a skipped-QC run reports
        // every sample as produced, which is correct: no QC ran, so no sample
        // failed QC.
        def ch_qc_produced_ids = ch_qc_reads
            .filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map }
            .map { meta, reads -> [ meta.id, 'qc' ] }
            .unique()

        // A sample can also be lost AFTER QC. conf/error_isolation.config sets
        // errorStrategy 'ignore' on exit 1/2 for all three KRAKEN2 processes --
        // the normal failure codes for them -- so a barcode whose classification
        // died leaves its QC output intact and simply produces no report. Judging
        // "produced" on QC alone marked such a sample healthy and let the
        // manifest claim a <sample>.classification.json that was never written.
        // For a screening tool that is the worst kind of wrong: the sample reads
        // as screened and clear when it was never screened at all.
        //
        // TAXONOMIC_CLASSIFICATION.out.report carries the
        // EMIT_EMPTY_KRAKEN2_REPORT placeholder too, so a sample whose post-QC
        // FASTQ was legitimately empty still counts as produced -- it was
        // screened and found to hold nothing, which is a result, not a failure.
        //
        // The intersection is a keyed .join rather than a .collect on each side
        // followed by List.intersect: .combine and .merge spread a List emission
        // across the output tuple, so two collected id lists arrive as loose
        // Strings and the intersect lands on the first sample name instead of
        // the list. Joining the per-sample streams keeps the ids as keys, and a
        // plain join (no remainder) emits only keys present on both sides,
        // which is the intersection by definition.
        //
        // The presence-decides contract is preserved: .collect().ifEmpty([])
        // closes every branch, so the manifest always gets a determined answer.
        def ch_produced_sample_ids
        if (params.kraken2_db && !params.skip_kraken2) {
            def ch_classified_ids = TAXONOMIC_CLASSIFICATION.out.report
                .filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map && it[1] != null }
                .map { meta, report -> [ meta.id, 'classified' ] }
                .unique()
            ch_produced_sample_ids = ch_qc_produced_ids
                .join(ch_classified_ids)
                .map { sample_id, qc_marker, classified_marker -> sample_id }
                .collect()
                .ifEmpty([])
        } else {
            // Classification did not run, so it cannot have failed a sample.
            ch_produced_sample_ids = ch_qc_produced_ids
                .map { sample_id, qc_marker -> sample_id }
                .collect()
                .ifEmpty([])
        }

        def effective_classifier = (params.kraken2_db && !params.skip_kraken2) ? (params.classifier ?: 'kraken2') : ""
        def effective_qc_tool = (!params.skip_fastp || !params.skip_nanoplot) ? (params.qc_tool ?: 'chopper') : ""
        def effective_assembler = params.enable_assembly ? (params.assembler ?: 'flye') : ""
        def effective_validation = (run_validation_effective && params.pathogen_genomes) ? (params.validation_method ?: 'blast') : ""
        def effective_mode = params.realtime_mode ? "realtime" : "batch"

        // Collect canonical writer outputs so manifest runs after all files are published.
        // Each subworkflow emits canonical outputs only when write_canonical is enabled.
        // The subworkflows attach `.ifEmpty([])` to these channels, so an empty
        // stage (e.g. no classified reads -> EMIT_EMPTY_KRAKEN2_REPORT, or a
        // negative-control sample) emits the `[]` sentinel. Filter it out before
        // the `{ meta, f -> f }` destructuring map -- otherwise the closure is
        // called with `[]` and the run aborts with MissingMethodException. Same
        // guard pattern as the QC-path sentinel fix (PR #11). Use an inline
        // closure (not a closure variable): `.filter(var)` can be dispatched as
        // a value/equality filter rather than a predicate.
        def ch_canonical_done = Channel.empty()
        if (!params.skip_fastp || !params.skip_nanoplot) {
            ch_canonical_done = ch_canonical_done.mix(
                QC_ANALYSIS.out.canonical_qc
                    .filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map }
                    .map { meta, f -> f }
            )
        }
        if (params.kraken2_db && !params.skip_kraken2) {
            ch_canonical_done = ch_canonical_done.mix(
                TAXONOMIC_CLASSIFICATION.out.canonical_classification
                    .filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map }
                    .map { meta, f -> f }
            )
        }
        if (params.enable_assembly) {
            ch_canonical_done = ch_canonical_done.mix(
                ASSEMBLY.out.canonical_assembly
                    .filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map }
                    .map { meta, f -> f }
            )
        }
        if (run_validation_effective && params.pathogen_genomes) {
            ch_canonical_done = ch_canonical_done.mix(
                VALIDATION.out.canonical_alignments
                    .filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map }
                    .map { meta, f -> f }
            )
        }

        // Wait for all canonical files before writing manifest
        def ch_canonical_ready = ch_canonical_done
            .collect()
            .ifEmpty([])
            .map { 'ready' }

        // The assembly stats files that exist, from the canonical writer's own
        // output. The manifest used to derive these names from the sample list,
        // so it asserted a file per sample even when every assembly failed
        // (assembly audit, 2026-09-03).
        ch_assembly_files = (params.enable_assembly
                ? ASSEMBLY.out.canonical_assembly
                    .filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map }
                    .map { meta, f -> f }
                : Channel.empty())
            .collect()
            .ifEmpty([])

        MANIFEST_WRITER (
            Channel.value(effective_classifier),
            Channel.value(effective_qc_tool),
            Channel.value(effective_assembler),
            Channel.value(effective_validation),
            ch_sample_ids,
            ch_produced_sample_ids,
            ch_assembly_files,
            Channel.value(effective_mode),
            ch_canonical_ready
        )
        ch_versions = ch_versions.mix(MANIFEST_WRITER.out.versions)
    }

    // Placed BEFORE the version collation below, not after. ch_versions is a
    // local variable and .mix() REBINDS it, so softwareVersionsToYAML captures
    // whatever channel the name pointed at when it was called -- a later
    // ch_versions = ch_versions.mix(...) creates a new channel the collation
    // never sees. This block used to sit after it, so MULTIQC_NANOPORE_STATS
    // was absent from nanometanf_software_mqc_versions.yml on every run.
    //
    // MODULE: Generate nanopore-specific MultiQC custom content (optional)
    //
    if (params.enable_nanopore_stats_mqc) {
        // Collect SeqKit/FASTP stats as file inputs for nanopore statistics.
        // The upstream QC_ANALYSIS subworkflow attaches ``.ifEmpty([])`` to
        // ``qc_json`` so the top-level test harness sees an emission even
        // when every QC task failed. That synthetic ``[]`` placeholder
        // must be dropped before any tuple-destructuring closure
        // ``{ meta, stats_file -> ... }``; otherwise it crashes with
        // ``MissingMethodException``. Same guard pattern as in the
        // ``QC_ANALYSIS.out.qc_json.collect{ it[1] }`` consumers above.
        // Use the ch_qc_json channel captured in both QC branches: when QC is
        // skipped (skip_fastp + skip_nanoplot) QC_ANALYSIS is never invoked, so
        // referencing QC_ANALYSIS.out here aborts the run with "Access to
        // 'QC_ANALYSIS.out' is undefined".
        ch_stats_files = ch_qc_json
            .filter { it instanceof List && it.size() >= 2 && it[1] != null }
            .map { meta, stats_file -> stats_file }
            .collect()

        MULTIQC_NANOPORE_STATS (
            ch_stats_files,
            'nanometanf'
        )
        ch_versions = ch_versions.mix(MULTIQC_NANOPORE_STATS.out.versions)
        ch_multiqc_files = ch_multiqc_files.mix(MULTIQC_NANOPORE_STATS.out.multiqc_files)
    }

    //
    // Collate and save software versions
    //
    // Bridges two emission patterns coexisting in this pipeline:
    //   1. Legacy: modules with `path "versions.yml"` (collected via ch_versions)
    //   2. Topic channel: modules emitting (process, tool, version) tuples on the
    //      'versions' topic (e.g. fastp, chopper, kraken2/kraken2 from upstream
    //      master, plus fastqc and seqkit/stats which already use this pattern).
    //
    // Mirrors the upstream nf-core pipeline-template aggregator so both kinds of
    // emissions land in a single nanometanf_software_mqc_versions.yml file.
    //
    def topic_versions = Channel.topic('versions')
        .distinct()
        .branch { entry ->
            versions_file:  entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[(process.lastIndexOf(':') + 1)..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by: 0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    // Guard: softwareVersionsToYAML calls Yaml.load() on each item, which throws
    // MethodSelectionException for a List or null. A skipped subworkflow process
    // can otherwise inject an empty list `[]` into ch_versions (see the validation
    // subworkflow). Drop any non-file item so version collection can never abort
    // the run.
    softwareVersionsToYAML(ch_versions.filter { it != null && !(it instanceof List) }.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:  'nanometanf_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


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
    classification_reports = (params.kraken2_db && !params.skip_kraken2) ? TAXONOMIC_CLASSIFICATION.out.report : Channel.empty() // channel: [ val(meta), path(txt) ] - Original format
    standardized_reports   = (params.kraken2_db && !params.skip_kraken2) ? TAXONOMIC_CLASSIFICATION.out.standardized_report : Channel.empty() // channel: [ val(meta), path(tsv/csv/etc) ] - Taxpasta format
    classifier_used        = (params.kraken2_db && !params.skip_kraken2) ? TAXONOMIC_CLASSIFICATION.out.classifier_used : Channel.empty() // channel: val(classifier_name)
    blast_results          = (run_validation_effective && params.pathogen_genomes) ? VALIDATION.out.blast_results : Channel.empty()  // channel: [ val(meta), path(txt) ]
    versions               = ch_versions                                     // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
