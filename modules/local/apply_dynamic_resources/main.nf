process APPLY_DYNAMIC_RESOURCES {
    tag "$meta.id"
    label 'process_single'

    input:
    tuple val(meta), path(allocation_file)
    val target_process_name

    output:
    tuple val(meta), val(dynamic_config), emit: config
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    #!/usr/bin/env python3
    
    import json
    import os
    from pathlib import Path
    
    meta = ${groovy.json.JsonBuilder(meta).toString()}
    target_process = "${target_process_name}"
    
    # Load optimal allocation
    with open('${allocation_file}', 'r') as f:
        allocation = json.load(f)
    
    # Extract the Nextflow process configuration
    dynamic_config = allocation.get('nextflow_process_config', {})
    
    print(f"Dynamic resource configuration for {meta['id']} -> {target_process}:")
    for key, value in dynamic_config.items():
        print(f"  {key}: {value}")
    
    # Generate versions file
    with open('versions.yml', 'w') as f:
        f.write('''\"${task.process}\":
    python: \"3.9\"
    dynamic_resources: \"1.0\"''')
    """

    stub:
    """
    echo '{}' > stub_config.json
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.9"
        dynamic_resources: "1.0"
    END_VERSIONS
    """
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    HELPER FUNCTIONS FOR DYNAMIC RESOURCE APPLICATION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

def applyDynamicResources(process_config, sample_meta = null, default_config = [:]) {
    /*
    Apply dynamic resource configuration to a process
    This function merges dynamic configs with default configs and applies them
    */
    
    // Start with default configuration
    def final_config = [:]
    final_config.putAll(default_config)
    
    // Apply dynamic configuration if available
    if (process_config && process_config.size() > 0) {
        final_config.putAll(process_config)
        log.info "Applied dynamic resource allocation for ${sample_meta?.id ?: 'unknown'}: ${final_config}"
    } else {
        log.debug "Using default resource configuration: ${final_config}"
    }
    
    return final_config
}

def configureDynamicProcess(process_name, resource_configs, sample_meta = null) {
    /*
    Configure a specific process with dynamic resources
    */
    
    def process_configs = [:]
    
    resource_configs.subscribe { meta, config ->
        if (meta.id == sample_meta?.id) {
            process_configs[process_name] = config
            
            // Apply the configuration to the process
            withName:process_name {
                cpus = config.cpus ?: 1
                memory = config.memory ?: '4.GB'
                time = config.time ?: '6.h'
                
                if (config.accelerator) {
                    accelerator = config.accelerator
                }
                
                if (config.errorStrategy) {
                    errorStrategy = config.errorStrategy
                }
                
                if (config.maxRetries) {
                    maxRetries = config.maxRetries
                }
            }
        }
    }
    
    return process_configs
}

def createResourceSelector(ch_resource_configs) {
    /*
    Create a resource selector that processes can use to get their optimal configuration
    */
    
    def resource_selector = ch_resource_configs
        .map { meta, config_file ->
            // Parse the configuration file to extract the nextflow config
            def config = readJSON(file: config_file)
            def nextflow_config = config.nextflow_process_config ?: [:]
            
            [ meta, nextflow_config ]
        }
    
    return resource_selector
}

def getOptimalResourceConfig(sample_meta, tool_name, ch_resource_configs, default_config = [:]) {
    /*
    Get optimal resource configuration for a specific sample and tool
    Returns a channel with the configuration
    */
    
    def optimal_config = ch_resource_configs
        .filter { meta, config -> meta.id == sample_meta.id }
        .map { meta, config ->
            // Apply tool-specific adjustments if needed
            def adjusted_config = config.clone()
            
            // Tool-specific resource adjustments
            switch(tool_name) {
                case 'KRAKEN2':
                    // Ensure minimum memory for Kraken2
                    def memory_val = config.memory?.replaceAll(/[^0-9.]/, '')?.toFloat() ?: 4
                    if (memory_val < 16) {
                        adjusted_config.memory = '16.GB'
                    }
                    break
                    
                case 'DORADO_BASECALLER':
                    // Ensure GPU configuration is properly set
                    if (config.accelerator) {
                        adjusted_config.clusterOptions = '--gres=gpu:1'
                    }
                    break
                    
                case 'FLYE':
                case 'MINIASM':
                    // Assembly tools need more time
                    def time_val = config.time?.replaceAll(/[^0-9.]/, '')?.toFloat() ?: 6
                    adjusted_config.time = "${Math.max(time_val, 12)}.h"
                    break
            }
            
            // Merge with defaults
            def final_config = [:]
            final_config.putAll(default_config)
            final_config.putAll(adjusted_config)
            
            [ meta, final_config ]
        }
        .ifEmpty { [ sample_meta, default_config ] }
    
    return optimal_config
}