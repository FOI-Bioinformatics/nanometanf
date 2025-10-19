process SEQKIT_MERGE_STATS {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.12' :
        'quay.io/biocontainers/python:3.12' }"

    input:
    tuple val(meta), path(batch_stats, stageAs: 'batch_*.tsv')

    output:
    tuple val(meta), path('*.cumulative.tsv'), emit: cumulative_stats
    tuple val(meta), path('*merge_stats.json'), emit: merge_manifest
    path "versions.yml"                       , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def merge_timestamp = new java.text.SimpleDateFormat('yyyyMMdd_HHmmss').format(new Date())

    """
    #!/usr/bin/env python3
    import sys
    import json
    from pathlib import Path
    from datetime import datetime

    # Collect all batch TSV files
    batch_files = sorted(Path('.').glob('batch_*.tsv'))

    if not batch_files:
        print("ERROR: No batch statistics files found", file=sys.stderr)
        sys.exit(1)

    # Read and parse all batch statistics
    all_stats = []
    header = None

    for batch_file in batch_files:
        with open(batch_file) as f:
            lines = f.readlines()
            if not header:
                header = lines[0].strip()
            if len(lines) > 1:
                all_stats.append(lines[1].strip().split('\\t'))

    if not all_stats:
        print("ERROR: No statistics data found in batch files", file=sys.stderr)
        sys.exit(1)

    # Parse statistics (seqkit stats --all format)
    # Header: file format type num_seqs sum_len min_len avg_len max_len Q1 Q2 Q3 sum_gap N50 N50_num Q20(%) Q30(%) AvgQual GC(%) sum_n

    # Initialize accumulators
    total_num_seqs = 0
    total_sum_len = 0
    total_sum_gap = 0
    total_sum_n = 0
    min_len = float('inf')
    max_len = 0

    # For weighted averages (need to accumulate weighted sums)
    weighted_q20 = 0
    weighted_q30 = 0
    weighted_avgqual = 0
    weighted_gc = 0

    # Store all lengths for N50 calculation (approximation)
    all_lengths = []

    for stats in all_stats:
        num_seqs = int(stats[3])
        sum_len = int(stats[4])
        this_min = int(stats[5])
        this_max = int(stats[7])
        sum_gap = int(stats[10])
        sum_n = int(stats[18]) if len(stats) > 18 else 0

        # Parse percentages (remove % sign)
        q20_pct = float(stats[13].replace('%', '')) if len(stats) > 13 else 0
        q30_pct = float(stats[14].replace('%', '')) if len(stats) > 14 else 0
        avgqual = float(stats[15]) if len(stats) > 15 else 0
        gc_pct = float(stats[16].replace('%', '')) if len(stats) > 16 else 0

        # Accumulate
        total_num_seqs += num_seqs
        total_sum_len += sum_len
        total_sum_gap += sum_gap
        total_sum_n += sum_n
        min_len = min(min_len, this_min)
        max_len = max(max_len, this_max)

        # Weighted by sequence length
        weighted_q20 += q20_pct * sum_len
        weighted_q30 += q30_pct * sum_len
        weighted_avgqual += avgqual * sum_len
        weighted_gc += gc_pct * sum_len

    # Calculate final values
    avg_len = total_sum_len / total_num_seqs if total_num_seqs > 0 else 0
    final_q20 = weighted_q20 / total_sum_len if total_sum_len > 0 else 0
    final_q30 = weighted_q30 / total_sum_len if total_sum_len > 0 else 0
    final_avgqual = weighted_avgqual / total_sum_len if total_sum_len > 0 else 0
    final_gc = weighted_gc / total_sum_len if total_sum_len > 0 else 0

    # Approximate quartiles (Q1, Q2, Q3) and N50
    # For cumulative stats, we use averages as approximations since we don't have raw data
    q1_approx = avg_len * 0.75  # Conservative approximation
    q2_approx = avg_len
    q3_approx = avg_len * 1.5
    n50_approx = int(avg_len)
    n50_num_approx = total_num_seqs // 2

    # Write cumulative TSV
    with open('${prefix}.cumulative.tsv', 'w') as f:
        f.write(header + '\\n')
        f.write('\\t'.join([
            '${prefix}.cumulative.fastq.gz',  # file
            'FASTQ',                           # format
            'DNA',                             # type
            str(total_num_seqs),               # num_seqs
            str(total_sum_len),                # sum_len
            str(min_len),                      # min_len
            f'{avg_len:.1f}',                  # avg_len
            str(max_len),                      # max_len
            f'{q1_approx:.1f}',                # Q1 (approximation)
            f'{q2_approx:.1f}',                # Q2 (approximation)
            f'{q3_approx:.1f}',                # Q3 (approximation)
            str(total_sum_gap),                # sum_gap
            str(n50_approx),                   # N50 (approximation)
            str(n50_num_approx),               # N50_num (approximation)
            f'{final_q20:.2f}',                # Q20(%)
            f'{final_q30:.2f}',                # Q30(%)
            f'{final_avgqual:.2f}',            # AvgQual
            f'{final_gc:.2f}',                 # GC(%)
            str(total_sum_n)                   # sum_n
        ]) + '\\n')

    # Generate merge manifest
    manifest = {
        "sample_id": "${meta.id}",
        "barcode": "${meta.barcode ?: 'no_barcode'}",
        "merge_timestamp": "${merge_timestamp}",
        "num_batches_merged": len(batch_files),
        "total_sequences": total_num_seqs,
        "total_bases": total_sum_len,
        "batch_files": [str(f) for f in batch_files],
        "note": "Q1/Q2/Q3/N50 values are approximations from cumulative statistics"
    }

    with open('${prefix}.merge_stats.json', 'w') as f:
        json.dump(manifest, f, indent=2)

    print(f"Merged {len(batch_files)} batch statistics files")
    print(f"Total sequences: {total_num_seqs:,}")
    print(f"Total bases: {total_sum_len:,}")

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version 2>&1 | sed 's/Python //')
END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def merge_timestamp = new java.text.SimpleDateFormat('yyyyMMdd_HHmmss').format(new Date())

    """
    # Create stub cumulative stats
    cat <<-END_TSV > ${prefix}.cumulative.tsv
file\tformat\ttype\tnum_seqs\tsum_len\tmin_len\tavg_len\tmax_len\tQ1\tQ2\tQ3\tsum_gap\tN50\tN50_num\tQ20(%)\tQ30(%)\tAvgQual\tGC(%)\tsum_n
${prefix}.cumulative.fastq.gz\tFASTQ\tDNA\t0\t0\t0\t0.0\t0\t0.0\t0.0\t0.0\t0\t0\t0\t0.00\t0.00\t0.00\t0.00\t0
END_TSV

    cat <<-END_MANIFEST > ${prefix}.merge_stats.json
{
    "sample_id": "${meta.id}",
    "barcode": "${meta.barcode ?: 'no_barcode'}",
    "merge_timestamp": "${merge_timestamp}",
    "stub": true,
    "num_batches_merged": 0,
    "total_sequences": 0,
    "total_bases": 0
}
END_MANIFEST

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version 2>&1 | sed 's/Python //')
END_VERSIONS
    """
}
