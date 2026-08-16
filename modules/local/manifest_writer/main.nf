process MANIFEST_WRITER {
    tag "manifest"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'quay.io/biocontainers/python:3.11' }"

    // Publishing is configured in conf/modules.config, which is included after
    // this module and overrides any publishDir set here. An in-module block was
    // therefore inert while reading as the module's publish target.

    input:
    val(classifier)
    val(qc_tool)
    val(assembler)
    val(validation_method)
    val(sample_ids)
    val(produced_sample_ids)
    val(mode)
    val(canonical_ready)

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
    // Quoted: a sample id containing a space or a shell metacharacter would
    // otherwise split into extra positional arguments, and write_manifest.py
    // would silently record a truncated sample list.
    def samples_arg = samples_str ? "--samples '${samples_str}'" : ""
    // Samples that actually emitted QC output. A sample whose QC task failed is
    // absorbed by conf/error_isolation.config and never reaches that channel,
    // so the difference between the two lists is the set that was attempted and
    // produced nothing.
    def produced_str = produced_sample_ids instanceof List ? produced_sample_ids.join(",") : produced_sample_ids
    // Gate on the value being supplied at all, NOT on it being non-empty.
    // An empty produced set is a real, determined answer -- every sample in
    // this batch failed QC -- and is precisely the case failed_samples exists
    // to report. Testing the joined string's truthiness dropped the flag
    // entirely for that case, so it arrived indistinguishable from "the
    // caller never told us" and the manifest recorded null.
    //
    // A List, INCLUDING an empty one, is a determined answer; the workflow
    // always sends one (ch_produced_sample_ids ends .ifEmpty([])). Anything
    // else -- an empty string -- means the caller did not determine it.
    // Nextflow cannot carry null through a `val` input ("A process input
    // channel evaluates to null"), so the undetermined case has to be an
    // empty string rather than null.
    //
    // Quoted because the value is legitimately empty here; unquoted, the
    // shell would swallow the following argument.
    def produced_determined = produced_sample_ids instanceof List || produced_str
    def produced_arg = produced_determined ? "--produced-samples '${produced_str}'" : ""
    """
    write_manifest.py \\
        --outdir . \\
        ${classifier_arg} \\
        ${qc_arg} \\
        ${assembler_arg} \\
        ${validation_arg} \\
        ${samples_arg} \\
        ${produced_arg} \\
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
