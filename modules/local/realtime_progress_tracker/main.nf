process REALTIME_PROGRESS_TRACKER {
    tag "realtime_monitoring"
    label 'process_single'
    publishDir "${params.outdir}/realtime_monitoring", mode: params.publish_dir_mode

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'biocontainers/python:3.11' }"

    input:
    val(tracking_data)  // Map with progress information

    output:
    path "progress_dashboard.html", emit: dashboard
    path "progress_stats.json"    , emit: stats
    path "versions.yml"           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    #!/usr/bin/env python3
    import json
    import sys
    from datetime import datetime, timedelta
    from pathlib import Path

    # Parse tracking data
    tracking = ${groovy.json.JsonOutput.toJson(tracking_data)}

    # Generate statistics
    stats = {
        'timestamp': datetime.now().isoformat(),
        'total_files_detected': tracking.get('total_detected', 0),
        'files_ready': tracking.get('ready', 0),
        'files_not_ready': tracking.get('not_ready', 0),
        'files_processed': tracking.get('processed', 0),
        'files_failed': tracking.get('failed', 0),
        'retry_count': tracking.get('retries', 0),
        'processing_rate': tracking.get('rate', 0.0),
        'last_file_time': tracking.get('last_file', None),
        'watchdog_status': tracking.get('watchdog_status', 'ACTIVE')
    }

    # Check for stalled run (no new files in watchdog_timeout)
    watchdog_timeout = tracking.get('watchdog_timeout', 3600)  # Default 1 hour
    last_file_time_str = stats['last_file_time']

    if last_file_time_str:
        try:
            last_file_time = datetime.fromisoformat(last_file_time_str)
            time_since_last = (datetime.now() - last_file_time).total_seconds()

            if time_since_last > watchdog_timeout:
                stats['watchdog_status'] = 'STALLED'
                stats['time_since_last_file'] = time_since_last
                print(f"⚠️  WATCHDOG: No new files for {time_since_last:.0f}s (threshold: {watchdog_timeout}s)", file=sys.stderr)
            else:
                stats['watchdog_status'] = 'ACTIVE'
                stats['time_since_last_file'] = time_since_last
        except (ValueError, TypeError):
            stats['watchdog_status'] = 'UNKNOWN'

    # Write JSON stats
    with open('progress_stats.json', 'w') as f:
        json.dump(stats, f, indent=2)

    # Generate HTML dashboard
    html_content = f'''
    <!DOCTYPE html>
    <html>
    <head>
        <title>Real-time Monitoring Dashboard</title>
        <meta http-equiv="refresh" content="30">
        <style>
            body {{
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                margin: 20px;
                background-color: #f5f5f5;
            }}
            .container {{
                max-width: 1200px;
                margin: 0 auto;
                background-color: white;
                padding: 30px;
                border-radius: 10px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }}
            h1 {{
                color: #2c3e50;
                border-bottom: 3px solid #3498db;
                padding-bottom: 10px;
            }}
            .stats-grid {{
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                gap: 20px;
                margin: 20px 0;
            }}
            .stat-card {{
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                padding: 20px;
                border-radius: 8px;
                color: white;
                box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            }}
            .stat-card.success {{
                background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            }}
            .stat-card.warning {{
                background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            }}
            .stat-card.info {{
                background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
            }}
            .stat-value {{
                font-size: 32px;
                font-weight: bold;
                margin: 10px 0;
            }}
            .stat-label {{
                font-size: 14px;
                opacity: 0.9;
            }}
            .status-indicator {{
                display: inline-block;
                width: 12px;
                height: 12px;
                border-radius: 50%;
                margin-right: 8px;
            }}
            .status-active {{ background-color: #2ecc71; }}
            .status-stalled {{ background-color: #e74c3c; }}
            .status-unknown {{ background-color: #95a5a6; }}
            .timestamp {{
                color: #7f8c8d;
                font-size: 12px;
                margin-top: 20px;
            }}
            .progress-bar {{
                width: 100%;
                height: 30px;
                background-color: #ecf0f1;
                border-radius: 15px;
                overflow: hidden;
                margin: 20px 0;
            }}
            .progress-fill {{
                height: 100%;
                background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
                transition: width 0.3s ease;
                display: flex;
                align-items: center;
                justify-content: center;
                color: white;
                font-weight: bold;
            }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🔬 Real-time Sequencing Monitoring Dashboard</h1>

            <div class="stats-grid">
                <div class="stat-card info">
                    <div class="stat-label">Total Files Detected</div>
                    <div class="stat-value">{stats['total_files_detected']}</div>
                </div>

                <div class="stat-card success">
                    <div class="stat-label">Files Processed</div>
                    <div class="stat-value">{stats['files_processed']}</div>
                </div>

                <div class="stat-card">
                    <div class="stat-label">Files Ready</div>
                    <div class="stat-value">{stats['files_ready']}</div>
                </div>

                <div class="stat-card warning">
                    <div class="stat-label">Files Failed</div>
                    <div class="stat-value">{stats['files_failed']}</div>
                </div>

                <div class="stat-card info">
                    <div class="stat-label">Retry Attempts</div>
                    <div class="stat-value">{stats['retry_count']}</div>
                </div>

                <div class="stat-card success">
                    <div class="stat-label">Processing Rate</div>
                    <div class="stat-value">{stats['processing_rate']:.1f}/min</div>
                </div>
            </div>

            <div style="margin: 30px 0;">
                <h2>Processing Progress</h2>
                <div class="progress-bar">
                    <div class="progress-fill" style="width: {(stats['files_processed'] / max(stats['total_files_detected'], 1)) * 100:.1f}%">
                        {(stats['files_processed'] / max(stats['total_files_detected'], 1)) * 100:.1f}%
                    </div>
                </div>
            </div>

            <div style="margin: 30px 0;">
                <h2>Watchdog Status</h2>
                <p>
                    <span class="status-indicator status-{stats['watchdog_status'].lower()}"></span>
                    <strong>{stats['watchdog_status']}</strong>
                    {f" - {stats.get('time_since_last_file', 0):.0f}s since last file" if 'time_since_last_file' in stats else ""}
                </p>
            </div>

            <div class="timestamp">
                Last updated: {stats['timestamp']}<br>
                Page auto-refreshes every 30 seconds
            </div>
        </div>
    </body>
    </html>
    '''

    with open('progress_dashboard.html', 'w') as f:
        f.write(html_content)

    # Write versions
    with open('versions.yml', 'w') as f:
        f.write('"${task.process}":\\n')
        f.write(f'  python: {sys.version.split()[0]}\\n')

    print(f"📊 Dashboard generated: {stats['files_processed']}/{stats['total_files_detected']} files processed", file=sys.stderr)
    """

    stub:
    """
    echo '{"timestamp": "2025-01-01T00:00:00", "total_files_detected": 0}' > progress_stats.json
    echo '<html><body>Dashboard Stub</body></html>' > progress_dashboard.html

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/Python //g')
    END_VERSIONS
    """
}
