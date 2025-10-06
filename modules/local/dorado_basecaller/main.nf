process DORADO_BASECALLER {
    tag "$meta.id"
    label 'process_high'

    // Assume dorado is available in PATH
    // conda "${moduleDir}/environment.yml"

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
    def trim_adapters = params.trim_adapters ? '--trim adapters' : ''
    def trim_barcodes = params.trim_barcodes ? '--trim' : ''
    def demultiplex = params.demultiplex && params.barcode_kit ? "--kit-name ${params.barcode_kit}" : ''

    // Handle both single POD5 file and directory of POD5 files
    def input_path = pod5_files.size() == 1 && pod5_files[0].isFile() ? pod5_files[0] : '.'
    
    """
    # Check if dorado is available
    if ! command -v dorado &> /dev/null; then
        echo "ERROR: Dorado not found in PATH"
        exit 1
    fi

    # GPU Detection and Device Selection
    echo "=== GPU Detection ==="
    GPU_AVAILABLE=false
    GPU_DEVICES=""
    
    # Check for NVIDIA GPUs
    if command -v nvidia-smi &> /dev/null; then
        echo "NVIDIA drivers detected, checking for available GPUs..."
        if nvidia-smi -L 2>/dev/null | grep -q "GPU"; then
            GPU_COUNT=\$(nvidia-smi -L | wc -l)
            echo "Found \$GPU_COUNT NVIDIA GPU(s)"
            GPU_AVAILABLE=true
            # Use all available GPUs
            GPU_DEVICES="cuda:all"
        else
            echo "NVIDIA drivers found but no GPUs detected"
        fi
    else
        echo "No NVIDIA drivers detected"
    fi
    
    # Check for Apple Silicon GPUs (Metal Performance Shaders)
    if [[ "\$(uname)" == "Darwin" ]] && [[ "\$(uname -m)" == "arm64" ]]; then
        if system_profiler SPDisplaysDataType 2>/dev/null | grep -q "Apple"; then
            echo "Apple Silicon GPU detected"
            GPU_AVAILABLE=true
            GPU_DEVICES="metal"
        fi
    fi
    
    # Set device argument based on availability
    if [ "\$GPU_AVAILABLE" = true ]; then
        DEVICE_ARG="--device \$GPU_DEVICES"
        echo "Using GPU acceleration: \$GPU_DEVICES"
        
        # Optimize batch size for GPU
        if [[ "\$GPU_DEVICES" == "cuda:all" ]]; then
            BATCH_SIZE_ARG="--batchsize 384"  # Optimized for NVIDIA GPUs
            CHUNK_SIZE_ARG="--chunksize 10000"
        elif [[ "\$GPU_DEVICES" == "metal" ]]; then
            BATCH_SIZE_ARG="--batchsize 192"  # Conservative for Apple Silicon
            CHUNK_SIZE_ARG="--chunksize 4000"
        fi
    else
        DEVICE_ARG="--device cpu"
        BATCH_SIZE_ARG="--batchsize 128"   # Conservative for CPU
        CHUNK_SIZE_ARG="--chunksize 4000"
        echo "Using CPU processing (no suitable GPU found)"
    fi
    
    echo "Device configuration: \$DEVICE_ARG \$BATCH_SIZE_ARG \$CHUNK_SIZE_ARG"

    # Download model if not available locally  
    echo "=== Model Download ==="
    dorado download --model ${model} || echo "Model may already be available"

    # Run basecalling with optimal settings
    echo "=== Basecalling ==="
    dorado basecaller \\
        ${model} \\
        ${input_path} \\
        \$DEVICE_ARG \\
        \$BATCH_SIZE_ARG \\
        \$CHUNK_SIZE_ARG \\
        --emit-fastq \\
        --min-qscore ${min_qscore} \\
        --verbose \\
        ${trim_adapters} \\
        ${trim_barcodes} \\
        ${demultiplex} \\
        ${args} \\
        > ${prefix}.fastq

    # Compress output
    echo "=== Compression ==="
    gzip ${prefix}.fastq

    # Create detailed summary file
    echo "=== Summary Generation ==="
    cat > ${prefix}_summary.txt << EOF
Sample: ${prefix}
Model: ${model}
Min Q-score: ${min_qscore}
Device: \$GPU_DEVICES
GPU Available: \$GPU_AVAILABLE
Trim Adapters: ${params.trim_adapters ?: false}
Trim Barcodes: ${params.trim_barcodes ?: false}
Demultiplex: ${params.demultiplex ?: false}
Barcode Kit: ${params.barcode_kit ?: 'none'}
Input files: ${pod5_files.join(', ')}
Input file count: ${pod5_files.size()}
Basecalling started: \$(date)
Basecalling completed: \$(date)
Host: \$(hostname)
CPUs: ${task.cpus}
Memory: ${task.memory}
EOF

    # Add GPU information to summary if available
    if [ "\$GPU_AVAILABLE" = true ]; then
        echo "GPU Information:" >> ${prefix}_summary.txt
        if command -v nvidia-smi &> /dev/null; then
            nvidia-smi --query-gpu=name,memory.total,utilization.gpu --format=csv,noheader,nounits >> ${prefix}_summary.txt 2>/dev/null || echo "GPU info unavailable" >> ${prefix}_summary.txt
        elif [[ "\$(uname)" == "Darwin" ]]; then
            system_profiler SPDisplaysDataType | grep "Chipset Model" >> ${prefix}_summary.txt 2>/dev/null || echo "Apple GPU info" >> ${prefix}_summary.txt
        fi
    fi

    # Version information
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dorado: \$(dorado --version 2>&1 | head -n 1 | sed 's/.*dorado //g')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def min_qscore = params.min_qscore ?: 9
    """
    # Create stub FASTQ with realistic structure
    cat > ${prefix}.fastq << 'EOF'
@stub_read_001 runid=stub basecall_model_version=${model}
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
+
IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
@stub_read_002 runid=stub basecall_model_version=${model}
TGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCA
+
JJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJ
EOF
    gzip ${prefix}.fastq

    # Create comprehensive summary matching real output structure
    cat > ${prefix}_summary.txt << EOF
Sample: ${prefix}
Model: ${model}
Min Q-score: ${min_qscore}
Device: cpu
GPU Available: false
Trim Adapters: ${params.trim_adapters ?: false}
Trim Barcodes: ${params.trim_barcodes ?: false}
Demultiplex: ${params.demultiplex ?: false}
Barcode Kit: ${params.barcode_kit ?: 'none'}
Input files: stub_input.pod5
Input file count: 1
Basecalling started: \$(date "+%Y-%m-%d %H:%M:%S")
Basecalling completed: \$(date "+%Y-%m-%d %H:%M:%S")
Host: \$(hostname)
CPUs: ${task.cpus}
Memory: ${task.memory}
EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        dorado: 1.1.1
    END_VERSIONS
    """
}