process CONSENSUS_VALIDATION {
    tag "${meta.id}:taxid${meta.taxid}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/66/66dc96eff11ab80dfd5c044e9b3425f52d818847b9c074794cf0c02bfa781661/data' :
        'community.wave.seqera.io/library/minimap2_samtools:33bb43c18d22e29c' }"

    input:
    tuple val(meta), path(reads), path(reference)
    val minimap2_preset
    val min_depth

    output:
    tuple val(meta), path("*.consensus.fasta"),       emit: consensus
    tuple val(meta), path("*.consensus_stats.json"),  emit: stats
    path "versions.yml",                              emit: versions

    when:
    task.ext.when == null || task.ext.when

    // Amplicon-focused consensus from read mapping. Reads are aligned to the
    // per-taxid reference with minimap2, then samtools consensus calls a base
    // per covered reference position. Positions below min_depth are masked N;
    // leading and trailing N are then trimmed so the emitted sequence spans
    // only the covered region (the amplicon), while interior low-depth bases
    // remain N. No primer scheme is required.
    //
    // Realtime note: ``reads`` are the reads extracted in THIS batch, so in
    // realtime mode the consensus reflects the latest batch (last-batch-wins).
    // A true run-so-far consensus would need a cumulative aggregator that
    // persists per-batch sorted BAMs, runs ``samtools merge`` with the prior
    // cumulative BAM, and re-calls the consensus -- mirroring
    // BLAST_CUMULATIVE_AGGREGATOR / MINIMAP2_CUMULATIVE_AGGREGATOR. That is a
    // deliberate follow-up, not part of this version.
    script:
    def prefix = task.ext.prefix ?: "${meta.id}_taxid${meta.taxid}"
    def preset = task.ext.preset ?: minimap2_preset ?: "map-ont"
    def depth = task.ext.min_depth ?: min_depth ?: 10
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

    MAPPED_READS=0
    REF_NAME="unknown"
    REF_LEN=0
    COV_START=0
    COV_END=0
    MEAN_DEPTH=0
    SPAN=0
    N_COUNT=0
    CONS_LEN=0

    if [ "\$TOTAL_READS" -gt 0 ]; then
        # Map reads to the reference and produce a sorted, indexed BAM
        minimap2 -a -x ${preset} -t ${task.cpus} "${reference}" "${reads}" \\
            | samtools sort -@ ${task.cpus} -o "${prefix}.sorted.bam" -
        samtools index "${prefix}.sorted.bam"

        MAPPED_READS=\$(samtools view -c -F 0x904 "${prefix}.sorted.bam")

        # Per-position depth (1-based). The reference contig with the most
        # positions at or above the depth threshold is the amplicon target.
        samtools depth -a "${prefix}.sorted.bam" > depth.txt || true
        awk -v min_depth="${depth}" '
            { len[\$1] = \$2 }
            \$3 + 0 >= min_depth {
                c = \$1
                if (!(c in first)) first[c] = \$2
                last[c] = \$2
                cnt[c]++
                dsum[c] += \$3
            }
            END {
                best = ""; bestcnt = 0
                for (c in cnt) { if (cnt[c] > bestcnt) { bestcnt = cnt[c]; best = c } }
                if (best == "") { print "unknown 0 0 0 0 0"; exit }
                md = (cnt[best] > 0) ? dsum[best] / cnt[best] : 0
                printf "%s %d %d %d %.2f %d\\n", best, first[best], last[best], cnt[best], md, len[best]
            }
        ' depth.txt > window.txt

        read REF_NAME COV_START COV_END COV_CNT MEAN_DEPTH REF_LEN < window.txt

        # Depth-masked consensus (positions below min_depth become N). The
        # ``|| true`` keeps a non-zero exit on an all-unmapped BAM (some
        # samtools versions) from aborting the task under ``set -e``; the
        # no-coverage branch below then writes the header-only FASTA.
        samtools consensus --min-depth ${depth} "${prefix}.sorted.bam" -o raw_consensus.fasta || true

        if [ "\$COV_START" -gt 0 ] && [ -s raw_consensus.fasta ]; then
            # Extract the target contig and strip leading/trailing N so the
            # sequence spans only the covered amplicon; interior N is kept.
            awk -v want="\$REF_NAME" -v hdr="${prefix}" -v refn="\$REF_NAME" \\
                -v cs="\$COV_START" -v ce="\$COV_END" '
                /^>/ { rid = substr(\$1, 2); inrec = (rid == want); next }
                inrec { seq = seq \$0 }
                END {
                    sub(/^N+/, "", seq)
                    sub(/N+\$/, "", seq)
                    slen = length(seq)
                    ncount = gsub(/N/, "N", seq)
                    outfa = hdr ".consensus.fasta"
                    if (slen == 0) {
                        printf ">%s no_consensus\\n", hdr > outfa
                    } else {
                        printf ">%s ref=%s region=%d-%d\\n", hdr, refn, cs, ce > outfa
                        for (i = 1; i <= slen; i += 70) print substr(seq, i, 70) >> outfa
                    }
                    print slen " " ncount > "seqstats.txt"
                }
            ' raw_consensus.fasta
            read CONS_LEN N_COUNT < seqstats.txt
            SPAN=\$CONS_LEN
        else
            printf ">%s no_consensus\\n" "${prefix}" > "${prefix}.consensus.fasta"
        fi
    else
        printf ">%s no_consensus\\n" "${prefix}" > "${prefix}.consensus.fasta"
    fi

    # Write consensus stats JSON. Newline escapes are doubled so one Groovy
    # unescape leaves backslash-n for awk to turn into a real newline.
    awk -v sample_id="${sample_id}" -v taxid="${taxid}" \\
        -v ref_name="\$REF_NAME" -v ref_len="\$REF_LEN" \\
        -v cov_start="\$COV_START" -v cov_end="\$COV_END" -v span="\$SPAN" \\
        -v mean_depth="\$MEAN_DEPTH" -v min_depth="${depth}" \\
        -v n_count="\$N_COUNT" -v cons_len="\$CONS_LEN" \\
        -v total_reads="\$TOTAL_READS" -v mapped_reads="\$MAPPED_READS" \\
        -v out_file="${prefix}.consensus_stats.json" '
        BEGIN {
            printf "{\\n" > out_file
            printf "  \\"sample_id\\": \\"%s\\",\\n", sample_id > out_file
            printf "  \\"taxid\\": %s,\\n", taxid > out_file
            printf "  \\"validation_method\\": \\"consensus\\",\\n" > out_file
            printf "  \\"ref_name\\": \\"%s\\",\\n", ref_name > out_file
            printf "  \\"ref_length\\": %d,\\n", ref_len > out_file
            printf "  \\"covered_start\\": %d,\\n", cov_start > out_file
            printf "  \\"covered_end\\": %d,\\n", cov_end > out_file
            printf "  \\"span\\": %d,\\n", span > out_file
            printf "  \\"mean_depth\\": %.2f,\\n", mean_depth > out_file
            printf "  \\"min_depth_threshold\\": %s,\\n", min_depth > out_file
            printf "  \\"n_count\\": %d,\\n", n_count > out_file
            printf "  \\"consensus_length\\": %d,\\n", cons_len > out_file
            printf "  \\"total_reads\\": %d,\\n", total_reads > out_file
            printf "  \\"mapped_reads\\": %d\\n", mapped_reads > out_file
            printf "}\\n" > out_file
        }'

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        minimap2: \$(minimap2 --version)
        samtools: \$(samtools --version | head -n1 | sed 's/samtools //')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}_taxid${meta.taxid}"
    def depth = task.ext.min_depth ?: min_depth ?: 10
    """
    printf ">%s no_consensus\\n" "${prefix}" > "${prefix}.consensus.fasta"
    cat > "${prefix}.consensus_stats.json" << EOF
    {
        "sample_id": "${meta.id}",
        "taxid": ${meta.taxid},
        "validation_method": "consensus",
        "ref_name": "unknown",
        "ref_length": 0,
        "covered_start": 0,
        "covered_end": 0,
        "span": 0,
        "mean_depth": 0.0,
        "min_depth_threshold": ${depth},
        "n_count": 0,
        "consensus_length": 0,
        "total_reads": 0,
        "mapped_reads": 0
    }
    EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        minimap2: 2.29
        samtools: 1.21
    END_VERSIONS
    """
}
