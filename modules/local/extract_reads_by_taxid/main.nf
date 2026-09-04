process EXTRACT_READS_BY_TAXID {
    tag "${meta.id}:taxid${taxid}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/seqtk:1.4--he4a0461_2' :
        'quay.io/biocontainers/seqtk:1.4--he4a0461_2' }"

    input:
    tuple val(meta), path(reads), path(kraken_output), val(taxid), val(clade_taxids)

    output:
    // ``reads`` is optional: a taxid with zero classified reads in this batch
    // emits no FASTQ, so the downstream BLAST/minimap2 validators are not
    // scheduled for it. In a realtime run most watchlist taxids are absent from
    // any given batch; validating them on empty input was the bulk of the
    // per-batch x per-taxid task explosion (see issue #29). ``stats`` is always
    // emitted so the extracted-read count is still recorded.
    tuple val(meta), path("*_taxid${taxid}.fastq.gz"), emit: reads, optional: true
    tuple val(meta), path("*_extraction_stats.json"), emit: stats
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/bin/bash
    set -euo pipefail

    # Extract read IDs classified anywhere in this taxid's CLADE.
    #
    # Kraken2 assigns each read to the most specific node it can, so an
    # organism's reads scatter across its species row and the subspecies
    # below it. Matching the exact taxid took 279 of the 1,051 reads of
    # F. tularensis in one real sample and confirmed the organism from a
    # quarter of its evidence (assembly audit, 2026-09-03, A5b).
    #
    # The caller resolves the clade from the sample's own report and passes
    # it as a comma-separated list; it always contains at least the taxid
    # itself, so an unreadable report degrades to the previous behaviour
    # rather than to selecting nothing.
    CLADE="${clade_taxids ?: taxid}"
    awk -F'\\t' -v clade="\$CLADE" '
        BEGIN { n = split(clade, a, ","); for (i = 1; i <= n; i++) want[a[i]] = 1 }
        \$1 == "C" && (\$3 in want) { print \$2 }
    ' "${kraken_output}" > read_ids.txt

    # Count extracted read IDs
    EXTRACTED_COUNT=\$(wc -l < read_ids.txt | tr -d ' ')

    if [ "\$EXTRACTED_COUNT" -gt 0 ]; then
        # Extract reads using seqtk
        seqtk subseq "${reads}" read_ids.txt | gzip -c > "${prefix}_taxid${taxid}.fastq.gz"
        echo "Extracted \$EXTRACTED_COUNT reads for taxid ${taxid} from sample ${prefix}" >&2
    else
        # No reads for this taxid in this batch: emit NO FASTQ (the reads output
        # is optional) so the downstream validators skip it. Nothing to validate
        # on an empty extraction, and scheduling BLAST/minimap2 on it was pure
        # overhead. The stats JSON below still records the zero count.
        echo "No reads found for taxid ${taxid} in sample ${prefix}; skipping validation for this batch" >&2
    fi

    # Count total classified reads for this sample
    TOTAL_CLASSIFIED=\$(awk -F'\\t' '\$1 == "C"' "${kraken_output}" | wc -l | tr -d ' ')

    # Calculate extraction rate using awk (avoids bc dependency)
    EXTRACTION_RATE=\$(awk -v ext="\$EXTRACTED_COUNT" -v tot="\$TOTAL_CLASSIFIED" 'BEGIN {
        if (tot > 0) printf "%.6f", ext / tot
        else printf "0.000000"
    }')

    # Generate extraction stats JSON
    cat > "${prefix}_taxid${taxid}_extraction_stats.json" << EOF
{
    "sample_id": "${meta.id}",
    "taxid": ${taxid},
    "extracted_reads": \${EXTRACTED_COUNT},
    "total_classified_reads": \${TOTAL_CLASSIFIED},
    "extraction_rate": \${EXTRACTION_RATE},
    "source_file": "${reads}",
    "kraken_output": "${kraken_output}"
}
EOF

    cat <<-END_VERSIONS > versions.yml
"${task.process}":
    seqtk: \$(seqtk 2>&1 | grep -oE '[0-9]+\\.[0-9]+(-r[0-9]+)?' | head -1)
    bash: \$(echo \${BASH_VERSION})
END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "@stub_read_1" | gzip > "${prefix}_taxid${taxid}.fastq.gz"
    cat > "${prefix}_taxid${taxid}_extraction_stats.json" << EOF
{
    "sample_id": "${meta.id}",
    "taxid": ${taxid},
    "extracted_reads": 0,
    "total_classified_reads": 0,
    "extraction_rate": 0.0,
    "source_file": "${reads}",
    "kraken_output": "stub"
}
EOF

    cat <<-END_VERSIONS > versions.yml
"${task.process}":
    seqtk: 1.4
    bash: 5.0
END_VERSIONS
    """
}
