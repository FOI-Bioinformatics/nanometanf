# QC Tools Guide for nanometanf Pipeline

## Overview

The nanometanf pipeline implements an advanced multi-tool QC framework that allows users to easily switch between different quality control tools optimized for nanopore sequencing data. This guide provides comprehensive recommendations for choosing the right QC approach for your data and use case.

## Quick Start

### Basic Usage
```bash
# Use default FASTP (general-purpose)
nextflow run foi-bioinformatics/nanometanf --input samplesheet.csv --outdir results

# Use FILTLONG (nanopore-optimized)
nextflow run foi-bioinformatics/nanometanf --input samplesheet.csv --outdir results --qc_tool filtlong

# Use FILTLONG with adapter trimming (recommended)
nextflow run foi-bioinformatics/nanometanf --input samplesheet.csv --outdir results --qc_tool filtlong --enable_adapter_trimming true
```

### Using QC Strategy Profiles
```bash
# Stringent QC for genomics/variant calling
nextflow run foi-bioinformatics/nanometanf -profile docker,nanopore_strict --input samplesheet.csv --outdir results

# Optimized for metagenomics
nextflow run foi-bioinformatics/nanometanf -profile docker,nanopore_metagenomics --input samplesheet.csv --outdir results

# Optimized for genome assembly
nextflow run foi-bioinformatics/nanometanf -profile docker,nanopore_assembly --input samplesheet.csv --outdir results
```

## QC Tools Comparison

### FASTP (General-Purpose)
- **Best for**: Cross-platform compatibility, detailed reporting, RNA data
- **Strengths**: Rich HTML reports, JSON output, comprehensive statistics
- **Optimal use cases**: Mixed sequencing technologies, transcriptomics, detailed QC analysis
- **Performance**: Moderate speed, moderate memory usage

### FILTLONG (Nanopore-Optimized)
- **Best for**: Nanopore data, length-based filtering, speed
- **Strengths**: Nanopore-specific algorithms, length-weighted quality scoring, fast processing
- **Optimal use cases**: Genomics, metagenomics, assembly projects
- **Performance**: Fast processing, low memory usage
- **Enhanced reporting**: Automatically includes FastQC and SeqKit statistics

### PORECHOP + FILTLONG (Enhanced)
- **Best for**: High-quality requirements, contaminated samples
- **Strengths**: Adapter removal, highest quality output
- **Optimal use cases**: Critical applications, contaminated samples, publication-quality data
- **Performance**: Slower due to two-step process, highest quality output

## QC Strategy Profiles

The pipeline includes pre-configured QC profiles optimized for different use cases:

### nanopore_strict
**Use for**: High-quality genomics, variant calling, publication data
```bash
# Configuration highlights:
--qc_tool filtlong
--enable_adapter_trimming true
--filtlong_min_length 2000
--filtlong_keep_percent 75
--filtlong_min_mean_q 10.0
```

### nanopore_balanced (Recommended)
**Use for**: General nanopore analysis, routine QC
```bash
# Configuration highlights:
--qc_tool filtlong
--enable_adapter_trimming true
--filtlong_min_length 1000
--filtlong_keep_percent 90
--filtlong_min_mean_q 8.0
```

### nanopore_permissive
**Use for**: Low-coverage samples, contaminated data, challenging datasets
```bash
# Configuration highlights:
--qc_tool filtlong
--enable_adapter_trimming false
--filtlong_min_length 500
--filtlong_keep_percent 95
--filtlong_min_mean_q 6.0
```

### nanopore_metagenomics
**Use for**: Metagenomic analysis, taxonomic profiling
```bash
# Configuration highlights:
--qc_tool filtlong
--filtlong_keep_percent 85
--filtlong_min_mean_q 9.0
--save_reads_assignment true
--enable_taxpasta_standardization true
```

### nanopore_assembly
**Use for**: Genome assembly projects
```bash
# Configuration highlights:
--qc_tool filtlong
--filtlong_min_length 1500
--filtlong_keep_percent 80
--filtlong_min_mean_q 9.0
--enable_assembly true
```

### nanopore_rna
**Use for**: RNA/transcriptomic analysis
```bash
# Configuration highlights:
--qc_tool fastp  # Better adapter handling for RNA
--fastp_qualified_quality 10
--fastp_length_required 500
--enable_assembly false
```

## Parameter Optimization Guide

### FILTLONG Parameters

#### `filtlong_min_length` (default: 1000)
- **1000-1500**: Standard for most applications
- **2000+**: Strict filtering for high-quality assemblies
- **500-800**: Permissive for low-coverage or transcriptomic data

#### `filtlong_keep_percent` (default: 90)
- **75-85%**: Strict quality requirements
- **90-95%**: Balanced approach
- **95-99%**: Permissive filtering

#### `filtlong_min_mean_q` (default: 8.0)
- **10+**: High-quality requirements
- **8-9**: Standard filtering
- **6-7**: Permissive for challenging data

### FASTP Parameters

#### `fastp_qualified_quality` (default: 15)
- **20+**: Strict quality filtering
- **15-20**: Standard filtering
- **10-15**: Permissive filtering

