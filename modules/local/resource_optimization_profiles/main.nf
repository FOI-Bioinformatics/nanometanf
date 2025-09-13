process LOAD_OPTIMIZATION_PROFILES {
    tag "optimization_profiles"
    label 'process_single'
    publishDir "${params.outdir}/resource_analysis/profiles", mode: 'copy'

    input:
    val profile_name
    val system_context

    output:
    path "optimization_profiles.json", emit: profiles
    path "active_profile.json", emit: active_profile  
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    #!/usr/bin/env python3
    
    import json
    import os
    from datetime import datetime
    from pathlib import Path
    
    profile_name = "${profile_name}"
    system_context = ${groovy.json.JsonBuilder(system_context).toString()}
    
    def create_optimization_profiles():
        \"\"\"Create comprehensive resource optimization profiles\"\"\"
        
        profiles = {
            'high_throughput': {
                'name': 'High Throughput',
                'description': 'Optimized for maximum processing speed with high resource usage',
                'target_scenario': 'Large-scale batch processing with ample system resources',
                'resource_multipliers': {
                    'cpu_factor': 1.2,
                    'memory_factor': 1.5,
                    'time_factor': 0.8,
                    'parallel_job_factor': 1.5
                },
                'optimization_settings': {
                    'safety_factor': 0.9,           # Use more resources
                    'enable_aggressive_caching': True,
                    'prefer_parallel_processing': True,
                    'gpu_utilization': 'maximum',
                    'io_optimization': 'throughput'
                },
                'tool_specific_configs': {
                    'dorado_basecaller': {
                        'batch_size_multiplier': 1.5,
                        'concurrent_streams': 4,
                        'gpu_memory_utilization': 0.95
                    },
                    'kraken2': {
                        'memory_aggressive': True,
                        'thread_scaling': 'linear',
                        'preload_database': True
                    },
                    'flye': {
                        'memory_multiplier': 2.0,
                        'thread_scaling': 'maximum',
                        'aggressive_optimization': True
                    }
                },
                'performance_targets': {
                    'min_cpu_utilization': 85,
                    'min_memory_utilization': 70,
                    'max_queue_time_minutes': 2
                }
            },
            
            'balanced': {
                'name': 'Balanced Performance',
                'description': 'Balanced resource usage suitable for most scenarios',
                'target_scenario': 'Standard processing with moderate system load',
                'resource_multipliers': {
                    'cpu_factor': 1.0,
                    'memory_factor': 1.0,
                    'time_factor': 1.0,
                    'parallel_job_factor': 1.0
                },
                'optimization_settings': {
                    'safety_factor': 0.8,
                    'enable_aggressive_caching': False,
                    'prefer_parallel_processing': False,
                    'gpu_utilization': 'balanced',
                    'io_optimization': 'balanced'
                },
                'tool_specific_configs': {
                    'dorado_basecaller': {
                        'batch_size_multiplier': 1.0,
                        'concurrent_streams': 2,
                        'gpu_memory_utilization': 0.8
                    },
                    'kraken2': {
                        'memory_aggressive': False,
                        'thread_scaling': 'conservative',
                        'preload_database': False
                    },
                    'flye': {
                        'memory_multiplier': 1.2,
                        'thread_scaling': 'moderate',
                        'aggressive_optimization': False
                    }
                },
                'performance_targets': {
                    'min_cpu_utilization': 60,
                    'min_memory_utilization': 50,
                    'max_queue_time_minutes': 5
                }
            },
            
            'resource_conservative': {
                'name': 'Resource Conservative',
                'description': 'Minimal resource usage for resource-constrained environments',
                'target_scenario': 'Limited system resources or shared computing environments',
                'resource_multipliers': {
                    'cpu_factor': 0.7,
                    'memory_factor': 0.6,
                    'time_factor': 1.5,
                    'parallel_job_factor': 0.5
                },
                'optimization_settings': {
                    'safety_factor': 0.6,
                    'enable_aggressive_caching': False,
                    'prefer_parallel_processing': False,
                    'gpu_utilization': 'conservative',
                    'io_optimization': 'memory_efficient'
                },
                'tool_specific_configs': {
                    'dorado_basecaller': {
                        'batch_size_multiplier': 0.5,
                        'concurrent_streams': 1,
                        'gpu_memory_utilization': 0.6
                    },
                    'kraken2': {
                        'memory_aggressive': False,
                        'thread_scaling': 'minimal',
                        'preload_database': False
                    },
                    'flye': {
                        'memory_multiplier': 0.8,
                        'thread_scaling': 'minimal',
                        'aggressive_optimization': False
                    }
                },
                'performance_targets': {
                    'min_cpu_utilization': 40,
                    'min_memory_utilization': 30,
                    'max_queue_time_minutes': 15
                }
            },
            
            'gpu_optimized': {
                'name': 'GPU Optimized',
                'description': 'Optimized for GPU-accelerated workloads',
                'target_scenario': 'Systems with powerful GPU resources for basecalling',
                'resource_multipliers': {
                    'cpu_factor': 0.8,
                    'memory_factor': 1.2,
                    'time_factor': 0.5,
                    'parallel_job_factor': 1.0
                },
                'optimization_settings': {
                    'safety_factor': 0.85,
                    'enable_aggressive_caching': True,
                    'prefer_parallel_processing': False,  # GPU handles parallelization
                    'gpu_utilization': 'maximum',
                    'io_optimization': 'gpu_focused'
                },
                'tool_specific_configs': {
                    'dorado_basecaller': {
                        'batch_size_multiplier': 2.0,
                        'concurrent_streams': 8,
                        'gpu_memory_utilization': 0.95,
                        'cpu_threads_per_gpu': 4
                    },
                    'kraken2': {
                        'memory_aggressive': False,
                        'thread_scaling': 'moderate',
                        'preload_database': True
                    },
                    'flye': {
                        'memory_multiplier': 1.0,
                        'thread_scaling': 'moderate',
                        'aggressive_optimization': False
                    }
                },
                'performance_targets': {
                    'min_gpu_utilization': 90,
                    'min_cpu_utilization': 50,
                    'min_memory_utilization': 60,
                    'max_queue_time_minutes': 1
                }
            },
            
            'realtime_optimized': {
                'name': 'Real-time Optimized',
                'description': 'Optimized for real-time processing with low latency',
                'target_scenario': 'Real-time nanopore data processing with strict latency requirements',
                'resource_multipliers': {
                    'cpu_factor': 1.1,
                    'memory_factor': 1.3,
                    'time_factor': 0.7,
                    'parallel_job_factor': 1.2
                },
                'optimization_settings': {
                    'safety_factor': 0.9,
                    'enable_aggressive_caching': True,
                    'prefer_parallel_processing': True,
                    'gpu_utilization': 'maximum',
                    'io_optimization': 'latency_focused',
                    'enable_preemptive_scaling': True
                },
                'tool_specific_configs': {
                    'dorado_basecaller': {
                        'batch_size_multiplier': 0.8,  # Smaller batches for lower latency
                        'concurrent_streams': 6,
                        'gpu_memory_utilization': 0.9,
                        'low_latency_mode': True
                    },
                    'kraken2': {
                        'memory_aggressive': True,
                        'thread_scaling': 'aggressive',
                        'preload_database': True,
                        'streaming_mode': True
                    },
                    'filtlong': {
                        'streaming_processing': True,
                        'small_batch_mode': True
                    }
                },
                'performance_targets': {
                    'max_latency_seconds': 30,
                    'min_throughput_files_per_minute': 10,
                    'max_queue_time_minutes': 0.5
                }
            },
            
            'development_testing': {
                'name': 'Development & Testing',
                'description': 'Fast processing for development and testing workflows',
                'target_scenario': 'Development environments with quick iteration needs',
                'resource_multipliers': {
                    'cpu_factor': 0.5,
                    'memory_factor': 0.5,
                    'time_factor': 2.0,
                    'parallel_job_factor': 0.3
                },
                'optimization_settings': {
                    'safety_factor': 0.5,
                    'enable_aggressive_caching': False,
                    'prefer_parallel_processing': False,
                    'gpu_utilization': 'minimal',
                    'io_optimization': 'simple',
                    'enable_debug_mode': True
                },
                'tool_specific_configs': {
                    'dorado_basecaller': {
                        'batch_size_multiplier': 0.2,
                        'concurrent_streams': 1,
                        'gpu_memory_utilization': 0.3,
                        'fast_mode': True
                    },
                    'kraken2': {
                        'memory_aggressive': False,
                        'thread_scaling': 'minimal',
                        'preload_database': False,
                        'sample_mode': True
                    }
                },
                'performance_targets': {
                    'max_resource_usage': 25,
                    'quick_completion': True
                }
            }
        }
        
        return profiles
    
    def select_optimal_profile(profiles, system_context, user_preference=None):
        \"\"\"Select optimal profile based on system context and user preference\"\"\"
        
        if user_preference and user_preference in profiles:
            selected_profile = profiles[user_preference]
            selection_reason = f"User specified profile: {user_preference}"
        else:
            # Auto-select based on system characteristics
            gpu_available = system_context.get('gpu_available', False)
            memory_gb = system_context.get('total_memory_gb', 8)
            cpu_cores = system_context.get('cpu_cores', 4)
            realtime_mode = system_context.get('realtime_mode', False)
            
            if realtime_mode:
                selected_key = 'realtime_optimized'
                selection_reason = "Real-time mode detected"
            elif gpu_available and memory_gb > 16:
                selected_key = 'gpu_optimized'
                selection_reason = "GPU available with sufficient memory"
            elif memory_gb > 32 and cpu_cores > 16:
                selected_key = 'high_throughput'
                selection_reason = "High-resource system detected"
            elif memory_gb < 8 or cpu_cores < 4:
                selected_key = 'resource_conservative'
                selection_reason = "Resource-constrained system detected"
            else:
                selected_key = 'balanced'
                selection_reason = "Standard system configuration"
            
            selected_profile = profiles[selected_key]
            selected_profile['profile_key'] = selected_key
        
        selected_profile['selection_reason'] = selection_reason
        selected_profile['selection_timestamp'] = datetime.now().isoformat()
        
        return selected_profile
    
    def apply_profile_adjustments(profile, system_context):
        \"\"\"Apply system-specific adjustments to the selected profile\"\"\"
        
        adjusted_profile = profile.copy()
        
        # Adjust based on actual system capabilities
        memory_gb = system_context.get('total_memory_gb', 8)
        cpu_cores = system_context.get('cpu_cores', 4)
        current_load = system_context.get('current_load_classification', 'medium')
        
        # Memory-based adjustments
        if memory_gb < 16:
            # Reduce memory factors for low-memory systems
            adjusted_profile['resource_multipliers']['memory_factor'] *= 0.8
            adjusted_profile['optimization_settings']['safety_factor'] *= 0.9
        
        # CPU-based adjustments
        if cpu_cores < 8:
            # Reduce parallelization for low-CPU systems
            adjusted_profile['resource_multipliers']['parallel_job_factor'] *= 0.7
        
        # Load-based adjustments
        if current_load == 'high':
            # Be more conservative under high load
            for factor in ['cpu_factor', 'memory_factor', 'parallel_job_factor']:
                adjusted_profile['resource_multipliers'][factor] *= 0.8
            adjusted_profile['optimization_settings']['safety_factor'] *= 0.9
        
        adjusted_profile['system_adjustments'] = {
            'memory_adjustment': memory_gb < 16,
            'cpu_adjustment': cpu_cores < 8,
            'load_adjustment': current_load == 'high',
            'adjustment_timestamp': datetime.now().isoformat()
        }
        
        return adjusted_profile
    
    # Generate all optimization profiles
    all_profiles = create_optimization_profiles()
    
    # Select optimal profile for current system
    selected_profile = select_optimal_profile(all_profiles, system_context, profile_name if profile_name != 'auto' else None)
    
    # Apply system-specific adjustments
    optimized_profile = apply_profile_adjustments(selected_profile, system_context)
    
    print(f"Resource optimization profile selected: {optimized_profile.get('name', 'Unknown')}")
    print(f"Selection reason: {optimized_profile.get('selection_reason', 'Not specified')}")
    print(f"Profile description: {optimized_profile.get('description', 'No description')}")
    
    # Save all profiles
    with open('optimization_profiles.json', 'w') as f:
        json.dump({
            'available_profiles': all_profiles,
            'profile_metadata': {
                'total_profiles': len(all_profiles),
                'creation_timestamp': datetime.now().isoformat(),
                'system_context': system_context
            }
        }, f, indent=2)
    
    # Save active profile
    with open('active_profile.json', 'w') as f:
        json.dump(optimized_profile, f, indent=2)
    
    print(f"Optimization profiles loaded successfully")
    print(f"Active profile: {optimized_profile.get('profile_key', optimized_profile.get('name'))}")
    
    # Generate versions file
    with open('versions.yml', 'w') as f:
        f.write('''\"${task.process}\":
    python: \"3.9\"
    optimization_profiles: \"1.0\"''')
    """

    stub:
    """
    echo '{"available_profiles": {"balanced": {"name": "Balanced"}}}' > optimization_profiles.json
    echo '{"name": "Balanced", "stub": true}' > active_profile.json
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.9"
        optimization_profiles: "1.0"
    END_VERSIONS
    """
}