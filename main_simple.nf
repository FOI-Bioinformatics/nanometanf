#!/usr/bin/env nextflow

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    foi-bioinformatics/nanometanf
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Simplified main workflow for testing
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Enable DSL2
nextflow.enable.dsl=2

// Import modules
include { FASTP } from './modules/nf-core/fastp/main'
include { MULTIQC } from './modules/nf-core/multiqc/main'

// Parameters
params.input = null
params.outdir = './results'

// Define a simple samplesheet channel
def create_test_channel() {
    return Channel.of([
        [id: 'test_sample', single_end: true], 
        file("$projectDir/tests/test_sample.fastq.gz", checkIfExists: true)
    ])
}

// Main workflow
workflow {
    
    main:
    
    // Create test input channel if no input provided
    if (params.input) {
        // TODO: Parse samplesheet
        ch_input = Channel.empty()
    } else {
        ch_input = create_test_channel()
    }
    
    // Run FASTP for quality filtering
    FASTP(
        ch_input,
        [],     // adapter_fasta
        false,  // discard_trimmed_pass
        false,  // save_trimmed_fail  
        false   // save_merged
    )
    
    // Collect files for MultiQC
    ch_multiqc_files = Channel.empty()
    ch_multiqc_files = ch_multiqc_files.mix(FASTP.out.json.collect{it[1]})
    
    // Run MultiQC
    MULTIQC(
        ch_multiqc_files.collect(),
        [],  // multiqc_config
        [],  // multiqc_custom_config  
        [],  // multiqc_logo
        [],  // multiqc_extra_config
        []   // multiqc_custom_plots
    )
    
    emit:
    fastp_reports = FASTP.out.html
    multiqc_report = MULTIQC.out.report
}