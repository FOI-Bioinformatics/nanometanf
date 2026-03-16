process MANIFEST_WRITER {
    tag "manifest"
    label 'process_single'

    publishDir "${params.outdir}/canonical/",
        mode: params.publish_dir_mode,
        saveAs: { filename -> filename }

    input:
    val(classifier)
    val(qc_tool)
    val(assembler)
    val(validation_method)
    val(sample_ids)
    val(mode)

    output:
    path "_manifest.json",  emit: manifest
    path "versions.yml",    emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def classifier_arg = classifier ? "--classifier ${classifier}" : ""
    def qc_arg = qc_tool ? "--qc-tool ${qc_tool}" : ""
    def assembler_arg = assembler ? "--assembler ${assembler}" : ""
    def validation_arg = validation_method ? "--validation-method ${validation_method}" : ""
    def samples_str = sample_ids instanceof List ? sample_ids.join(",") : sample_ids
    def samples_arg = samples_str ? "--samples ${samples_str}" : ""
    """
    write_manifest.py \\
        --outdir . \\
        ${classifier_arg} \\
        ${qc_arg} \\
        ${assembler_arg} \\
        ${validation_arg} \\
        ${samples_arg} \\
        --mode "${mode}"

    cat << END_VERSIONS > versions.yml
"${task.process}":
    write_manifest.py: 1.0.0
    python: \$(python3 --version | sed 's/Python //')
END_VERSIONS
    """

    stub:
    """
    echo '{"format_version":"1.0.0","samples":[]}' > _manifest.json

    cat << END_VERSIONS > versions.yml
"${task.process}":
    write_manifest.py: 1.0.0
    python: 3.11.0
END_VERSIONS
    """
}
