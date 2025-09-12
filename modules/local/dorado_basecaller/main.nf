process DORADO_BASECALLER {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/dorado:0.7.3--h9ee0642_0':
        'biocontainers/dorado:0.7.3--h9ee0642_0' }"

    input:
    tuple val(meta), path(pod5_files)
    val model

    output:
    tuple val(meta), path("*.fastq.gz"), emit: fastq
    tuple val(meta), path("*_summary.txt"), emit: summary
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def min_qscore = params.min_qscore ?: 9
    
    // Handle both single POD5 file and directory of POD5 files
    def input_path = pod5_files.size() == 1 && pod5_files[0].isFile() ? pod5_files[0] : '.'
    
    """
    # Check if dorado is available
    if [ ! -f "${params.dorado_path}" ]; then
        echo "ERROR: Dorado not found at ${params.dorado_path}"
        exit 1
    fi

    # Download model if not available locally
    ${params.dorado_path} download --model ${model} || echo "Model may already be available"

    # Run basecalling
    ${params.dorado_path} basecaller \\
        ${model} \\
        ${input_path} \\
        --min-qscore ${min_qscore} \\
        --verbose \\
        ${args} \\
        > ${prefix}.fastq

    # Compress output
    gzip ${prefix}.fastq

    # Create summary file
    echo "Sample: ${prefix}" > ${prefix}_summary.txt
    echo "Model: ${model}" >> ${prefix}_summary.txt
    echo "Min Q-score: ${min_qscore}" >> ${prefix}_summary.txt
    echo "Input files: ${pod5_files.join(', ')}" >> ${prefix}_summary.txt
    echo "Basecalling completed: \$(date)" >> ${prefix}_summary.txt

    # Version information
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dorado: \$(${params.dorado_path} --version 2>&1 | head -n 1 | sed 's/.*dorado //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.fastq.gz
    touch ${prefix}_summary.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dorado: \$(echo "0.7.3")
    END_VERSIONS
    """
}