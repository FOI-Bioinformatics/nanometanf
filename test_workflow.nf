#!/usr/bin/env nextflow

/*
 * Simple test workflow to verify basic functionality
 */

// Enable DSL2
nextflow.enable.dsl=2

// Parameters
params.outdir = './test_results'
params.input = null

// Simple process for testing
process HELLO {
    container 'ubuntu:20.04'
    
    output:
    stdout
    
    script:
    """
    echo "Hello from Nanometanf pipeline!"
    echo "Testing basic functionality..."
    """
}

// Main workflow
workflow {
    HELLO()
    HELLO.out.view()
}