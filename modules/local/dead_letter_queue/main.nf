process DEAD_LETTER_QUEUE {
    tag "$prefix"
    label 'process_single'
    publishDir "${params.outdir}/failed_samples", mode: params.publish_dir_mode

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'biocontainers/python:3.11' }"

    input:
    val(failed_samples)  // List of failed sample records
    val(prefix)

    output:
    path "failed_samples_manifest.json", emit: manifest
    path "failed_samples_summary.txt" , emit: summary
    path "failed_samples/*.json"       , emit: individual_reports, optional: true
    path "versions.yml"                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    #!/usr/bin/env python3
    import json
    import os
    import sys
    from datetime import datetime
    from pathlib import Path
    from collections import Counter

    failed_samples = ${groovy.json.JsonOutput.toJson(failed_samples)}

    # Create directory for individual failure reports
    Path('failed_samples').mkdir(exist_ok=True)

    # Process each failed sample
    processed_failures = []
    for sample in failed_samples:
        sample_id = sample.get('sample_id', 'unknown')
        error_message = sample.get('error_message', 'No error message')
        error_category = sample.get('error_category', 'unknown')
        retry_count = sample.get('retry_count', 0)
        timestamp = sample.get('timestamp', datetime.now().isoformat())

        # Create individual failure report
        failure_report = {
            'sample_id': sample_id,
            'failure_timestamp': timestamp,
            'error_details': {
                'message': error_message,
                'category': error_category,
                'type': sample.get('error_type', 'unknown')
            },
            'retry_history': {
                'attempts': retry_count,
                'max_retries_exceeded': True
            },
            'metadata': sample.get('metadata', {}),
            'recommended_action': get_recommendation(error_category)
        }

        # Write individual report
        report_path = f"failed_samples/{sample_id}_failure.json"
        with open(report_path, 'w') as f:
            json.dump(failure_report, f, indent=2)

        processed_failures.append(failure_report)
        print(f"💀 DEAD LETTER: {sample_id} - {error_category}", file=sys.stderr)

    def get_recommendation(category):
        \"\"\"Get remediation recommendation based on error category.\"\"\"
        recommendations = {
            'file_io': 'Check file permissions and disk space. Verify file paths are accessible.',
            'resource_exhaustion': 'Increase resource allocation (memory/disk). Check for resource leaks.',
            'transient_network': 'Verify network connectivity. Check firewall/proxy settings.',
            'data_corruption': 'Re-download or regenerate input files. Verify data integrity.',
            'configuration': 'Review pipeline parameters. Check configuration file syntax.',
            'unsupported': 'Upgrade software version or use compatible file format.',
            'unknown': 'Review error logs for additional context. Contact support if issue persists.'
        }
        return recommendations.get(category, recommendations['unknown'])

    # Generate summary statistics
    total_failures = len(processed_failures)
    error_categories = Counter(f['error_details']['category'] for f in processed_failures)
    affected_samples = [f['sample_id'] for f in processed_failures]

    # Create manifest
    manifest = {
        'generated_at': datetime.now().isoformat(),
        'total_failed_samples': total_failures,
        'error_category_distribution': dict(error_categories),
        'failed_sample_ids': affected_samples,
        'individual_reports_directory': 'failed_samples/',
        'recovery_instructions': {
            'manual_review': 'Review individual failure reports in failed_samples/ directory',
            'resubmission': 'Fix underlying issues and resubmit failed samples with original input files',
            'support': 'Contact pipeline maintainer with failed_samples_manifest.json for assistance'
        }
    }

    # Write manifest
    with open('failed_samples_manifest.json', 'w') as f:
        json.dump(manifest, f, indent=2)

    # Generate human-readable summary
    summary_lines = [
        "=" * 80,
        "FAILED SAMPLES SUMMARY - DEAD LETTER QUEUE",
        "=" * 80,
        f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"Total Failed Samples: {total_failures}",
        "",
        "Error Category Distribution:",
    ]

    for category, count in error_categories.most_common():
        percentage = (count / total_failures * 100) if total_failures > 0 else 0
        summary_lines.append(f"  {category:30s}: {count:3d} ({percentage:5.1f}%)")

    summary_lines.extend([
        "",
        "Failed Sample IDs:",
    ])

    for sample_id in affected_samples:
        summary_lines.append(f"  - {sample_id}")

    summary_lines.extend([
        "",
        "Next Steps:",
        "  1. Review individual failure reports in failed_samples/ directory",
        "  2. Address underlying issues based on error categories",
        "  3. Resubmit failed samples after fixes",
        "",
        "=" * 80
    ])

    with open('failed_samples_summary.txt', 'w') as f:
        f.write('\\n'.join(summary_lines))

    # Print summary to stderr
    print("", file=sys.stderr)
    print("=" * 80, file=sys.stderr)
    print(f"💀 DEAD LETTER QUEUE: {total_failures} samples failed permanently", file=sys.stderr)
    print("=" * 80, file=sys.stderr)
    for category, count in error_categories.most_common():
        print(f"   {category}: {count} samples", file=sys.stderr)
    print(f"\\n   📋 Manifest: failed_samples_manifest.json", file=sys.stderr)
    print(f"   📄 Summary: failed_samples_summary.txt", file=sys.stderr)
    print("=" * 80, file=sys.stderr)

    # Write versions
    with open('versions.yml', 'w') as f:
        f.write('"${task.process}":\\n')
        f.write(f'  python: {sys.version.split()[0]}\\n')
    """

    stub:
    """
    mkdir -p failed_samples
    echo '{"generated_at": "2025-01-01T00:00:00", "total_failed_samples": 0}' > failed_samples_manifest.json
    echo "No failed samples" > failed_samples_summary.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/Python //g')
    END_VERSIONS
    """
}
