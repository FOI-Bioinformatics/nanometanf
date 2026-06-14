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

    // Build channels from existing Kraken2 output files
    // Kraken2 classified reads (FASTQ)
    ch_classified_reads = Channel.fromFilePairs(
        "${params.reads_dir}/*.fastq{,.gz}",
        size: 1,
        flat: true
    ).map { sample_id, fastq ->
        def meta = [id: sample_id]
        [ meta, fastq ]
    }

    // Kraken2 raw output (per-read classification)
    ch_kraken_output = Channel.fromFilePairs(
        "${params.kraken2_output_dir}/*.kraken2.output.txt",
        size: 1,
        flat: true
    ).map { sample_id, output_file ->
        def meta = [id: sample_id]
        [ meta, output_file ]
    }

    // Kraken2 reports
    ch_kraken_reports = Channel.fromFilePairs(
        "${params.kraken2_output_dir}/*.kraken2.report.txt",
        size: 1,
        flat: true
    ).map { sample_id, report ->
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

    if (params.validation_only) {
        //
        // WORKFLOW: Validation-only mode (skip classification)
        //
        VALIDATION_ONLY()
    } else {
        //
        // SUBWORKFLOW: Run initialisation tasks
        //
        PIPELINE_INITIALISATION (
            params.version,
            params.validate_params,
            params.monochrome_logs,
            args,
            params.outdir,
            params.input
        )

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
            params.hook_url,
            FOIBIOINFORMATICS_NANOMETANF.out.multiqc_report
        )
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