#### `fastp_length_required` (default: 1000)
- Adjust based on expected read lengths for your application

## Performance Benchmarking

### Enable Benchmarking
```bash
nextflow run foi-bioinformatics/nanometanf \
  --input samplesheet.csv \
  --outdir results \
  --enable_qc_benchmark true
```

This will run all QC tools on your data and generate a comprehensive comparison report including:
- Processing time comparison
- Memory usage analysis
- Read retention rates
- Quality improvement metrics
- Tool-specific recommendations

### Benchmark Analysis
```bash
# Generate benchmark report
python bin/qc_benchmark_analyzer.py \
  --results_dir results/qc_benchmark \
  --output qc_benchmark_report.html
```

## Best Practices

### Data Type Considerations

#### Genomic DNA
- **Recommended**: `nanopore_balanced` or `nanopore_strict` profiles
- **Tool**: FILTLONG with adapter trimming
- **Focus**: Read length preservation, quality improvement

#### Metagenomic samples
- **Recommended**: `nanopore_metagenomics` profile
- **Tool**: FILTLONG with moderate stringency
- **Focus**: Taxonomic accuracy, diversity preservation

#### RNA/cDNA
- **Recommended**: `nanopore_rna` profile
- **Tool**: FASTP (better adapter handling)
- **Focus**: Transcript integrity, splice junction preservation

#### Assembly projects
- **Recommended**: `nanopore_assembly` profile
- **Tool**: FILTLONG with length priority
- **Focus**: Long read retention, quality over quantity

### Quality Control Workflow

1. **Initial Assessment**
   - Run with default settings first
   - Review NanoPlot visualization
   - Assess data quality characteristics

2. **Profile Selection**
   - Choose appropriate pre-configured profile
   - Or customize parameters based on data characteristics

3. **Optional Benchmarking**
   - Enable benchmarking for critical projects
   - Compare tool performance on your specific data

4. **Validation**
   - Check output quality metrics
   - Verify downstream analysis compatibility

## Troubleshooting

### Common Issues

#### Low read retention with FILTLONG
- **Solution**: Reduce `filtlong_keep_percent` or `filtlong_min_mean_q`
- **Profile**: Switch to `nanopore_permissive`

#### Slow processing with PORECHOP
- **Solution**: Disable adapter trimming for speed: `--enable_adapter_trimming false`
- **Alternative**: Use FASTP for faster adapter detection

#### Memory issues
- **Solution**: FILTLONG typically uses less memory than FASTP
- **Recommendation**: Use `--qc_tool filtlong` for large datasets

#### Poor assembly results
- **Solution**: Use `nanopore_assembly` profile with longer minimum length
- **Parameters**: Increase `filtlong_min_length` to 2000+

### Performance Optimization

#### Speed Priority
```bash
--qc_tool filtlong
--enable_adapter_trimming false
--skip_nanoplot false  # Keep visualization
```

#### Quality Priority
```bash
--qc_tool filtlong
--enable_adapter_trimming true
--filtlong_keep_percent 75
--filtlong_min_mean_q 10.0
```

#### Memory Efficiency
```bash
--qc_tool filtlong  # More memory efficient than FASTP
--skip_nanoplot true  # Reduce memory usage
```

## Advanced Configuration

### Custom QC Profiles
Create custom profiles in `conf/qc_profiles.config`:
```groovy
my_custom_profile {
    params {
        qc_tool = 'filtlong'
        filtlong_min_length = 1200
        filtlong_keep_percent = 88
        // ... additional parameters
    }
}
```

### Combining with Other Profiles
```bash
nextflow run foi-bioinformatics/nanometanf \
  -profile docker,nanopore_strict,my_custom_profile \
  --input samplesheet.csv --outdir results
```

## Output Interpretation

### FILTLONG + Enhanced Reporting
- **FILTLONG log**: Filtering statistics and decisions
- **FastQC HTML**: Comprehensive sequence quality reports
- **SeqKit stats**: Detailed sequence statistics
- **NanoPlot HTML**: Nanopore-specific visualizations

### FASTP Reporting
- **FASTP HTML**: Rich interactive QC report
- **FASTP JSON**: Machine-readable statistics
- **NanoPlot HTML**: Additional nanopore visualizations

### Benchmark Reports
- **Performance comparison**: Processing time, memory usage
- **Quality metrics**: Read retention, quality improvement
- **Recommendations**: Tool selection guidance

## Integration with Downstream Analysis

### Taxonomic Classification
- Use `nanopore_metagenomics` profile
- Enable taxonomic assignment saving
- Use taxpasta standardization for consistent outputs

### Genome Assembly
- Use `nanopore_assembly` profile
- Prioritize read length over quantity
- Consider strict quality filtering

### Variant Calling
- Use `nanopore_strict` profile
- Enable adapter trimming
- Maximize quality metrics

## Conclusion

The multi-tool QC framework in nanometanf provides flexible, optimized quality control for diverse nanopore sequencing applications. By choosing the appropriate QC strategy and parameters, users can achieve optimal results for their specific use case while maintaining the ease of use through pre-configured profiles.

For additional support or questions about QC tool selection, please refer to the pipeline documentation or create an issue on the GitHub repository.