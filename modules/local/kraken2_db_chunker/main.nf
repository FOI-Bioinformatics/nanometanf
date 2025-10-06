process KRAKEN2_DB_CHUNKER {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'biocontainers/python:3.11' }"

    input:
    tuple val(meta), path(reads)
    path  db_chunks   // List of database chunk directories
    val   merge_strategy  // How to merge results: 'union', 'intersection', 'consensus'

    output:
    tuple val(meta), path('*merged_report.txt')          , emit: merged_report
    tuple val(meta), path('*chunk_reports')              , emit: chunk_reports
    path  "${prefix}.chunking_performance.json"          , emit: performance_metrics
    path  "versions.yml"                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env python3
    import json
    import os
    import sys
    from datetime import datetime
    from pathlib import Path
    from collections import defaultdict

    reads_path = "${reads}"
    db_chunks = ${groovy.json.JsonOutput.toJson(db_chunks)}
    merge_strategy = "${merge_strategy}"
    prefix = "${prefix}"

    # Create output directory for individual chunk reports
    chunk_reports_dir = Path(f"{prefix}.chunk_reports")
    chunk_reports_dir.mkdir(exist_ok=True)

    def parse_kraken2_report(report_path):
        \"\"\"
        Parse Kraken2 report file.

        Format:
        % of reads, num reads clade, num reads taxon, rank, taxid, name
        \"\"\"
        classifications = {}

        if not Path(report_path).exists():
            return classifications

        with open(report_path, 'r') as f:
            for line in f:
                parts = line.strip().split('\\t')
                if len(parts) < 6:
                    continue

                percent = float(parts[0])
                clade_count = int(parts[1])
                taxon_count = int(parts[2])
                rank = parts[3]
                taxid = int(parts[4])
                name = parts[5].strip()

                classifications[taxid] = {
                    'percent': percent,
                    'clade_count': clade_count,
                    'taxon_count': taxon_count,
                    'rank': rank,
                    'name': name
                }

        return classifications

    def merge_classifications(chunk_results, strategy='union'):
        \"\"\"
        Merge classifications from multiple database chunks.

        Strategies:
        - union: Include all taxa from any chunk (most sensitive)
        - intersection: Only include taxa found in all chunks (most specific)
        - consensus: Include taxa found in majority of chunks (balanced)
        \"\"\"
        if not chunk_results:
            return {}

        if strategy == 'union':
            # Combine all taxa, sum counts
            merged = defaultdict(lambda: {
                'clade_count': 0,
                'taxon_count': 0,
                'rank': '',
                'name': '',
                'chunk_sources': []
            })

            for chunk_id, classifications in chunk_results.items():
                for taxid, data in classifications.items():
                    merged[taxid]['clade_count'] += data['clade_count']
                    merged[taxid]['taxon_count'] += data['taxon_count']
                    merged[taxid]['rank'] = data['rank']
                    merged[taxid]['name'] = data['name']
                    merged[taxid]['chunk_sources'].append(chunk_id)

            return dict(merged)

        elif strategy == 'intersection':
            # Only keep taxa found in ALL chunks
            if not chunk_results:
                return {}

            # Get taxa IDs from first chunk
            common_taxa = set(list(chunk_results.values())[0].keys())

            # Intersect with other chunks
            for classifications in chunk_results.values():
                common_taxa &= set(classifications.keys())

            # Build merged results for common taxa
            merged = {}
            for taxid in common_taxa:
                merged[taxid] = {
                    'clade_count': sum(
                        chunk_results[cid][taxid]['clade_count']
                        for cid in chunk_results
                    ),
                    'taxon_count': sum(
                        chunk_results[cid][taxid]['taxon_count']
                        for cid in chunk_results
                    ),
                    'rank': chunk_results[list(chunk_results.keys())[0]][taxid]['rank'],
                    'name': chunk_results[list(chunk_results.keys())[0]][taxid]['name'],
                    'chunk_sources': list(chunk_results.keys())
                }

            return merged

        elif strategy == 'consensus':
            # Include taxa found in majority of chunks
            taxa_counts = defaultdict(int)
            all_data = defaultdict(list)

            for chunk_id, classifications in chunk_results.items():
                for taxid, data in classifications.items():
                    taxa_counts[taxid] += 1
                    all_data[taxid].append((chunk_id, data))

            num_chunks = len(chunk_results)
            majority_threshold = num_chunks / 2

            merged = {}
            for taxid, count in taxa_counts.items():
                if count >= majority_threshold:
                    # This taxon is in majority of chunks
                    chunk_data = all_data[taxid]
                    merged[taxid] = {
                        'clade_count': sum(d['clade_count'] for _, d in chunk_data),
                        'taxon_count': sum(d['taxon_count'] for _, d in chunk_data),
                        'rank': chunk_data[0][1]['rank'],
                        'name': chunk_data[0][1]['name'],
                        'chunk_sources': [cid for cid, _ in chunk_data],
                        'consensus_strength': count / num_chunks
                    }

            return merged

        else:
            raise ValueError(f"Unknown merge strategy: {strategy}")

    # Note: This is a simulation/planning module
    # Actual multi-DB classification would require multiple Kraken2 runs
    # This module demonstrates the chunking strategy

    print(f"\\nDatabase Chunking Configuration:", file=sys.stderr)
    print(f"  Number of DB chunks: {len(db_chunks)}", file=sys.stderr)
    print(f"  Merge strategy: {merge_strategy}", file=sys.stderr)
    print(f"  Sample: {prefix}", file=sys.stderr)

    # Generate performance metrics
    performance_metrics = {
        'sample_id': prefix,
        'timestamp': datetime.now().isoformat(),
        'chunking_configuration': {
            'num_chunks': len(db_chunks),
            'merge_strategy': merge_strategy,
            'chunk_paths': [str(p) for p in db_chunks]
        },
        'performance_estimate': {
            'expected_speedup': f'{len(db_chunks)}x (parallel)',
            'memory_reduction': f'{100 / len(db_chunks):.1f}% per chunk',
            'accuracy_impact': {
                'union': 'High sensitivity, may include false positives',
                'intersection': 'High specificity, may miss true positives',
                'consensus': 'Balanced sensitivity and specificity'
            }[merge_strategy]
        }
    }

    # Write performance metrics
    with open(f'{prefix}.chunking_performance.json', 'w') as f:
        json.dump(performance_metrics, f, indent=2)

    # Create placeholder merged report
    with open(f'{prefix}.kraken2.merged_report.txt', 'w') as f:
        f.write(f"# Kraken2 Database Chunking Report\\n")
        f.write(f"# Sample: {prefix}\\n")
        f.write(f"# Chunks: {len(db_chunks)}\\n")
        f.write(f"# Merge strategy: {merge_strategy}\\n")
        f.write(f"#\\n")
        f.write(f"# Note: This is a chunking strategy demonstration\\n")
        f.write(f"# Actual implementation requires running Kraken2 on each chunk\\n")

    print(f"\\n{'='*60}", file=sys.stderr)
    print("Database Chunking Strategy Created", file=sys.stderr)
    print(f"{'='*60}", file=sys.stderr)
    print(f"This module demonstrates database chunking for large datasets.", file=sys.stderr)
    print(f"\\nFor production use:", file=sys.stderr)
    print(f"  1. Split your database into {len(db_chunks)} chunks", file=sys.stderr)
    print(f"  2. Run Kraken2 on each chunk in parallel", file=sys.stderr)
    print(f"  3. Merge results using '{merge_strategy}' strategy", file=sys.stderr)
    print(f"\\nExpected benefits:", file=sys.stderr)
    print(f"  - Memory: {100 / len(db_chunks):.1f}% per chunk (vs. 100% for full DB)", file=sys.stderr)
    print(f"  - Speed: Up to {len(db_chunks)}x with parallel execution", file=sys.stderr)
    print(f"  - Accuracy: Depends on merge strategy chosen", file=sys.stderr)
    print(f"{'='*60}", file=sys.stderr)

    # Write versions
    with open('versions.yml', 'w') as f:
        f.write('"${task.process}":\\n')
        f.write(f'  python: {sys.version.split()[0]}\\n')
    """

    stub:
    """
    mkdir -p ${prefix}.chunk_reports
    touch ${prefix}.kraken2.merged_report.txt
    echo '{"sample_id": "${prefix}", "chunking_configuration": {"num_chunks": 1}}' > ${prefix}.chunking_performance.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/Python //g')
    END_VERSIONS
    """
}
