process KRAKEN2_REPORT_GENERATOR {
    tag "${meta.id}_batch${meta.batch_id}"
    label 'process_low'
    // SCALABLE STREAMING: Stateless per-batch report processor
    // Parses a single batch report and emits per-batch taxid counts.
    // No shared state, no outdir reads. Cumulative merging done by FINAL_AGGREGATOR.

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/krakentools:1.2--pyh5e36f6f_0' :
        'quay.io/biocontainers/krakentools:1.2--pyh5e36f6f_0' }"

    input:
    tuple val(meta), path(batch_output), path(batch_report)
    path  db

    output:
    tuple val(meta), path("${meta.id}_batch${meta.batch_id}.kraken2.report.txt"), emit: report
    tuple val(meta), path("batch_taxid_counts.json"),                               emit: taxid_counts
    tuple val(meta), path("report_stats.json"),                                     emit: stats
    path  "versions.yml",                                                           emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = meta.id
    def batch_id = meta.batch_id
    def args = task.ext.args ?: ''
    """
    #!/usr/bin/env python3

    import json
    import sys
    import shutil
    from pathlib import Path

    sample_id = '${prefix}'
    batch_id = ${batch_id}

    print(f"Processing report for {sample_id} batch {batch_id}", file=sys.stderr)

    # Parse batch report to extract per-batch taxid counts
    batch_taxa = {}
    batch_total = 0
    batch_classified = 0
    batch_unclassified = 0

    with open('${batch_report}') as f:
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

                    batch_taxa[taxid] = {
                        'reads': reads,
                        'cumul': cumul,
                        'rank': rank,
                        'name': name
                    }

                    if taxid == '0':
                        batch_unclassified = reads
                    elif taxid == '1':
                        batch_classified = cumul
                except (ValueError, IndexError):
                    continue

    batch_total = batch_classified + batch_unclassified

    print(f"  Batch {batch_id}: {batch_total} reads, {len(batch_taxa)} taxa", file=sys.stderr)

    # Copy batch report with standardized naming
    output_report = f'{sample_id}_batch{batch_id}.kraken2.report.txt'
    shutil.copy('${batch_report}', output_report)

    # Emit per-batch taxid counts (stateless - no cumulative state)
    batch_taxid_counts = {
        'sample_id': sample_id,
        'batch_id': batch_id,
        'total_reads': batch_total,
        'classified_reads': batch_classified,
        'unclassified_reads': batch_unclassified,
        'taxa': batch_taxa
    }

    with open('batch_taxid_counts.json', 'w') as f:
        json.dump(batch_taxid_counts, f, indent=2)

    # Generate report statistics
    report_stats = {
        'sample_id': sample_id,
        'batch_id': batch_id,
        'total_reads': batch_total,
        'classified_reads': batch_classified,
        'unclassified_reads': batch_unclassified,
        'classification_rate': batch_classified / batch_total if batch_total > 0 else 0,
        'unique_taxa': len(batch_taxa)
    }

    with open('report_stats.json', 'w') as stats:
        json.dump(report_stats, stats, indent=2)

    print(f"  Classification rate: {report_stats['classification_rate']*100:.1f}%", file=sys.stderr)

    # Generate versions.yml
    with open('versions.yml', 'w') as v:
        v.write('"${task.process}":\\n')
        v.write(f'    python: {sys.version.split()[0]}\\n')
        v.write(f'    krakentools: 1.2\\n')
    """

    stub:
    def prefix = meta.id
    def batch_id = meta.batch_id
    """
    touch ${prefix}_batch${batch_id}.kraken2.report.txt
    echo '{"sample_id": "${prefix}", "batch_id": ${batch_id}, "total_reads": 0, "taxa": {}}' > batch_taxid_counts.json
    echo '{"sample_id": "${prefix}", "batch_id": ${batch_id}, "total_reads": 0}' > report_stats.json

cat <<-END_VERSIONS > versions.yml
"${task.process}":
    python: \$(python3 --version | sed 's/Python //g')
    krakentools: 1.2
END_VERSIONS
    """
}
