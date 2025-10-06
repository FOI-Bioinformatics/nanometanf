# Performance Tuning Guide

Optimize nanometanf for production workloads and large-scale processing.

## Performance Profiles Overview

```bash
# Auto-select optimal profile (recommended)
nextflow run ... --optimization_profile auto

# Available profiles:
# - auto                  : Automatic selection
# - high_throughput      : Maximum speed (high resources)
# - balanced             : Default production settings
# - resource_conservative: Minimal resource usage
# - gpu_optimized        : GPU-accelerated workloads
# - realtime_optimized   : Low-latency real-time processing
```

---

## Quick Wins (5-minute optimizations)

### 1. Enable Dynamic Resource Allocation
**Impact**: 20-40% faster execution, 30% better resource utilization

```bash
nextflow run ... \
    --enable_dynamic_resources \
    --optimization_profile auto
```

### 2. Use Local Disk for Work Directory
**Impact**: 2-3x faster I/O, especially on network filesystems

```bash
nextflow run ... \
    -w /local/fast/disk/work \
    --outdir /network/storage/results
```

### 3. Enable Process Caching
**Impact**: Instant resume of failed runs

```bash
# Always use -resume
nextflow run ... -resume

# Set cache strategy
nextflow.config:
process.cache = 'deep'  # Hash inputs deeply
```

---

## Computational Resources

### CPU Optimization

**Default behavior**: Pipeline auto-detects available CPUs

**Fine-tuning**:
```bash
# Limit total concurrent processes
nextflow run ... -c <(cat << 'EOF'
process {
    maxForks = 10           # Max 10 processes at once
    cpus = 4                # Default 4 CPUs per process
}
EOF
)

# Per-process tuning
nextflow run ... -c <(cat << 'EOF'
process {
    withName:KRAKEN2_KRAKEN2 {
        cpus = 16           # Kraken2 benefits from more CPUs
    }
    withName:FASTP {
        cpus = 4            # FASTP optimal at 4 CPUs
    }
}
EOF
)
```

**Benchmarks** (typical runtimes):
- Kraken2 (10GB database, 1M reads): 4 CPUs = 10min, 16 CPUs = 3min
- FASTP (1M reads): 4 CPUs = 2min, 16 CPUs = 1.5min

---

### Memory Optimization

**Memory profiles**:
```bash
# Conservative (8GB total)
nextflow run ... --optimization_profile resource_conservative

# Balanced (32GB total)
nextflow run ... --optimization_profile balanced

# High-throughput (128GB+ total)
nextflow run ... --optimization_profile high_throughput
```

**Per-process memory**:
```bash
nextflow run ... -c <(cat << 'EOF'
process {
    withName:KRAKEN2_KRAKEN2 {
        memory = '64.GB'    # Kraken2 with large DB
    }
    withName:NANOPLOT {
        memory = '8.GB'     # NanoPlot is memory-light
    }
}
EOF
)
```

**Memory tips**:
- Kraken2: `database_size × 1.2` (e.g., 50GB DB needs 60GB RAM)
- Dorado GPU: 8GB+ GPU RAM for HAC models
- MultiQC: 2GB per 100 samples

---

### Disk I/O Optimization

**Storage hierarchy** (fastest to slowest):
1. Local NVMe/SSD (`-w /local/nvme/work`)
2. Local HDD (`-w /local/hdd/work`)
3. Network storage (`-w /nfs/work`)

**Reduce I/O**:
```bash
# Publish only final results (not intermediate)
nextflow run ... -c <(cat << 'EOF'
process {
    publishDir = [
        path: params.outdir,
        mode: 'copy',
        saveAs: { filename ->
            // Only save specific files
            filename.endsWith('.html') || filename.endsWith('.txt') ?
                filename : null
        }
    ]
}
EOF
)

# Use symlinks for large files
nextflow run ... --outdir results --publish_dir_mode symlink
```

---

## Workflow-Specific Optimizations

