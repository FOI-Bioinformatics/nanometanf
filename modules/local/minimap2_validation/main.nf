process MINIMAP2_VALIDATION {
    tag "${meta.id}:taxid${meta.taxid}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/minimap2:2.28--he4a0461_0' :
        'quay.io/biocontainers/minimap2:2.28--he4a0461_0' }"

    input:
    tuple val(meta), path(reads), path(reference)

    output:
    tuple val(meta), path("*.paf"), emit: alignments
    tuple val(meta), path("*.minimap2_stats.json"), emit: stats
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}_taxid${meta.taxid}"
    def preset = task.ext.preset ?: params.minimap2_preset ?: "map-ont"
    def min_mapq = task.ext.min_mapq ?: params.minimap2_min_mapq ?: 10
    def hit_threshold = params.validation_hit_rate_threshold ?: 0.5
    def identity_threshold = params.validation_identity_threshold ?: 90.0
    def sample_id = meta.id
    def taxid = meta.taxid
    """
    #!/bin/bash
    set -euo pipefail

    # Count input reads (handle gzipped files)
    if [[ "${reads}" == *.gz ]]; then
        TOTAL_READS=\$(zcat "${reads}" | awk 'NR%4==1' | wc -l | tr -d ' ')
    else
        TOTAL_READS=\$(awk 'NR%4==1' "${reads}" | wc -l | tr -d ' ')
    fi

    if [ "\$TOTAL_READS" -gt 0 ]; then
        # Run minimap2
        minimap2 \\
            -x ${preset} \\
            -t ${task.cpus} \\
            --secondary=no \\
            -o "${prefix}.paf" \\
            "${reference}" \\
            "${reads}"
    else
        # Create empty output if no reads
        touch "${prefix}.paf"
    fi

    # Generate minimap2 stats using Python
    python3 << EOF
import json
import sys
from pathlib import Path

paf_file = "${prefix}.paf"
total_reads = \$TOTAL_READS
min_mapq_val = ${min_mapq}

# Parse PAF results
# PAF format: qname qlen qstart qend strand tname tlen tstart tend nmatch alen mapq ...
mapped_reads = set()
mapqs = []
identities = []
coverages = []

with open(paf_file) as f:
    for line_num, line in enumerate(f, 1):
        cols = line.strip().split('\\t')
        if len(cols) >= 12:
            try:
                qname = cols[0]
                qlen = int(cols[1])
                qstart = int(cols[2])
                qend = int(cols[3])
                nmatch = int(cols[9])
                alen = int(cols[10])
                mapq = int(cols[11])
            except (ValueError, IndexError) as e:
                # Skip malformed lines but continue processing
                print(f"Warning: Skipping malformed PAF line {line_num}: {e}", file=sys.stderr)
                continue

            # Only count reads that pass MAPQ threshold
            if mapq >= min_mapq_val:
                mapped_reads.add(qname)
                mapqs.append(mapq)

                # Calculate identity as nmatch / alen
                if alen > 0:
                    identities.append(nmatch / alen * 100)

                # Calculate query coverage (use abs to handle reverse strand alignments)
                if qlen > 0:
                    coverages.append(abs(qend - qstart) / qlen)

hits = len(mapped_reads)
hit_rate = hits / total_reads if total_reads > 0 else 0.0
avg_mapq = sum(mapqs) / len(mapqs) if mapqs else 0.0
avg_identity = sum(identities) / len(identities) if identities else 0.0
avg_coverage = sum(coverages) / len(coverages) if coverages else 0.0

# Determine validation status based on thresholds
hit_threshold = ${hit_threshold}
identity_threshold = ${identity_threshold}

if hit_rate >= hit_threshold and avg_identity >= identity_threshold:
    status = "confirmed"
elif hit_rate >= hit_threshold * 0.5 or avg_identity >= identity_threshold * 0.9:
    status = "uncertain"
else:
    status = "rejected"

stats = {
    "sample_id": "${sample_id}",
    "taxid": ${taxid},
    "validation_method": "minimap2",
    "total_reads": total_reads,
    "mapped_reads": hits,
    "hit_rate": round(hit_rate, 6),
    "avg_mapq": round(avg_mapq, 2),
    "avg_identity": round(avg_identity, 2),
    "avg_coverage": round(avg_coverage, 4),
    "validation_status": status,
    "parameters": {
        "preset": "${preset}",
        "min_mapq": min_mapq_val
    }
}

with open("${prefix}.minimap2_stats.json", "w") as out:
    json.dump(stats, out, indent=2)

print(f"Minimap2 validation: {hits}/{total_reads} mapped ({hit_rate*100:.1f}%), avg identity {avg_identity:.1f}%, status: {status}", file=sys.stderr)
EOF

    cat <<-END_VERSIONS > versions.yml
"${task.process}":
    minimap2: \$(minimap2 --version)
    python: \$(python3 --version | sed 's/Python //')
END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}_taxid${meta.taxid}"
    """
    touch "${prefix}.paf"
    cat > "${prefix}.minimap2_stats.json" << EOF
{
    "sample_id": "${meta.id}",
    "taxid": ${meta.taxid},
    "validation_method": "minimap2",
    "total_reads": 0,
    "mapped_reads": 0,
    "hit_rate": 0.0,
    "avg_mapq": 0.0,
    "avg_identity": 0.0,
    "avg_coverage": 0.0,
    "validation_status": "stub"
}
EOF

    cat <<-END_VERSIONS > versions.yml
"${task.process}":
    minimap2: 2.28
    python: 3.11.0
END_VERSIONS
    """
}
