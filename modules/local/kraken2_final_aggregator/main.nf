process KRAKEN2_FINAL_AGGREGATOR {
    tag "${meta.id}"
    label 'process_low'
    // End-of-session aggregation: receives all batch files via Nextflow channels,
    // concatenates outputs and merges reports into cumulative files.
    // Stateless: all input arrives via channels, no outdir reads.

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'quay.io/biocontainers/python:3.11' }"

    input:
    tuple val(meta), path(batch_outputs), path(batch_reports)

    output:
    tuple val(meta), path("${meta.id}.cumulative.kraken2.output.txt"), emit: cumulative_output
    tuple val(meta), path("${meta.id}.cumulative.kraken2.report.txt"), emit: cumulative_report
    tuple val(meta), path("aggregation_stats.json"),                   emit: stats
    path  "versions.yml",                                              emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = meta.id
    """
    #!/usr/bin/env python3

    import json
    import sys
    import glob
    from pathlib import Path

    sample_id = '${meta.id}'
    expected_batches = ${meta.batch_count ?: 0}

    print(f"Final aggregation for sample {sample_id}", file=sys.stderr)

    # Discover batch files staged into the work directory by Nextflow
    # Files are staged flat or as a list depending on channel cardinality
    batch_output_files = sorted(glob.glob('batch_*.kraken2.output.txt'))
    batch_report_files = sorted(glob.glob('batch_*.kraken2.report.txt'))

    print(f"  Found {len(batch_output_files)} output files, {len(batch_report_files)} report files", file=sys.stderr)

    if expected_batches > 0:
        if len(batch_output_files) != expected_batches:
            print(f"  WARNING: Expected {expected_batches} output files, found {len(batch_output_files)}", file=sys.stderr)
        if len(batch_report_files) != expected_batches:
            print(f"  WARNING: Expected {expected_batches} report files, found {len(batch_report_files)}", file=sys.stderr)

    # Concatenate all batch output files
    cumulative_output_file = f'{sample_id}.cumulative.kraken2.output.txt'
    total_reads = 0
    classified_reads = 0

    with open(cumulative_output_file, 'w') as out:
        for batch_file in batch_output_files:
            with open(batch_file) as f:
                for line in f:
                    out.write(line)
                    total_reads += 1
                    if line.startswith('C\\t'):
                        classified_reads += 1

    print(f"  Concatenated {total_reads} reads to cumulative output", file=sys.stderr)

    # Merge all batch reports to create cumulative report
    cumulative_report_file = f'{sample_id}.cumulative.kraken2.report.txt'
    merged_taxa = {}

    for report_file in batch_report_files:
        with open(report_file) as f:
            for line in f:
                line = line.rstrip('\\n')
                if not line or line.startswith('#'):
                    continue
                parts = line.split('\\t')
                if len(parts) >= 6:
                    try:
                        reads = int(parts[2])
                        cumul = int(parts[1])
                        rank = parts[3]
                        taxid = parts[4]
                        name = parts[5] if len(parts) > 5 else ''

                        if taxid not in merged_taxa:
                            merged_taxa[taxid] = {
                                'reads': 0,
                                'cumul': 0,
                                'rank': rank,
                                'name': name
                            }
                        merged_taxa[taxid]['reads'] += reads
                        merged_taxa[taxid]['cumul'] += cumul
                    except (ValueError, IndexError):
                        continue

    # Write merged report in standard Kraken2 format
    with open(cumulative_report_file, 'w') as out:
        sorted_taxa = sorted(merged_taxa.items(), key=lambda x: (-x[1]['cumul'], x[0]))
        for taxid, data in sorted_taxa:
            pct = (data['cumul'] / total_reads * 100) if total_reads > 0 else 0
            out.write(f"{pct:.2f}\\t{data['cumul']}\\t{data['reads']}\\t{data['rank']}\\t{taxid}\\t{data['name']}\\n")

    print(f"  Generated cumulative report with {len(merged_taxa)} taxa", file=sys.stderr)

    # Generate aggregation statistics
    stats = {
        'sample_id': sample_id,
        'expected_batches': expected_batches,
        'total_batches': len(batch_output_files),
        'batches_complete': len(batch_output_files) == expected_batches if expected_batches > 0 else True,
        'total_reads': total_reads,
        'classified_reads': classified_reads,
        'unclassified_reads': total_reads - classified_reads,
        'classification_rate': classified_reads / total_reads if total_reads > 0 else 0,
        'unique_taxa': len(merged_taxa),
        'cumulative_output': cumulative_output_file,
        'cumulative_report': cumulative_report_file
    }

    with open('aggregation_stats.json', 'w') as f:
        json.dump(stats, f, indent=2)

    print(f"  Total batches: {len(batch_output_files)}", file=sys.stderr)
    print(f"  Total reads: {total_reads}", file=sys.stderr)
    print(f"  Classification rate: {stats['classification_rate']*100:.1f}%", file=sys.stderr)

    # Generate versions.yml
    with open('versions.yml', 'w') as v:
        v.write('"${task.process}":\\n')
        v.write(f'    python: {sys.version.split()[0]}\\n')
    """

    stub:
    def prefix = meta.id
    """
    touch ${prefix}.cumulative.kraken2.output.txt
    touch ${prefix}.cumulative.kraken2.report.txt
    echo '{"sample_id": "${meta.id}", "total_batches": 0, "total_reads": 0}' > aggregation_stats.json

cat <<-END_VERSIONS > versions.yml
"${task.process}":
    python: 3.11
END_VERSIONS
    """
}
