process CANONICAL_QC_WRITER {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'quay.io/biocontainers/python:3.11' }"

    // Publishing is configured in conf/modules.config, which is included after
    // this module and overrides any publishDir set here. An in-module block was
    // therefore inert while reading as the module's publish target.

    input:
    tuple val(meta), path(qc_stats)
    val(tool_name)
    val(tool_version)

    output:
    tuple val(meta), path("*.qc_stats.json"),          emit: canonical
    tuple val(meta), path("*.qc_stats.sidecar.json"),  emit: sidecar
    path "versions.yml",                               emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def mode = params.realtime_mode ? "realtime" : "batch"
    """
    qc_to_canonical.py \\
        --input "${qc_stats}" \\
        --tool "${tool_name}" \\
        --tool-version "${tool_version}" \\
        --sample "${prefix}" \\
        --mode "${mode}" \\
        --output "${prefix}.qc_stats.json" \\
        --sidecar "${prefix}.qc_stats.sidecar.json"

    cat << END_VERSIONS > versions.yml
"${task.process}":
    qc_to_canonical.py: 1.0.0
    python: \$(python3 --version | sed 's/Python //')
END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch "${prefix}.qc_stats.json"
    touch "${prefix}.qc_stats.sidecar.json"

    cat << END_VERSIONS > versions.yml
"${task.process}":
    qc_to_canonical.py: 1.0.0
    python: 3.11.0
END_VERSIONS
    """
}
