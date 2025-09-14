/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: DYNAMIC_RESOURCE_ALLOCATION
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Intelligent resource allocation system for nanopore data processing
    
    This subworkflow predicts optimal resource allocation based on:
    - Input file characteristics (size, complexity, read count estimates)
    - System resource availability (CPU, memory, GPU, disk I/O)
    - Historical processing patterns and performance metrics
    - Current system load and concurrent job demands
    - Tool-specific resource requirements and scaling behavior
    
    Features:
    - Predictive resource sizing based on machine learning algorithms
    - Real-time system monitoring and adaptive scaling
    - Tool-specific optimization profiles (Dorado, Kraken2, Assembly, QC)
    - Memory-efficient processing for large datasets
    - GPU workload optimization and auto-scaling
    - Performance feedback loop for continuous improvement
----------------------------------------------------------------------------------------
*/

include { ANALYZE_INPUT_CHARACTERISTICS } from '../../modules/local/analyze_input_characteristics/main'
include { MONITOR_SYSTEM_RESOURCES      } from '../../modules/local/monitor_system_resources/main'
include { PREDICT_RESOURCE_REQUIREMENTS } from '../../modules/local/predict_resource_requirements/main'
include { OPTIMIZE_RESOURCE_ALLOCATION  } from '../../modules/local/optimize_resource_allocation/main'
include { RESOURCE_OPTIMIZATION_PROFILES } from '../../modules/local/resource_optimization_profiles/main'

