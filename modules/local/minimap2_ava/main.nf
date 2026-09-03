process MINIMAP2_AVA {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/minimap2:2.28--he4a0461_0' :
        'quay.io/biocontainers/minimap2:2.28--he4a0461_0' }"

    // All-vs-all read overlaps for miniasm. The reads are the query AND the
    // target of one minimap2 call, so they are staged once. The nf-core
    // minimap2/align module takes reads and reference as two inputs and
    // stages both under the same name, which Nextflow refuses ("input file
    // name collision"), so every miniasm run aborted (nanometa_live audit
    // round 5, 2026-09-03, P2).
    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.paf.gz"), emit: paf
    path "versions.yml"              , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    minimap2 \\
        -x ava-ont \\
        -t $task.cpus \\
        $args \\
        $reads \\
        $reads \\
        | gzip -n > ${prefix}.ava.paf.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        minimap2: \$(minimap2 --version 2>&1)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "" | gzip -n > ${prefix}.ava.paf.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        minimap2: \$(minimap2 --version 2>&1)
    END_VERSIONS
    """
}
