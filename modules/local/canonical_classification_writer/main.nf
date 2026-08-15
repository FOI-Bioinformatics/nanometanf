process CANONICAL_CLASSIFICATION_WRITER {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'quay.io/biocontainers/python:3.11' }"

    publishDir "${params.outdir}/canonical/classification/",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename }

    input:
    tuple val(meta), path(kreport)
    val(tool_name)
    val(tool_version)

    output:
    tuple val(meta), path("*.classification.json"),          emit: canonical
    tuple val(meta), path("*.classification.sidecar.json"),  emit: sidecar
    path "versions.yml",                                     emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def mode = params.realtime_mode ? "realtime" : "batch"
    def batch_arg = meta.batch_id != null ? "--batch-id ${meta.batch_id}" : ""
    def cumulative_arg = meta.is_cumulative ? "--is-cumulative" : ""
    """
    kreport_to_canonical.py \\
        --input "${kreport}" \\
        --tool "${tool_name}" \\
        --tool-version "${tool_version}" \\
        --sample "${prefix}" \\
        --mode "${mode}" \\
        --output "${prefix}.classification.json" \\
        --sidecar "${prefix}.classification.sidecar.json" \\
        ${batch_arg} \\
        ${cumulative_arg}

    cat << END_VERSIONS > versions.yml
"${task.process}":
    kreport_to_canonical.py: 1.0.0
    python: \$(python3 --version | sed 's/Python //')
END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch "${prefix}.classification.json"
    touch "${prefix}.classification.sidecar.json"

    cat << END_VERSIONS > versions.yml
"${task.process}":
    kreport_to_canonical.py: 1.0.0
    python: 3.11.0
END_VERSIONS
    """
}
