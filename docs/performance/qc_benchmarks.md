# QC Tool Benchmarking Results

This document contains performance benchmarking results for the QC tools available in the nanometanf pipeline.

## Overview

The pipeline supports three primary QC filtering tools, each optimized for different use cases:

| Tool | Category | Optimization | Language | Best For |
|------|----------|-------------|----------|----------|
| **Chopper** | Nanopore-native Rust | Nanopore long reads | Rust | High-throughput nanopore QC (default) |
| **Filtlong** | Nanopore-optimized | Length-weighted quality | C++ | Length-based nanopore filtering |
| **FASTP** | General-purpose | Illumina/short reads | C++ | Legacy/mixed read types |

## Benchmark Framework

The QC_BENCHMARK subworkflow (`subworkflows/local/qc_benchmark`) provides automated performance comparison:

### Metrics Collected

**For all tools:**
- Processing time (wall clock)
- Memory usage (peak RSS)
- CPU utilization
- Reads processed per second

**Tool-specific metrics:**
- **Chopper**: num_seqs, avg_len, avg_qual, Q20%, Q30% (via SeqKit)
- **Filtlong**: reads_kept, bases_kept, mean_length (via log parsing)
- **FASTP**: reads_before/after, q30_rate, duplication_rate (via JSON)

### Running Benchmarks

```bash
# Enable QC benchmarking in your pipeline run
nextflow run . \\
    --input samplesheet.csv \\
    --outdir results \\
    --enable_qc_benchmark true \\
    --max_cpus 8 \\
    --max_memory '16.GB'
```

Or run the benchmark subworkflow tests:

```bash
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH
nf-test test subworkflows/local/qc_benchmark/tests/main.nf.test --verbose
```

## Expected Performance Characteristics

Based on tool design and literature:

### Chopper (Nanopore-Native Rust)

**Expected Performance:**
- **Speed**: 7-10x faster than NanoFilt/Python-based tools
- **Memory**: Low footprint (~50-100 MB for 10K reads)
- **Throughput**: >50,000 reads/second on modern CPU
- **Quality**: Optimized for nanopore Q-score distributions

**Strengths:**
- Rust-based: zero-cost abstractions, no GC pauses
- Streaming processing: constant memory usage
- Nanopore-aware quality filtering
- Fast headcrop/tailcrop for adapter removal

**Use Cases:**
- Real-time sequencing analysis
- High-throughput production pipelines
- Resource-constrained environments
- Default for all nanopore workflows

### Filtlong (Length-Weighted Nanopore)

**Expected Performance:**
- **Speed**: 3-5x faster than FASTP on long reads
- **Memory**: Moderate (200-500 MB for 10K reads)
- **Throughput**: ~15,000 reads/second
- **Quality**: Best for length-based quality filtering

**Strengths:**
- Length-weighted quality scoring
- Excellent for assembly prep (N50 optimization)
- Keeps longest high-quality reads
- Good memory efficiency for large datasets

**Use Cases:**
- Genome assembly workflows
- When read length is critical
- Quality-length tradeoff optimization
- Alternative to Chopper for specific use cases

### FASTP (General-Purpose/Legacy)

**Expected Performance:**
- **Speed**: Baseline (optimized for short reads)
- **Memory**: Higher (400-800 MB for 10K reads)
- **Throughput**: ~8,000 long reads/second
- **Quality**: Best for Illumina, adequate for nanopore

**Strengths:**
- Rich HTML reporting
- Mature, well-tested
- Adapter trimming
- Duplication detection

**Use Cases:**
- Mixed short/long read datasets
- When FASTP-specific features needed
- Backward compatibility
- Illumina contamination removal

## Benchmark Results Placeholders

> **Note**: Actual benchmark results will be populated when run with your specific dataset.
> Results vary based on read length distribution, quality profiles, and system specifications.

### Performance Matrix (Example Template)

**Test Dataset**: 10,000 nanopore reads, mean length 5kb, Q10-Q15

| Metric | Chopper | Filtlong | FASTP | Winner |
|--------|---------|----------|-------|--------|
| **Processing Time** | TBD s | TBD s | TBD s | - |
| **Peak Memory** | TBD MB | TBD MB | TBD MB | - |
| **Reads Retained** | TBD | TBD | TBD | - |
| **Mean Length After** | TBD bp | TBD bp | TBD bp | - |
| **Mean Quality After** | TBD | TBD | TBD | - |
| **Q30 Bases %** | TBD% | TBD% | TBD% | - |
| **Throughput** | TBD reads/s | TBD reads/s | TBD reads/s | - |

### Speed Comparison (Relative)

```
Chopper:    ████████████████████ 100% (baseline)
Filtlong:   ███████████          55%
FASTP:      ████████             40%
```

### Memory Efficiency

```
Chopper:    ████                 Low  (~100 MB)
Filtlong:   ████████             Med  (~300 MB)
FASTP:      ████████████         High (~600 MB)
```

