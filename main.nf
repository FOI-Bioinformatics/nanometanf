#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    foi-bioinformatics/nanometanf
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Github : https://github.com/foi-bioinformatics/nanometanf
----------------------------------------------------------------------------------------
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS / WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { NANOMETANF  } from './workflows/nanometanf'
include { PIPELINE_INITIALISATION } from './subworkflows/local/utils_nfcore_nanometanf_pipeline'
include { PIPELINE_COMPLETION     } from './subworkflows/local/utils_nfcore_nanometanf_pipeline'
include { getGenomeAttribute      } from './subworkflows/local/utils_nfcore_nanometanf_pipeline'
include { VALIDATION as VALIDATION_ONLY_SUB } from './subworkflows/local/validation'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    GENOME PARAMETER VALUES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Reference genome FASTA file for validation workflows and BLAST database creation
// Uses getGenomeAttribute() to fetch parameters from igenomes.config using `--genome`
params.fasta = getGenomeAttribute('fasta')

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    NAMED WORKFLOWS FOR PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// WORKFLOW: Run main analysis pipeline depending on type of input
//
workflow FOIBIOINFORMATICS_NANOMETANF {

    take:
    samplesheet // channel: samplesheet read in from --input

    main:

    //
    // WORKFLOW: Run pipeline
    //
    NANOMETANF (
        samplesheet
    )
    emit:
    multiqc_report         = NANOMETANF.out.multiqc_report         // channel: /path/to/multiqc_report.html
    qc_reports             = NANOMETANF.out.qc_reports             // channel: [ val(meta), path(html) ]
    nanoplot_reports       = NANOMETANF.out.nanoplot_reports       // channel: [ val(meta), path(html) ]
    classification_reports = NANOMETANF.out.classification_reports // channel: [ val(meta), path(txt) ]
    standardized_reports   = NANOMETANF.out.standardized_reports   // channel: [ val(meta), path(tsv/csv/etc) ]
    blast_results          = NANOMETANF.out.blast_results          // channel: [ val(meta), path(txt) ]
    assemblies             = NANOMETANF.out.assemblies             // channel: [ val(meta), path(fasta.gz) ]
    assembly_graphs        = NANOMETANF.out.assembly_graphs        // channel: [ val(meta), path(gfa.gz) ]
    versions               = NANOMETANF.out.versions               // channel: [ path(versions.yml) ]
}
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    VALIDATION-ONLY WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// WORKFLOW: Run validation against existing Kraken2 output (skip classification)
// Triggered via: nextflow run . --validation_only --kraken2_output_dir <path> --reads_dir <path>
//
workflow VALIDATION_ONLY {

    main:

    //
    // INPUT VALIDATION
    //
    // The schema requires both paths for the validation-only input mode
    // (PIPELINE_INITIALISATION runs validateParameters() before this entry
    // since 2026-11). The guards stay for a launch with --validate_params
    // false: both params default to null, and without them the globs below
    // interpolate to "null/*.fastq{,.gz}", every channel is empty, and the
    // run reports SUCCESS having validated nothing.
    //
    if (!params.reads_dir) {
        error "--validation_only requires --reads_dir <path to the FASTQ files " +
              "that were classified>."
    }
    if (!params.kraken2_output_dir) {
        error "--validation_only requires --kraken2_output_dir <path to the " +
              "existing Kraken2 output>."
    }

    def reads_dir = file(params.reads_dir)
    if (!reads_dir.exists()) {
        error "reads_dir does not exist: ${params.reads_dir}"
    }
    def kraken_dir = file(params.kraken2_output_dir)
    if (!kraken_dir.exists()) {
        error "kraken2_output_dir does not exist: ${params.kraken2_output_dir}"
    }

    // Build channels from existing Kraken2 output files
    //
    // Per-sample read pools. Prefer the classified FASTQs the original run
    // published into kraken2_output_dir (*.kraken2.classified.fastq.gz):
    // one file per sample, the stem IS the sample id (which the join in the
    // validation subworkflow matches against the Kraken2 outputs), and it is
    // the same pool main-mode validation consumes. The reads_dir glob is the
    // fallback for outdirs without saved classified FASTQs; it only works
    // for flat directories whose file stems equal sample ids -- a by_barcode
    // layout (barcode01/reads.fastq.gz) matches nothing, which made
    // on-demand validation impossible for multiplexed runs (2026-08-18).
    def classified_suffix = '.kraken2.classified.fastq.gz'
    def classified_pools = file(
        "${params.kraken2_output_dir}/*${classified_suffix}"
    )
    if (classified_pools) {
        ch_classified_reads = Channel.fromList(
            classified_pools instanceof List ? classified_pools : [classified_pools]
        ).map { fastq ->
            def meta = [id: fastq.name - classified_suffix]
            [ meta, fastq ]
        }
    } else {
        ch_classified_reads = Channel.fromFilePairs(
            "${params.reads_dir}/*.fastq{,.gz}",
            size: 1,
            flat: true
        ).map { sample_id, fastq ->
            def meta = [id: sample_id]
            [ meta, fastq ]
        }.ifEmpty {
            error "No *${classified_suffix} files in " +
                  "${params.kraken2_output_dir} and no *.fastq/*.fastq.gz " +
                  "directly in ${params.reads_dir}. Either re-run the " +
                  "pipeline with save_output_fastqs, or point --reads_dir at " +
                  "a flat directory of per-sample FASTQ files named by " +
                  "sample id."
        }
    }

    // Kraken2 raw output (per-read classification) and reports, one per
    // sample. The standard classifier publishes <sample>.kraken2.output.txt;
    // the incremental path (real time, chunked batch mode -- the default --
    // and kraken2_enable_incremental) publishes the end-of-session
    // <sample>.cumulative.kraken2.output.txt instead, and its only flat
    // <sample>.kraken2.report.txt is the zero-read placeholder for a batch
    // that produced nothing. ValidationOnlyInputs.perSample strips the
    // marker so the stem is the sample id -- globbed as a stem it was the
    // sample "barcode01.cumulative", which matched no read pool and left
    // every on-demand validation after a default run with nothing to do
    // (bug audit 2026-11-06, finding 4) -- and prefers the cumulative file
    // where a sample has both.
    def output_suffix = '.kraken2.output.txt'
    def outputs_found = file("${params.kraken2_output_dir}/*${output_suffix}")
    def per_sample_outputs = ValidationOnlyInputs.perSample(
        outputs_found instanceof List ? outputs_found : (outputs_found ? [outputs_found] : []),
        output_suffix)
    if (!per_sample_outputs) {
        error "No *${output_suffix} files found in " +
              "${params.kraken2_output_dir}. Validation needs the per-read " +
              "Kraken2 output, which requires save_reads_assignment on the " +
              "original run."
    }
    ch_kraken_output = Channel.fromList(per_sample_outputs).map { sample_id, output_file ->
        def meta = [id: sample_id]
        [ meta, output_file ]
    }

    def report_suffix = '.kraken2.report.txt'
    def reports_found = file("${params.kraken2_output_dir}/*${report_suffix}")
    def per_sample_reports = ValidationOnlyInputs.perSample(
        reports_found instanceof List ? reports_found : (reports_found ? [reports_found] : []),
        report_suffix)
    if (!per_sample_reports) {
        error "No *${report_suffix} files found in " +
              "${params.kraken2_output_dir}."
    }
    ch_kraken_reports = Channel.fromList(per_sample_reports).map { sample_id, report ->
        def meta = [id: sample_id]
        [ meta, report ]
    }

    // Run validation subworkflow
    VALIDATION_ONLY_SUB(
        ch_classified_reads,
        ch_kraken_output,
        ch_kraken_reports,
        params.pathogen_genomes,
        params.taxids_to_validate ?: 'auto',
        params.validation_method ?: 'blast',
        params.min_batch_reads_for_validation
    )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow {

    main:

    //
    // ENVIRONMENT CHECK: Provide helpful guidance on container availability
    //
    if (!workflow.containerEngine && !workflow.profile?.contains('conda')) {
        log.warn "========================================================================="
        log.warn "  No container engine or conda detected."
        log.warn ""
        log.warn "  This pipeline requires containerized dependencies. Please use one of:"
        log.warn "    -profile docker      (recommended)"
        log.warn "    -profile singularity (for HPC clusters)"
        log.warn "    -profile conda       (slower, but works without containers)"
        log.warn ""
        log.warn "  Example: nextflow run foi-bioinformatics/nanometanf -profile docker ..."
        log.warn "========================================================================="
    }

    //
    // SUBWORKFLOW: Run initialisation tasks
    //
    // Both entry workflows run it. Until 2026-11 the validation-only entry
    // skipped it, so --validation_only never validated its parameters: a
    // missing --kraken2_output_dir fell through to the hand-written guards
    // in VALIDATION_ONLY, a mistyped --taxids_to_validate was never seen,
    // and --help / --version did nothing in that mode. The schema names
    // validation-only as the fifth input mode (nextflow_schema.json,
    // input_mode_selection), so validateParameters() accepts it.
    //
    PIPELINE_INITIALISATION (
        params.version,
        params.validate_params,
        params.monochrome_logs,
        args,
        params.outdir,
        params.input,
        params.help,
        params.help_full,
        params.show_hidden
    )

    if (params.validation_only) {
        //
        // WORKFLOW: Validation-only mode (skip classification)
        //
        VALIDATION_ONLY()
    } else {
        //
        // WORKFLOW: Run main workflow
        //
        FOIBIOINFORMATICS_NANOMETANF (
            PIPELINE_INITIALISATION.out.samplesheet
        )
        //
        // SUBWORKFLOW: Run completion tasks
        //
        PIPELINE_COMPLETION (
            params.email,
            params.email_on_fail,
            params.plaintext_email,
            params.outdir,
            params.monochrome_logs,
            FOIBIOINFORMATICS_NANOMETANF.out.multiqc_report
        )
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
