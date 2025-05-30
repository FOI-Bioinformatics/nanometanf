process EXTRACT_QC_INFO {
    tag "$meta.id"
    label 'process_single'

    conda "bioconda::python=3.12 bioconda::biopython=1.84"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/biopython:1.84' :
        'biocontainers/biopython:1.84' }"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.qc_info.txt"), emit: qc_info
    path "versions.yml"                    , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def input_files = meta.single_end ? reads : reads.join(' ')
    """
    extract_qc_info.py \\
        --input ${input_files} \\
        --output ${prefix}.qc_info.txt \\
        --sample ${meta.id}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
        biopython: \$(python -c "import Bio; print(Bio.__version__)")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.qc_info.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
        biopython: \$(python -c "import Bio; print(Bio.__version__)")
    END_VERSIONS
    """
}
