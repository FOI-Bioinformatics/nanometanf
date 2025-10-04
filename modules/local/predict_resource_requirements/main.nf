process PREDICT_RESOURCE_REQUIREMENTS {
    tag "$meta.id"
    label 'process_single'
    publishDir "${params.outdir}/resource_analysis", mode: 'copy'

    input:
    tuple val(meta), path(characteristics), path(system_metrics)
    val resource_config

    output:
    tuple val(meta), path("${meta.id}_resource_predictions.json"), emit: predictions
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
    import numpy as np
    from datetime import datetime
    from pathlib import Path
    
    # Load input data
    meta = json.loads('${new groovy.json.JsonBuilder(meta).toString()}')
    resource_config = json.loads('${new groovy.json.JsonBuilder(resource_config).toString()}')
    
    # Load characteristics and system metrics
    with open('${characteristics}', 'r') as f:
        characteristics = json.load(f)
    
    with open('${system_metrics}', 'r') as f:
        system_metrics = json.load(f)
    
    def predict_cpu_requirements(characteristics, tool_context):
        \"\"\"Predict optimal CPU requirements based on input characteristics\"\"\"
        tool_name = tool_context.get('tool_name', 'unknown')
        
        # Base CPU requirements per tool
        base_cpu_requirements = {
            'dorado_basecaller': {
                'base_cores': 4,
                'scaling_factor': 0.1,  # cores per GB input
                'max_cores': 16,
                'gpu_factor': 0.5  # reduce CPU when GPU available
            },
            'kraken2': {
                'base_cores': 2,
                'scaling_factor': 0.05,  # cores per million reads
                'max_cores': 8,
                'memory_bound': True
            },
            'filtlong': {
                'base_cores': 1,
                'scaling_factor': 0.02,  # cores per GB input
                'max_cores': 4,
                'io_bound': True
            },
            'fastp': {
                'base_cores': 2,
                'scaling_factor': 0.03,
                'max_cores': 6,
                'thread_efficient': True
            },
            'flye': {
                'base_cores': 8,
                'scaling_factor': 0.5,  # cores per GB coverage
                'max_cores': 32,
                'memory_intensive': True
            },
            'miniasm': {
                'base_cores': 4,
                'scaling_factor': 0.2,
                'max_cores': 16,
                'cpu_intensive': True
            }
        }
        
        profile = base_cpu_requirements.get(tool_name, base_cpu_requirements.get('filtlong'))
        
        # Calculate based on data size
        base_cores = profile['base_cores']
        data_size_gb = characteristics.get('total_size_gb', 1)
        estimated_reads_millions = characteristics.get('total_estimated_reads', 1000000) / 1000000
        
        if tool_name in ['kraken2', 'fastp']:
            scaling_input = estimated_reads_millions
        else:
            scaling_input = data_size_gb
        
        predicted_cores = base_cores + (scaling_input * profile['scaling_factor'])
        
        # Apply complexity adjustment
        complexity_score = characteristics.get('complexity_metrics', {}).get('overall_complexity', 1.0)
        predicted_cores *= complexity_score
        
        # GPU adjustment for basecalling
        if tool_name == 'dorado_basecaller' and system_metrics.get('gpu', {}).get('gpu_available'):
            predicted_cores *= profile['gpu_factor']
        
        # Cap at maximum
        predicted_cores = min(predicted_cores, profile['max_cores'])
        predicted_cores = max(1, int(predicted_cores))
        
        return {
            'predicted_cores': predicted_cores,
            'base_cores': base_cores,
            'scaling_factor': profile['scaling_factor'],
            'complexity_adjustment': complexity_score,
            'tool_profile': profile
        }
    
    def predict_memory_requirements(characteristics, tool_context):
        \"\"\"Predict optimal memory requirements\"\"\"
        tool_name = tool_context.get('tool_name', 'unknown')
        
        # Base memory requirements per tool (GB)
        base_memory_requirements = {
            'dorado_basecaller': {
                'base_memory_gb': 8,
                'memory_per_gb_input': 1.5,
                'max_memory_gb': 64,
                'gpu_memory_factor': 0.7
            },
            'kraken2': {
                'base_memory_gb': 16,  # Database dependent
                'memory_per_million_reads': 0.1,
                'max_memory_gb': 128,
                'database_factor': 1.2
            },
            'filtlong': {
                'base_memory_gb': 4,
                'memory_per_gb_input': 0.8,
                'max_memory_gb': 32,
                'read_buffer_factor': 1.1
            },
            'fastp': {
                'base_memory_gb': 2,
                'memory_per_gb_input': 0.5,
                'max_memory_gb': 16,
                'compression_factor': 0.8
            },
            'flye': {
                'base_memory_gb': 32,
                'memory_per_gb_coverage': 8,
                'max_memory_gb': 256,
                'assembly_overhead': 2.0
            },
            'miniasm': {
                'base_memory_gb': 16,
                'memory_per_gb_input': 4,
                'max_memory_gb': 128,
                'overlap_memory': 1.5
            }
        }
        
        profile = base_memory_requirements.get(tool_name, base_memory_requirements.get('filtlong'))
        
        base_memory = profile['base_memory_gb']
        data_size_gb = characteristics.get('total_size_gb', 1)
        estimated_reads_millions = characteristics.get('total_estimated_reads', 1000000) / 1000000
        
        # Tool-specific memory calculation
        if tool_name == 'kraken2':
            memory_scaling = estimated_reads_millions * profile['memory_per_million_reads']
            # Add database memory requirement
            database_memory = base_memory * profile.get('database_factor', 1.2)
            predicted_memory = database_memory + memory_scaling
        elif tool_name in ['flye', 'miniasm']:
            # Assembly tools scale with genome coverage
            estimated_coverage = min(data_size_gb / 0.005, 100)  # Assume 5MB genome, cap at 100x
            predicted_memory = base_memory + (estimated_coverage * profile.get('memory_per_gb_coverage', 4))
        else:
            predicted_memory = base_memory + (data_size_gb * profile.get('memory_per_gb_input', 1))
        
        # Apply complexity and quality adjustments
        complexity_score = characteristics.get('complexity_metrics', {}).get('overall_complexity', 1.0)
        predicted_memory *= complexity_score
        
        # GPU memory adjustment for basecalling
        if tool_name == 'dorado_basecaller' and system_metrics.get('gpu', {}).get('gpu_available'):
            predicted_memory *= profile.get('gpu_memory_factor', 0.7)
        
        # Apply overhead factors
        overhead_factor = profile.get('assembly_overhead', 1.0)
        predicted_memory *= overhead_factor
        
        # Cap at maximum
        predicted_memory = min(predicted_memory, profile['max_memory_gb'])
        predicted_memory = max(2, predicted_memory)  # Minimum 2GB
        
        return {
            'predicted_memory_gb': round(predicted_memory, 1),
            'base_memory_gb': base_memory,
            'scaling_component': round(predicted_memory - base_memory, 1),
            'complexity_adjustment': complexity_score,
            'tool_profile': profile
        }
    
    def predict_runtime_requirements(characteristics, cpu_prediction, memory_prediction, tool_context):
        \"\"\"Predict processing time and resource duration\"\"\"
        tool_name = tool_context.get('tool_name', 'unknown')
        
        # Base processing times (seconds per million reads/GB)
        processing_rates = {
            'dorado_basecaller': {
                'cpu_rate': 1800,  # seconds per GB on CPU
                'gpu_rate': 300,   # seconds per GB on GPU
                'startup_time': 120
            },
            'kraken2': {
                'cpu_rate': 60,    # seconds per million reads
                'startup_time': 30,
                'database_load_time': 120
            },
            'filtlong': {
                'cpu_rate': 180,   # seconds per GB
                'startup_time': 10
            },
            'fastp': {
                'cpu_rate': 120,   # seconds per GB
                'startup_time': 5
            },
            'flye': {
                'cpu_rate': 3600,  # seconds per GB coverage
                'startup_time': 300
            },
            'miniasm': {
                'cpu_rate': 1800,  # seconds per GB
                'startup_time': 60
            }
        }
        
        profile = processing_rates.get(tool_name, processing_rates.get('filtlong'))
        
        data_size_gb = characteristics.get('total_size_gb', 1)
        estimated_reads_millions = characteristics.get('total_estimated_reads', 1000000) / 1000000
        
        # Calculate base processing time
        if tool_name == 'kraken2':
            processing_input = estimated_reads_millions
        elif tool_name in ['flye']:
            estimated_coverage = min(data_size_gb / 0.005, 100)
            processing_input = estimated_coverage
        else:
            processing_input = data_size_gb
        
        # Choose rate based on GPU availability
        if tool_name == 'dorado_basecaller' and system_metrics.get('gpu', {}).get('gpu_available'):
            rate = profile['gpu_rate']
        else:
            rate = profile['cpu_rate']
        
        base_time = processing_input * rate
        startup_time = profile.get('startup_time', 30)
        
        # Apply CPU scaling (more cores = faster processing)
        cpu_cores = cpu_prediction['predicted_cores']
        parallelization_efficiency = min(cpu_cores / 4, 4)  # Efficiency drops after 16 cores
        scaled_time = base_time / parallelization_efficiency
        
        total_time = startup_time + scaled_time
        
        # Add database load time for kraken2
        if tool_name == 'kraken2':
            total_time += profile.get('database_load_time', 120)
        
        # Apply complexity adjustment
        complexity_score = characteristics.get('complexity_metrics', {}).get('overall_complexity', 1.0)
        total_time *= complexity_score
        
        return {
            'predicted_runtime_seconds': int(total_time),
            'predicted_runtime_minutes': round(total_time / 60, 1),
            'predicted_runtime_hours': round(total_time / 3600, 2),
            'base_processing_time': int(base_time),
            'startup_time': startup_time,
            'parallelization_efficiency': round(parallelization_efficiency, 2)
        }
    
    def predict_io_requirements(characteristics, tool_context):
        \"\"\"Predict I/O requirements and recommendations\"\"\"
        tool_name = tool_context.get('tool_name', 'unknown')
        
        data_size_gb = characteristics.get('total_size_gb', 1)
        file_count = characteristics.get('file_count', 1)
        
        # I/O patterns per tool
        io_patterns = {
            'dorado_basecaller': {
                'read_intensity': 'high',    # Reading POD5 files
                'write_intensity': 'medium', # Writing FASTQ
                'random_access': True,
                'temp_space_factor': 0.5
            },
            'kraken2': {
                'read_intensity': 'medium',
                'write_intensity': 'low',
                'random_access': True,      # Database access
                'temp_space_factor': 0.1
            },
            'filtlong': {
                'read_intensity': 'high',
                'write_intensity': 'medium',
                'sequential': True,
                'temp_space_factor': 0.2
            },
            'fastp': {
                'read_intensity': 'high',
                'write_intensity': 'medium',
                'sequential': True,
                'temp_space_factor': 0.3
            },
            'flye': {
                'read_intensity': 'high',
                'write_intensity': 'high',   # Assembly graph and contigs
                'random_access': True,
                'temp_space_factor': 2.0     # Significant temp space
            },
            'miniasm': {
                'read_intensity': 'high',
                'write_intensity': 'medium',
                'sequential': False,
                'temp_space_factor': 1.0
            }
        }
        
        pattern = io_patterns.get(tool_name, io_patterns.get('filtlong'))
        
        # Calculate temp space requirements
        temp_space_gb = data_size_gb * pattern.get('temp_space_factor', 0.5)
        
        # Calculate I/O throughput requirements
        io_throughput = {
            'high': 200,    # MB/s
            'medium': 100,  # MB/s
            'low': 50       # MB/s
        }
        
        read_throughput = io_throughput.get(pattern['read_intensity'], 100)
        write_throughput = io_throughput.get(pattern['write_intensity'], 100)
        
        return {
            'temp_space_gb': round(temp_space_gb, 1),
            'read_throughput_mb_s': read_throughput,
            'write_throughput_mb_s': write_throughput,
            'io_pattern': pattern,
            'multiple_files': file_count > 1,
            'concurrent_io': file_count > 4
        }
    
    def generate_resource_confidence_score(characteristics, system_metrics, predictions):
        \"\"\"Generate confidence score for resource predictions\"\"\"
        confidence_factors = []
        
        # Data completeness factor
        required_fields = ['total_size_gb', 'total_estimated_reads', 'file_count']
        completeness = sum(1 for field in required_fields if characteristics.get(field, 0) > 0) / len(required_fields)
        confidence_factors.append(completeness)
        
        # System metrics availability
        system_completeness = 1.0 if system_metrics.get('cpu') and system_metrics.get('memory') else 0.5
        confidence_factors.append(system_completeness)
        
        # File type certainty
        file_types = [f.get('file_type', 'unknown') for f in characteristics.get('file_details', [])]
        type_certainty = sum(1 for ft in file_types if ft != 'unknown') / max(len(file_types), 1)
        confidence_factors.append(type_certainty)
        
        # Size reasonableness (not too small or too large)
        size_gb = characteristics.get('total_size_gb', 1)
        size_factor = 1.0
        if size_gb < 0.01:  # Very small files
            size_factor = 0.7
        elif size_gb > 100:  # Very large files
            size_factor = 0.8
        confidence_factors.append(size_factor)
        
        # Calculate overall confidence
        overall_confidence = sum(confidence_factors) / len(confidence_factors)
        
        return {
            'confidence_score': round(overall_confidence, 3),
            'confidence_level': 'high' if overall_confidence > 0.8 else 'medium' if overall_confidence > 0.6 else 'low',
            'factors': {
                'data_completeness': round(completeness, 3),
                'system_metrics_quality': round(system_completeness, 3),
                'file_type_certainty': round(type_certainty, 3),
                'size_reasonableness': round(size_factor, 3)
            }
        }
    
    # Generate predictions
    print(f"Predicting resource requirements for {meta['id']}")
    
    tool_context = characteristics.get('tool_context', {})
    print(f"Tool context: {tool_context}")
    
    # Run prediction algorithms
    cpu_prediction = predict_cpu_requirements(characteristics, tool_context)
    memory_prediction = predict_memory_requirements(characteristics, tool_context)
    runtime_prediction = predict_runtime_requirements(characteristics, cpu_prediction, memory_prediction, tool_context)
    io_prediction = predict_io_requirements(characteristics, tool_context)
    
    # Generate confidence metrics
    confidence_metrics = generate_resource_confidence_score(characteristics, system_metrics, {
        'cpu': cpu_prediction,
        'memory': memory_prediction,
        'runtime': runtime_prediction,
        'io': io_prediction
    })
    
    # Compile final predictions
    resource_predictions = {
        'sample_id': meta['id'],
        'prediction_timestamp': datetime.now().isoformat(),
        'tool_context': tool_context,
        'input_characteristics_summary': {
            'total_size_gb': characteristics.get('total_size_gb'),
            'total_estimated_reads': characteristics.get('total_estimated_reads'),
            'file_count': characteristics.get('file_count'),
            'complexity_score': characteristics.get('complexity_metrics', {}).get('overall_complexity')
        },
        'system_context_summary': {
            'cpu_cores_available': system_metrics.get('cpu', {}).get('logical_cores'),
            'memory_gb_available': system_metrics.get('memory', {}).get('available_gb'),
            'gpu_available': system_metrics.get('gpu', {}).get('gpu_available'),
            'current_load': system_metrics.get('current_load', {}).get('load_classification')
        },
        'predictions': {
            'cpu_requirements': cpu_prediction,
            'memory_requirements': memory_prediction,
            'runtime_estimates': runtime_prediction,
            'io_requirements': io_prediction
        },
        'confidence_metrics': confidence_metrics,
        'recommendations': {
            'optimal_cpu_cores': cpu_prediction['predicted_cores'],
            'optimal_memory_gb': memory_prediction['predicted_memory_gb'],
            'estimated_runtime_hours': runtime_prediction['predicted_runtime_hours'],
            'temp_space_gb': io_prediction['temp_space_gb'],
            'gpu_acceleration': tool_context.get('tool_name') == 'dorado_basecaller' and system_metrics.get('gpu', {}).get('gpu_available'),
            'priority_level': characteristics.get('processing_hints', {}).get('recommended_priority', 'normal')
        }
    }
    
    # Save predictions
    output_file = f"{meta['id']}_resource_predictions.json"
    with open(output_file, 'w') as f:
        json.dump(resource_predictions, f, indent=2)
    
    print(f"Resource predictions generated for {meta['id']}:")
    print(f"  Predicted CPU cores: {cpu_prediction['predicted_cores']}")
    print(f"  Predicted memory: {memory_prediction['predicted_memory_gb']:.1f} GB")
    print(f"  Estimated runtime: {runtime_prediction['predicted_runtime_hours']:.1f} hours")
    print(f"  Confidence level: {confidence_metrics['confidence_level']} ({confidence_metrics['confidence_score']:.2f})")
    
    # Generate versions file
    with open('versions.yml', 'w') as f:
        f.write('''\"${task.process}\":
    python: \"3.9\"
    numpy: \"1.21.0\"
    resource_prediction: \"1.0\"''')
    """

    stub:
    """
    cat > ${meta.id}_resource_predictions.json <<'STUB_EOF'
{
  "sample_id": "${meta.id}",
  "prediction_timestamp": "2024-01-01T00:00:00",
  "tool_context": {
    "tool_name": "stub_tool"
  },
  "input_characteristics_summary": {
    "total_size_gb": 1.0,
    "total_estimated_reads": 100000,
    "file_count": 1,
    "complexity_score": 1.0
  },
  "system_context_summary": {
    "cpu_cores_available": 4,
    "memory_gb_available": 8.0,
    "gpu_available": false,
    "current_load": "low"
  },
  "predictions": {
    "cpu_requirements": {
      "predicted_cores": 4,
      "base_cores": 2,
      "scaling_factor": 0.1,
      "complexity_adjustment": 1.0,
      "tool_profile": {}
    },
    "memory_requirements": {
      "predicted_memory_gb": 8.0,
      "base_memory_gb": 4.0,
      "scaling_component": 4.0,
      "complexity_adjustment": 1.0,
      "tool_profile": {}
    },
    "runtime_estimates": {
      "predicted_runtime_seconds": 3600,
      "predicted_runtime_minutes": 60.0,
      "predicted_runtime_hours": 1.0,
      "base_processing_time": 3000,
      "startup_time": 30,
      "parallelization_efficiency": 1.0
    },
    "io_requirements": {
      "temp_space_gb": 0.5,
      "read_throughput_mb_s": 100,
      "write_throughput_mb_s": 50,
      "io_pattern": {},
      "multiple_files": false,
      "concurrent_io": false
    }
  },
  "confidence_metrics": {
    "confidence_score": 0.800,
    "confidence_level": "medium",
    "factors": {
      "data_completeness": 0.800,
      "system_metrics_quality": 1.000,
      "file_type_certainty": 0.800,
      "size_reasonableness": 1.000
    }
  },
  "recommendations": {
    "optimal_cpu_cores": 4,
    "optimal_memory_gb": 8.0,
    "estimated_runtime_hours": 1.0,
    "temp_space_gb": 0.5,
    "gpu_acceleration": false,
    "priority_level": "normal"
  }
}
STUB_EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.9"
        resource_prediction: "1.0"
    END_VERSIONS
    """
}