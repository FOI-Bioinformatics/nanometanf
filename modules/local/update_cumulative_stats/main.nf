process UPDATE_CUMULATIVE_STATS {
    tag "$batch_meta.batch_id"
    label 'process_single'
    publishDir "${params.outdir}/realtime_stats", mode: 'copy'

    input:
    tuple val(batch_meta), path(snapshot_stats), path(previous_cumulative)
    val stats_config

    output:
    tuple val(batch_meta), path("cumulative_stats.json"), emit: cumulative_stats
    tuple val(batch_meta), path("alerts.json"), emit: alerts, optional: true
    path "cumulative_state.json", emit: state
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def has_previous = previous_cumulative.name != 'input.1' && previous_cumulative.size() > 0
    def has_previous_py = has_previous ? 'True' : 'False'

    """
    #!/usr/bin/env python3

    import json
    import time
    from datetime import datetime, timedelta
    from pathlib import Path

    # Load current snapshot
    with open('${snapshot_stats}', 'r') as f:
        snapshot = json.load(f)

    # Load previous cumulative state if it exists
    cumulative = {}
    if ${has_previous_py} and Path('${previous_cumulative}').exists():
        try:
            with open('${previous_cumulative}', 'r') as f:
                cumulative = json.load(f)
        except:
            cumulative = {}
    
    # Initialize cumulative structure if empty
    if not cumulative:
        cumulative = {
            'session_info': {
                'session_start': snapshot['batch_info']['processing_timestamp'],
                'session_start_formatted': snapshot['batch_info']['processing_time_formatted'],
                'total_batches': 0,
                'last_update': 0
            },
            'totals': {
                'total_files': 0,
                'total_size_bytes': 0,
                'total_size_mb': 0,
                'total_estimated_reads': 0,
                'total_compressed_files': 0
            },
            'averages': {
                'avg_files_per_batch': 0,
                'avg_batch_size_mb': 0,
                'avg_reads_per_batch': 0,
                'avg_file_size_mb': 0
            },
            'performance': {
                'files_per_second': 0,
                'mb_per_second': 0,
                'reads_per_second': 0,
                'batches_per_minute': 0,
                'session_duration_seconds': 0
            },
            'trends': {
                'batch_timestamps': [],
                'batch_file_counts': [],
                'batch_sizes_mb': [],
                'batch_read_counts': []
            },
            'quality_trends': {
                'compression_ratios': [],
                'priority_scores': [],
                'large_file_ratios': []
            },
            'source_summary': {
                'unique_directories': set(),
                'unique_samples': set(),
                'directory_totals': {}
            }
        }
    
    # Update with current snapshot
    current_time = snapshot['batch_info']['processing_timestamp']
    
    # Update session info
    cumulative['session_info']['total_batches'] += 1
    cumulative['session_info']['last_update'] = current_time
    cumulative['session_info']['last_update_formatted'] = snapshot['batch_info']['processing_time_formatted']
    
    # Update totals
    cumulative['totals']['total_files'] += snapshot['file_statistics']['file_count']
    cumulative['totals']['total_size_bytes'] += snapshot['file_statistics']['total_size_bytes']
    cumulative['totals']['total_size_mb'] += snapshot['file_statistics']['total_size_mb']
    cumulative['totals']['total_estimated_reads'] += snapshot['file_statistics']['estimated_total_reads']
    cumulative['totals']['total_compressed_files'] += snapshot['file_statistics']['compressed_files']
    
    # Calculate session duration
    session_duration = (current_time - cumulative['session_info']['session_start']) / 1000.0  # Convert to seconds
    cumulative['performance']['session_duration_seconds'] = round(session_duration, 2)
    
    # Update performance metrics
    if session_duration > 0:
        cumulative['performance']['files_per_second'] = round(cumulative['totals']['total_files'] / session_duration, 2)
        cumulative['performance']['mb_per_second'] = round(cumulative['totals']['total_size_mb'] / session_duration, 2)
        cumulative['performance']['reads_per_second'] = round(cumulative['totals']['total_estimated_reads'] / session_duration, 0)
        cumulative['performance']['batches_per_minute'] = round((cumulative['session_info']['total_batches'] / session_duration) * 60, 2)
    
    # Update averages
    total_batches = cumulative['session_info']['total_batches']
    cumulative['averages']['avg_files_per_batch'] = round(cumulative['totals']['total_files'] / total_batches, 2)
    cumulative['averages']['avg_batch_size_mb'] = round(cumulative['totals']['total_size_mb'] / total_batches, 2)
    cumulative['averages']['avg_reads_per_batch'] = round(cumulative['totals']['total_estimated_reads'] / total_batches, 0)
    if cumulative['totals']['total_files'] > 0:
        cumulative['averages']['avg_file_size_mb'] = round(cumulative['totals']['total_size_mb'] / cumulative['totals']['total_files'], 2)
    
    # Update trends (keep last 100 data points)
    max_trend_points = 100
    cumulative['trends']['batch_timestamps'].append(current_time)
    cumulative['trends']['batch_file_counts'].append(snapshot['file_statistics']['file_count'])
    cumulative['trends']['batch_sizes_mb'].append(snapshot['file_statistics']['total_size_mb'])
    cumulative['trends']['batch_read_counts'].append(snapshot['file_statistics']['estimated_total_reads'])
    
    # Trim trends to max points
    for trend_key in ['batch_timestamps', 'batch_file_counts', 'batch_sizes_mb', 'batch_read_counts']:
        if len(cumulative['trends'][trend_key]) > max_trend_points:
            cumulative['trends'][trend_key] = cumulative['trends'][trend_key][-max_trend_points:]
    
    # Update quality trends
    cumulative['quality_trends']['compression_ratios'].append(snapshot['quality_indicators']['compressed_ratio'])
    cumulative['quality_trends']['priority_scores'].append(snapshot['priority_analysis']['average_priority'])
    cumulative['quality_trends']['large_file_ratios'].append(snapshot['quality_indicators']['large_files_ratio'])
    
    # Trim quality trends
    for quality_key in ['compression_ratios', 'priority_scores', 'large_file_ratios']:
        if len(cumulative['quality_trends'][quality_key]) > max_trend_points:
            cumulative['quality_trends'][quality_key] = cumulative['quality_trends'][quality_key][-max_trend_points:]
    
    # Update source summary
    cumulative['source_summary']['unique_directories'].update(snapshot['source_analysis']['watch_directories'])
    cumulative['source_summary']['unique_samples'].update(snapshot['source_analysis']['sample_ids'])
    
    for directory, count in snapshot['source_analysis']['directory_file_counts'].items():
        if directory not in cumulative['source_summary']['directory_totals']:
            cumulative['source_summary']['directory_totals'][directory] = 0
        cumulative['source_summary']['directory_totals'][directory] += count
    
    # Convert sets to lists for JSON serialization
    cumulative['source_summary']['unique_directories'] = list(cumulative['source_summary']['unique_directories'])
    cumulative['source_summary']['unique_samples'] = list(cumulative['source_summary']['unique_samples'])
    
    # Generate alerts based on configurable thresholds
    alerts = []
    stats_config = json.loads('${new groovy.json.JsonBuilder(stats_config).toString()}')
    
    # Performance alerts
    if 'performance_thresholds' in stats_config:
        thresholds = stats_config['performance_thresholds']
        
        if 'min_files_per_second' in thresholds:
            if cumulative['performance']['files_per_second'] < thresholds['min_files_per_second']:
                alerts.append({
                    'type': 'performance',
                    'level': 'warning',
                    'message': f"Low throughput: {cumulative['performance']['files_per_second']} files/sec (threshold: {thresholds['min_files_per_second']})",
                    'timestamp': current_time,
                    'metric': 'files_per_second',
                    'value': cumulative['performance']['files_per_second'],
                    'threshold': thresholds['min_files_per_second']
                })
        
        if 'max_avg_file_age_minutes' in thresholds:
            avg_file_age_minutes = snapshot['timing_analysis']['average_file_age_ms'] / 60000
            if avg_file_age_minutes > thresholds['max_avg_file_age_minutes']:
                alerts.append({
                    'type': 'latency',
                    'level': 'warning',
                    'message': f"High file age: {avg_file_age_minutes:.1f} minutes (threshold: {thresholds['max_avg_file_age_minutes']})",
                    'timestamp': current_time,
                    'metric': 'average_file_age_minutes',
                    'value': avg_file_age_minutes,
                    'threshold': thresholds['max_avg_file_age_minutes']
                })
    
    # Quality alerts
    if 'quality_thresholds' in stats_config:
        quality_thresholds = stats_config['quality_thresholds']
        
        if 'min_compression_ratio' in quality_thresholds:
            compression_ratio = snapshot['quality_indicators']['compressed_ratio']
            if compression_ratio < quality_thresholds['min_compression_ratio']:
                alerts.append({
                    'type': 'quality',
                    'level': 'info',
                    'message': f"Low compression ratio: {compression_ratio:.2f} (threshold: {quality_thresholds['min_compression_ratio']})",
                    'timestamp': current_time,
                    'metric': 'compression_ratio',
                    'value': compression_ratio,
                    'threshold': quality_thresholds['min_compression_ratio']
                })
    
    # Save cumulative statistics
    with open('cumulative_stats.json', 'w') as f:
        json.dump(cumulative, f, indent=2)
    
    # Save state for next iteration (copy of cumulative)
    with open('cumulative_state.json', 'w') as f:
        json.dump(cumulative, f, indent=2)
    
    # Save alerts if any
    if alerts:
        with open('alerts.json', 'w') as f:
            json.dump({
                'batch_id': snapshot['batch_info']['batch_id'],
                'timestamp': current_time,
                'alert_count': len(alerts),
                'alerts': alerts
            }, f, indent=2)
        
        print(f"Generated {len(alerts)} alerts for batch {snapshot['batch_info']['batch_id']}")
        for alert in alerts:
            print(f"  {alert['level'].upper()}: {alert['message']}")
    
    print(f"Updated cumulative statistics:")
    print(f"  Total batches: {cumulative['session_info']['total_batches']}")
    print(f"  Total files: {cumulative['totals']['total_files']:,}")
    print(f"  Total size: {cumulative['totals']['total_size_mb']:.1f} MB")
    print(f"  Session duration: {cumulative['performance']['session_duration_seconds']:.1f} seconds")
    print(f"  Throughput: {cumulative['performance']['files_per_second']:.2f} files/sec")
    
    # Generate versions file
    with open('versions.yml', 'w') as f:
        f.write('''"${task.process}":
    python: "3.9"
    statistics_framework: "1.0"''')
    """

    stub:
    """
    # Create comprehensive cumulative statistics matching real output structure
    cat > cumulative_stats.json << 'EOF'
{
    "session_info": {
        "session_start": \$(date +%s)000,
        "session_start_formatted": "\$(date -Iseconds)",
        "total_batches": 3,
        "last_update": \$(date +%s)000,
        "last_update_formatted": "\$(date -Iseconds)"
    },
    "totals": {
        "total_files": 15,
        "total_size_bytes": 157286400,
        "total_size_mb": 150.0,
        "total_estimated_reads": 37500,
        "total_compressed_files": 9
    },
    "averages": {
        "avg_files_per_batch": 5.0,
        "avg_batch_size_mb": 50.0,
        "avg_reads_per_batch": 12500.0,
        "avg_file_size_mb": 10.0
    },
    "performance": {
        "files_per_second": 2.5,
        "mb_per_second": 25.0,
        "reads_per_second": 6250.0,
        "batches_per_minute": 30.0,
        "session_duration_seconds": 360.0
    },
    "trends": {
        "batch_timestamps": [\$(date +%s)000, \$(date +%s)000, \$(date +%s)000],
        "batch_file_counts": [5, 5, 5],
        "batch_sizes_mb": [50.0, 50.0, 50.0],
        "batch_read_counts": [12500, 12500, 12500]
    },
    "quality_trends": {
        "compression_ratios": [0.6, 0.6, 0.6],
        "priority_scores": [75.5, 75.5, 75.5],
        "large_file_ratios": [0.4, 0.4, 0.4]
    },
    "source_summary": {
        "unique_directories": ["/data/nanopore/run1"],
        "unique_samples": ["sample_001", "sample_002"],
        "directory_totals": {
            "/data/nanopore/run1": 15
        }
    }
}
EOF

    # Create alerts file with sample alerts
    cat > alerts.json << 'EOF'
{
    "batch_id": "${batch_meta.batch_id}",
    "timestamp": \$(date +%s)000,
    "alert_count": 2,
    "alerts": [
        {
            "type": "performance",
            "level": "info",
            "message": "High throughput detected: 2.5 files/sec",
            "timestamp": \$(date +%s)000,
            "metric": "files_per_second",
            "value": 2.5,
            "threshold": 1.0
        },
        {
            "type": "quality",
            "level": "info",
            "message": "Good compression ratio: 0.60",
            "timestamp": \$(date +%s)000,
            "metric": "compression_ratio",
            "value": 0.6,
            "threshold": 0.5
        }
    ]
}
EOF

    # Create cumulative state (copy of cumulative stats for next iteration)
    cp cumulative_stats.json cumulative_state.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.9"
        statistics_framework: "1.0"
    END_VERSIONS
    """
}