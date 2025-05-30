//
// Subworkflow with functionality specific to the foi-bioinformatics/nanometanf pipeline
//

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT FUNCTIONS / MODULES / SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { UTILS_NFSCHEMA_PLUGIN     } from '../../nf-core/utils_nfschema_plugin'
include { paramsSummaryMap          } from 'plugin/nf-schema'
include { samplesheetToList         } from 'plugin/nf-schema'
include { completionEmail           } from '../../nf-core/utils_nfcore_pipeline'
include { completionSummary         } from '../../nf-core/utils_nfcore_pipeline'
include { imNotification            } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NFCORE_PIPELINE     } from '../../nf-core/utils_nfcore_pipeline'
include { UTILS_NEXTFLOW_PIPELINE   } from '../../nf-core/utils_nextflow_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW TO INITIALISE PIPELINE
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_INITIALISATION {

    take:
    version           // boolean: Display version and exit
    validate_params   // boolean: Boolean whether to validate parameters against the schema at runtime
    monochrome_logs   // boolean: Do not use coloured log outputs
    nextflow_cli_args //   array: List of positional nextflow CLI args
    outdir            //  string: The output directory where the results will be saved
    input             //  string: Path to input samplesheet or directory

    main:

    ch_versions = Channel.empty()

    //
    // Print version and exit if required and dump pipeline parameters to JSON file
    //
    UTILS_NEXTFLOW_PIPELINE (
        version,
        true,
        outdir,
        workflow.profile.tokenize(',').intersect(['conda', 'mamba']).size() >= 1
    )

    //
    // Validate parameters and generate parameter summary to stdout
    //
    UTILS_NFSCHEMA_PLUGIN (
        workflow,
        validate_params,
        null
    )

    //
    // Check config provided to the pipeline
    //
    UTILS_NFCORE_PIPELINE (
        nextflow_cli_args
    )

    //
    // Custom validation for pipeline parameters
    //
    validateInputParameters()

    //
    // Create channel from input
    //
    if (params.input.endsWith('.csv')) {
        // Traditional samplesheet input
        Channel
            .fromList(samplesheetToList(params.input, "${projectDir}/assets/schema_input.json"))
            .map {
                meta, fastq_1, fastq_2 ->
                    if (!fastq_2) {
                        return [ meta.id, meta + [ single_end:true ], [ fastq_1 ] ]
                    } else {
                        return [ meta.id, meta + [ single_end:false ], [ fastq_1, fastq_2 ] ]
                    }
            }
            .groupTuple()
            .map { samplesheet ->
                validateInputSamplesheet(samplesheet)
            }
            .map {
                meta, fastqs ->
                    return [ meta, fastqs.flatten() ]
            }
            .set { ch_samplesheet }
    } else {
        // Directory input - scan for fastq files
        def input_dir = file(params.input)
        if (!input_dir.exists()) {
            error "Input directory does not exist: ${params.input}"
        }

        // Check if directory contains subdirectories with fastq files
        def subdirs = input_dir.listFiles().findAll { it.isDirectory() && !it.name.startsWith('.') }
        def has_subdirs = subdirs.size() > 0 && subdirs.any { subdir ->
            subdir.listFiles().any { it.name =~ /\.fastq(\.gz)?$/ }
        }

        if (has_subdirs) {
            // Process subdirectories as samples
            Channel
                .fromPath("${params.input}/*/", type: 'dir')
                .filter { !it.name.startsWith('.') }
                .map { subdir ->
                    def sample_id = subdir.name
                    def fastq_files = []
                    subdir.eachFileMatch(~/.*\.fastq(\.gz)?$/) { fastq_files << it }

                    if (fastq_files.size() == 0) {
                        return null
                    }

                    // Sort files to ensure R1/R2 pairing
                    fastq_files = fastq_files.sort()

                    def meta = [
                        id: sample_id,
                        sample: sample_id,
                        single_end: true
                    ]

                    // Check for paired-end by looking for R1/R2 or _1/_2 patterns
                    def r1_files = fastq_files.findAll { it.name =~ /[._]R?1[._]/ }
                    def r2_files = fastq_files.findAll { it.name =~ /[._]R?2[._]/ }

                    if (r1_files.size() > 0 && r1_files.size() == r2_files.size()) {
                        // Paired-end data
                        meta.single_end = false
                        def paired_files = []
                        r1_files.eachWithIndex { r1, idx ->
                            paired_files << r1
                            paired_files << r2_files[idx]
                        }
                        return [ meta, paired_files ]
                    } else {
                        // Single-end data or unpaired files
                        return [ meta, fastq_files ]
                    }
                }
                .filter { it != null }
                .set { ch_samplesheet }
        } else {
            // Process files directly in the input directory
            Channel
                .fromPath("${params.input}/*.fastq{,.gz}", checkIfExists: true)
                .collect()
                .map { files ->
                    if (files.size() == 0) {
                        error "No fastq files found in ${params.input}"
                    }

                    def meta = [
                        id: 'all_samples',
                        sample: 'all_samples',
                        single_end: true
                    ]

                    // Sort files
                    files = files.sort()

                    // Check for paired-end
                    def r1_files = files.findAll { it.name =~ /[._]R?1[._]/ }
                    def r2_files = files.findAll { it.name =~ /[._]R?2[._]/ }

                    if (r1_files.size() > 0 && r1_files.size() == r2_files.size()) {
                        meta.single_end = false
                        def paired_files = []
                        r1_files.eachWithIndex { r1, idx ->
                            paired_files << r1
                            paired_files << r2_files[idx]
                        }
                        return [ meta, paired_files ]
                    } else {
                        return [ meta, files ]
                    }
                }
                .set { ch_samplesheet }
        }
    }

    // Watch for new files if requested
    if (params.watch_mode) {
        ch_samplesheet = watchForNewFiles(ch_samplesheet, params.input)
    }

    emit:
    samplesheet = ch_samplesheet
    versions    = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW FOR PIPELINE COMPLETION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PIPELINE_COMPLETION {

    take:
    email           //  string: email address
    email_on_fail   //  string: email address sent on pipeline failure
    plaintext_email // boolean: Send plain-text email instead of HTML
    outdir          //    path: Path to output directory where results will be published
    monochrome_logs // boolean: Disable ANSI colour codes in log output
    hook_url        //  string: hook URL for notifications
    multiqc_report  //  string: Path to MultiQC report

    main:
    summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def multiqc_reports = multiqc_report.toList()

    //
    // Completion email and summary
    //
    workflow.onComplete {
        if (email || email_on_fail) {
            completionEmail(
                summary_params,
                email,
                email_on_fail,
                plaintext_email,
                outdir,
                monochrome_logs,
                multiqc_reports.getVal(),
            )
        }

        completionSummary(monochrome_logs)
        if (hook_url) {
            imNotification(summary_params, hook_url)
        }
    }

    workflow.onError {
        log.error "Pipeline failed. Please refer to troubleshooting docs: https://nf-co.re/docs/usage/troubleshooting"
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// Watch for new files in input directory
//
def watchForNewFiles(initial_channel, input_path) {
    def processed_files = Collections.synchronizedSet(new HashSet())

    // Add initial files to processed set
    initial_channel.subscribe { meta, files ->
        files.each { processed_files.add(it.toString()) }
    }

    // Create a channel that polls for new files
    def watch_channel = Channel
        .interval(params.check_interval)
        .map {
            def new_files = []
            def input_dir = file(input_path)

            if (input_dir.isDirectory()) {
                // Check subdirectories
                input_dir.eachDir { subdir ->
                    if (!subdir.name.startsWith('.')) {
                        subdir.eachFileMatch(~/.*\.fastq(\.gz)?$/) { file ->
                            if (!processed_files.contains(file.toString())) {
                                new_files << [subdir.name, file]
                                processed_files.add(file.toString())
                            }
                        }
                    }
                }

                // Check main directory
                input_dir.eachFileMatch(~/.*\.fastq(\.gz)?$/) { file ->
                    if (!processed_files.contains(file.toString())) {
                        new_files << ['all_samples', file]
                        processed_files.add(file.toString())
                    }
                }
            }

            return new_files
        }
        .flatMap { it }
        .groupTuple()
        .map { sample_id, files ->
            def meta = [
                id: sample_id,
                sample: sample_id,
                single_end: true
            ]

            // Simple paired-end detection
            def r1_files = files.findAll { it.name =~ /[._]R?1[._]/ }
            def r2_files = files.findAll { it.name =~ /[._]R?2[._]/ }

            if (r1_files.size() > 0 && r1_files.size() == r2_files.size()) {
                meta.single_end = false
            }

            return [ meta, files ]
        }

    return initial_channel.mix(watch_channel)
}

//
// Check and validate pipeline parameters
//
def validateInputParameters() {
    genomeExistsError()
}

//
// Validate channels from input samplesheet
//
def validateInputSamplesheet(input) {
    def (metas, fastqs) = input[1..2]

    // Check that multiple runs of the same sample are of the same datatype i.e. single-end / paired-end
    def endedness_ok = metas.collect{ meta -> meta.single_end }.unique().size == 1
    if (!endedness_ok) {
        error("Please check input samplesheet -> Multiple runs of a sample must be of the same datatype i.e. single-end or paired-end: ${metas[0].id}")
    }

    return [ metas[0], fastqs ]
}
//
// Get attribute from genome config file e.g. fasta
//
def getGenomeAttribute(attribute) {
    if (params.genomes && params.genome && params.genomes.containsKey(params.genome)) {
        if (params.genomes[ params.genome ].containsKey(attribute)) {
            return params.genomes[ params.genome ][ attribute ]
        }
    }
    return null
}

//
// Exit pipeline if incorrect --genome key provided
//
def genomeExistsError() {
    if (params.genomes && params.genome && !params.genomes.containsKey(params.genome)) {
        def error_string = "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n" +
            "  Genome '${params.genome}' not found in any config files provided to the pipeline.\n" +
            "  Currently, the available genome keys are:\n" +
            "  ${params.genomes.keySet().join(", ")}\n" +
            "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        error(error_string)
    }
}
//
// Generate methods description for MultiQC
//
def toolCitationText() {
    def citation_text = [
            "Tools used in the workflow included:",
            "FastQC (Andrews 2010),",
            "fastp (Chen et al. 2018),",
            "Kraken2 (Wood et al. 2019),",
            "MultiQC (Ewels et al. 2016)",
            "."
        ].join(' ').trim()

    return citation_text
}

def toolBibliographyText() {
    def reference_text = [
            "<li>Andrews S, (2010) FastQC, URL: https://www.bioinformatics.babraham.ac.uk/projects/fastqc/).</li>",
            "<li>Chen S, Zhou Y, Chen Y, Gu J. fastp: an ultra-fast all-in-one FASTQ preprocessor. Bioinformatics. 2018 Sep 1;34(17):i884-i890. doi: 10.1093/bioinformatics/bty560.</li>",
            "<li>Wood DE, Lu J, Langmead B. Improved metagenomic analysis with Kraken 2. Genome Biol. 2019 Nov 28;20(1):257. doi: 10.1186/s13059-019-1891-0.</li>",
            "<li>Ewels, P., Magnusson, M., Lundin, S., & Käller, M. (2016). MultiQC: summarize analysis results for multiple tools and samples in a single report. Bioinformatics , 32(19), 3047–3048. doi: /10.1093/bioinformatics/btw354</li>"
        ].join(' ').trim()

    return reference_text
}

def methodsDescriptionText(mqc_methods_yaml) {
    // Convert  to a named map so can be used as with familiar NXF ${workflow} variable syntax in the MultiQC YML file
    def meta = [:]
    meta.workflow = workflow.toMap()
    meta["manifest_map"] = workflow.manifest.toMap()

    // Pipeline DOI
    if (meta.manifest_map.doi) {
        // Using a loop to handle multiple DOIs
        // Removing `https://doi.org/` to handle pipelines using DOIs vs DOI resolvers
        // Removing ` ` since the manifest.doi is a string and not a proper list
        def temp_doi_ref = ""
        def manifest_doi = meta.manifest_map.doi.tokenize(",")
        manifest_doi.each { doi_ref ->
            temp_doi_ref += "(doi: <a href=\'https://doi.org/${doi_ref.replace("https://doi.org/", "").replace(" ", "")}\'>${doi_ref.replace("https://doi.org/", "").replace(" ", "")}</a>), "
        }
        meta["doi_text"] = temp_doi_ref.substring(0, temp_doi_ref.length() - 2)
    } else meta["doi_text"] = ""
    meta["nodoi_text"] = meta.manifest_map.doi ? "" : "<li>If available, make sure to update the text to include the Zenodo DOI of version of the pipeline used. </li>"

    // Tool references
    meta["tool_citations"] = toolCitationText()
    meta["tool_bibliography"] = toolBibliographyText()

    def methods_text = mqc_methods_yaml.text

    def engine =  new groovy.text.SimpleTemplateEngine()
    def description_html = engine.createTemplate(methods_text).make(meta)

    return description_html.toString()
}
