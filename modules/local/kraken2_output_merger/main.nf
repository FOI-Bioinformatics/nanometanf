process KRAKEN2_OUTPUT_MERGER {
    tag "${meta.id}_batch${meta.batch_id}"
    label 'process_low'
    // SCALABLE STREAMING: Stateless batch organizer
    // Each invocation writes only its own batch files to the work directory.
    // No shared state, no outdir reads. publishDir handled via modules.config.

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'quay.io/biocontainers/python:3.11' }"

    input:
    tuple val(meta), path(kraken2_output), path(batch_metadata), path(batch_report)

    output:
    tuple val(meta), path("batches/batch_${meta.batch_id}.kraken2.output.txt"),                                         emit: batch_output
    tuple val(meta), path("batch_reports/batch_${meta.batch_id}.kraken2.report.txt"),                                    emit: batch_report_copy
    tuple val(meta), path("batches/batch_${meta.batch_id}.kraken2.output.txt"), path("batch_reports/batch_${meta.batch_id}.kraken2.report.txt"), emit: merger_output
    tuple val(meta), path("merge_stats.json"),                                                                           emit: stats
    path  "versions.yml",                                                                                                emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = meta.id
    def batch_id = meta.batch_id
    """
    #!/usr/bin/env python3

    import json
    import sys
    import shutil
    from pathlib import Path

    batch_id = ${batch_id}
    sample_id = '${prefix}'

    print(f"Processing batch {batch_id} for sample {sample_id}", file=sys.stderr)

    # Create output directories in work dir only
    batches_dir = Path('batches')
    reports_dir = Path('batch_reports')
    batches_dir.mkdir(parents=True, exist_ok=True)
    reports_dir.mkdir(parents=True, exist_ok=True)

    # APPEND-ONLY STORAGE: Write batch to separate file (O(1) per batch)
    batch_output_file = batches_dir / f'batch_{batch_id}.kraken2.output.txt'
    batch_report_file = reports_dir / f'batch_{batch_id}.kraken2.report.txt'

    # Count reads in current batch
    current_reads = 0
    classified_reads = 0

    with open('${kraken2_output}') as f_in, open(batch_output_file, 'w') as f_out:
        for line in f_in:
            f_out.write(line)
            current_reads += 1
            if line.startswith('C\\t'):
                classified_reads += 1

    print(f"  Batch {batch_id}: {current_reads} reads ({classified_reads} classified)", file=sys.stderr)

    # Copy batch report
    shutil.copy('${batch_report}', batch_report_file)

    # Generate merge statistics (local to this batch only)
    merge_stats = {
        'sample_id': sample_id,
        'batch_id': batch_id,
        'batch_reads': current_reads,
        'batch_classified_reads': classified_reads,
        'batch_output_file': str(batch_output_file),
        'batch_report_file': str(batch_report_file)
    }

    with open('merge_stats.json', 'w') as stats:
        json.dump(merge_stats, stats, indent=2)

    print(f"  Output: {batch_output_file}", file=sys.stderr)
    print(f"  Report: {batch_report_file}", file=sys.stderr)

    # Generate versions.yml
    with open('versions.yml', 'w') as v:
        v.write('"${task.process}":\\n')
        v.write(f'    python: {sys.version.split()[0]}\\n')
    """

    stub:
    def prefix = meta.id
    def batch_id = meta.batch_id
    """
    mkdir -p batches batch_reports
    touch batches/batch_${batch_id}.kraken2.output.txt
    touch batch_reports/batch_${batch_id}.kraken2.report.txt
    echo '{"sample_id": "${prefix}", "batch_id": ${batch_id}, "batch_reads": 0}' > merge_stats.json

cat <<-END_VERSIONS > versions.yml
"${task.process}":
    python: 3.11
END_VERSIONS
    """
}
