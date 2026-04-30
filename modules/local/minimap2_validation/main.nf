process MINIMAP2_VALIDATION {
    tag "${meta.id}:taxid${meta.taxid}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/minimap2:2.28--he4a0461_0' :
        'quay.io/biocontainers/minimap2:2.28--he4a0461_0' }"

    input:
    tuple val(meta), path(reads), path(reference)
    val minimap2_preset
    val minimap2_min_mapq
    val validation_hit_rate_threshold
    val validation_identity_threshold

    output:
    tuple val(meta), path("*.paf"), emit: alignments
    tuple val(meta), path("*.minimap2_stats.json"), emit: stats
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}_taxid${meta.taxid}"
    def preset = task.ext.preset ?: minimap2_preset ?: "map-ont"
    def min_mapq = task.ext.min_mapq ?: minimap2_min_mapq ?: 10
    def hit_threshold = validation_hit_rate_threshold ?: 0.5
    def identity_threshold = validation_identity_threshold ?: 90.0
    def sample_id = meta.id
    def taxid = meta.taxid
    """
    #!/bin/bash
    set -euo pipefail

    # Count input reads (handle gzipped files)
    if [[ "${reads}" == *.gz ]]; then
        TOTAL_READS=\$(gunzip -c "${reads}" | awk 'NR%4==1' | wc -l | tr -d ' ')
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

    # Generate minimap2 stats using awk
    # PAF format: qname qlen qstart qend strand tname tlen tstart tend nmatch alen mapq [tags...]
    awk -v total_reads="\$TOTAL_READS" \
        -v min_mapq="${min_mapq}" \
        -v hit_threshold="${hit_threshold}" \
        -v identity_threshold="${identity_threshold}" \
        -v sample_id="${sample_id}" \
        -v taxid="${taxid}" \
        -v preset="${preset}" \
        -v out_file="${prefix}.minimap2_stats.json" \
    'BEGIN { OFS="\\t" }
    NF >= 12 {
        qname = \$1
        qlen  = \$2 + 0
        qstart = \$3 + 0
        qend   = \$4 + 0
        tname  = \$6
        tlen   = \$7 + 0
        nmatch = \$10 + 0
        alen   = \$11 + 0
        mapq   = \$12 + 0

        # Track the longest reference contig seen
        if (tlen > ref_max_len) {
            ref_max_len  = tlen
            ref_max_name = tname
        }

        if (mapq >= min_mapq) {
            # Deduplicate by read name
            if (!(qname in seen)) {
                seen[qname] = 1
                hits++
                mapq_sum += mapq
                mapq_n++

                # Prefer dv:f: tag for identity; fall back to nmatch/alen
                identity = -1
                for (i = 13; i <= NF; i++) {
                    if (\$i ~ /^dv:f:/) {
                        split(\$i, parts, ":")
                        dv = parts[3] + 0
                        identity = (1.0 - dv) * 100
                        break
                    }
                }
                if (identity < 0 && alen > 0) {
                    identity = nmatch / alen * 100
                }
                if (identity >= 0) {
                    id_sum += identity
                    id_n++
                }

                # Query coverage (absolute value handles reverse-strand coords)
                span = qend - qstart
                if (span < 0) span = -span
                if (qlen > 0) {
                    cov_sum += span / qlen
                    cov_n++
                }
            }
        }
    }
    END {
        if (ref_max_name == "") { ref_max_name = "unknown"; ref_max_len = 0 }
        hit_rate   = (total_reads > 0) ? hits / total_reads : 0.0
        avg_mapq   = (mapq_n > 0) ? mapq_sum / mapq_n : 0.0
        avg_id     = (id_n > 0) ? id_sum / id_n : 0.0
        avg_cov    = (cov_n > 0) ? cov_sum / cov_n : 0.0

        if (hit_rate >= hit_threshold && avg_id >= identity_threshold)
            status = "confirmed"
        else if (hit_rate >= hit_threshold * 0.5 || avg_id >= identity_threshold * 0.9)
            status = "uncertain"
        else
            status = "rejected"

        # Newline escapes here MUST be doubled. Groovy unescapes one
        # level when expanding the script block, so backslash-backslash-n
        # in the source reaches bash as backslash-n, which awk then
        # interprets as a newline. A single backslash-n in the source
        # would expand to a literal newline at Groovy parse time and
        # break the awk string literal.
        printf "{\\n" > out_file
        printf "  \\"sample_id\\": \\"%s\\",\\n", sample_id > out_file
        printf "  \\"taxid\\": %s,\\n", taxid > out_file
        printf "  \\"validation_method\\": \\"minimap2\\",\\n" > out_file
        printf "  \\"total_reads\\": %d,\\n", total_reads > out_file
        printf "  \\"mapped_reads\\": %d,\\n", hits > out_file
        printf "  \\"hit_rate\\": %.6f,\\n", hit_rate > out_file
        printf "  \\"avg_mapq\\": %.2f,\\n", avg_mapq > out_file
        printf "  \\"avg_identity\\": %.2f,\\n", avg_id > out_file
        printf "  \\"avg_coverage\\": %.4f,\\n", avg_cov > out_file
        printf "  \\"validation_status\\": \\"%s\\",\\n", status > out_file
        printf "  \\"ref_name\\": \\"%s\\",\\n", ref_max_name > out_file
        printf "  \\"ref_length\\": %d,\\n", ref_max_len > out_file
        printf "  \\"parameters\\": {\\"preset\\": \\"%s\\", \\"min_mapq\\": %s}\\n", preset, min_mapq > out_file
        printf "}\\n" > out_file

        printf "Minimap2 validation: %d/%d mapped (%.1f%%), avg identity %.1f%%, status: %s\\n", \
            hits, total_reads, hit_rate * 100, avg_id, status > "/dev/stderr"
    }' "${prefix}.paf"

    cat <<-END_VERSIONS > versions.yml
"${task.process}":
    minimap2: \$(minimap2 --version)
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
END_VERSIONS
    """
}
