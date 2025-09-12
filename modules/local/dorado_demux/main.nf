process DORADO_DEMUX {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/dorado:0.7.3--h9ee0642_0':
        'biocontainers/dorado:0.7.3--h9ee0642_0' }"

    input:
    tuple val(meta), path(fastq)
    val barcode_kit

    output:
    tuple val(meta), path("demux_*.fastq.gz"), emit: fastq
    tuple val(meta), path("*_demux_summary.txt"), emit: summary
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def trim_barcodes = params.trim_barcodes ? '--trim' : '--no-trim'
    
    """
    # Check if dorado is available
    if [ ! -f "${params.dorado_path}" ]; then
        echo "ERROR: Dorado not found at ${params.dorado_path}"
        exit 1
    fi

    # Create output directory for demultiplexed reads
    mkdir -p demux_output

    # Run demultiplexing
    ${params.dorado_path} demux \\
        --kit-name ${barcode_kit} \\
        ${trim_barcodes} \\
        --output-dir demux_output \\
        ${args} \\
        ${fastq}

    # Process demultiplexed files
    for barcode_file in demux_output/*.fastq; do
        if [ -f "\$barcode_file" ]; then
            # Extract barcode name from filename
            barcode_name=\$(basename "\$barcode_file" .fastq)
            
            # Skip unclassified reads if empty
            if [ "\$barcode_name" = "unclassified" ] && [ ! -s "\$barcode_file" ]; then
                continue
            fi
            
            # Compress and rename
            gzip "\$barcode_file"
            mv "demux_output/\${barcode_name}.fastq.gz" "demux_\${barcode_name}.fastq.gz"
        fi
    done

    # Create summary
    echo "Original sample: ${prefix}" > ${prefix}_demux_summary.txt
    echo "Barcode kit: ${barcode_kit}" >> ${prefix}_demux_summary.txt
    echo "Trim barcodes: ${params.trim_barcodes}" >> ${prefix}_demux_summary.txt
    echo "Demultiplexing completed: \$(date)" >> ${prefix}_demux_summary.txt
    echo "" >> ${prefix}_demux_summary.txt
    echo "Demultiplexed samples:" >> ${prefix}_demux_summary.txt
    for file in demux_*.fastq.gz; do
        if [ -f "\$file" ]; then
            reads=\$(zcat "\$file" | wc -l | awk '{print \$1/4}')
            echo "  \$file: \$reads reads" >> ${prefix}_demux_summary.txt
        fi
    done

    # Clean up
    rm -rf demux_output

    # Version information
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dorado: \$(${params.dorado_path} --version 2>&1 | head -n 1 | sed 's/.*dorado //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch demux_barcode01.fastq.gz
    touch demux_barcode02.fastq.gz
    touch ${prefix}_demux_summary.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dorado: \$(echo "0.7.3")
    END_VERSIONS
    """
}