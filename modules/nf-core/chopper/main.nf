process CHOPPER {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    // The Seqera community image for chopper 0.12.0b ships chopper alone --
    // no gzip/gunzip -- and the script below pipes through `gunzip -c | gzip`.
    // The biocontainers/galaxy build is debian-based and includes coreutils,
    // so it works under apptainer/singularity on Linux without extra config.
    // macOS development continues to use the conda env (which now pins
    // conda-forge::gzip explicitly).
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/chopper:0.12.0b--hdcadc20_0':
        'biocontainers/chopper:0.12.0b--hdcadc20_0' }"

    input:
    tuple val(meta), path(fastq)
    path  fasta

    output:
    tuple val(meta), path("*.fastq.gz") , emit: fastq
    tuple val("${task.process}"), val('chopper'), eval("chopper --version 2>&1 | cut -d ' ' -f 2"), topic: versions, emit: versions_chopper

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def args2  = task.ext.args2  ?: ''
    def args3  = task.ext.args3  ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def fasta_filtering = fasta ? "--contam ${fasta}" : ""

    if ("$fastq" == "${prefix}.fastq.gz") error "Input and output names are the same, set prefix in module configuration to disambiguate!"
    // Use `gunzip -c` rather than `zcat`. macOS BSD `zcat` only handles
    // legacy `.Z` files and fails on `.fastq.gz` inputs. The companion
    // environment.yml lists `conda-forge::gzip` alongside chopper so that
    // GNU gzip/gunzip is on PATH on both macOS and Linux, including when
    // the seqera wave service rebuilds the container from this env file
    // (the original community image is too slim to include coreutils).
    // Filed locally because the upstream nf-core module is the same
    // shape; if the upstream module ever ships its own gunzip-c version
    // and pins gzip in the env, this comment can be removed at the next
    // `nf-core modules update`.
    """
    gunzip -c \\
        $args \\
        $fastq | \\
    chopper \\
        --threads $task.cpus \\
        $fasta_filtering \\
        $args2 | \\
    gzip \\
        $args3 > ${prefix}.fastq.gz
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo | gzip > ${prefix}.fastq.gz
    """
}
