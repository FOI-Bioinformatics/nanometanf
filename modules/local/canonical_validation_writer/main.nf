process CANONICAL_VALIDATION_WRITER {
    tag "${meta.id}:taxid${meta.taxid}"
    label 'process_single'

    publishDir "${params.outdir}/canonical/validation/",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename }

    input:
    tuple val(meta), path(alignment), val(tool_name), val(input_format)

    output:
    tuple val(meta), path("*.alignments.tsv"),  emit: canonical
    path "versions.yml",                        emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}_taxid${meta.taxid}"
    def sample_id = meta.id
    def taxid = meta.taxid
    """
    alignment_to_canonical.py \\
        --input "${alignment}" \\
        --tool "${tool_name}" \\
        --format "${input_format}" \\
        --sample "${sample_id}" \\
        --taxid "${taxid}" \\
        --output "${prefix}.alignments.tsv"

    cat << END_VERSIONS > versions.yml
"${task.process}":
    alignment_to_canonical.py: 1.0.0
    python: \$(python3 --version | sed 's/Python //')
END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}_taxid${meta.taxid}"
    """
    touch "${prefix}.alignments.tsv"

    cat << END_VERSIONS > versions.yml
"${task.process}":
    alignment_to_canonical.py: 1.0.0
    python: 3.11.0
END_VERSIONS
    """
}
