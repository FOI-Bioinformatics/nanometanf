process MULTIQC_NANOPORE_STATS {
    tag "$prefix"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/multiqc:1.21--pyhdfd78af_0' :
        'quay.io/biocontainers/multiqc:1.21--pyhdfd78af_0' }"

    input:
    // stageAs: '?/*' isolates each input file in its own numbered
    // subdirectory so realtime mode can emit multiple per-sample
    // stats files (one per batch) with the same basename without
    // hitting Nextflow's "input file name collision" abort. Mirrors
    // the upstream nf-core MULTIQC module's pattern at
    // modules/nf-core/multiqc/main.nf:11.
    path(stats_files, stageAs: '?/*')  // SeqKit TSV or FASTP JSON files
    val(prefix)

    output:
    path "*_mqc.json"          , emit: multiqc_files
    path "versions.yml"        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    #!/usr/bin/env python3
    import csv
    import glob
    import json
    import os
    import sys

    # Parse SeqKit stats TSV files and FASTP JSON files. Inputs are
    # staged under numbered subdirectories (stageAs: '?/*') so multiple
    # per-batch files for the same sample do not collide. We walk every
    # subdirectory and key by sample_id; later batches overwrite earlier
    # ones for the same sample, leaving the final/cumulative stats
    # visible to MultiQC. This matches the realtime-mode contract where
    # the operator wants the latest per-sample numbers, not a per-batch
    # history.
    samples = {}

    # Sort by the NUMERIC stage index, not lexicographically. Inputs are staged
    # under '1/', '2/', ... '10/', '11/' and a plain sort orders those as
    # 1, 10, 11, 2 -- so with "later overwrites earlier" the surviving row for a
    # sample was whichever batch happened to land in the highest-sorting-by-string
    # directory, typically batch 9, not the latest one. Files whose parent is not
    # a number sort last but keep a stable relative order.
    def stage_order(path):
        parent = os.path.basename(os.path.dirname(path))
        return (0, int(parent), path) if parent.isdigit() else (1, 0, path)

    tsv_files = sorted(glob.glob('*/*.tsv'), key=stage_order)
    json_files = sorted(glob.glob('*/*.json'), key=stage_order)

    for f in tsv_files:
        # SeqKit stats TSV format
        with open(f) as fh:
            reader = csv.DictReader(fh, delimiter='\\t')
            for row in reader:
                # SeqKit stats columns: file, format, type, num_seqs, sum_len,
                # min_len, avg_len, max_len, Q1, Q2, Q3, sum_gap, N50, Q20(%), Q30(%)
                sample_id = os.path.splitext(os.path.basename(f))[0]
                # Strip .chopped suffix if present
                sample_id = sample_id.replace('.chopped', '')
                samples[sample_id] = {
                    'Total Reads': int(row.get('num_seqs', 0)),
                    'Total Bases': int(row.get('sum_len', 0)),
                    'Mean Read Length': round(float(row.get('avg_len', 0)), 1),
                    'Min Read Length': int(row.get('min_len', 0)),
                    'Max Read Length': int(row.get('max_len', 0)),
                    'N50': int(row.get('N50', 0)),
                }
                # AvgQual is the mean Phred quality; it is present because
                # SEQKIT_STATS runs with --all (see the module's ext.args
                # default) and SEQKIT_MERGE_STATS carries the column through.
                # This used to read Q2, which in `seqkit stats` is the second
                # quartile of read LENGTH -- so the "Mean Quality" column
                # reported a median read length, e.g. 4821 shown as a Phred
                # score. Omitted rather than faked when the column is absent.
                if row.get('AvgQual'):
                    samples[sample_id]['Mean Quality'] = round(float(row['AvgQual']), 1)

    for f in json_files:
        if os.path.basename(f).endswith('_mqc.json'):
            continue
        # FASTP JSON format
        try:
            with open(f) as fh:
                data = json.load(fh)
            sample_id = os.path.splitext(os.path.basename(f))[0].replace('.fastp', '')
            summary = data.get('summary', {})
            before = summary.get('before_filtering', {})
            after = summary.get('after_filtering', {})
            src = after if after else before
            samples[sample_id] = {
                'Total Reads': src.get('total_reads', 0),
                'Total Bases': src.get('total_bases', 0),
                'Mean Read Length': round(src.get('total_bases', 0) / max(src.get('total_reads', 1), 1), 1),
                # No 'Mean Quality' here on purpose. fastp's summary carries no
                # mean Phred score, and the previous q30_rate * 30 was arithmetic
                # with no meaning: a run with 100% of bases at Q30+ reported
                # exactly 30.0, and one at 50% reported 15.0, a score no read in
                # it necessarily had. Q20/Q30 rates below are the real fastp
                # quality figures; the seqkit branch supplies a true mean via
                # AvgQual.
                'Q20 Rate': round(src.get('q20_rate', 0) * 100, 1),
                'Q30 Rate': round(src.get('q30_rate', 0) * 100, 1),
            }
        except (json.JSONDecodeError, KeyError):
            pass

    # Generate MultiQC custom content
    general_stats = {
        "id": "nanopore_general_stats",
        "section_name": "Nanopore Sequencing Statistics",
        "description": "Overview of sequencing run metrics after quality filtering",
        "plot_type": "table",
        "pconfig": {
            "id": "nanopore_stats_table",
            "title": "Nanopore Run Summary"
        },
        "data": samples
    }

    # Quality distribution bar graph, plotted only for samples that actually
    # have a mean Phred score. seqkit supplies one (AvgQual); fastp does not,
    # and the removed q30_rate * 30 stand-in was not a quality score at all.
    # Plotting a column of zeros in its place is not an option either: MultiQC
    # raises "No datasets to plot" and fails the whole report, so a run whose
    # only QC tool is fastp needs a section that carries the explanation
    # instead of a chart.
    quality_scores = {
        s: d["Mean Quality"] for s, d in samples.items()
        if d.get("Mean Quality") is not None
    }

    if quality_scores:
        quality_data = {
            "id": "nanopore_quality",
            "section_name": "Quality Score Distribution",
            "description": "Mean quality scores across samples",
            "plot_type": "bargraph",
            "pconfig": {
                "id": "nanopore_quality_plot",
                "title": "Quality Score Distribution",
                "ylab": "Mean Quality Score"
            },
            "data": {s: {"Quality Score": v} for s, v in quality_scores.items()}
        }
    else:
        quality_data = {
            "id": "nanopore_quality",
            "section_name": "Quality Score Distribution",
            "description": "No mean quality score is available for this run",
            "plot_type": "html",
            "data": (
                "<p>The QC tool used in this run does not report a mean Phred "
                "quality score. fastp reports the proportion of bases at or above "
                "Q20 and Q30, which are shown in the Nanopore Sequencing Statistics "
                "table above; seqkit reports a true mean (AvgQual) and does produce "
                "this chart.</p>"
            )
        }

    # Write MultiQC JSON files
    with open('${prefix}_nanopore_stats_mqc.json', 'w') as f:
        json.dump(general_stats, f, indent=2)

    with open('${prefix}_quality_mqc.json', 'w') as f:
        json.dump(quality_data, f, indent=2)

    print(f"Generated MultiQC custom content for {len(samples)} samples", file=sys.stderr)

    # Write versions
    with open('versions.yml', 'w') as f:
        f.write('"${task.process}":\\n')
        f.write(f'  python: {sys.version.split()[0]}\\n')
    """

    stub:
    """
    touch ${prefix}_nanopore_stats_mqc.json
    touch ${prefix}_quality_mqc.json

    cat <<-END_VERSIONS > versions.yml
"${task.process}":
    python: 3.11
END_VERSIONS
    """
}
