process KRAKEN2_OPTIMIZED {
    tag "$meta.id"
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
    val   use_memory_mapping     // Enable memory-mapped database loading
    val   confidence_threshold   // Confidence score filter (0.0-1.0)
    val   minimum_hit_groups     // Minimum number of hit groups for classification

    output:
    tuple val(meta), path('*.classified{.,_}*')     , optional:true, emit: classified_reads_fastq
    tuple val(meta), path('*.unclassified{.,_}*')   , optional:true, emit: unclassified_reads_fastq
    tuple val(meta), path('*classifiedreads.txt')   , optional:true, emit: classified_reads_assignment
    tuple val(meta), path('*report.txt')                           , emit: report
    path  "${prefix}.kraken2.performance.json"                     , emit: performance_metrics
    path  "versions.yml"                                           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    def paired       = meta.single_end ? "" : "--paired"
    def classified   = meta.single_end ? "${prefix}.classified.fastq"   : "${prefix}.classified#.fastq"
    def unclassified = meta.single_end ? "${prefix}.unclassified.fastq" : "${prefix}.unclassified#.fastq"
    def classified_option = save_output_fastqs ? "--classified-out ${classified}" : ""
    def unclassified_option = save_output_fastqs ? "--unclassified-out ${unclassified}" : ""
    def readclassification_option = save_reads_assignment ? "--output ${prefix}.kraken2.classifiedreads.txt" : "--output /dev/null"
    def compress_reads_command = save_output_fastqs ? "pigz -p $task.cpus *.fastq" : ""

    // Kraken2 optimization flags
    def memory_mapping = use_memory_mapping ? "--memory-mapping" : ""
    def confidence = confidence_threshold > 0 ? "--confidence ${confidence_threshold}" : ""
    def min_hit_groups = minimum_hit_groups > 0 ? "--minimum-hit-groups ${minimum_hit_groups}" : ""

    """
    #!/bin/bash
    set -euo pipefail

    # Record start time for performance metrics
    START_TIME=\$(date +%s)
    START_TIMESTAMP=\$(date -Iseconds)

    # Memory usage monitoring (background process)
    (while true; do
        ps aux | grep kraken2 | grep -v grep | awk '{print \$6}' >> mem_usage.tmp 2>/dev/null || true
        sleep 5
    done) &
    MONITOR_PID=\$!

    # Run Kraken2 with optimizations
    echo "Running Kraken2 with optimizations:" >&2
    echo "  Memory mapping: ${use_memory_mapping}" >&2
    echo "  Confidence threshold: ${confidence_threshold}" >&2
    echo "  Minimum hit groups: ${minimum_hit_groups}" >&2

    kraken2 \\
        --db $db \\
        --threads $task.cpus \\
        --report ${prefix}.kraken2.report.txt \\
        --gzip-compressed \\
        $memory_mapping \\
        $confidence \\
        $min_hit_groups \\
        $unclassified_option \\
        $classified_option \\
        $readclassification_option \\
        $paired \\
        $args \\
        $reads

    # Stop memory monitoring
    kill \$MONITOR_PID 2>/dev/null || true

    # Compress output FASTQs if required
    $compress_reads_command

    # Calculate performance metrics
    END_TIME=\$(date +%s)
    END_TIMESTAMP=\$(date -Iseconds)
    DURATION=\$((END_TIME - START_TIME))

    # Extract classification statistics from report
    TOTAL_SEQS=\$(awk '{total+=\$3} END {print total}' ${prefix}.kraken2.report.txt)
    CLASSIFIED_SEQS=\$(awk '\$1!="U" {total+=\$3} END {print total}' ${prefix}.kraken2.report.txt)
    UNCLASSIFIED_SEQS=\$(awk '\$1=="U" {print \$3}' ${prefix}.kraken2.report.txt)

    # Calculate peak memory usage
    if [ -f mem_usage.tmp ]; then
        PEAK_MEM_KB=\$(sort -n mem_usage.tmp | tail -1)
        PEAK_MEM_MB=\$((PEAK_MEM_KB / 1024))
        rm -f mem_usage.tmp
    else
        PEAK_MEM_MB=0
    fi

    # Generate performance metrics JSON
    cat > ${prefix}.kraken2.performance.json <<EOF
{
  "sample_id": "${meta.id}",
  "start_time": "\$START_TIMESTAMP",
  "end_time": "\$END_TIMESTAMP",
  "duration_seconds": \$DURATION,
  "classification_statistics": {
    "total_sequences": \$TOTAL_SEQS,
    "classified_sequences": \$CLASSIFIED_SEQS,
    "unclassified_sequences": \$UNCLASSIFIED_SEQS,
    "classification_rate": \$(awk "BEGIN {printf \"%.2f\", (\$CLASSIFIED_SEQS / \$TOTAL_SEQS * 100)}")
  },
  "performance_metrics": {
    "sequences_per_second": \$(awk "BEGIN {printf \"%.2f\", (\$TOTAL_SEQS / \$DURATION)}"),
    "peak_memory_mb": \$PEAK_MEM_MB,
    "threads_used": $task.cpus
  },
  "optimization_settings": {
    "memory_mapping_enabled": ${use_memory_mapping},
    "confidence_threshold": ${confidence_threshold},
    "minimum_hit_groups": ${minimum_hit_groups}
  }
}
EOF

    # Log performance summary
    echo "" >&2
    echo "========================================" >&2
    echo "Kraken2 Performance Summary" >&2
    echo "========================================" >&2
    echo "Sample: ${meta.id}" >&2
    echo "Duration: \${DURATION}s" >&2
    echo "Classified: \$CLASSIFIED_SEQS / \$TOTAL_SEQS (\$(awk "BEGIN {printf \"%.1f\", (\$CLASSIFIED_SEQS / \$TOTAL_SEQS * 100)}")%)" >&2
    echo "Speed: \$(awk "BEGIN {printf \"%.0f\", (\$TOTAL_SEQS / \$DURATION)}") seqs/sec" >&2
    echo "Peak memory: \${PEAK_MEM_MB} MB" >&2
    echo "========================================" >&2

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        kraken2: \$(echo \$(kraken2 --version 2>&1) | sed 's/^.*Kraken version //; s/ .*\$//')
        pigz: \$( pigz --version 2>&1 | sed 's/pigz //g' )
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    def paired       = meta.single_end ? "" : "--paired"
    def classified   = meta.single_end ? "${prefix}.classified.fastq.gz"   : "${prefix}.classified_1.fastq.gz ${prefix}.classified_2.fastq.gz"
    def unclassified = meta.single_end ? "${prefix}.unclassified.fastq.gz" : "${prefix}.unclassified_1.fastq.gz ${prefix}.unclassified_2.fastq.gz"
    """
    touch ${prefix}.kraken2.report.txt
    echo '{"sample_id": "${meta.id}", "duration_seconds": 0}' > ${prefix}.kraken2.performance.json

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