## Tool Selection Guidelines

### Decision Tree

```
┌─ Need maximum speed? ─────────────────────> Chopper
│
├─ Need length optimization for assembly? ──> Filtlong
│
├─ Mixed Illumina + Nanopore data? ─────────> FASTP
│
└─ Default nanopore workflow? ─────────────> Chopper
```

### Recommendation Matrix

| Workflow Type | Recommended Tool | Rationale |
|---------------|------------------|-----------|
| **Real-time analysis** | Chopper | Lowest latency, streaming |
| **Genome assembly** | Filtlong | Length-weighted N50 optimization |
| **Metagenomics** | Chopper | Speed + nanopore Q-score handling |
| **Hybrid assembly** | FASTP first, then Filtlong | Remove Illumina contam, then length filter |
| **Production pipeline** | Chopper | Speed, reliability, resource efficiency |
| **Legacy workflows** | FASTP | Backward compatibility |

## Configuration Examples

### High-Throughput (Chopper)

```nextflow
params {
    qc_tool = 'chopper'
    chopper_quality = 10        // Relaxed for speed
    chopper_minlength = 1000
    chopper_maxlength = null    // No upper limit
}
```

### Assembly-Optimized (Filtlong)

```nextflow
params {
    qc_tool = 'filtlong'
    filtlong_min_length = 2000       // Longer reads for assembly
    filtlong_keep_percent = 90       // Keep 90% best
    filtlong_target_bases = 500000000 // 500 Mbp target
}
```

### Balanced (Chopper + Filtlong)

```nextflow
// First pass: Chopper for quality
params {
    qc_tool = 'chopper'
    chopper_quality = 12
    chopper_minlength = 1500
}

// Then manual Filtlong step for length optimization
```

## Performance Tuning

### Chopper Optimization

```bash
# Minimal filtering (maximum speed)
--qc_tool chopper --chopper_quality 7 --chopper_minlength 500

# Balanced quality-speed
--qc_tool chopper --chopper_quality 10 --chopper_minlength 1000

# High quality (slower but better)
--qc_tool chopper --chopper_quality 15 --chopper_minlength 2000
```

### Resource Allocation

```bash
# For benchmark comparison
--max_cpus 8           # Single-threaded tools, but parallel samples
--max_memory '16.GB'   # Comfortable for all tools

# Memory-constrained (prefer Chopper)
--qc_tool chopper --max_memory '4.GB'

# Time-critical (maximum Chopper speed)
--qc_tool chopper --chopper_quality 8 --max_cpus 16
```

## Validation and Quality Assurance

All benchmark results are validated with:

1. **FastQC**: HTML reports for visual QC inspection
2. **SeqKit Stats**: Comprehensive read statistics
3. **NanoPlot**: Nanopore-specific quality plots
4. **Comparison Analysis**: Automated tool performance comparison

Output channels include:
- `benchmark_results`: Combined metrics for all tools
- `chopper_results`: Chopper-specific outputs
- `filtlong_results`: Filtlong-specific outputs
- `fastp_results`: FASTP-specific outputs
- `nanoplot_reports`: Visualization for all tools

## References

- **Chopper**: https://github.com/wdecoster/chopper (Rust-based nanopore QC)
- **Filtlong**: https://github.com/rrwick/Filtlong (Length-based quality filtering)
- **FASTP**: https://github.com/OpenGene/fastp (Fast all-in-one preprocessing)
- **NanoPlot**: https://github.com/wdecoster/NanoPlot (Nanopore read visualization)
- **SeqKit**: https://bioinf.shenwei.me/seqkit/ (FASTA/Q toolkit)

## Contributing Benchmark Results

To contribute your benchmark results to this documentation:

1. Run the QC_BENCHMARK subworkflow with your dataset
2. Extract metrics from the output channels
3. Document system specifications (CPU, memory, read characteristics)
4. Submit a PR with updated performance tables

Example benchmark submission:

```yaml
dataset:
  name: "E. coli R9.4.1 MinION"
  reads: 50000
  mean_length: 8500bp
  mean_quality: Q12
  total_bases: 425Mb

system:
  cpu: "Intel Xeon Gold 6248R @ 3.0GHz"
  cores: 8
  memory: "32GB DDR4"
  os: "Ubuntu 22.04"

results:
  chopper:
    time: 12.3s
    memory: 95MB
    throughput: 4065 reads/s
    reads_kept: 45200
    mean_qual_after: Q13.2

  filtlong:
    time: 45.7s
    memory: 340MB
    throughput: 1094 reads/s
    reads_kept: 43100
    mean_length_after: 9200bp

  fastp:
    time: 67.2s
    memory: 720MB
    throughput: 744 reads/s
    reads_kept: 42800
    q30_rate: 38.5%
```

---

**Last Updated**: 2025-10-06
**Pipeline Version**: 1.1.0+
**Benchmark Framework Version**: 1.0
