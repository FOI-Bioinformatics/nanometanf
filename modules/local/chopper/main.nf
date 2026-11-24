// Copyright (c) the nf-core community under an open-source MIT license.
// See https://github.com/nf-core/modules for full license, file patching instructions and upstream contributing.
//
// Local copy of nf-core/modules chopper at 7b3452a (2026-10-27). One change:
// chopper's standard error, which carries its "Kept K reads out of N reads"
// line, is kept as the `counts` output, so Nanometa Live can show the reads
// before filtering. Kept local rather than as an nf-core patch because the
// module linter compares a patched module's original meta.yml with its
// patched main.nf and fails any patch that adds an output. Port upstream
// updates by hand.

process CHOPPER {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
?         'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/b9/b9dd927988112cce2d9586eaebaba7d32a12e569531a7559c76692ca35862cca/data'
:         'community.wave.seqera.io/library/chopper_pigz:4ae8a43e228724c3' }"

    input:
    tuple val(meta), path(fastq, stageAs: 'input/*')
    path  fasta

    output:
    tuple val(meta), path("*.fastq.gz") , emit: fastq
    tuple val(meta), path("*.chopper_counts.txt"), emit: counts
    tuple val("${task.process}"), val('chopper'), eval("chopper --version 2>&1 | cut -d ' ' -f 2"), topic: versions, emit: versions_chopper
    tuple val("${task.process}"), val('pigz'),    eval("pigz --version | sed 's/pigz //g'"),        topic: versions, emit: versions_pigz

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def args2  = task.ext.args2  ?: ''
    def args3  = task.ext.args3  ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}.chopper"
    def fasta_filtering = fasta ? "--contam ${fasta}" : ""

    if ("$fastq" == "${prefix}.fastq.gz") error "Input and output names are the same, set prefix in module configuration to disambiguate!"
    """
    trap 'cat ${prefix}.chopper_counts.txt >&2 2>/dev/null || true' EXIT
    pigz \\
        --decompress \\
        --processes $task.cpus \\
        --stdout \\
        $args \\
        $fastq | \\
    chopper \\
        --threads $task.cpus \\
        $fasta_filtering \\
        $args2 2> ${prefix}.chopper_counts.txt | \\
    pigz \\
        --processes $task.cpus \\
        --stdout \\
        $args3 > ${prefix}.fastq.gz
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}.chopper"
    """
    echo "" | gzip > ${prefix}.fastq.gz
    echo "Kept 0 reads out of 0 reads" > ${prefix}.chopper_counts.txt
    """
}
