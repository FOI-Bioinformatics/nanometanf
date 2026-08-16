// Maintain a run-so-far cumulative view of per-(sample, taxid) validation
// results during realtime processing. Every batch seen so far for the
// (sample, taxid) pair is merged and the statistics are recomputed over the
// merged set, mirroring the schema of MINIMAP2_VALIDATION / BLASTN_VALIDATION.
// Coverage breadth is recomputed (it is not additive); total_reads is summed
// across the batch stats because it is not present in the alignment files.
//
// The batch set arrives through the channel, from CumulativeBatchAccumulator.
// An earlier version instead read the PRIOR cumulative file out of
// params.outdir -- the module's own output path -- which raced the task that
// writes it and silently dropped batches. Nothing in this module may read the
// publish directory: the result must be a pure function of its inputs, so that
// a concurrent or late aggregation can only ever be less complete, never wrong.
process VALIDATION_CUMULATIVE_AGGREGATOR {
    tag "${meta.id}:taxid${taxid}:${method}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.12' :
        'quay.io/biocontainers/python:3.12' }"

    input:
    // Every batch result for this (sample, taxid) carries the SAME basename
    // (<prefix>.paf / <prefix>.*_stats.json), which is also the cumulative
    // output name. The indexed stageAs patterns solve both problems at once:
    // the '*' is replaced with a per-file index so same-named batch files do
    // not collide in the work directory, and the generic prefix keeps them out
    // of the output matching set (an input sharing the output name is excluded
    // from it, giving "Missing output file").
    tuple val(meta), val(taxid),
        path(batch_files, stageAs: 'batch_input_*'),
        path(batch_stats, stageAs: 'batch_stats_*')
    val method

    output:
    tuple val(meta), val(taxid), path("${meta.id}_taxid${taxid}.paf"),       optional: true, emit: minimap2_cumulative
    tuple val(meta), val(taxid), path("${meta.id}_taxid${taxid}.blast.tsv"), optional: true, emit: blast_cumulative
    tuple val(meta), val(taxid), path("*_stats.json"),                                       emit: stats
    path "versions.yml",                                                                     emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = "${meta.id}_taxid${taxid}"
    def sample_id = meta.id
    def min_mapq = params.minimap2_min_mapq ?: 10
    def preset = params.minimap2_preset ?: "map-ont"
    def hit_threshold = params.validation_hit_rate_threshold ?: 0.5
    def identity_threshold = params.validation_identity_threshold ?: 90.0
    def blast_evalue = params.blast_evalue ?: "1e-10"
    def blast_perc_identity = params.blast_perc_identity ?: 90
    def blast_max_target_seqs = params.blast_max_target_seqs ?: 1
    if (method == 'minimap2') {
        """
        #!/bin/bash
        set -euo pipefail

        # Merge every batch PAF seen so far for this (sample, taxid). The
        # per-read dedup in the recompute below collapses any duplicate primary
        # alignments seen across batches.
        : > merged.paf
        for batch_paf in batch_input_*; do
            if [ -s "\$batch_paf" ]; then cat "\$batch_paf" >> merged.paf; fi
        done
        cp merged.paf "${prefix}.paf"

        python3 << 'PYEOF'
import json
from pathlib import Path

min_mapq = ${min_mapq}
hit_threshold = ${hit_threshold}
identity_threshold = ${identity_threshold}

def total_reads_of(path):
    if path and Path(path).exists() and Path(path).stat().st_size > 0:
        try:
            return int(json.load(open(path)).get("total_reads", 0) or 0)
        except Exception:
            return 0
    return 0

# total_reads is the per-batch classified-read count and is NOT in the PAF, so
# sum it over the batch stats. Summing the batch set rather than carrying a
# running total means a re-run of the same batch cannot inflate the figure.
cum_total = sum(total_reads_of(p) for p in sorted(Path(".").glob("batch_stats_*")))

seen = set()
hits = 0
mapq_sum = 0.0; mapq_n = 0
id_sum = 0.0; id_n = 0
cov_sum = 0.0; cov_n = 0
ref_max_len = 0; ref_max_name = ""

with open("merged.paf") as fh:
    for line in fh:
        cols = line.rstrip("\\n").split("\\t")
        if len(cols) < 12:
            continue
        qname = cols[0]
        qlen = int(cols[1]); qstart = int(cols[2]); qend = int(cols[3])
        tname = cols[5]; tlen = int(cols[6])
        nmatch = int(cols[9]); alen = int(cols[10]); mapq = int(cols[11])
        if tlen > ref_max_len:
            ref_max_len = tlen; ref_max_name = tname
        if mapq >= min_mapq and qname not in seen:
            seen.add(qname)
            hits += 1
            mapq_sum += mapq; mapq_n += 1
            identity = -1.0
            for tag in cols[12:]:
                if tag.startswith("dv:f:"):
                    identity = (1.0 - float(tag.split(":")[2])) * 100.0
                    break
            if identity < 0 and alen > 0:
                identity = nmatch / alen * 100.0
            if identity >= 0:
                id_sum += identity; id_n += 1
            span = abs(qend - qstart)
            if qlen > 0:
                cov_sum += span / qlen; cov_n += 1

if ref_max_name == "":
    ref_max_name = "unknown"; ref_max_len = 0
hit_rate = hits / cum_total if cum_total > 0 else 0.0
avg_mapq = mapq_sum / mapq_n if mapq_n > 0 else 0.0
avg_id = id_sum / id_n if id_n > 0 else 0.0
avg_cov = cov_sum / cov_n if cov_n > 0 else 0.0
if hit_rate >= hit_threshold and avg_id >= identity_threshold:
    status = "confirmed"
elif hit_rate >= hit_threshold * 0.5 or avg_id >= identity_threshold * 0.9:
    status = "uncertain"
else:
    status = "rejected"

stats = {
    "sample_id": "${sample_id}",
    "taxid": ${taxid},
    "validation_method": "minimap2",
    "total_reads": cum_total,
    "mapped_reads": hits,
    "hit_rate": round(hit_rate, 6),
    "avg_mapq": round(avg_mapq, 2),
    "avg_identity": round(avg_id, 2),
    "avg_coverage": round(avg_cov, 4),
    "validation_status": status,
    "ref_name": ref_max_name,
    "ref_length": ref_max_len,
    "parameters": {"preset": "${preset}", "min_mapq": ${min_mapq}},
}
with open("${prefix}.minimap2_stats.json", "w") as out:
    json.dump(stats, out, indent=2)
PYEOF

        cat <<-END_VERSIONS > versions.yml
"${task.process}":
    python: \$(python3 --version | sed 's/Python //')
END_VERSIONS
        """
    } else {
        """
        #!/bin/bash
        set -euo pipefail

        # Merge every batch BLAST table seen so far for this (sample, taxid).
        # The per-qseqid dedup in the recompute keeps the merged hit set
        # well-defined.
        : > merged.blast.tsv
        for batch_tsv in batch_input_*; do
            if [ -s "\$batch_tsv" ]; then cat "\$batch_tsv" >> merged.blast.tsv; fi
        done
        cp merged.blast.tsv "${prefix}.blast.tsv"

        python3 << 'PYEOF'
import json
from pathlib import Path

hit_threshold = ${hit_threshold}
identity_threshold = ${identity_threshold}

def total_reads_of(path):
    if path and Path(path).exists() and Path(path).stat().st_size > 0:
        try:
            return int(json.load(open(path)).get("total_reads", 0) or 0)
        except Exception:
            return 0
    return 0

cum_total = sum(total_reads_of(p) for p in sorted(Path(".").glob("batch_stats_*")))

hits = 0
seen = set()
identities = []
coverages = []
evalues = []
with open("merged.blast.tsv") as fh:
    for line in fh:
        cols = line.strip().split("\\t")
        if len(cols) >= 15:
            qseqid = cols[0]
            if qseqid in seen:
                continue
            seen.add(qseqid)
            hits += 1
            identities.append(float(cols[2]))
            coverages.append(float(cols[14]) / 100.0)
            evalues.append(float(cols[10]))

hit_rate = hits / cum_total if cum_total > 0 else 0.0
avg_identity = sum(identities) / len(identities) if identities else 0.0
avg_coverage = sum(coverages) / len(coverages) if coverages else 0.0
min_evalue = min(evalues) if evalues else 1.0
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
    "total_reads": cum_total,
    "blast_hits": hits,
    "hit_rate": round(hit_rate, 6),
    "avg_identity": round(avg_identity, 2),
    "avg_coverage": round(avg_coverage, 4),
    "min_evalue": min_evalue,
    "validation_status": status,
    "thresholds": {
        "evalue": "${blast_evalue}",
        "perc_identity": ${blast_perc_identity},
        "max_target_seqs": ${blast_max_target_seqs},
    },
}
with open("${prefix}.blast_stats.json", "w") as out:
    json.dump(stats, out, indent=2)
PYEOF

        cat <<-END_VERSIONS > versions.yml
"${task.process}":
    python: \$(python3 --version | sed 's/Python //')
END_VERSIONS
        """
    }

    stub:
    def prefix = "${meta.id}_taxid${taxid}"
    if (method == 'minimap2') {
        """
        touch "${prefix}.paf"
        echo '{"sample_id": "${meta.id}", "taxid": ${taxid}, "validation_method": "minimap2", "total_reads": 0, "mapped_reads": 0, "hit_rate": 0.0, "avg_mapq": 0.0, "avg_identity": 0.0, "avg_coverage": 0.0, "validation_status": "rejected", "ref_name": "unknown", "ref_length": 0, "parameters": {"preset": "map-ont", "min_mapq": 10}}' > "${prefix}.minimap2_stats.json"

        cat <<-END_VERSIONS > versions.yml
"${task.process}":
    python: \$(python3 --version | sed 's/Python //')
END_VERSIONS
        """
    } else {
        """
        touch "${prefix}.blast.tsv"
        echo '{"sample_id": "${meta.id}", "taxid": ${taxid}, "validation_method": "blast", "total_reads": 0, "blast_hits": 0, "hit_rate": 0.0, "avg_identity": 0.0, "avg_coverage": 0.0, "min_evalue": 1.0, "validation_status": "rejected", "thresholds": {"evalue": "1e-10", "perc_identity": 90, "max_target_seqs": 1}}' > "${prefix}.blast_stats.json"

        cat <<-END_VERSIONS > versions.yml
"${task.process}":
    python: \$(python3 --version | sed 's/Python //')
END_VERSIONS
        """
    }
}
