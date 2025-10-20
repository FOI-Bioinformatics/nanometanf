process KRAKEN2_INCREMENTAL_CLASSIFIER {
    tag "${meta.id}_batch${meta.batch_id}"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/29/29ed8f68315625eca61a3de9fcb7b8739fe8da23f5779eda3792b9d276aa3b8f/data' :
        'community.wave.seqera.io/library/kraken2_coreutils_pigz:45764814c4bb5bf3' }"

    input:
    tuple val(meta), path(reads)
    path  db
    val   save_output_fastqs
    val   save_reads_assignment

    output:
    tuple val(meta), path('*.kraken2.output.txt')       , emit: raw_kraken2_output
    tuple val(meta), path('*.kraken2.report.txt')       , emit: report
    tuple val(meta), path('batch_metadata.json')        , emit: batch_metadata
    tuple val(meta), path('*.classified{,_*}.fastq.gz') , optional:true, emit: classified_reads_fastq
    tuple val(meta), path('*.unclassified{,_*}.fastq.gz'), optional:true, emit: unclassified_reads_fastq
    tuple val(meta), path('*classifiedreads.txt')       , optional:true, emit: classified_reads_assignment
    path  "versions.yml"                                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}_batch${meta.batch_id ?: 0}"
    def paired       = meta.single_end ? "" : "--paired"
    def classified   = meta.single_end ? "${prefix}.classified.fastq"   : "${prefix}.classified#.fastq"
    def unclassified = meta.single_end ? "${prefix}.unclassified.fastq" : "${prefix}.unclassified#.fastq"
    def classified_option = save_output_fastqs ? "--classified-out ${classified}" : ""
    def unclassified_option = save_output_fastqs ? "--unclassified-out ${unclassified}" : ""
    def readclassification_option = save_reads_assignment ? "--output ${prefix}.kraken2.classifiedreads.txt" : "--output /dev/null"

    """
    #!/bin/bash
    set -euo pipefail

    # Record start time
    START_TIME=\$(date +%s)
    START_TIMESTAMP=\$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Run Kraken2 on batch reads only
    echo "Running incremental Kraken2 classification on batch ${meta.batch_id ?: 0}" >&2
    echo "Sample: ${meta.id}" >&2

    kraken2 \\
        --db ${db} \\
        --threads ${task.cpus} \\
        --report ${prefix}.kraken2.report.txt \\
        --gzip-compressed \\
        $unclassified_option \\
        $classified_option \\
        $readclassification_option \\
        $paired \\
        $args \\
        ${reads} > ${prefix}.kraken2.output.txt

    # Compress output FASTQs if required
    if [ "$save_output_fastqs" == "true" ] && ls *.fastq 1> /dev/null 2>&1; then
        pigz -p $task.cpus *.fastq
    fi

    # Calculate statistics
    END_TIME=\$(date +%s)
    END_TIMESTAMP=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
    DURATION=\$((END_TIME - START_TIME))

    # Extract classification statistics from report
    TOTAL_SEQS=\$(awk '{total+=\$3} END {print total}' ${prefix}.kraken2.report.txt)
    CLASSIFIED_SEQS=\$(awk '\$1!="U" {total+=\$3} END {print total}' ${prefix}.kraken2.report.txt)
    UNCLASSIFIED_SEQS=\$(awk '\$1=="U" {print \$3}' ${prefix}.kraken2.report.txt)

    # Create batch metadata JSON
    cat > batch_metadata.json <<EOF
{
  "sample_id": "${meta.id}",
  "batch_id": ${meta.batch_id ?: 0},
  "start_time": "\$START_TIMESTAMP",
  "end_time": "\$END_TIMESTAMP",
  "duration_seconds": \$DURATION,
  "input_reads": "${reads}",
  "kraken2_output": "${prefix}.kraken2.output.txt",
  "kraken2_report": "${prefix}.kraken2.report.txt",
  "classification_statistics": {
    "total_sequences": \$TOTAL_SEQS,
    "classified_sequences": \$CLASSIFIED_SEQS,
    "unclassified_sequences": \$UNCLASSIFIED_SEQS
  }
}
EOF

    # Log summary
    echo "" >&2
    echo "Batch ${meta.batch_id ?: 0} completed in \${DURATION}s" >&2
    echo "Classified: \$CLASSIFIED_SEQS / \$TOTAL_SEQS reads" >&2

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        kraken2: \$(echo \$(kraken2 --version 2>&1) | sed 's/^.*Kraken version //; s/ .*\$//')
        pigz: \$( pigz --version 2>&1 | sed 's/pigz //g' )
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}_batch${meta.batch_id ?: 0}"
    def classified   = meta.single_end ? "${prefix}.classified.fastq.gz"   : "${prefix}.classified_1.fastq.gz ${prefix}.classified_2.fastq.gz"
    def unclassified = meta.single_end ? "${prefix}.unclassified.fastq.gz" : "${prefix}.unclassified_1.fastq.gz ${prefix}.unclassified_2.fastq.gz"
    """
    touch ${prefix}.kraken2.output.txt
    touch ${prefix}.kraken2.report.txt
    echo '{"sample_id": "${meta.id}", "batch_id": ${meta.batch_id ?: 0}}' > batch_metadata.json

    if [ "$save_output_fastqs" == "true" ]; then
        touch $classified
        touch $unclassified
    fi
    if [ "$save_reads_assignment" == "true" ]; then
        touch ${prefix}.kraken2.classifiedreads.txt
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        kraken2: \$(echo \$(kraken2 --version 2>&1) | sed 's/^.*Kraken version //; s/ .*\$//')
        pigz: \$( pigz --version 2>&1 | sed 's/pigz //g' )
    END_VERSIONS
    """
}
