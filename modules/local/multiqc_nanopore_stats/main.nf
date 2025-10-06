process MULTIQC_NANOPORE_STATS {
    tag "$prefix"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'biocontainers/python:3.11' }"

    input:
    val(sample_stats)  // List of sample statistics from various sources
    val(prefix)

    output:
    path "*_mqc.json"          , emit: multiqc_files
    path "*_mqc.yaml"          , emit: multiqc_yaml
    path "versions.yml"        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    #!/usr/bin/env python3
    import json
    import yaml
    import sys
    from collections import defaultdict

    sample_stats = ${groovy.json.JsonOutput.toJson(sample_stats)}

    # Generate MultiQC custom content for nanopore statistics
    # Format: https://multiqc.info/docs/#custom-content

    # 1. General Statistics Table
    general_stats = {
        "id": "nanopore_general_stats",
        "section_name": "Nanopore Sequencing Statistics",
        "description": "Overview of Oxford Nanopore sequencing run metrics",
        "plot_type": "table",
        "pconfig": {
            "id": "nanopore_stats_table",
            "title": "Nanopore Run Summary"
        },
        "data": {}
    }

    # 2. Read Length Distribution
    read_length_data = {
        "id": "nanopore_read_length",
        "section_name": "Read Length Distribution",
        "description": "Distribution of read lengths across all samples",
        "plot_type": "linegraph",
        "pconfig": {
            "id": "nanopore_read_length_plot",
            "title": "Read Length Distribution",
            "xlab": "Read Length (bp)",
            "ylab": "Number of Reads",
            "yLog": True
        },
        "data": {}
    }

    # 3. Quality Score Distribution
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
        "data": {}
    }

    # Parse sample statistics
    for sample in sample_stats:
        sample_id = sample.get('sample_id', 'unknown')

        # General stats
        general_stats['data'][sample_id] = {
            'Total Reads': sample.get('total_reads', 0),
            'Total Bases': sample.get('total_bases', 0),
            'Mean Read Length': sample.get('mean_length', 0),
            'Median Read Length': sample.get('median_length', 0),
            'N50': sample.get('n50', 0),
            'Mean Quality': sample.get('mean_quality', 0)
        }

        # Read length distribution (if available)
        if 'read_length_histogram' in sample:
            read_length_data['data'][sample_id] = sample['read_length_histogram']

        # Quality distribution
        if 'mean_quality' in sample:
            quality_data['data'][sample_id] = {
                'Quality Score': sample['mean_quality']
            }

    # Write MultiQC JSON files
    with open('${prefix}_nanopore_stats_mqc.json', 'w') as f:
        json.dump(general_stats, f, indent=2)

    with open('${prefix}_read_length_mqc.json', 'w') as f:
        json.dump(read_length_data, f, indent=2)

    with open('${prefix}_quality_mqc.json', 'w') as f:
        json.dump(quality_data, f, indent=2)

    # Write YAML config for MultiQC
    multiqc_config = {
        'custom_data': {
            'nanopore_stats': {
                'file_format': 'json',
                'section_name': 'Nanopore Sequencing',
                'plot_type': 'table'
            }
        }
    }

    with open('${prefix}_multiqc_config_mqc.yaml', 'w') as f:
        yaml.dump(multiqc_config, f)

    print(f"Generated MultiQC custom content for {len(sample_stats)} samples", file=sys.stderr)

    # Write versions
    with open('versions.yml', 'w') as f:
        f.write('"${task.process}":\\n')
        f.write(f'  python: {sys.version.split()[0]}\\n')
    """

    stub:
    """
    touch ${prefix}_nanopore_stats_mqc.json
    touch ${prefix}_read_length_mqc.json
    touch ${prefix}_quality_mqc.json
    touch ${prefix}_multiqc_config_mqc.yaml

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/Python //g')
    END_VERSIONS
    """
}
