process OPTIMIZE_RESOURCE_ALLOCATION {
    tag "$meta.id"
    label 'process_single'
    publishDir "${params.outdir}/resource_analysis", mode: 'copy'

    input:
    tuple val(meta), path(predictions), path(system_metrics)
    val resource_config

    output:
    tuple val(meta), path("${meta.id}_optimal_allocation.json"), emit: allocations
    tuple val(meta), val(process_config), emit: process_configs
    tuple val(meta), path("${meta.id}_performance_metrics.json"), emit: performance_metrics
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    
    """
    #!/usr/bin/env python3
    
    import json
    import os
    import math
    from datetime import datetime
    from pathlib import Path
    
    # Load input data
    meta = ${groovy.json.JsonBuilder(meta).toString()}
    resource_config = ${groovy.json.JsonBuilder(resource_config).toString()}
    
    # Load predictions and system metrics
    with open('${predictions}', 'r') as f:
        predictions = json.load(f)
    
    with open('${system_metrics}', 'r') as f:
        system_metrics = json.load(f)
    
    def calculate_system_capacity():
        \"\"\"Calculate current system capacity and constraints\"\"\"
        cpu_info = system_metrics.get('cpu', {})
        memory_info = system_metrics.get('memory', {})
        current_load = system_metrics.get('current_load', {})
        
        # Calculate available resources considering current load
        total_cores = cpu_info.get('logical_cores', 4)
        total_memory_gb = memory_info.get('total_gb', 8)
        available_memory_gb = memory_info.get('available_gb', 4)
        
        cpu_utilization = current_load.get('cpu_utilization_percent', 0) / 100.0
        memory_utilization = current_load.get('memory_utilization_percent', 0) / 100.0
        
        # Apply safety factors
        safety_factor = resource_config.get('safety_factor', 0.8)
        
        capacity = {
            'max_cpu_cores': max(1, int(total_cores * safety_factor)),
            'max_memory_gb': max(2, available_memory_gb * safety_factor),
            'cpu_pressure': cpu_utilization > 0.75,
            'memory_pressure': memory_utilization > 0.8,
            'load_classification': current_load.get('load_classification', 'medium'),
            'available_cpu_cores': max(1, int(total_cores * (1 - cpu_utilization) * safety_factor)),
            'available_memory_gb': max(2, available_memory_gb * safety_factor)
        }
        
        return capacity
    
    def optimize_cpu_allocation(predicted_cores, system_capacity, priority):
        \"\"\"Optimize CPU allocation based on system constraints\"\"\"
        max_cores = system_capacity['max_cpu_cores']
        available_cores = system_capacity['available_cpu_cores']
        
        # Priority-based allocation
        priority_factors = {
            'high': 1.0,     # Get full requested resources
            'normal': 0.8,   # Get 80% of requested resources
            'low': 0.6       # Get 60% of requested resources
        }
        
        priority_factor = priority_factors.get(priority, 0.8)
        
        # Apply priority adjustment
        adjusted_cores = int(predicted_cores * priority_factor)
        
        # System constraint checks
        if system_capacity['cpu_pressure']:
            # Reduce allocation under high CPU pressure
            adjusted_cores = min(adjusted_cores, max(1, available_cores // 2))
        else:
            # Normal allocation up to available cores
            adjusted_cores = min(adjusted_cores, available_cores)
        
        # Ensure minimum and maximum bounds
        final_cores = max(1, min(adjusted_cores, max_cores))
        
        return {
            'allocated_cores': final_cores,
            'requested_cores': predicted_cores,
            'priority_adjustment': priority_factor,
            'constraint_limited': final_cores < predicted_cores,
            'allocation_efficiency': final_cores / predicted_cores if predicted_cores > 0 else 1.0
        }
    
    def optimize_memory_allocation(predicted_memory_gb, system_capacity, priority):
        \"\"\"Optimize memory allocation based on system constraints\"\"\"
        max_memory = system_capacity['max_memory_gb']
        available_memory = system_capacity['available_memory_gb']
        
        # Priority-based allocation
        priority_factors = {
            'high': 1.0,
            'normal': 0.85,
            'low': 0.7
        }
        
        priority_factor = priority_factors.get(priority, 0.85)
        
        # Apply priority adjustment
        adjusted_memory = predicted_memory_gb * priority_factor
        
        # System constraint checks
        if system_capacity['memory_pressure']:
            # Conservative allocation under memory pressure
            adjusted_memory = min(adjusted_memory, available_memory * 0.5)
        else:
            # Normal allocation up to available memory
            adjusted_memory = min(adjusted_memory, available_memory)
        
        # Ensure minimum and maximum bounds
        final_memory = max(2, min(adjusted_memory, max_memory))
        
        return {
            'allocated_memory_gb': round(final_memory, 1),
            'requested_memory_gb': predicted_memory_gb,
            'priority_adjustment': priority_factor,
            'constraint_limited': final_memory < predicted_memory_gb,
            'allocation_efficiency': final_memory / predicted_memory_gb if predicted_memory_gb > 0 else 1.0
        }
    
    def optimize_gpu_allocation(tool_context, system_capacity):
        \"\"\"Optimize GPU allocation based on tool requirements and availability\"\"\"
        gpu_info = system_metrics.get('gpu', {})
        tool_name = tool_context.get('tool_name', 'unknown')
        
        gpu_allocation = {
            'gpu_enabled': False,
            'gpu_devices': None,
            'gpu_memory_gb': 0,
            'acceleration_factor': 1.0
        }
        
        # Check if GPU is beneficial for this tool
        gpu_beneficial_tools = ['dorado_basecaller', 'guppy_basecaller']
        
        if tool_name in gpu_beneficial_tools and gpu_info.get('gpu_available'):
            nvidia_gpus = gpu_info.get('nvidia_gpus', [])
            apple_gpus = gpu_info.get('apple_gpus', [])
            
            if nvidia_gpus:
                # Use NVIDIA GPU
                gpu_allocation['gpu_enabled'] = True
                gpu_allocation['gpu_devices'] = 'cuda:all'
                gpu_allocation['gpu_memory_gb'] = sum(gpu['memory_total_mb'] for gpu in nvidia_gpus) / 1024
                gpu_allocation['acceleration_factor'] = 5.0  # 5x speedup estimate
            elif apple_gpus:
                # Use Apple Silicon GPU
                gpu_allocation['gpu_enabled'] = True
                gpu_allocation['gpu_devices'] = 'metal'
                gpu_allocation['gpu_memory_gb'] = 'shared'  # Apple Silicon shares system memory
                gpu_allocation['acceleration_factor'] = 3.0  # 3x speedup estimate
        
        return gpu_allocation
    
    def calculate_optimal_parallelization(predictions, optimized_resources, tool_context):
        \"\"\"Calculate optimal parallelization strategy\"\"\"
        tool_name = tool_context.get('tool_name', 'unknown')
        allocated_cores = optimized_resources['cpu']['allocated_cores']
        
        # Tool-specific parallelization strategies
        parallelization_profiles = {
            'dorado_basecaller': {
                'max_parallel_jobs': 1,  # GPU-bound, single job optimal
                'thread_scaling': 'linear',
                'batch_optimization': True
            },
            'kraken2': {
                'max_parallel_jobs': min(4, allocated_cores // 2),
                'thread_scaling': 'diminishing',
                'memory_per_job': 8  # GB
            },
            'filtlong': {
                'max_parallel_jobs': min(allocated_cores, 8),
                'thread_scaling': 'linear',
                'io_bound': True
            },
            'fastp': {
                'max_parallel_jobs': min(allocated_cores // 2, 4),
                'thread_scaling': 'linear',
                'thread_optimal': 4
            },
            'flye': {
                'max_parallel_jobs': 1,  # Single-threaded assembly
                'thread_scaling': 'internal',
                'cpu_intensive': True
            },
            'miniasm': {
                'max_parallel_jobs': 2,
                'thread_scaling': 'limited',
                'memory_intensive': True
            }
        }
        
        profile = parallelization_profiles.get(tool_name, parallelization_profiles.get('filtlong'))
        
        # Calculate optimal job configuration
        max_jobs = profile.get('max_parallel_jobs', 1)
        
        if profile.get('memory_per_job'):
            # Memory-limited parallelization
            memory_limited_jobs = int(optimized_resources['memory']['allocated_memory_gb'] / profile['memory_per_job'])
            max_jobs = min(max_jobs, memory_limited_jobs)
        
        threads_per_job = max(1, allocated_cores // max(max_jobs, 1))
        
        return {
            'parallel_jobs': max_jobs,
            'threads_per_job': threads_per_job,
            'total_threads': max_jobs * threads_per_job,
            'parallelization_strategy': profile.get('thread_scaling', 'linear'),
            'optimization_notes': profile
        }
    
    def generate_process_configuration(optimized_resources, parallelization, tool_context):
        \"\"\"Generate Nextflow process configuration\"\"\"
        cpu_config = optimized_resources['cpu']
        memory_config = optimized_resources['memory']
        gpu_config = optimized_resources['gpu']
        
        # Base process configuration
        process_config = {
            'cpus': cpu_config['allocated_cores'],
            'memory': f"{memory_config['allocated_memory_gb']}.GB",
            'time': f"{optimized_resources['runtime']['adjusted_time_hours']:.1f}h"
        }
        
        # Add GPU configuration if enabled
        if gpu_config['gpu_enabled']:
            if 'nvidia' in str(gpu_config['gpu_devices']):
                process_config['accelerator'] = [1, 'nvidia-tesla-v100']  # Generic NVIDIA config
            else:
                process_config['accelerator'] = [1, 'apple-silicon-gpu']  # Apple Silicon
        
        # Add tool-specific configurations
        tool_name = tool_context.get('tool_name', 'unknown')
        
        if tool_name == 'kraken2':
            # Kraken2 needs significant memory
            process_config['memory'] = f"{max(16, memory_config['allocated_memory_gb'])}.GB"
        elif tool_name in ['flye', 'miniasm']:
            # Assembly tools need extra time
            extended_time = optimized_resources['runtime']['adjusted_time_hours'] * 1.5
            process_config['time'] = f"{extended_time:.1f}h"
        
        # Add retry and error strategies
        process_config['errorStrategy'] = 'retry'
        process_config['maxRetries'] = 2
        
        return process_config
    
    def calculate_performance_metrics(predictions, optimized_resources, system_capacity):
        \"\"\"Calculate performance and efficiency metrics\"\"\"
        cpu_efficiency = optimized_resources['cpu']['allocation_efficiency']
        memory_efficiency = optimized_resources['memory']['allocation_efficiency']
        
        # Resource utilization scores
        cpu_utilization = optimized_resources['cpu']['allocated_cores'] / system_capacity['max_cpu_cores']
        memory_utilization = optimized_resources['memory']['allocated_memory_gb'] / system_capacity['max_memory_gb']
        
        # Performance predictions
        baseline_runtime = predictions['predictions']['runtime_estimates']['predicted_runtime_hours']
        
        # Apply acceleration factors
        gpu_factor = optimized_resources['gpu']['acceleration_factor']
        cpu_factor = optimized_resources['cpu']['allocated_cores'] / predictions['predictions']['cpu_requirements']['predicted_cores']
        
        adjusted_runtime = baseline_runtime / (gpu_factor * min(cpu_factor, 2.0))  # Cap CPU scaling benefit
        
        performance_metrics = {
            'resource_efficiency': {
                'cpu_efficiency': round(cpu_efficiency, 3),
                'memory_efficiency': round(memory_efficiency, 3),
                'overall_efficiency': round((cpu_efficiency + memory_efficiency) / 2, 3)
            },
            'system_utilization': {
                'cpu_utilization': round(cpu_utilization, 3),
                'memory_utilization': round(memory_utilization, 3),
                'resource_pressure': system_capacity['cpu_pressure'] or system_capacity['memory_pressure']
            },
            'performance_predictions': {
                'baseline_runtime_hours': round(baseline_runtime, 2),
                'optimized_runtime_hours': round(adjusted_runtime, 2),
                'speedup_factor': round(baseline_runtime / adjusted_runtime, 2) if adjusted_runtime > 0 else 1.0,
                'gpu_acceleration': optimized_resources['gpu']['gpu_enabled']
            },
            'optimization_summary': {
                'cpu_constraint_limited': optimized_resources['cpu']['constraint_limited'],
                'memory_constraint_limited': optimized_resources['memory']['constraint_limited'],
                'system_load_impact': system_capacity['load_classification'],
                'allocation_confidence': predictions['confidence_metrics']['confidence_level']
            }
        }
        
        return performance_metrics
    
    # Main optimization logic
    print(f"Optimizing resource allocation for {meta['id']}")
    
    # Extract key information
    tool_context = predictions.get('tool_context', {})
    cpu_prediction = predictions['predictions']['cpu_requirements']['predicted_cores']
    memory_prediction = predictions['predictions']['memory_requirements']['predicted_memory_gb']
    priority = predictions['recommendations'].get('priority_level', 'normal')
    
    print(f"Tool: {tool_context.get('tool_name', 'unknown')}")
    print(f"Predicted requirements - CPU: {cpu_prediction} cores, Memory: {memory_prediction:.1f} GB")
    print(f"Priority: {priority}")
    
    # Calculate system capacity
    system_capacity = calculate_system_capacity()
    print(f"System capacity - CPU: {system_capacity['available_cpu_cores']} cores, Memory: {system_capacity['available_memory_gb']:.1f} GB")
    
    # Optimize resource allocations
    cpu_optimization = optimize_cpu_allocation(cpu_prediction, system_capacity, priority)
    memory_optimization = optimize_memory_allocation(memory_prediction, system_capacity, priority)
    gpu_optimization = optimize_gpu_allocation(tool_context, system_capacity)
    
    # Calculate runtime adjustments
    runtime_optimization = {
        'baseline_time_hours': predictions['predictions']['runtime_estimates']['predicted_runtime_hours'],
        'adjusted_time_hours': predictions['predictions']['runtime_estimates']['predicted_runtime_hours'] / gpu_optimization['acceleration_factor']
    }
    
    # Combine optimized resources
    optimized_resources = {
        'cpu': cpu_optimization,
        'memory': memory_optimization,
        'gpu': gpu_optimization,
        'runtime': runtime_optimization
    }
    
    # Calculate optimal parallelization
    parallelization = calculate_optimal_parallelization(predictions, optimized_resources, tool_context)
    
    # Generate process configuration
    process_config = generate_process_configuration(optimized_resources, parallelization, tool_context)
    
    # Calculate performance metrics
    performance_metrics = calculate_performance_metrics(predictions, optimized_resources, system_capacity)
    
    # Compile final allocation
    optimal_allocation = {
        'sample_id': meta['id'],
        'optimization_timestamp': datetime.now().isoformat(),
        'tool_context': tool_context,
        'system_capacity': system_capacity,
        'original_predictions': {
            'cpu_cores': cpu_prediction,
            'memory_gb': memory_prediction,
            'runtime_hours': predictions['predictions']['runtime_estimates']['predicted_runtime_hours']
        },
        'optimized_allocation': {
            'cpu_cores': cpu_optimization['allocated_cores'],
            'memory_gb': memory_optimization['allocated_memory_gb'],
            'gpu_enabled': gpu_optimization['gpu_enabled'],
            'estimated_runtime_hours': runtime_optimization['adjusted_time_hours']
        },
        'parallelization_strategy': parallelization,
        'optimization_details': optimized_resources,
        'performance_predictions': performance_metrics['performance_predictions'],
        'nextflow_process_config': process_config
    }
    
    # Save optimal allocation
    output_file = f"{meta['id']}_optimal_allocation.json"
    with open(output_file, 'w') as f:
        json.dump(optimal_allocation, f, indent=2)
    
    # Save performance metrics
    performance_file = f"{meta['id']}_performance_metrics.json"
    with open(performance_file, 'w') as f:
        json.dump(performance_metrics, f, indent=2)
    
    print(f"Optimization complete for {meta['id']}:")
    print(f"  Allocated CPU cores: {cpu_optimization['allocated_cores']} (requested: {cpu_prediction})")
    print(f"  Allocated memory: {memory_optimization['allocated_memory_gb']:.1f} GB (requested: {memory_prediction:.1f} GB)")
    print(f"  GPU acceleration: {'enabled' if gpu_optimization['gpu_enabled'] else 'disabled'}")
    print(f"  Estimated runtime: {runtime_optimization['adjusted_time_hours']:.1f} hours")
    print(f"  Resource efficiency: {performance_metrics['resource_efficiency']['overall_efficiency']:.2f}")
    
    # Generate versions file
    with open('versions.yml', 'w') as f:
        f.write('''\"${task.process}\":
    python: \"3.9\"
    resource_optimization: \"1.0\"''')
    """

    stub:
    """
    echo '{"sample_id": "${meta.id}", "stub": true, "optimized_allocation": {"cpu_cores": 4, "memory_gb": 8}}' > ${meta.id}_optimal_allocation.json
    echo '{"resource_efficiency": {"overall_efficiency": 0.8}}' > ${meta.id}_performance_metrics.json
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.9"
        resource_optimization: "1.0"
    END_VERSIONS
    """
}