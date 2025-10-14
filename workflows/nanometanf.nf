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
include { BARCODE_DISCOVERY          } from '../subworkflows/local/barcode_discovery'
include { DEMULTIPLEXING             } from '../subworkflows/local/demultiplexing'
include { QC_ANALYSIS                } from '../subworkflows/local/qc_analysis'
include { ASSEMBLY                   } from '../subworkflows/local/assembly'
include { TAXONOMIC_CLASSIFICATION   } from '../subworkflows/local/taxonomic_classification'
include { VALIDATION                 } from '../subworkflows/local/validation'
include { DYNAMIC_RESOURCE_ALLOCATION } from '../subworkflows/local/dynamic_resource_allocation'
include { NANOPLOT_COMPARE           } from '../modules/local/nanoplot_compare/main'

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
                params.nanopore_output_dir,
                params.file_pattern ?: "**/*.pod5",
                params.batch_size ?: 10,
                params.batch_interval ?: "5min",
                params.dorado_model
            )
            ch_processed_samples = REALTIME_POD5_MONITORING.out.samples
            ch_versions = ch_versions.mix(REALTIME_POD5_MONITORING.out.versions.ifEmpty([]))
            
        } else {
            // Static POD5 basecalling
            if (!params.pod5_input_dir) {
                error "POD5 input directory is required when use_dorado is true and not in realtime mode"
            }
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
        } else {
            // Standard samplesheet input
            ch_processed_samples = ch_samplesheet
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
    } else {
        // If QC is skipped, pass through original reads
        log.info "Skipping QC analysis - using original reads"
        ch_qc_reads = DEMULTIPLEXING.out.samples
        ch_qc_reports = Channel.empty()
        ch_nanoplot_reports = Channel.empty()
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
        ch_classification_db = Channel.fromPath(params.kraken2_db, checkIfExists: true)
        
        TAXONOMIC_CLASSIFICATION (
            ch_qc_reads,
            ch_classification_db
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

    if (!params.skip_multiqc) {
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
    blast_results          = params.blast_validation ? VALIDATION.out.txt : Channel.empty()           // channel: [ val(meta), path(txt) ]
    versions               = ch_versions                                     // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