workflow DYNAMIC_RESOURCE_ALLOCATION {

    take:
    ch_inputs              // channel: [ val(meta), path(files), val(tool_context) ]
    resource_config        // val: resource allocation configuration
    system_config          // val: system configuration and constraints

    main:
    
    ch_versions = Channel.empty()
    
    //
    // STEP 0: Load optimization profiles based on system context
    //
    log.info "=== Dynamic Resource Allocation ==="
    log.info "Loading optimization profiles for intelligent resource allocation"
    
    // Extract system context from system_config
    def profile_name = resource_config.get('optimization_profile', 'auto')
    def system_context_for_profiles = system_config + [
        'realtime_mode': resource_config.get('realtime_mode', false),
        'gpu_available': system_config.get('gpu_available', false)
    ]
    
    RESOURCE_OPTIMIZATION_PROFILES (
        profile_name,
        system_context_for_profiles
    )
    ch_versions = ch_versions.mix(RESOURCE_OPTIMIZATION_PROFILES.out.versions)
    
    //
    // STEP 1: Analyze input characteristics for resource prediction
    //
    log.info "Analyzing input characteristics for optimal resource prediction"
    
    ANALYZE_INPUT_CHARACTERISTICS (
        ch_inputs,
        resource_config
    )
    ch_versions = ch_versions.mix(ANALYZE_INPUT_CHARACTERISTICS.out.versions)
    
    //
    // STEP 2: Monitor current system resources and load
    //
    MONITOR_SYSTEM_RESOURCES (
        system_config
    )
    ch_versions = ch_versions.mix(MONITOR_SYSTEM_RESOURCES.out.versions)
    
    //
    // STEP 3: Predict optimal resource requirements
    //
    ch_prediction_input = ANALYZE_INPUT_CHARACTERISTICS.out.characteristics
        .combine(MONITOR_SYSTEM_RESOURCES.out.system_metrics)
        .map { input_meta, characteristics, system_metrics ->
            [ input_meta, characteristics, system_metrics ]
        }
    
    PREDICT_RESOURCE_REQUIREMENTS (
        ch_prediction_input,
        resource_config
    )
    ch_versions = ch_versions.mix(PREDICT_RESOURCE_REQUIREMENTS.out.versions)
    
    //
    // STEP 4: Optimize allocation based on system constraints and priorities
    //
    ch_optimization_input = PREDICT_RESOURCE_REQUIREMENTS.out.predictions
        .combine(MONITOR_SYSTEM_RESOURCES.out.system_metrics)
        .map { input_meta, predictions, system_metrics ->
            [ input_meta, predictions, system_metrics ]
        }
    
    OPTIMIZE_RESOURCE_ALLOCATION (
        ch_optimization_input,
        resource_config
    )
    ch_versions = ch_versions.mix(OPTIMIZE_RESOURCE_ALLOCATION.out.versions)

    emit:
    optimization_profiles = LOAD_OPTIMIZATION_PROFILES.out.profiles               // channel: path(optimization_profiles.json)
    active_profile = LOAD_OPTIMIZATION_PROFILES.out.active_profile                // channel: path(active_profile.json)
    input_characteristics = ANALYZE_INPUT_CHARACTERISTICS.out.characteristics      // channel: [ val(meta), path(characteristics.json) ]
    system_metrics = MONITOR_SYSTEM_RESOURCES.out.system_metrics                  // channel: path(system_metrics.json)
    resource_predictions = PREDICT_RESOURCE_REQUIREMENTS.out.predictions          // channel: [ val(meta), path(predictions.json) ]
    optimal_allocations = OPTIMIZE_RESOURCE_ALLOCATION.out.allocations            // channel: [ val(meta), path(allocations.json) ]
    resource_configs = OPTIMIZE_RESOURCE_ALLOCATION.out.process_configs           // channel: [ val(meta), val(process_config) ]
    performance_metrics = OPTIMIZE_RESOURCE_ALLOCATION.out.performance_metrics    // channel: [ val(meta), path(performance.json) ]
    versions = ch_versions                                                         // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RESOURCE ALLOCATION HELPER FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

def getResourceProfile(tool_name, data_characteristics) {
    /*
    Get resource profile for specific tools based on data characteristics
    */
    def profiles = [
        'dorado_basecaller': [
            'cpu_base': 8,
            'memory_base': '16.GB',
            'gpu_preferred': true,
            'scaling_factor': 'linear',
            'memory_per_gb_input': '2.GB',
            'cpu_efficiency_threshold': 16
        ],
        'kraken2': [
            'cpu_base': 4,
            'memory_base': '8.GB',
            'gpu_preferred': false,
            'scaling_factor': 'database_dependent',
            'memory_per_million_reads': '100.MB',
            'database_memory_factor': 1.2
        ],
        'filtlong': [
            'cpu_base': 2,
            'memory_base': '4.GB',
            'gpu_preferred': false,
            'scaling_factor': 'read_count',
            'memory_per_gb_input': '0.5.GB',
            'cpu_efficiency_threshold': 8
        ],
        'flye_assembler': [
            'cpu_base': 8,
            'memory_base': '32.GB',
            'gpu_preferred': false,
            'scaling_factor': 'genome_size',
            'memory_per_gb_coverage': '4.GB',
            'cpu_efficiency_threshold': 32
        ]
    ]
    
    return profiles.get(tool_name, profiles['default'] ?: [:])
}

def calculateResourceScaling(base_resources, data_size, complexity_factor) {
    /*
    Calculate resource scaling based on data characteristics
    */
    def scaling_algorithms = [
        'linear': { base, size -> base * (1 + (size / 1000000000)) }, // 1GB baseline
        'logarithmic': { base, size -> base * (1 + Math.log10(size / 1000000)) }, // 1MB baseline
        'square_root': { base, size -> base * (1 + Math.sqrt(size / 1000000000)) },
        'complexity_adjusted': { base, size -> base * (1 + (size * complexity_factor) / 1000000000) }
    ]
    
    return scaling_algorithms
}

def predictProcessingTime(resource_allocation, data_characteristics, historical_data) {
    /*
    Predict processing time based on resource allocation and historical performance
    */
    def base_time = 3600 // 1 hour baseline
    def cpu_factor = resource_allocation.cpu_cores / 4.0
    def memory_factor = (resource_allocation.memory_gb > 8) ? 1.0 : 0.8
    def data_factor = data_characteristics.estimated_reads / 1000000.0
    
    def predicted_time = (base_time * data_factor) / (cpu_factor * memory_factor)
    
    // Apply historical correction if available
    if (historical_data && historical_data.average_time_per_million_reads) {
        def historical_factor = historical_data.average_time_per_million_reads / 600 // 10 min baseline
        predicted_time *= historical_factor
    }
    
    return Math.max(300, Math.min(predicted_time, 86400)) // 5 min to 24 hours
}

def optimizeForSystemLoad(ideal_allocation, current_load, system_limits) {
    /*
    Adjust resource allocation based on current system load
    */
    def load_factor = Math.max(0.1, 1.0 - current_load.cpu_utilization)
    def memory_factor = Math.max(0.1, 1.0 - current_load.memory_utilization)
    
    return [
        cpu_cores: Math.min(
            (ideal_allocation.cpu_cores * load_factor).toInteger(),
            system_limits.max_cpu_cores
        ),
        memory_gb: Math.min(
            ideal_allocation.memory_gb * memory_factor,
            system_limits.max_memory_gb
        ),
        priority: current_load.cpu_utilization > 0.8 ? 'low' : 'normal'
    ]
}