### Dorado Basecalling

**GPU acceleration**:
```bash
# Automatic GPU detection and optimization
nextflow run ... \
    --use_dorado \
    --optimization_profile gpu_optimized

# Manual GPU tuning
nextflow run ... \
    --use_dorado \
    -c <(cat << 'EOF'
process {
    withName:DORADO_BASECALLER {
        ext.args = '--batchsize 384 --chunksize 10000'
        accelerator = 1, type: 'nvidia-tesla-v100'
    }
}
EOF
)
```

**Batch size recommendations**:
- NVIDIA A100 (80GB): `--batchsize 512`
- NVIDIA V100 (32GB): `--batchsize 384`
- NVIDIA T4 (16GB): `--batchsize 192`
- Apple M1/M2: `--batchsize 192`
- CPU only: `--batchsize 128`

**Performance** (HAC model, POD5 → FASTQ):
- A100: ~40-50M bases/sec
- V100: ~25-30M bases/sec
- CPU (32-core): ~2-3M bases/sec

---

### Kraken2 Classification

**Database optimization**:
```bash
# Option 1: Use memory-mapped I/O (faster startup)
nextflow run ... \
    --kraken2_use_optimizations \
    --kraken2_memory_mapping

# Option 2: Preload database to RAM disk
mkdir /dev/shm/kraken2_db
cp -r /path/to/kraken2_db/* /dev/shm/kraken2_db/
nextflow run ... --kraken2_db /dev/shm/kraken2_db/
```

**Confidence filtering** (reduce false positives):
```bash
nextflow run ... \
    --kraken2_use_optimizations \
    --kraken2_confidence 0.1  # Filter low-confidence hits
```

**Database selection** (speed vs accuracy):
| Database | Size | RAM | Classification Time (1M reads) |
|----------|------|-----|-------------------------------|
| MiniKraken | 8GB | 8GB | 2 min |
| Standard | 50GB | 50GB | 3 min |
| Standard-8 | 8GB | 8GB | 4 min |
| PlusPF | 75GB | 75GB | 5 min |

---

### Real-time Monitoring

**Latency optimization**:
```bash
nextflow run ... \
    --realtime_mode \
    --optimization_profile realtime_optimized \
    --batch_size 5              # Smaller batches
    --batch_interval "2min"     # Faster intervals
```

**Throughput vs latency**:
- **Low latency** (real-time alerts): `batch_size=5, interval=2min`
- **High throughput** (overnight runs): `batch_size=50, interval=30min`

---

## Parallelization Strategies

### Horizontal Scaling (Multiple samples)

```bash
# Process all samples in parallel
nextflow run ... \
    -c <(echo "executor.queueSize = 100") \
    --input large_samplesheet.csv
```

**Best for**: 100+ samples, cluster environments

---

### Vertical Scaling (Single sample)

```bash
# Allocate more resources per sample
nextflow run ... \
    -c <(cat << 'EOF'
process {
    withName:DORADO_BASECALLER {
        cpus = 32
        memory = '128.GB'
        accelerator = 4, type: 'nvidia-tesla-a100'
    }
}
EOF
)
```

**Best for**: <10 samples, large per-sample data

---

## Cloud/Cluster Optimization

### AWS Batch

```bash
nextflow run ... \
    -profile awsbatch \
    --optimization_profile high_throughput \
    --outdir s3://my-bucket/results \
    -w s3://my-bucket/work
```

**Cost optimization**:
- Use spot instances (`ec2.instanceType = 'r5.4xlarge' ec2.spotPrice = '0.50'`)
- Auto-terminate idle instances
- Store databases on EFS (mounted once)

---

### HPC/Slurm

```bash
nextflow run ... \
    -profile slurm \
    --optimization_profile high_throughput \
    -c <(cat << 'EOF'
process {
    executor = 'slurm'
    queue = 'normal'
    cpus = 16
    memory = '64.GB'
    time = '24.h'

    withLabel:process_high {
        queue = 'highmem'
        memory = '128.GB'
        cpus = 32
    }
}
executor {
    queueSize = 100
    pollInterval = '30sec'
}
EOF
)
```

