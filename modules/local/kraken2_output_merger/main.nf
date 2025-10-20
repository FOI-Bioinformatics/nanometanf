process KRAKEN2_OUTPUT_MERGER {
    tag "${meta.id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'quay.io/biocontainers/python:3.11' }"

    input:
    tuple val(meta), path(kraken2_outputs)
    path  batch_metadata_files

    output:
    tuple val(meta), path("*.cumulative.kraken2.output.txt"), emit: cumulative_output
    tuple val(meta), path("merge_stats.json"), emit: stats
    path  "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env python3

    import json
    import sys
    from pathlib import Path

    # Load all batch metadata files
    metadata = []
    metadata_files = "${batch_metadata_files}".split()

    for f in metadata_files:
        with open(f) as fh:
            metadata.append(json.load(fh))

    # Sort by batch_id to ensure correct order
    metadata.sort(key=lambda x: x['batch_id'])

    print(f"Merging {len(metadata)} batch outputs for sample ${meta.id}", file=sys.stderr)

    # Concatenate outputs in batch order
    total_reads = 0
    with open('${prefix}.cumulative.kraken2.output.txt', 'w') as out:
        for m in metadata:
            # Find the corresponding output file
            output_basename = Path(m['kraken2_output']).name

            # Search for the file in the current directory
            output_file = None
            for f in Path('.').glob('*.kraken2.output.txt'):
                if f.name == output_basename or \
                   f.name.startswith(f"${meta.id}_batch{m['batch_id']}"):
                    output_file = f
                    break

            if output_file is None:
                print(f"WARNING: Could not find output for batch {m['batch_id']}", file=sys.stderr)
                continue

            print(f"  Batch {m['batch_id']}: {m['classification_statistics']['total_sequences']} reads", file=sys.stderr)

            with open(output_file) as f:
                lines = f.readlines()
                out.writelines(lines)
                total_reads += len(lines)

    # Generate merge statistics
    merge_stats = {
        'sample_id': '${meta.id}',
        'total_batches': len(metadata),
        'total_reads': total_reads,
        'batches': [m['batch_id'] for m in metadata],
        'cumulative_output': '${prefix}.cumulative.kraken2.output.txt'
    }

    with open('merge_stats.json', 'w') as stats:
        json.dump(merge_stats, stats, indent=2)

    print(f"", file=sys.stderr)
    print(f"Merge complete: {total_reads} total reads from {len(metadata)} batches", file=sys.stderr)

    # Generate versions.yml
    with open('versions.yml', 'w') as v:
        v.write('"${task.process}":\n')
        v.write(f'    python: {sys.version.split()[0]}\n')
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.cumulative.kraken2.output.txt
    echo '{"sample_id": "${meta.id}", "total_batches": 0, "total_reads": 0}' > merge_stats.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/Python //g')
    END_VERSIONS
    """
}
