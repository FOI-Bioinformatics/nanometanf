process ANALYZE_INPUT_CHARACTERISTICS {
    tag "$meta.id"
    label 'process_single'
    publishDir "${params.outdir}/resource_analysis", mode: 'copy'

    input:
    tuple val(meta), path(files), val(tool_context)
    val resource_config

    output:
    tuple val(meta), path("${meta.id}_characteristics.json"), emit: characteristics
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    
    """
    #!/usr/bin/env python3
    
    import json
    import os
    import time
    import gzip
    import math
    from pathlib import Path
    from datetime import datetime
    
    # Input metadata and configuration
    meta = json.loads('${new groovy.json.JsonBuilder(meta).toString()}')
    tool_context = json.loads('${new groovy.json.JsonBuilder(tool_context).toString()}')
    resource_config = json.loads('${new groovy.json.JsonBuilder(resource_config).toString()}')
    
    files = [${files.collect { "'${it}'" }.join(', ')}]
    
    def analyze_file_characteristics(file_path):
        """Analyze individual file characteristics for resource prediction"""
        file_stats = {
            'file_path': str(file_path),
            'file_name': os.path.basename(file_path),
            'file_size_bytes': 0,
            'file_size_mb': 0,
            'is_compressed': False,
            'compression_ratio': 1.0,
            'estimated_reads': 0,
            'estimated_bases': 0,
            'file_type': 'unknown',
            'complexity_score': 1.0,
            'processing_priority': 'normal'
        }
        
        try:
            # Basic file information
            file_stats['file_size_bytes'] = os.path.getsize(file_path)
            file_stats['file_size_mb'] = file_stats['file_size_bytes'] / (1024 * 1024)
            file_stats['is_compressed'] = file_path.endswith('.gz')
            
            # Determine file type
            if any(ext in file_path.lower() for ext in ['.fastq', '.fq']):
                file_stats['file_type'] = 'fastq'
            elif '.pod5' in file_path.lower():
                file_stats['file_type'] = 'pod5'
            elif any(ext in file_path.lower() for ext in ['.fasta', '.fa']):
                file_stats['file_type'] = 'fasta'
            
            # Estimate read characteristics for FASTQ files
            if file_stats['file_type'] == 'fastq':
                read_stats = estimate_fastq_characteristics(file_path, file_stats['is_compressed'])
                file_stats.update(read_stats)
            
            # Estimate characteristics for POD5 files
            elif file_stats['file_type'] == 'pod5':
                pod5_stats = estimate_pod5_characteristics(file_path)
                file_stats.update(pod5_stats)
            
            # Calculate complexity score
            file_stats['complexity_score'] = calculate_complexity_score(file_stats)
            
            # Determine processing priority
            file_stats['processing_priority'] = determine_processing_priority(file_stats, meta)
            
        except Exception as e:
            print(f"Warning: Could not analyze file {file_path}: {e}")
        
        return file_stats
    
    def estimate_fastq_characteristics(file_path, is_compressed):
        """Estimate FASTQ file characteristics by sampling"""
        characteristics = {
            'estimated_reads': 0,
            'estimated_bases': 0,
            'average_read_length': 0,
            'quality_profile': 'unknown',
            'compression_ratio': 1.0
        }
        
        try:
            # Sample first N reads to estimate characteristics
            sample_size = min(10000, 1000)  # Sample up to 10k reads
            reads_sampled = 0
            total_length = 0
            quality_scores = []
            
            open_func = gzip.open if is_compressed else open
            mode = 'rt' if is_compressed else 'r'
            
            with open_func(file_path, mode) as f:
                line_count = 0
                for line in f:
                    line_count += 1
                    if line_count % 4 == 2:  # Sequence line
                        sequence_length = len(line.strip())
                        total_length += sequence_length
                        reads_sampled += 1
                    elif line_count % 4 == 0:  # Quality line
                        quality_line = line.strip()
                        if quality_line:
                            avg_qual = sum(ord(c) - 33 for c in quality_line) / len(quality_line)
                            quality_scores.append(avg_qual)
                    
                    if reads_sampled >= sample_size:
                        break
            
            if reads_sampled > 0:
                characteristics['average_read_length'] = total_length / reads_sampled
                
                # Estimate total reads based on file size
                estimated_bytes_per_read = (os.path.getsize(file_path) / reads_sampled) if reads_sampled > 0 else 1000
                characteristics['estimated_reads'] = int(os.path.getsize(file_path) / estimated_bytes_per_read)
                characteristics['estimated_bases'] = int(characteristics['estimated_reads'] * characteristics['average_read_length'])
                
                # Quality profile assessment
                if quality_scores:
                    avg_quality = sum(quality_scores) / len(quality_scores)
                    if avg_quality > 15:
                        characteristics['quality_profile'] = 'high'
                    elif avg_quality > 10:
                        characteristics['quality_profile'] = 'medium'
                    else:
                        characteristics['quality_profile'] = 'low'
                
                # Estimate compression ratio for compressed files
                if is_compressed:
                    uncompressed_estimate = reads_sampled * 4 * (characteristics['average_read_length'] + 50)  # Rough estimate
                    compressed_sample_size = line_count * 100  # Rough estimate of sampled bytes
                    if compressed_sample_size > 0:
                        characteristics['compression_ratio'] = uncompressed_estimate / compressed_sample_size
        
        except Exception as e:
            print(f"Warning: Could not sample FASTQ file {file_path}: {e}")
        
        return characteristics
    
    def estimate_pod5_characteristics(file_path):
        """Estimate POD5 file characteristics"""
        characteristics = {
            'estimated_reads': 0,
            'estimated_bases': 0,
            'average_read_length': 4000,  # Typical nanopore read length
            'signal_complexity': 'medium',
            'compression_ratio': 0.3  # POD5 files are highly compressed
        }
        
        try:
            # POD5 files are binary, estimate based on file size
            file_size_mb = os.path.getsize(file_path) / (1024 * 1024)
            
            # Rough estimates based on typical POD5 compression
            estimated_reads_per_mb = 100  # Conservative estimate
            characteristics['estimated_reads'] = int(file_size_mb * estimated_reads_per_mb)
            characteristics['estimated_bases'] = int(characteristics['estimated_reads'] * characteristics['average_read_length'])
            
        except Exception as e:
            print(f"Warning: Could not analyze POD5 file {file_path}: {e}")
        
        return characteristics
    
    def calculate_complexity_score(file_stats):
        """Calculate complexity score for resource prediction"""
        score = 1.0
        
        # File size factor
        if file_stats['file_size_mb'] > 1000:  # > 1GB
            score *= 1.5
        elif file_stats['file_size_mb'] > 100:  # > 100MB
            score *= 1.2
        
        # Read count factor
        if file_stats['estimated_reads'] > 10000000:  # > 10M reads
            score *= 1.4
        elif file_stats['estimated_reads'] > 1000000:  # > 1M reads
            score *= 1.1
        
        # Quality factor (higher quality = more processing)
        if file_stats.get('quality_profile') == 'high':
            score *= 1.1
        elif file_stats.get('quality_profile') == 'low':
            score *= 0.9
        
        # Compression factor (compressed files need decompression)
        if file_stats['is_compressed']:
            score *= 1.1
        
        return round(score, 2)
    
    def determine_processing_priority(file_stats, meta):
        """Determine processing priority based on file and metadata"""
        priority = 'normal'
        
        # Check if sample is in priority list
        priority_samples = resource_config.get('priority_samples', [])
        if meta.get('id') in priority_samples:
            priority = 'high'
        
        # Large files might need special handling
        elif file_stats['file_size_mb'] > 5000:  # > 5GB
            priority = 'low'  # Process in off-peak times
        
        # High-quality small files can be processed quickly
        elif (file_stats['file_size_mb'] < 100 and 
              file_stats.get('quality_profile') == 'high'):
            priority = 'high'
        
        return priority
    
    # Analyze all input files
    print(f"Analyzing input characteristics for {meta['id']}")
    print(f"Files to analyze: {len(files)}")
    print(f"Tool context: {tool_context}")
    
    file_analyses = []
    total_size_bytes = 0
    total_estimated_reads = 0
    total_estimated_bases = 0
    
    for file_path in files:
        if os.path.exists(file_path):
            print(f"Analyzing: {file_path}")
            file_analysis = analyze_file_characteristics(file_path)
            file_analyses.append(file_analysis)
            
            total_size_bytes += file_analysis['file_size_bytes']
            total_estimated_reads += file_analysis['estimated_reads']
            total_estimated_bases += file_analysis['estimated_bases']
        else:
            print(f"Warning: File not found: {file_path}")
    
    # Calculate aggregate characteristics
    aggregate_characteristics = {
        'sample_id': meta['id'],
        'analysis_timestamp': datetime.now().isoformat(),
        'tool_context': tool_context,
        'file_count': len(file_analyses),
        'total_size_bytes': total_size_bytes,
        'total_size_mb': round(total_size_bytes / (1024 * 1024), 2),
        'total_size_gb': round(total_size_bytes / (1024 * 1024 * 1024), 2),
        'total_estimated_reads': total_estimated_reads,
        'total_estimated_bases': total_estimated_bases,
        'average_file_size_mb': round((total_size_bytes / len(file_analyses)) / (1024 * 1024), 2) if file_analyses else 0,
        'estimated_coverage': 'unknown',  # Would need genome size
        'complexity_metrics': {
            'overall_complexity': round(sum(f['complexity_score'] for f in file_analyses) / len(file_analyses), 2) if file_analyses else 1.0,
            'size_complexity': 'high' if total_size_bytes > 5000000000 else 'medium' if total_size_bytes > 1000000000 else 'low',
            'read_complexity': 'high' if total_estimated_reads > 50000000 else 'medium' if total_estimated_reads > 10000000 else 'low'
        },
        'processing_hints': {
            'recommended_parallelization': min(len(file_analyses), 8),
            'memory_intensive': total_size_bytes > 10000000000,  # > 10GB
            'cpu_intensive': total_estimated_reads > 20000000,   # > 20M reads
            'io_intensive': len(file_analyses) > 10,
            'gpu_beneficial': tool_context.get('tool_name') == 'dorado_basecaller'
        },
        'file_details': file_analyses
    }
    
    # Add tool-specific hints
    if tool_context.get('tool_name') == 'kraken2':
        aggregate_characteristics['processing_hints']['database_dependent'] = True
        aggregate_characteristics['processing_hints']['memory_requirement'] = 'database_size * 1.2'
    
    elif tool_context.get('tool_name') == 'dorado_basecaller':
        aggregate_characteristics['processing_hints']['gpu_acceleration'] = True
        aggregate_characteristics['processing_hints']['batch_optimization'] = True
    
    elif tool_context.get('tool_name') in ['flye', 'miniasm']:
        aggregate_characteristics['processing_hints']['assembly_mode'] = True
        aggregate_characteristics['processing_hints']['memory_scaling'] = 'genome_size_dependent'
    
    # Save characteristics analysis
    output_file = f"{meta['id']}_characteristics.json"
    with open(output_file, 'w') as f:
        json.dump(aggregate_characteristics, f, indent=2)
    
    print(f"Analysis complete for {meta['id']}:")
    print(f"  Total size: {aggregate_characteristics['total_size_gb']:.2f} GB")
    print(f"  Estimated reads: {aggregate_characteristics['total_estimated_reads']:,}")
    print(f"  Complexity score: {aggregate_characteristics['complexity_metrics']['overall_complexity']}")
    print(f"  Memory intensive: {aggregate_characteristics['processing_hints']['memory_intensive']}")
    print(f"  CPU intensive: {aggregate_characteristics['processing_hints']['cpu_intensive']}")
    print(f"  GPU beneficial: {aggregate_characteristics['processing_hints']['gpu_beneficial']}")
    
    # Generate versions file
    with open('versions.yml', 'w') as f:
        f.write('''"${task.process}":
    python: "3.9"
    resource_analysis: "1.0"''')
    """

    stub:
    """
    echo '{"sample_id": "${meta.id}", "stub": true}' > ${meta.id}_characteristics.json
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.9"
        resource_analysis: "1.0"
    END_VERSIONS
    """
}