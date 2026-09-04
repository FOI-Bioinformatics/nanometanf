process ASSEMBLY_READ_POOL {
    tag "${meta.id}${meta.taxid ? ':taxid' + meta.taxid : ''}:attempt${meta.assembly_attempt ?: 1}"
    label 'process_low'
    maxForks 1

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/ubuntu:22.04' :
        'nf-core/ubuntu:22.04' }"

    // Concatenates a sample's accumulated read files into one FASTQ so an
    // assembly sees the sample rather than a single arriving file.
    //
    // Realtime flattens each batch back into one emission per file, so
    // assembly ran per file and published every result to the same path: a
    // 28-file run left four artifacts, each a single batch's assembly at a
    // ninth to a thirty-fourth of what the sample could give (nanometa_live
    // assembly audit, 2026-09-03, A3). Gzip members concatenate as a valid
    // stream, so no decompression is needed.

    input:
    // stageAs with a wildcard directory per file: every batch of a sample
    // carries the SAME filename (CHOPPER names its output for the sample, not
    // the batch), so staging an accumulated set flat fails with "input file
    // name collision" -- found by a live realtime run, and the same shape as
    // the collision that broke miniasm in v1.9.0.
    tuple val(meta), path(reads, stageAs: "pool_input*/*")

    output:
    tuple val(meta), path("*.pooled.fastq.gz"), emit: pooled
    path "versions.yml",                        emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: (meta.taxid ? "${meta.id}.taxid${meta.taxid}" : "${meta.id}")
    def attempt = meta.assembly_attempt ?: 1
    """
    # Uncompressed inputs are gzipped on the way in so the output is one
    # valid stream either way.
    for f in ${reads}; do
        case "\$f" in
            *.gz) cat "\$f" ;;
            *)    gzip -c "\$f" ;;
        esac
    done > "${prefix}.attempt${attempt}.pooled.fastq.gz"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cat: \$(cat --version 2>/dev/null | head -1 | sed 's/.* //' || echo "coreutils")
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: (meta.taxid ? "${meta.id}.taxid${meta.taxid}" : "${meta.id}")
    def attempt = meta.assembly_attempt ?: 1
    """
    echo "" | gzip -n > "${prefix}.attempt${attempt}.pooled.fastq.gz"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        cat: "coreutils"
    END_VERSIONS
    """
}
