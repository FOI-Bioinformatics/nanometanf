process CANONICAL_ASSEMBLY_WRITER {
    tag "$meta.id"
    label 'process_single'

    conda "conda-forge::python=3.11"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'quay.io/biocontainers/python:3.11' }"

    publishDir "${params.outdir}/canonical/assembly/",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename }

    input:
    tuple val(meta), path(assembly_info)
    tuple val(meta2), path(assembly_fasta)
    val(tool_name)
    val(tool_version)

    output:
    tuple val(meta), path("*.assembly_stats.json"),          emit: canonical
    tuple val(meta), path("*.assembly_stats.sidecar.json"),  emit: sidecar
    path "versions.yml",                                     emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def fasta_arg = assembly_fasta.name != 'NO_FASTA' ? "--fasta ${assembly_fasta}" : ""
    """
    assembly_to_canonical.py \\
        --input "${assembly_info}" \\
        --tool "${tool_name}" \\
        --tool-version "${tool_version}" \\
        --sample "${prefix}" \\
        --output "${prefix}.assembly_stats.json" \\
        --sidecar "${prefix}.assembly_stats.sidecar.json" \\
        ${fasta_arg}

    cat << END_VERSIONS > versions.yml
"${task.process}":
    assembly_to_canonical.py: 1.0.0
    python: \$(python3 --version | sed 's/Python //')
END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch "${prefix}.assembly_stats.json"
    touch "${prefix}.assembly_stats.sidecar.json"

    cat << END_VERSIONS > versions.yml
"${task.process}":
    assembly_to_canonical.py: 1.0.0
    python: 3.11.0
END_VERSIONS
    """
}
