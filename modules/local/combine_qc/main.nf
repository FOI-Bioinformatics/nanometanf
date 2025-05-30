process COMBINE_QC {
    tag "$meta.id"
    label 'process_single'

    conda "conda-forge::coreutils=9.4"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/ubuntu:20.04' :
        'quay.io/biocontainers/ubuntu:20.04' }"

    input:
    tuple val(meta), path(qc_files)
    val(suffix)

    output:
    tuple val(meta), path("*cumul_qc.txt"), emit: combined_qc
    path "versions.yml"                    , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def output_suffix = suffix ?: ""
    """
    cat ${qc_files} > ${prefix}${output_suffix}.cumul_qc.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        coreutils: \$(cat --version | head -n1 | sed 's/cat (GNU coreutils) //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def output_suffix = suffix ?: ""
    """
    touch ${prefix}${output_suffix}.cumul_qc.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        coreutils: \$(cat --version | head -n1 | sed 's/cat (GNU coreutils) //g')
    END_VERSIONS
    """
}
