process COMBINE_KREPORTS {
    tag "$meta.id"
    label 'process_single'

    conda "bioconda::python=3.12 bioconda::krakentools=1.2"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/krakentools:1.2--pyh5e36f6f_0' :
        'biocontainers/krakentools:1.2--pyh5e36f6f_0' }"

    input:
    tuple val(meta), path(kreports)
    val(suffix)

    output:
    tuple val(meta), path("*.combined.kreport2"), emit: combined_report
    path "versions.yml"                          , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def output_suffix = suffix ?: ""
    def args = task.ext.args ?: ''
    """
    combine_kreports.py \\
        --no-headers \\
        --only-combined \\
        -r ${kreports} \\
        -o ${prefix}${output_suffix}.combined.kreport2 \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
        krakentools: \$(echo '1.2')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def output_suffix = suffix ?: ""
    """
    touch ${prefix}${output_suffix}.combined.kreport2

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
        krakentools: \$(echo '1.2')
    END_VERSIONS
    """
}
