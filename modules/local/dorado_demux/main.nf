process DORADO_DEMUX {
    tag "$meta.id"
    label 'process_high'
    
    // Assume dorado is available in PATH
    // conda "${moduleDir}/environment.yml"

    input:
    tuple val(meta), path(reads)
    val barcode_kit

    output:
    tuple val(meta), path("demux_output/barcode*/*.fastq*"), emit: demuxed_reads
    tuple val(meta), path("demux_output/unclassified/*.fastq*"), emit: unclassified, optional: true
    path "demux_output/demux_summary.txt", emit: summary, optional: true
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def trim_barcodes = params.trim_barcodes ? "" : "--no-trim"
    
    """
    mkdir -p demux_output

    # Check if dorado is available
    if ! command -v dorado &> /dev/null; then
        echo "ERROR: Dorado not found in PATH"
        exit 1
    fi

    dorado demux \\
        --kit-name ${barcode_kit} \\
        --output-dir demux_output \\
        ${trim_barcodes} \\
        --emit-fastq \\
        ${args} \\
        ${reads}

    # Create summary
    find demux_output -name "*.fastq*" | wc -l > demux_output/demux_summary.txt
    echo "Demultiplexing completed for ${meta.id}" >> demux_output/demux_summary.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dorado: \$(dorado --version | head -n1 | sed 's/.*dorado //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p demux_output/barcode01
    mkdir -p demux_output/barcode02
    mkdir -p demux_output/unclassified

    # Create realistic stub FASTQ files for each barcode
    cat > demux_output/barcode01/reads.fastq << 'EOF'
@stub_bc01_read_001
ACGTACGTACGTACGTACGTACGTACGTACGTACGT
+
IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
@stub_bc01_read_002
TGCATGCATGCATGCATGCATGCATGCATGCATGCA
+
JJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJ
EOF

    cat > demux_output/barcode02/reads.fastq << 'EOF'
@stub_bc02_read_001
GGTTAACCGGTTAACCGGTTAACCGGTTAACCGGTT
+
KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK
EOF

    cat > demux_output/unclassified/reads.fastq << 'EOF'
@stub_unclass_read_001
NNNNACGTACGTNNNNACGTACGTNNNN
+
###IIIIIIII####IIIIIIII####
EOF

    # Create comprehensive summary
    cat > demux_output/demux_summary.txt << EOF
Demultiplexing Summary for ${meta.id}
=====================================
Barcode Kit: ${barcode_kit}
Trim Barcodes: ${params.trim_barcodes ?: false}

Files Created: 3
- barcode01: 2 reads
- barcode02: 1 read
- unclassified: 1 read

Demultiplexing completed: \$(date "+%Y-%m-%d %H:%M:%S")
EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dorado: 1.1.1
    END_VERSIONS
    """
}