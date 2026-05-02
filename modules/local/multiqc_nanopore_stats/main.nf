process MULTIQC_NANOPORE_STATS {
    tag "$prefix"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
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

    tsv_files = sorted(glob.glob('*/*.tsv'))
    json_files = sorted(glob.glob('*/*.json'))

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
                    'Mean Quality': round(float(row.get('Q2', 0)), 1) if row.get('Q2') else 0,
                }

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
                'Mean Quality': round(src.get('q30_rate', 0) * 30, 1),
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

    # Quality distribution bar graph
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
        "data": {s: {"Quality Score": d.get("Mean Quality", 0)} for s, d in samples.items()}
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
