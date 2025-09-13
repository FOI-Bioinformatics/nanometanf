process GENERATE_REALTIME_REPORT {
    tag "$batch_meta.batch_id"
    label 'process_single'
    publishDir "${params.outdir}/realtime_reports", mode: 'copy'

    input:
    tuple val(batch_meta), path(snapshot_stats), path(cumulative_stats)
    val stats_config

    output:
    tuple val(batch_meta), path("realtime_report_${batch_meta.batch_time}.html"), emit: html
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    
    """
    #!/usr/bin/env python3
    
    import json
    from datetime import datetime
    from pathlib import Path
    
    # Load statistics data
    with open('${snapshot_stats}', 'r') as f:
        snapshot = json.load(f)
    
    with open('${cumulative_stats}', 'r') as f:
        cumulative = json.load(f)
    
    stats_config = ${groovy.json.JsonBuilder(stats_config).toString()}
    
    # Generate HTML report
    report_html = f'''
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Nanometa Real-time Report - {snapshot["batch_info"]["batch_id"]}</title>
        <style>
            body {{
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                margin: 0;
                padding: 20px;
                background-color: #f5f7fa;
                color: #2c3e50;
            }}
            .header {{
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 30px;
                border-radius: 12px;
                margin-bottom: 30px;
                box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            }}
            .header h1 {{
                margin: 0;
                font-size: 2.5em;
                font-weight: 300;
            }}
            .header .subtitle {{
                margin: 10px 0 0 0;
                opacity: 0.9;
                font-size: 1.1em;
            }}
            .dashboard {{
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
                gap: 20px;
                margin-bottom: 30px;
            }}
            .card {{
                background: white;
                border-radius: 8px;
                padding: 25px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                border-left: 4px solid #3498db;
            }}
            .card.warning {{
                border-left-color: #f39c12;
            }}
            .card.success {{
                border-left-color: #27ae60;
            }}
            .card.error {{
                border-left-color: #e74c3c;
            }}
            .card h3 {{
                margin: 0 0 15px 0;
                color: #2c3e50;
                font-size: 1.2em;
            }}
            .metric {{
                display: flex;
                justify-content: space-between;
                align-items: center;
                padding: 8px 0;
                border-bottom: 1px solid #ecf0f1;
            }}
            .metric:last-child {{
                border-bottom: none;
            }}
            .metric-label {{
                font-weight: 500;
                color: #7f8c8d;
            }}
            .metric-value {{
                font-weight: 600;
                color: #2c3e50;
                font-size: 1.1em;
            }}
            .large-metric {{
                font-size: 2.5em;
                font-weight: 700;
                color: #3498db;
                text-align: center;
                margin: 15px 0;
            }}
            .trend-indicator {{
                display: inline-block;
                padding: 4px 8px;
                border-radius: 4px;
                font-size: 0.8em;
                font-weight: 600;
                margin-left: 10px;
            }}
            .trend-up {{
                background-color: #d5f4e6;
                color: #27ae60;
            }}
            .trend-down {{
                background-color: #fadbd8;
                color: #e74c3c;
            }}
            .alert {{
                background-color: #fff3cd;
                border: 1px solid #ffeaa7;
                border-radius: 6px;
                padding: 15px;
                margin: 10px 0;
                color: #856404;
            }}
            .alert.warning {{
                background-color: #fff3cd;
                border-color: #ffeaa7;
                color: #856404;
            }}
            .alert.error {{
                background-color: #f8d7da;
                border-color: #f5c6cb;
                color: #721c24;
            }}
            .progress-bar {{
                width: 100%;
                height: 20px;
                background-color: #ecf0f1;
                border-radius: 10px;
                overflow: hidden;
                margin: 10px 0;
            }}
            .progress-fill {{
                height: 100%;
                background: linear-gradient(90deg, #3498db, #2980b9);
                transition: width 0.3s ease;
            }}
            .source-list {{
                list-style: none;
                padding: 0;
                margin: 0;
            }}
            .source-list li {{
                padding: 8px;
                margin: 5px 0;
                background-color: #f8f9fa;
                border-radius: 4px;
                border-left: 3px solid #3498db;
            }}
            .footer {{
                text-align: center;
                color: #7f8c8d;
                margin-top: 40px;
                padding: 20px;
                border-top: 1px solid #ecf0f1;
            }}
            .timestamp {{
                font-family: 'Courier New', monospace;
                background-color: #f8f9fa;
                padding: 4px 8px;
                border-radius: 4px;
                font-size: 0.9em;
            }}
        </style>
    </head>
    <body>
        <div class="header">
            <h1>🧬 Nanometa Real-time Monitoring</h1>
            <div class="subtitle">
                Batch: {snapshot["batch_info"]["batch_id"]} | 
                <span class="timestamp">{snapshot["batch_info"]["processing_time_formatted"]}</span>
            </div>
        </div>
        
        <div class="dashboard">
            <!-- Current Batch Overview -->
            <div class="card">
                <h3>📊 Current Batch</h3>
                <div class="large-metric">{snapshot["file_statistics"]["file_count"]}</div>
                <div style="text-align: center; color: #7f8c8d;">Files Processed</div>
                <div class="metric">
                    <span class="metric-label">Total Size</span>
                    <span class="metric-value">{snapshot["file_statistics"]["total_size_mb"]:.1f} MB</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Estimated Reads</span>
                    <span class="metric-value">{snapshot["file_statistics"]["estimated_total_reads"]:,}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Compressed Files</span>
                    <span class="metric-value">{snapshot["file_statistics"]["compressed_files"]}</span>
                </div>
            </div>
            
            <!-- Session Summary -->
            <div class="card success">
                <h3>🎯 Session Summary</h3>
                <div class="large-metric">{cumulative["session_info"]["total_batches"]}</div>
                <div style="text-align: center; color: #7f8c8d;">Total Batches</div>
                <div class="metric">
                    <span class="metric-label">Total Files</span>
                    <span class="metric-value">{cumulative["totals"]["total_files"]:,}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Total Size</span>
                    <span class="metric-value">{cumulative["totals"]["total_size_mb"]:.1f} MB</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Session Duration</span>
                    <span class="metric-value">{cumulative["performance"]["session_duration_seconds"]:.0f}s</span>
                </div>
            </div>
            
            <!-- Performance Metrics -->
            <div class="card">
                <h3>⚡ Performance</h3>
                <div class="metric">
                    <span class="metric-label">Files/sec</span>
                    <span class="metric-value">{cumulative["performance"]["files_per_second"]:.2f}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">MB/sec</span>
                    <span class="metric-value">{cumulative["performance"]["mb_per_second"]:.2f}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Reads/sec</span>
                    <span class="metric-value">{cumulative["performance"]["reads_per_second"]:,.0f}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Batches/min</span>
                    <span class="metric-value">{cumulative["performance"]["batches_per_minute"]:.1f}</span>
                </div>
            </div>
            
            <!-- Quality Indicators -->
            <div class="card">
                <h3>✅ Quality Indicators</h3>
                <div class="metric">
                    <span class="metric-label">Compression Ratio</span>
                    <span class="metric-value">{snapshot["quality_indicators"]["compressed_ratio"]:.1%}</span>
                </div>
                <div class="progress-bar">
                    <div class="progress-fill" style="width: {snapshot['quality_indicators']['compressed_ratio']*100:.1f}%"></div>
                </div>
                <div class="metric">
                    <span class="metric-label">High Priority Files</span>
                    <span class="metric-value">{snapshot["priority_analysis"]["high_priority_files"]}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Large Files (>50MB)</span>
                    <span class="metric-value">{snapshot["quality_indicators"]["large_files_ratio"]:.1%}</span>
                </div>
            </div>
            
            <!-- Source Analysis -->
            <div class="card">
                <h3>📁 Data Sources</h3>
                <div class="metric">
                    <span class="metric-label">Watch Directories</span>
                    <span class="metric-value">{len(cumulative["source_summary"]["unique_directories"])}</span>
                </div>
                <ul class="source-list">
    '''
    
    for directory in cumulative["source_summary"]["unique_directories"][:5]:  # Show first 5
        total_files = cumulative["source_summary"]["directory_totals"].get(directory, 0)
        report_html += f'<li>{directory} ({total_files:,} files)</li>'
    
    if len(cumulative["source_summary"]["unique_directories"]) > 5:
        report_html += f'<li>... and {len(cumulative["source_summary"]["unique_directories"]) - 5} more directories</li>'
    
    report_html += f'''
                </ul>
                <div class="metric">
                    <span class="metric-label">Unique Samples</span>
                    <span class="metric-value">{len(cumulative["source_summary"]["unique_samples"])}</span>
                </div>
            </div>
            
            <!-- Timing Analysis -->
            <div class="card">
                <h3>⏱️ Timing Analysis</h3>
                <div class="metric">
                    <span class="metric-label">Avg File Age</span>
                    <span class="metric-value">{snapshot["timing_analysis"]["average_file_age_ms"]/60000:.1f} min</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Oldest File</span>
                    <span class="metric-value">{snapshot["timing_analysis"]["oldest_file_age_ms"]/60000:.1f} min</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Newest File</span>
                    <span class="metric-value">{snapshot["timing_analysis"]["newest_file_age_ms"]/60000:.1f} min</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Batch Created</span>
                    <span class="metric-value timestamp">{snapshot["batch_info"]["batch_time"]}</span>
                </div>
            </div>
        </div>
        
        <!-- Alerts Section -->
    '''
    
    # Add alerts if they exist
    alerts_file = Path('alerts.json')
    if alerts_file.exists():
        with open(alerts_file, 'r') as f:
            alerts_data = json.load(f)
            alerts = alerts_data.get('alerts', [])
            
        if alerts:
            report_html += '''
            <div class="card warning">
                <h3>⚠️ Active Alerts</h3>
            '''
            for alert in alerts:
                alert_class = 'warning' if alert['level'] == 'warning' else 'error'
                report_html += f'''
                <div class="alert {alert_class}">
                    <strong>{alert['type'].title()}:</strong> {alert['message']}
                </div>
                '''
            report_html += '</div>'
    
    # Footer
    report_html += f'''
        <div class="footer">
            <p>Generated by Nanometa-NF Real-time Monitoring | 
            <span class="timestamp">{datetime.now().isoformat()}</span></p>
            <p>Pipeline Version: {stats_config.get('pipeline_version', '1.0')} | 
            Session: {cumulative["session_info"]["session_start_formatted"]}</p>
        </div>
        
        <script>
            // Auto-refresh every 30 seconds (configurable)
            setTimeout(function() {{
                window.location.reload();
            }}, {stats_config.get('refresh_interval_ms', 30000)});
        </script>
    </body>
    </html>
    '''
    
    # Save the report
    output_file = f"realtime_report_{snapshot['batch_info']['batch_time']}.html"
    with open(output_file, 'w') as f:
        f.write(report_html)
    
    # Also save as latest report for easy access
    with open('latest_report.html', 'w') as f:
        f.write(report_html)
    
    print(f"Generated real-time HTML report: {output_file}")
    print(f"Report includes:")
    print(f"  - Batch: {snapshot['batch_info']['batch_id']}")
    print(f"  - Files: {snapshot['file_statistics']['file_count']}")
    print(f"  - Size: {snapshot['file_statistics']['total_size_mb']:.1f} MB")
    print(f"  - Session batches: {cumulative['session_info']['total_batches']}")
    print(f"  - Session files: {cumulative['totals']['total_files']:,}")
    print(f"  - Performance: {cumulative['performance']['files_per_second']:.2f} files/sec")
    
    # Generate versions file
    with open('versions.yml', 'w') as f:
        f.write('''"${task.process}":
    python: "3.9"
    statistics_framework: "1.0"''')
    """

    stub:
    """
    echo '<html><body><h1>Real-time Report (stub)</h1></body></html>' > realtime_report_${batch_meta.batch_time}.html
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.9"
        statistics_framework: "1.0"
    END_VERSIONS
    """
}