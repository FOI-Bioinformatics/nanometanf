process ASSEMBLY_DEPTH_GATE {
    tag "${meta.id}${meta.taxid ? ':taxid' + meta.taxid : ''}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'quay.io/biocontainers/python:3.11' }"

    // Decides whether a read set is deep enough to assemble, and records the
    // answer either way. The decision file is emitted on EVERY path: a
    // declined assembly is a measurement with a stated reason, where an
    // absent assembly is silence -- and silence is what made a failed
    // assembly indistinguishable from a disabled one (nanometa_live assembly
    // audit, 2026-09-03).

    input:
    tuple val(meta), path(reads), path(reference)

    output:
    tuple val(meta), path("*.assembly_decision.json"), emit: decision
    path "versions.yml",                              emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def scope = meta.assembly_scope ?: 'metagenome'
    def taxid_arg = meta.taxid ? "--taxid ${meta.taxid}" : ''
    def prefix = task.ext.prefix ?: (meta.taxid ? "${meta.id}.taxid${meta.taxid}" : "${meta.id}")
    // 'NO_REFERENCE' is the staged placeholder for a whole-sample assembly,
    // which has no single genome to divide by.
    def ref_arg = (reference && reference.name != 'NO_REFERENCE') ? "--reference ${reference}" : ''
    """
    assembly_depth_gate.py \\
        --reads ${reads} \\
        ${ref_arg} \\
        --sample "${meta.id}" \\
        ${taxid_arg} \\
        --scope ${scope} \\
        --min-depth ${params.assembly_min_depth} \\
        --min-bases ${params.assembly_min_bases} \\
        --genome-size "${params.genome_size ?: ''}" \\
        --attempt ${meta.assembly_attempt ?: 1} \\
        ${params.assembly_allow_low_depth ? '--allow-low-depth' : ''} \\
        ${args} \\
        --out "${prefix}.assembly_decision.json"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        assembly_depth_gate.py: 1.0.0
        python: \$(python3 --version | sed 's/Python //')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: (meta.taxid ? "${meta.id}.taxid${meta.taxid}" : "${meta.id}")
    """
    echo '{"schema_version":"1.0.0","sample_id":"${meta.id}","decision":"attempt","reason":"attempt","reason_text":"stub"}' \\
        > "${prefix}.assembly_decision.json"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        assembly_depth_gate.py: 1.0.0
        python: \$(python3 --version | sed 's/Python //')
    END_VERSIONS
    """
}
