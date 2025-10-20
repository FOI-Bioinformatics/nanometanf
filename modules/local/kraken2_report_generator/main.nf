process KRAKEN2_REPORT_GENERATOR {
    tag "${meta.id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/krakentools:1.2--pyh5e36f6f_0' :
        'quay.io/biocontainers/krakentools:1.2--pyh5e36f6f_0' }"

    input:
    tuple val(meta), path(cumulative_output)
    tuple val(meta), path(batch_reports)
    path  db

    output:
    tuple val(meta), path("*.cumulative.kraken2.report.txt"), emit: report
    tuple val(meta), path("report_stats.json"), emit: stats
    path  "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def args = task.ext.args ?: ''
    """
    #!/usr/bin/env python3

    import json
    import sys
    import subprocess
    from pathlib import Path

    # Get list of batch report files
    report_files = "${batch_reports}".split()
    print(f"Combining {len(report_files)} batch reports for sample ${meta.id}", file=sys.stderr)

    # Use KrakenTools combine_kreports.py to merge batch reports
    # This sums up the read counts across all batches
    cmd = [
        'combine_kreports.py',
        '-r'
    ] + report_files + [
        '-o', '${prefix}.cumulative.kraken2.report.txt',
        '--display-headers'
    ]

    print(f"Running: {' '.join(cmd)}", file=sys.stderr)

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        if result.stdout:
            print(result.stdout, file=sys.stderr)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
    except subprocess.CalledProcessError as e:
        print(f"ERROR: combine_kreports.py failed with exit code {e.returncode}", file=sys.stderr)
        print(f"STDOUT: {e.stdout}", file=sys.stderr)
        print(f"STDERR: {e.stderr}", file=sys.stderr)
        sys.exit(1)

    # Calculate statistics from the cumulative output
    total_reads = 0
    classified_reads = 0

    # Count lines in cumulative output (one line per read)
    with open('${cumulative_output}') as f:
        for line in f:
            total_reads += 1
            if line.strip() and not line.startswith('U'):
                classified_reads += 1

    # Generate report statistics JSON
    report_stats = {
        'sample_id': '${meta.id}',
        'total_reads': total_reads,
        'classified_reads': classified_reads,
        'classification_rate': classified_reads / total_reads if total_reads > 0 else 0,
        'num_batches': len(report_files),
        'cumulative_report': '${prefix}.cumulative.kraken2.report.txt'
    }

    with open('report_stats.json', 'w') as stats:
        json.dump(report_stats, stats, indent=2)

    print(f"", file=sys.stderr)
    print(f"Cumulative report generated:", file=sys.stderr)
    print(f"  Total reads: {total_reads}", file=sys.stderr)
    print(f"  Classified: {classified_reads} ({report_stats['classification_rate']*100:.1f}%)", file=sys.stderr)
    print(f"  Batches merged: {len(report_files)}", file=sys.stderr)

    # Generate versions.yml
    with open('versions.yml', 'w') as v:
        v.write('"${task.process}":\n')
        v.write(f'    python: {sys.version.split()[0]}\n')
        # Try to get KrakenTools version
        try:
            kt_version = subprocess.run(
                ['combine_kreports.py', '--version'],
                capture_output=True, text=True
            ).stdout.strip() or '1.2'
        except:
            kt_version = '1.2'
        v.write(f'    krakentools: {kt_version}\n')
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.cumulative.kraken2.report.txt
    echo '{"sample_id": "${meta.id}", "total_reads": 0, "classified_reads": 0}' > report_stats.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/Python //g')
        krakentools: 1.2
    END_VERSIONS
    """
}
