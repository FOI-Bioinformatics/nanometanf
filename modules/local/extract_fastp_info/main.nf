process EXTRACT_FASTP_INFO {
    tag "$meta.id"
    label 'process_single'

    conda "conda-forge::python=3.12 conda-forge::pandas=2.2.0"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/pandas:2.2.0' :
        'quay.io/biocontainers/pandas:2.2.0' }"

    input:
    tuple val(meta), path(json)

    output:
    tuple val(meta), path("*.fastp_info.txt"), emit: fastp_info
    path "versions.yml"                       , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    extract_fastp_info.py \\
        --input ${json} \\
        --output ${prefix}.fastp_info.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.fastp_info.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
    END_VERSIONS
    """
}
