process GENERATE_SNAPSHOT_STATS {
    tag "$batch_meta.batch_id"
    label 'process_single'
    publishDir "${params.outdir}/realtime_stats/snapshots", mode: 'copy'

    input:
    tuple val(batch_meta), val(file_metas)
    val stats_config

    output:
    tuple val(batch_meta), path("${batch_meta.batch_id}_snapshot.json"), emit: snapshot_stats
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    
    """
    #!/usr/bin/env python3
    
    import json
    import time
    from datetime import datetime
    from pathlib import Path
    
    # Batch metadata
    batch_meta = ${groovy.json.JsonBuilder(batch_meta).toString()}
    file_metas = ${groovy.json.JsonBuilder(file_metas).toString()}
    stats_config = ${groovy.json.JsonBuilder(stats_config).toString()}
    
    # Calculate snapshot statistics
    snapshot_stats = {
        'batch_info': {
            'batch_id': batch_meta['batch_id'],
            'batch_timestamp': batch_meta['batch_timestamp'],
            'batch_time_formatted': batch_meta['batch_time'],
            'processing_timestamp': int(time.time() * 1000),
            'processing_time_formatted': datetime.now().isoformat()
        },
        'file_statistics': {
            'file_count': len(file_metas),
            'total_size_bytes': sum(f.get('file_size', 0) for f in file_metas),
            'total_size_mb': round(sum(f.get('file_size', 0) for f in file_metas) / 1024 / 1024, 2),
            'estimated_total_reads': sum(f.get('estimated_reads', 0) for f in file_metas),
            'compressed_files': sum(1 for f in file_metas if f.get('is_compressed', False)),
            'average_file_size_mb': round((sum(f.get('file_size', 0) for f in file_metas) / len(file_metas)) / 1024 / 1024, 2) if file_metas else 0
        },
        'priority_analysis': {
            'average_priority': round(sum(f.get('priority_score', 0) for f in file_metas) / len(file_metas), 2) if file_metas else 0,
            'max_priority': max((f.get('priority_score', 0) for f in file_metas), default=0),
            'min_priority': min((f.get('priority_score', 0) for f in file_metas), default=0),
            'high_priority_files': sum(1 for f in file_metas if f.get('priority_score', 0) > 100)
        },
        'source_analysis': {
            'watch_directories': list(set(f.get('watch_dir', 'unknown') for f in file_metas)),
            'directory_file_counts': {},
            'sample_ids': list(set(f.get('sample_id', 'unknown') for f in file_metas))
        },
        'timing_analysis': {
            'batch_creation_time_ms': batch_meta.get('batch_timestamp', 0),
            'average_file_age_ms': round(sum(f.get('file_age_ms', 0) for f in file_metas) / len(file_metas), 2) if file_metas else 0,
            'oldest_file_age_ms': max((f.get('file_age_ms', 0) for f in file_metas), default=0),
            'newest_file_age_ms': min((f.get('file_age_ms', 0) for f in file_metas), default=0)
        },
        'performance_metrics': {
            'files_per_second': 0,  # Will be calculated in cumulative stats
            'mb_per_second': 0,     # Will be calculated in cumulative stats
            'reads_per_second': 0   # Will be calculated in cumulative stats
        }
    }
    
    # Calculate directory-specific file counts
    for file_meta in file_metas:
        watch_dir = file_meta.get('watch_dir', 'unknown')
        if watch_dir not in snapshot_stats['source_analysis']['directory_file_counts']:
            snapshot_stats['source_analysis']['directory_file_counts'][watch_dir] = 0
        snapshot_stats['source_analysis']['directory_file_counts'][watch_dir] += 1
    
    # Add quality indicators
    snapshot_stats['quality_indicators'] = {
        'large_files_ratio': sum(1 for f in file_metas if f.get('file_size', 0) > 50_000_000) / len(file_metas) if file_metas else 0,
        'compressed_ratio': snapshot_stats['file_statistics']['compressed_files'] / len(file_metas) if file_metas else 0,
        'high_priority_ratio': snapshot_stats['priority_analysis']['high_priority_files'] / len(file_metas) if file_metas else 0
    }
    
    # Save snapshot statistics
    output_file = "${batch_meta.batch_id}_snapshot.json"
    with open(output_file, 'w') as f:
        json.dump(snapshot_stats, f, indent=2)
    
    print(f"Generated snapshot statistics for batch {batch_meta['batch_id']}")
    print(f"Files processed: {len(file_metas)}")
    print(f"Total size: {snapshot_stats['file_statistics']['total_size_mb']} MB")
    print(f"Estimated reads: {snapshot_stats['file_statistics']['estimated_total_reads']:,}")
    
    # Generate versions file
    with open('versions.yml', 'w') as f:
        f.write('''"${task.process}":
    python: "3.9"
    statistics_framework: "1.0"''')
    """

    stub:
    """
    echo '{"batch_id": "${batch_meta.batch_id}", "stub": true}' > ${batch_meta.batch_id}_snapshot.json
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.9"
        statistics_framework: "1.0"
    END_VERSIONS
    """
}