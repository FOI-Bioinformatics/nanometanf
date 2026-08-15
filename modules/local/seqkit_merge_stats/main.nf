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
    def barcode = meta.barcode ?: 'no_barcode'

    // The Python aggregator is emitted via a heredoc rather than the bare
    // shebang form. Earlier revisions relied on a `#!/usr/bin/env python3`
    // shebang at the top of the script block, but Nextflow's process body
    // preserves the leading indentation of every line in the rendered
    // .command.sh, so Python tripped on `IndentationError: unexpected
    // indent` at the very first import. Writing the script to a temporary
    // file via `cat <<'PYEOF' > merge.py` lets Python receive the body
    // verbatim, with indentation that the interpreter actually expects.
    """
    cat <<'PYEOF' > merge.py
import sys
import json
from pathlib import Path

batch_files = sorted(Path('.').glob('batch_*.tsv'))

if not batch_files:
    print("ERROR: No batch statistics files found", file=sys.stderr)
    sys.exit(1)

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

# Header: file format type num_seqs sum_len min_len avg_len max_len Q1 Q2 Q3 sum_gap N50 N50_num Q20(%) Q30(%) AvgQual GC(%) sum_n

total_num_seqs = 0
total_sum_len = 0
total_sum_gap = 0
total_sum_n = 0
min_len = None
max_len = 0

weighted_q20 = 0.0
weighted_q30 = 0.0
weighted_avgqual = 0.0
weighted_gc = 0.0


def safe_int(value):
    try:
        return int(value)
    except (ValueError, TypeError):
        return 0


def safe_float(value):
    try:
        return float(str(value).replace('%', ''))
    except (ValueError, TypeError):
        return 0.0


for stats in all_stats:
    num_seqs = safe_int(stats[3])
    sum_len = safe_int(stats[4])
    this_min = safe_int(stats[5])
    this_max = safe_int(stats[7])
    sum_gap = safe_int(stats[10]) if len(stats) > 10 else 0
    sum_n = safe_int(stats[18]) if len(stats) > 18 else 0

    q20_pct = safe_float(stats[13]) if len(stats) > 13 else 0.0
    q30_pct = safe_float(stats[14]) if len(stats) > 14 else 0.0
    avgqual = safe_float(stats[15]) if len(stats) > 15 else 0.0
    gc_pct = safe_float(stats[16]) if len(stats) > 16 else 0.0

    total_num_seqs += num_seqs
    total_sum_len += sum_len
    total_sum_gap += sum_gap
    total_sum_n += sum_n

    # Empty batches report min_len = 0; ignore them so the cumulative
    # min_len reflects only batches that contributed reads.
    if num_seqs > 0:
        min_len = this_min if min_len is None else min(min_len, this_min)
        max_len = max(max_len, this_max)

    weighted_q20 += q20_pct * sum_len
    weighted_q30 += q30_pct * sum_len
    weighted_avgqual += avgqual * sum_len
    weighted_gc += gc_pct * sum_len

if min_len is None:
    min_len = 0

avg_len = total_sum_len / total_num_seqs if total_num_seqs > 0 else 0
final_q20 = weighted_q20 / total_sum_len if total_sum_len > 0 else 0.0
final_q30 = weighted_q30 / total_sum_len if total_sum_len > 0 else 0.0
final_avgqual = weighted_avgqual / total_sum_len if total_sum_len > 0 else 0.0
final_gc = weighted_gc / total_sum_len if total_sum_len > 0 else 0.0

# Quartile and N50 approximations -- cumulative stats do not expose the
# raw read-length distribution.
q1_approx = avg_len * 0.75
q2_approx = avg_len
q3_approx = avg_len * 1.5
n50_approx = int(avg_len)
n50_num_approx = total_num_seqs // 2

with open('${prefix}.cumulative.tsv', 'w') as f:
    f.write(header + '\\n')
    f.write('\\t'.join([
        '${prefix}.cumulative.fastq.gz',
        'FASTQ',
        'DNA',
        str(total_num_seqs),
        str(total_sum_len),
        str(min_len),
        '{:.1f}'.format(avg_len),
        str(max_len),
        '{:.1f}'.format(q1_approx),
        '{:.1f}'.format(q2_approx),
        '{:.1f}'.format(q3_approx),
        str(total_sum_gap),
        str(n50_approx),
        str(n50_num_approx),
        '{:.2f}'.format(final_q20),
        '{:.2f}'.format(final_q30),
        '{:.2f}'.format(final_avgqual),
        '{:.2f}'.format(final_gc),
        str(total_sum_n),
    ]) + '\\n')

manifest = {
    "sample_id": "${meta.id}",
    "barcode": "${barcode}",
    "merge_timestamp": "${merge_timestamp}",
    "num_batches_merged": len(batch_files),
    "total_sequences": total_num_seqs,
    "total_bases": total_sum_len,
    "batch_files": [str(f) for f in batch_files],
    "note": "Q1/Q2/Q3/N50 values are approximations from cumulative statistics",
}

with open('${prefix}.merge_stats.json', 'w') as f:
    json.dump(manifest, f, indent=2)

print('Merged {} batch statistics files'.format(len(batch_files)))
print('Total sequences: {:,}'.format(total_num_seqs))
print('Total bases: {:,}'.format(total_sum_len))
PYEOF

    python3 merge.py

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
    python: 3.12
END_VERSIONS
    """
}
