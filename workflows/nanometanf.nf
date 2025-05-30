/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { FASTQC                 } from '../modules/nf-core/fastqc/main'
include { FASTP                  } from '../modules/nf-core/fastp/main'
include { KRAKEN2_KRAKEN2        } from '../modules/nf-core/kraken2/kraken2/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_nanometanf_pipeline'

// Custom modules
include { EXTRACT_QC_INFO        } from '../modules/local/extract_qc_info/main'
include { COMBINE_KREPORTS       } from '../modules/local/combine_kreports/main'
include { COMBINE_QC             } from '../modules/local/combine_qc/main'
include { EXTRACT_FASTP_INFO     } from '../modules/local/extract_fastp_info/main'
include { COMBINE_FASTP          } from '../modules/local/combine_fastp/main'

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
    // MODULE: Extract QC information from raw reads
    //
    EXTRACT_QC_INFO (
        ch_samplesheet
    )
    ch_versions = ch_versions.mix(EXTRACT_QC_INFO.out.versions.first())

    //
    // Combine QC info per sample
    //
    EXTRACT_QC_INFO.out.qc_info
        .map { meta, qc_file ->
            def sample = meta.sample ?: 'all_samples'
            return [ sample, qc_file ]
        }
        .groupTuple()
        .map { sample, qc_files ->
            return [ [id: sample], qc_files ]
        }
        .set { ch_qc_per_sample }

    COMBINE_QC (
        ch_qc_per_sample
    )

    //
    // MODULE: Run FastQC
    //
    FASTQC (
        ch_samplesheet
    )
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{it[1]})
    ch_versions = ch_versions.mix(FASTQC.out.versions.first())

    //
    // MODULE: Run fastp filtering
    //
    FASTP (
        ch_samplesheet,
        [],  // adapter_fasta
        false,  // discard_trimmed_pass
        false,  // save_trimmed_fail
        false   // save_merged
    )
    ch_versions = ch_versions.mix(FASTP.out.versions.first())

    //
    // Extract fastp info
    //
    EXTRACT_FASTP_INFO (
        FASTP.out.json
    )

    //
    // Combine fastp info per sample
    //
    EXTRACT_FASTP_INFO.out.fastp_info
        .map { meta, fastp_file ->
            def sample = meta.sample ?: 'all_samples'
            return [ sample, fastp_file ]
        }
        .groupTuple()
        .map { sample, fastp_files ->
            return [ [id: sample], fastp_files ]
        }
        .set { ch_fastp_per_sample }

    COMBINE_FASTP (
        ch_fastp_per_sample
    )

    //
    // MODULE: Run Kraken2 classification
    //
    if (params.kraken2_db) {
        KRAKEN2_KRAKEN2 (
            FASTP.out.reads,
            params.kraken2_db,
            false,  // save_output_fastqs
            false   // save_reads_assignment
        )
        ch_versions = ch_versions.mix(KRAKEN2_KRAKEN2.out.versions.first())

        //
        // Combine kreports per sample
        //
        KRAKEN2_KRAKEN2.out.report
            .map { meta, report ->
                def sample = meta.sample ?: 'all_samples'
                return [ sample, report ]
            }
            .groupTuple()
            .map { sample, reports ->
                return [ [id: sample], reports ]
            }
            .set { ch_kreports_per_sample }

        COMBINE_KREPORTS (
            ch_kreports_per_sample
        )
        ch_multiqc_files = ch_multiqc_files.mix(KRAKEN2_KRAKEN2.out.report.collect{it[1]})
    }

    //
    // Create summary statistics across all samples if multiple samples exist
    //
    if (params.create_summary) {
        // Combine all QC files
        EXTRACT_QC_INFO.out.qc_info
            .map { meta, qc_file -> qc_file }
            .collect()
            .map { qc_files -> [ [id: 'all_samples_summary'], qc_files ] }
            .set { ch_all_qc }

        COMBINE_QC (
            ch_all_qc,
            'all_samples_summary'
        )

        // Combine all fastp files
        EXTRACT_FASTP_INFO.out.fastp_info
            .map { meta, fastp_file -> fastp_file }
            .collect()
            .map { fastp_files -> [ [id: 'all_samples_summary'], fastp_files ] }
            .set { ch_all_fastp }

        COMBINE_FASTP (
            ch_all_fastp,
            'all_samples_summary'
        )

        // Combine all kreports if kraken2 was run
        if (params.kraken2_db) {
            KRAKEN2_KRAKEN2.out.report
                .map { meta, report -> report }
                .collect()
                .map { reports -> [ [id: 'all_samples_summary'], reports ] }
                .set { ch_all_kreports }

            COMBINE_KREPORTS (
                ch_all_kreports,
                'all_samples_summary'
            )
        }
    }

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:  'nanometanf_software_mqc_versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }

    //
    // MODULE: MultiQC
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

    // Add fastp json files to MultiQC
    ch_multiqc_files = ch_multiqc_files.mix(FASTP.out.json.collect{it[1]})

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:
    multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
