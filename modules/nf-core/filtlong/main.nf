process FILTLONG {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/filtlong:0.2.1--h9a82719_0' :
        'biocontainers/filtlong:0.2.1--h9a82719_0' }"

    input:
    tuple val(meta), path(shortreads), path(longreads)

    output:
    tuple val(meta), path("*.fastq.gz"), emit: reads
    tuple val(meta), path("*.log")     , emit: log
    path "versions.yml"                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def short_reads = !shortreads ? "" : meta.single_end ? "-1 $shortreads" : "-1 ${shortreads[0]} -2 ${shortreads[1]}"
    if ("$longreads" == "${prefix}.fastq.gz") error "Longread FASTQ input and output names are the same, set prefix in module configuration to disambiguate!"
    // filtlong takes exactly one positional long-read file. A multi-file
    // sample (every barcode directory of a MinKNOW run) is concatenated
    // first; gzip members concatenate as a valid stream. Without this the
    // extra files are passed as positionals and filtlong exits 1
    // ("passed in argument, but no positional arguments were ready to
    // receive it"): nanometa_live audit round 5, 2026-09-03, P1.
    def longread_list = longreads instanceof List ? longreads : [longreads]
    def concat_input = longread_list.size() > 1
    def longread_input = concat_input ? "${prefix}.concat_input.fq.gz" : "${longreads}"
    def concat_cmd = concat_input ? "cat ${longread_list.join(' ')} > ${longread_input}" : "true"
    """
    $concat_cmd
    filtlong \\
        $short_reads \\
        $args \\
        $longread_input \\
        2>| >(tee ${prefix}.log >&2) \\
        | gzip -n > ${prefix}.fastq.gz
    rm -f ${prefix}.concat_input.fq.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        filtlong: \$( filtlong --version | sed -e "s/Filtlong v//g" )
    END_VERSIONS
    """
}