---

## Monitoring Performance

### Enable Profiling

```bash
nextflow run ... \
    -with-report report.html \
    -with-timeline timeline.html \
    -with-trace trace.txt \
    -with-dag dag.html
```

### Analyze Results

**Key metrics**:
```bash
# Check trace file
cat trace.txt | column -t | less -S

# Find slowest processes
sort -k10 -n trace.txt | tail -20

# Find memory-intensive processes
sort -k6 -n trace.txt | tail -20
```

### Performance Benchmarking

```bash
# Run baseline benchmark
python bin/performance_regression_tester.py run --test-suite baseline

# Compare with previous run
python bin/performance_regression_tester.py compare \
    --baseline .performance_tests/benchmark_baseline_*.json \
    --current .performance_tests/benchmark_current_*.json
```

---

## Production Recommendations

### Standard Production Settings

```bash
#!/bin/bash
# production_run.sh

export NXF_OPTS='-Xms2g -Xmx8g'  # Nextflow JVM memory

nextflow run foi-bioinformatics/nanometanf \
    --input samplesheet.csv \
    --outdir /production/results \
    --kraken2_db /databases/kraken2 \
    \
    --enable_dynamic_resources \
    --optimization_profile balanced \
    \
    -profile docker \
    -w /local/nvme/work \
    \
    -with-report report.html \
    -with-timeline timeline.html \
    -with-trace trace.txt \
    \
    -resume \
    \
    --email user@institution.org \
    --email_on_fail user@institution.org
```

### High-Throughput Settings (1000+ samples)

```bash
nextflow run ... \
    --optimization_profile high_throughput \
    --enable_dynamic_resources \
    \
    -c <(cat << 'EOF'
process {
    maxForks = 50
    cache = 'deep'
}
executor {
    queueSize = 200
}
EOF
) \
    \
    -w /fast/local/disk/work \
    --outdir /network/storage/results
```

---

## Troubleshooting Performance

### Pipeline slower than expected

**Check**:
```bash
# Generate timeline
nextflow run ... -with-timeline timeline.html

# Look for:
# 1. Sequential execution (should be parallel)
# 2. High queue time (resource starvation)
# 3. Long I/O wait times (slow disk)
```

**Common fixes**:
1. Increase `executor.queueSize`
2. Use local disk for work directory
3. Enable dynamic resources
4. Reduce batch sizes if memory-constrained

---

### High memory usage

**Monitor**:
```bash
# Watch memory during execution
watch -n 5 'free -h'

# Check per-process memory
cat trace.txt | awk '{print $1, $6, $10}' | sort -k2 -n
```

**Solutions**:
- Use `--optimization_profile resource_conservative`
- Reduce `kraken2_batch_size`
- Enable `kraken2_memory_mapping`
- Process fewer samples concurrently

---

## Performance Metrics (Reference)

**Typical throughput** (balanced profile, 16 CPU, 64GB RAM):
- FASTQ QC (NanoPlot): ~500K reads/min
- Kraken2 classification: ~200K reads/min (50GB DB)
- Dorado basecalling (CPU): ~50K bases/sec
- Dorado basecalling (A100 GPU): ~40M bases/sec
- FASTP filtering: ~1M reads/min

**Resource requirements** (per 1M reads):
- Disk space: ~2-5GB (FASTQ), ~10-15GB (POD5)
- Memory: 8-16GB (QC), 50-100GB (Kraken2)
- Time: ~10-30 minutes (full pipeline with classification)

---

## Additional Resources

- [Best Practices](best_practices.md) - Workflow optimization strategies
- [Troubleshooting](troubleshooting.md) - Resolve performance issues
- [Production Deployment](../development/production_deployment.md) - Enterprise setup
- [Developer Documentation](../development/) - Custom optimization
