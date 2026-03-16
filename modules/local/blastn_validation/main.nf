process BLASTN_VALIDATION {
    tag "${meta.id}:taxid${meta.taxid}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'oras://community.wave.seqera.io/library/blast_seqtk_python:0c6e3044e41ecb64' :
        'community.wave.seqera.io/library/blast_seqtk_python:0c6e3044e41ecb64' }"

    input:
    tuple val(meta), path(reads), path(reference)
    val blast_evalue
    val blast_perc_identity
    val blast_max_target_seqs
    val validation_hit_rate_threshold
    val validation_identity_threshold

    output:
    tuple val(meta), path("*.blast.tsv"), emit: results
    tuple val(meta), path("*.blast_stats.json"), emit: stats
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}_taxid${meta.taxid}"
    def evalue = task.ext.evalue ?: blast_evalue ?: "1e-10"
    def perc_identity = task.ext.perc_identity ?: blast_perc_identity ?: 90
    def max_target_seqs = task.ext.max_target_seqs ?: blast_max_target_seqs ?: 1
    def hit_threshold = validation_hit_rate_threshold ?: 0.5
    def identity_threshold = validation_identity_threshold ?: 90.0
    def sample_id = meta.id
    def taxid = meta.taxid
    """
    #!/bin/bash
    set -euo pipefail

    # Convert FASTQ to FASTA for BLAST
    seqtk seq -A "${reads}" > query.fasta

    # Count query sequences
    TOTAL_READS=\$(grep -c "^>" query.fasta || echo 0)

    # Determine if reference is a FASTA file or pre-built BLAST database
    # Check for BLAST database index files (.nhr, .nin, .nsq)
    BLAST_DB=""
    if [[ -f "${reference}.nhr" ]] || [[ -f "${reference}.nin" ]] || [[ -f "${reference}.nsq" ]]; then
        # Pre-built BLAST database
        BLAST_DB="${reference}"
    elif [[ "${reference}" == *.fasta ]] || [[ "${reference}" == *.fa ]] || [[ "${reference}" == *.fna ]] || [[ "${reference}" == *.fasta.gz ]] || [[ "${reference}" == *.fa.gz ]]; then
        # FASTA file - need to create BLAST database
        echo "Creating BLAST database from FASTA file..." >&2

        # Handle gzipped files
        if [[ "${reference}" == *.gz ]]; then
            if ! gunzip -c "${reference}" > reference_unzipped.fasta; then
                echo "ERROR: Failed to decompress reference file: ${reference}" >&2
                exit 1
            fi
            REF_FASTA="reference_unzipped.fasta"
        else
            REF_FASTA="${reference}"
        fi

        # Verify FASTA file is not empty
        if [ ! -s "\$REF_FASTA" ]; then
            echo "ERROR: Reference FASTA file is empty: \$REF_FASTA" >&2
            exit 1
        fi

        # Create BLAST database
        makeblastdb -in "\$REF_FASTA" -dbtype nucl -out blast_db -title "validation_ref"
        BLAST_DB="blast_db"
    else
        # Assume it's a database path without extension
        BLAST_DB="${reference}"
        # Validate the database exists by checking for at least one index file
        if [[ ! -f "\${BLAST_DB}.nhr" ]] && [[ ! -f "\${BLAST_DB}.nin" ]] && [[ ! -f "\${BLAST_DB}.nsq" ]] && \\
           [[ ! -f "\${BLAST_DB}.00.nhr" ]] && [[ ! -f "\${BLAST_DB}.nal" ]]; then
            echo "ERROR: BLAST database not found or invalid: \${BLAST_DB}" >&2
            echo "Expected one of: \${BLAST_DB}.nhr, \${BLAST_DB}.nin, \${BLAST_DB}.nsq, or multi-volume database" >&2
            exit 1
        fi
    fi

    if [ "\$TOTAL_READS" -gt 0 ]; then
        # Run BLAST
        blastn \\
            -query query.fasta \\
            -db "\$BLAST_DB" \\
            -out "${prefix}.blast.tsv" \\
            -outfmt "6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qlen slen qcovs" \\
            -evalue ${evalue} \\
            -max_target_seqs ${max_target_seqs} \\
            -perc_identity ${perc_identity} \\
            -num_threads ${task.cpus}
    else
        # Create empty output if no reads
        touch "${prefix}.blast.tsv"
    fi

    # Generate BLAST stats using Python
    python3 << EOF
import json
import sys
from pathlib import Path

blast_file = "${prefix}.blast.tsv"
total_reads = \$TOTAL_READS

# Parse BLAST results
hits = 0
identities = []
coverages = []
evalues = []

with open(blast_file) as f:
    for line in f:
        cols = line.strip().split('\\t')
        if len(cols) >= 15:
            hits += 1
            identities.append(float(cols[2]))  # pident
            coverages.append(float(cols[14]) / 100.0)  # qcovs (convert % to fraction)
            evalues.append(float(cols[10]))  # evalue

# Calculate statistics
hit_rate = hits / total_reads if total_reads > 0 else 0.0
avg_identity = sum(identities) / len(identities) if identities else 0.0
avg_coverage = sum(coverages) / len(coverages) if coverages else 0.0
min_evalue = min(evalues) if evalues else 1.0

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
    "validation_method": "blast",
    "total_reads": total_reads,
    "blast_hits": hits,
    "hit_rate": round(hit_rate, 6),
    "avg_identity": round(avg_identity, 2),
    "avg_coverage": round(avg_coverage, 4),
    "min_evalue": min_evalue,
    "validation_status": status,
    "thresholds": {
        "evalue": "${evalue}",
        "perc_identity": ${perc_identity},
        "max_target_seqs": ${max_target_seqs}
    }
}

with open("${prefix}.blast_stats.json", "w") as out:
    json.dump(stats, out, indent=2)

print(f"BLAST validation: {hits}/{total_reads} hits ({hit_rate*100:.1f}%), avg identity {avg_identity:.1f}%, status: {status}", file=sys.stderr)
EOF

    cat <<-END_VERSIONS > versions.yml
"${task.process}":
    blastn: \$(blastn -version 2>&1 | head -1 | sed 's/blastn: //')
    seqtk: \$(seqtk 2>&1 | grep -oE 'Version: [0-9.]+' | sed 's/Version: //' || echo "1.4")
    python: \$(python3 --version | sed 's/Python //')
END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}_taxid${meta.taxid}"
    def sample_id = meta.id
    def taxid = meta.taxid
    """
    touch "${prefix}.blast.tsv"
    cat > "${prefix}.blast_stats.json" << EOF
{
    "sample_id": "${sample_id}",
    "taxid": ${taxid},
    "validation_method": "blast",
    "total_reads": 0,
    "blast_hits": 0,
    "hit_rate": 0.0,
    "avg_identity": 0.0,
    "avg_coverage": 0.0,
    "min_evalue": 1.0,
    "validation_status": "stub"
}
EOF

    cat <<-END_VERSIONS > versions.yml
"${task.process}":
    blastn: 2.16.0
    seqtk: 1.4
    python: 3.11.0
END_VERSIONS
    """
}
