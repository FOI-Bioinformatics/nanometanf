/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { MULTIQC                    } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap           } from 'plugin/nf-schema'
include { paramsSummaryMultiqc       } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML     } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText     } from '../subworkflows/local/utils_nfcore_nanometanf_pipeline'

// Import local subworkflows
include { REALTIME_MONITORING        } from '../subworkflows/local/realtime_monitoring'
include { REALTIME_POD5_MONITORING   } from '../subworkflows/local/realtime_pod5_monitoring'
include { DORADO_BASECALLING         } from '../subworkflows/local/dorado_basecalling'
include { DEMULTIPLEXING             } from '../subworkflows/local/demultiplexing'
include { QC_ANALYSIS                } from '../subworkflows/local/qc_analysis'
include { TAXONOMIC_CLASSIFICATION   } from '../subworkflows/local/taxonomic_classification'
include { VALIDATION                 } from '../subworkflows/local/validation'

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
    // SUBWORKFLOW: Real-time monitoring (if enabled)
    //
    if (params.realtime_mode && params.use_dorado && params.nanopore_output_dir) {
        // Real-time POD5 monitoring with Dorado basecalling
        REALTIME_POD5_MONITORING (
            params.nanopore_output_dir,
            params.file_pattern ?: "**/*.pod5",
            params.batch_size ?: 10,
            params.batch_interval ?: "5min",
            params.dorado_model
        )
        ch_input_samples = REALTIME_POD5_MONITORING.out.samples
        ch_versions = ch_versions.mix(REALTIME_POD5_MONITORING.out.versions.ifEmpty(null))
        
    } else if (params.realtime_mode) {
        // Real-time FASTQ monitoring (traditional)
        REALTIME_MONITORING (
            params.nanopore_output_dir,
            params.file_pattern ?: "**/*.fastq{,.gz}",
            params.batch_size ?: 10,
            params.batch_interval ?: "5min"
        )
        ch_input_samples = REALTIME_MONITORING.out.samples
    } else {
        ch_input_samples = ch_samplesheet
    }
    
    //
    // SUBWORKFLOW: Dorado basecalling (if enabled)
    //
    if (params.use_dorado && params.pod5_input_dir) {
        // Create POD5 input channel
        ch_pod5_files = Channel.fromPath("${params.pod5_input_dir}/*.pod5", checkIfExists: true)
            .collect()
            .map { files -> 
                def meta = [ id: 'basecalled_sample', single_end: true ]
                [ meta, files ]
            }
        
        DORADO_BASECALLING (
            ch_pod5_files,
            params.dorado_model
        )
        ch_versions = ch_versions.mix(DORADO_BASECALLING.out.versions)
        
        // Use basecalled samples instead of input samples
        ch_processed_samples = DORADO_BASECALLING.out.fastq
    } else {
        // Use input samples directly
        ch_processed_samples = ch_input_samples
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
    QC_ANALYSIS (
        DEMULTIPLEXING.out.samples
    )
    ch_versions = ch_versions.mix(QC_ANALYSIS.out.versions)
    ch_multiqc_files = ch_multiqc_files.mix(QC_ANALYSIS.out.fastp_json.collect{it[1]})
    
    //
    // SUBWORKFLOW: Taxonomic classification with Kraken2
    //
    if (params.kraken2_db) {
        ch_kraken2_db = Channel.fromPath(params.kraken2_db, checkIfExists: true)
        
        TAXONOMIC_CLASSIFICATION (
            QC_ANALYSIS.out.reads,
            ch_kraken2_db
        )
        ch_versions = ch_versions.mix(TAXONOMIC_CLASSIFICATION.out.versions)
        ch_multiqc_files = ch_multiqc_files.mix(TAXONOMIC_CLASSIFICATION.out.report.collect{it[1]})
        
        //
        // SUBWORKFLOW: Optional BLAST validation
        //
        if (params.blast_validation && params.blast_db) {
            // Extract sequences for validation from Kraken2 classified reads
            ch_validation_seqs = TAXONOMIC_CLASSIFICATION.out.classified_reads
                .filter { meta, reads -> params.validation_taxa?.any { taxa -> meta.id.contains(taxa) } }
            
            if (!ch_validation_seqs.empty) {
                ch_blast_db = Channel.fromPath(params.blast_db, checkIfExists: true)
                
                VALIDATION (
                    ch_validation_seqs,
                    ch_blast_db
                )
                ch_versions = ch_versions.mix(VALIDATION.out.versions)
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

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:
    multiqc_report     = MULTIQC.out.report.toList()                    // channel: /path/to/multiqc_report.html
    qc_reports         = QC_ANALYSIS.out.fastp_html                     // channel: [ val(meta), path(html) ]
    nanoplot_reports   = QC_ANALYSIS.out.nanoplot                       // channel: [ val(meta), path(html) ]
    kraken2_reports    = params.kraken2_db ? TAXONOMIC_CLASSIFICATION.out.report : Channel.empty() // channel: [ val(meta), path(txt) ]
    blast_results      = params.blast_validation ? VALIDATION.out.txt : Channel.empty()           // channel: [ val(meta), path(txt) ]
    versions           = ch_versions                                     // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
