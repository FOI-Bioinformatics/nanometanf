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
    // Fix: Dorado --trim accepts 'none', 'all', or 'adapters'
    // If both adapters and barcodes need trimming, use 'all'
    // If only adapters, use 'adapters'
    // If neither, omit the argument (default behavior trims all)
    def trim_option = ''
    if (params.trim_adapters && params.trim_barcodes) {
        trim_option = '--trim all'
    } else if (params.trim_adapters) {
        trim_option = '--trim adapters'
    } else if (!params.trim_adapters && !params.trim_barcodes) {
        trim_option = '--no-trim'
    }
    // Note: trim_barcodes alone is not a valid Dorado option, so we use default behavior
    def demultiplex = params.demultiplex && params.barcode_kit ? "--kit-name ${params.barcode_kit}" : ''

    // Handle both single POD5 file and directory of POD5 files
    def input_path = pod5_files.size() == 1 && pod5_files[0].isFile() ? pod5_files[0] : '.'

    // Use custom dorado path if specified
    def dorado_cmd = params.dorado_path ?: 'dorado'

    """
    # Set dorado command
    DORADO_CMD="${dorado_cmd}"

    # Check if dorado is available
    if ! command -v \$DORADO_CMD &> /dev/null; then
        echo "ERROR: Dorado not found: \$DORADO_CMD"
        echo "Please ensure dorado is in PATH or set --dorado_path"
        exit 1
    fi

    # Resolve symlinks to find actual dorado location
    # This is required for Metal GPU support - dorado needs its metallib in ../lib/
    DORADO_PATH=\$(command -v \$DORADO_CMD)
    if [[ -L "\$DORADO_PATH" ]]; then
        # Resolve the symlink (macOS readlink -f equivalent)
        DORADO_REAL=\$(python3 -c "import os; print(os.path.realpath('\$DORADO_PATH'))" 2>/dev/null || readlink -f "\$DORADO_PATH" 2>/dev/null || echo "\$DORADO_PATH")
        DORADO_BIN_DIR=\$(dirname "\$DORADO_REAL")
        DORADO_LIB_DIR=\$(dirname "\$DORADO_BIN_DIR")/lib

        if [[ -d "\$DORADO_LIB_DIR" ]]; then
            echo "Resolved dorado symlink to: \$DORADO_REAL"
            echo "Setting library path: \$DORADO_LIB_DIR"
            export DYLD_LIBRARY_PATH="\$DORADO_LIB_DIR:\${DYLD_LIBRARY_PATH:-}"
            # Use real binary path for Metal GPU support (metallib lookup)
            DORADO_CMD="\$DORADO_REAL"
        fi
    fi

    echo "Using dorado binary: \$DORADO_CMD"

    # Device Selection - respect user's --dorado_device parameter
    echo "=== Device Configuration ==="
    REQUESTED_DEVICE="${params.dorado_device ?: 'auto'}"
    echo "Requested device: \$REQUESTED_DEVICE"

    if [[ "\$REQUESTED_DEVICE" == "cpu" ]]; then
        # User explicitly requested CPU - skip GPU detection
        DEVICE_ARG="--device cpu"
        BATCH_SIZE_ARG="--batchsize 128"
        GPU_DEVICES="cpu"
        GPU_AVAILABLE=false
        echo "Using CPU processing (user requested)"
    elif [[ "\$REQUESTED_DEVICE" != "auto" ]]; then
        # User specified a device (cuda:0, cuda:all, metal, etc.) - use it directly
        DEVICE_ARG="--device \$REQUESTED_DEVICE"
        GPU_DEVICES="\$REQUESTED_DEVICE"
        GPU_AVAILABLE=true
        if [[ "\$REQUESTED_DEVICE" == cuda* ]]; then
            BATCH_SIZE_ARG="--batchsize 384"
        elif [[ "\$REQUESTED_DEVICE" == "metal" ]]; then
            BATCH_SIZE_ARG="--batchsize 192"
        else
            BATCH_SIZE_ARG="--batchsize 128"
        fi
        echo "Using user-specified device: \$REQUESTED_DEVICE"
    else
        # Auto-detect GPU
        GPU_AVAILABLE=false
        GPU_DEVICES=""

        # Check for NVIDIA GPUs
        if command -v nvidia-smi &> /dev/null; then
            echo "NVIDIA drivers detected, checking for available GPUs..."
            if nvidia-smi -L 2>/dev/null | grep -q "GPU"; then
                GPU_COUNT=\$(nvidia-smi -L | wc -l)
                echo "Found \$GPU_COUNT NVIDIA GPU(s)"
                GPU_AVAILABLE=true
                GPU_DEVICES="cuda:all"
            else
                echo "NVIDIA drivers found but no GPUs detected"
            fi
        else
            echo "No NVIDIA drivers detected"
        fi

        # Check for Apple Silicon GPUs (Metal Performance Shaders)
        if [[ "\$GPU_AVAILABLE" == false ]] && [[ "\$(uname)" == "Darwin" ]] && [[ "\$(uname -m)" == "arm64" ]]; then
            if system_profiler SPDisplaysDataType 2>/dev/null | grep -q "Apple"; then
                echo "Apple Silicon GPU detected"
                GPU_AVAILABLE=true
                GPU_DEVICES="metal"
            fi
        fi

        # Set device argument based on detection
        if [ "\$GPU_AVAILABLE" = true ]; then
            DEVICE_ARG="--device \$GPU_DEVICES"
            echo "Using auto-detected GPU: \$GPU_DEVICES"

            if [[ "\$GPU_DEVICES" == "cuda:all" ]]; then
                BATCH_SIZE_ARG="--batchsize 384"
            elif [[ "\$GPU_DEVICES" == "metal" ]]; then
                BATCH_SIZE_ARG="--batchsize 192"
            fi
        else
            DEVICE_ARG="--device cpu"
            BATCH_SIZE_ARG="--batchsize 128"
            GPU_DEVICES="cpu"
            echo "Using CPU processing (no GPU found)"
        fi
    fi

    echo "Device configuration: \$DEVICE_ARG \$BATCH_SIZE_ARG"

    # Download model if not available locally
    echo "=== Model Download ==="
    \$DORADO_CMD download --model ${model} || echo "Model may already be available"

    # Run basecalling with optimal settings
    echo "=== Basecalling ==="
    \$DORADO_CMD basecaller \\
        ${model} \\
        ${input_path} \\
        \$DEVICE_ARG \\
        \$BATCH_SIZE_ARG \\
        --emit-fastq \\
        --min-qscore ${min_qscore} \\
        --verbose \\
        ${trim_option} \\
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
        dorado: \$(\$DORADO_CMD --version 2>&1 | head -n 1 | sed 's/.*dorado //g')
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