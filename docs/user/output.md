# nanometanf Output Structure

Comprehensive guide to pipeline outputs, file formats, and result interpretation.

## Table of Contents

- [Output Directory Structure](#output-directory-structure)
- [Core Analysis Outputs](#core-analysis-outputs)
- [Dorado Basecalling Outputs](#dorado-basecalling-outputs)
- [Real-time Processing Outputs](#real-time-processing-outputs)
- [Resource Monitoring Outputs](#resource-monitoring-outputs)
- [Pipeline Execution Reports](#pipeline-execution-reports)
- [Output Files by Execution Mode](#output-files-by-execution-mode)
- [File Format Reference](#file-format-reference)

## Output Directory Structure

### Standard FASTQ Processing

```
results/
├── fastp/                          # Quality filtering outputs
│   ├── <sample>.fastp.html         # Per-sample QC report
│   ├── <sample>.fastp.json         # Machine-readable QC metrics
│   └── <sample>.fastp.fastq.gz     # Filtered reads
├── nanoplot/                       # Nanopore-specific QC
│   ├── <sample>/
│   │   ├── NanoPlot-report.html    # Interactive QC plots
│   │   ├── NanoStats.txt           # Summary statistics
│   │   ├── LengthvsQualityScatterPlot_dot.png
│   │   ├── LengthHistogram.png
│   │   └── ...                     # Additional plots
├── kraken2/                        # Taxonomic classification
│   ├── <sample>.kraken2.report.txt # Taxonomy report
│   ├── <sample>.classified.fastq.gz # Classified reads
│   └── <sample>.unclassified.fastq.gz # Unclassified reads
├── taxpasta/                       # Standardized taxonomy
│   ├── taxpasta_standard.tsv       # Combined taxonomy table
│   └── taxpasta_standard.biom      # BIOM format (optional)
├── multiqc/                        # Comprehensive summary
│   ├── multiqc_report.html         # Interactive dashboard
│   └── multiqc_data/               # Raw data for plots
└── pipeline_info/                  # Execution metadata
    ├── execution_report_*.html     # Nextflow execution report
    ├── execution_timeline_*.html   # Process timeline
    ├── execution_trace_*.txt       # Detailed trace file
    └── params_*.json               # Parameters used
```

### POD5 Basecalling Mode (Additional Outputs)

```
results/
├── dorado/                         # Basecalling outputs
│   ├── basecalls/
│   │   └── <sample>.fastq.gz       # Basecalled reads
│   ├── sequencing_summary.txt      # Per-read statistics
│   └── dorado_stats.json           # Basecalling metrics
├── dorado_demux/                   # Demultiplexing outputs (if barcoded)
│   ├── barcode01/
│   │   └── reads.fastq.gz          # Demultiplexed reads
│   ├── barcode02/
│   │   └── reads.fastq.gz
│   ├── unclassified/
│   │   └── reads.fastq.gz          # Reads without barcode
│   └── demux_summary.txt           # Barcode assignment stats
└── [continues with fastp/, kraken2/, etc.]
```

### Real-time Processing Mode (Additional Outputs)

```
results/
├── realtime_stats/                 # Live statistics
│   ├── snapshots/                  # Time-series data
│   │   ├── stats_20250912_140001.json
│   │   ├── stats_20250912_140301.json
│   │   └── ...                     # Every batch interval
│   ├── cumulative/                 # Aggregated metrics
│   │   ├── cumulative_stats.json   # Latest cumulative data
│   │   └── session_history.json    # Full session tracking
│   └── performance/                # Performance metrics
│       ├── throughput_history.json
│       └── resource_usage.json
├── realtime_reports/               # Live dashboards
│   ├── realtime_dashboard.html     # Interactive monitoring
│   └── quality_dashboard.html      # Quality trends
└── [continues with fastp/, kraken2/, etc.]
```

## Core Analysis Outputs

### FASTP (Quality Filtering)

**Purpose**: Quality control and filtering of nanopore reads

**Key Files:**

**`<sample>.fastp.html`**
- Interactive HTML report with quality metrics
- Read length distribution before/after filtering
- Quality score distribution
- Adapter content analysis
- Duplication rates

**`<sample>.fastp.json`**
```json
{
  "summary": {
    "before_filtering": {
      "total_reads": 150000,
      "total_bases": 450000000,
      "q20_bases": 380000000,
      "q30_bases": 320000000
    },
    "after_filtering": {
      "total_reads": 142000,
      "total_bases": 430000000,
      "q20_bases": 375000000,
      "q30_bases": 318000000
    }
  },
  "filtering_result": {
    "passed_filter_reads": 142000,
    "low_quality_reads": 5200,
    "too_short_reads": 2800
  }
}
```

**`<sample>.fastp.fastq.gz`**
- Filtered reads passing quality thresholds
- Use for downstream analysis
- Compatible with all standard tools

**Default Filtering Criteria:**
- Minimum quality score: 15 (Phred)
- Minimum read length: 1000 bp
- Sliding window quality: 20

### NanoPlot (Nanopore QC)

**Purpose**: Nanopore-specific quality visualization

**Key Files:**

**`NanoPlot-report.html`**
- Comprehensive interactive report
- Read length vs. quality scatter plots
- Temporal quality trends
- Yield over time analysis

**`NanoStats.txt`**
```
General summary:
Mean read length:              3,245.6
Mean read quality:             12.8
Median read length:            2,847.0
Median read quality:           13.2
Number of reads:               142,000
Read length N50:               4,256
Total bases:                   460,872,000
Number, percentage and megabases of reads above quality cutoffs
>Q5:    141000 (99.3%) 458.1Mb
>Q7:    138500 (97.5%) 449.8Mb
>Q10:   125300 (88.2%) 406.7Mb
>Q12:   89400 (63.0%) 290.2Mb
```

**Key Plots:**
- `LengthvsQualityScatterPlot_dot.png` - Identify quality issues
- `LengthHistogram.png` - Size selection assessment
- `Yield_By_Length.png` - Sequencing productivity
- `WeightedLogTransformed_HistogramReadlength.png` - Read length distribution

### Kraken2 (Taxonomic Classification)

**Purpose**: Species-level identification of reads

**Key Files:**

**`<sample>.kraken2.report.txt`**
```
100.00  142000  142000  U       0       unclassified
  0.00  0       0       R       1       root
  0.00  0       0       D       2       Bacteria
  45.23 64240   1250    P       1224    Proteobacteria
  38.15 54173   890     C       1236    Gammaproteobacteria
  35.42 50290   4200    O       91347   Enterobacterales
  28.30 40180   2800    F       543     Enterobacteriaceae
  22.14 31430   31430   G       561     Escherichia
  18.45 26200   26200   S       562     Escherichia coli
```

**Columns:**
1. **Percentage** - % of reads assigned to this taxon
2. **Clade reads** - Reads assigned to this taxon + descendants
3. **Taxon reads** - Reads assigned directly to this taxon
4. **Rank** - U=unclassified, D=domain, P=phylum, C=class, O=order, F=family, G=genus, S=species
5. **NCBI TaxID** - Taxonomy database identifier
6. **Scientific name** - Taxon name

**`<sample>.classified.fastq.gz`**
- Reads with taxonomic assignment
- Headers contain Kraken2 classification
- Format: `@read_id|kraken:taxid|taxid:562`

**`<sample>.unclassified.fastq.gz`**
- Reads without taxonomic assignment
- May indicate novel organisms or contamination
- Review for quality issues

**Interpretation:**

**High classification rate (>70%):**
- Expected organisms detected
- Good database coverage
- High-quality sequencing

**Low classification rate (<30%):**
- Novel organisms
- Database limitations
- Quality issues (check NanoPlot)
- Host contamination

### Taxpasta (Standardized Taxonomy)

**Purpose**: Unified taxonomy format for cross-sample comparison

**Key Files:**

**`taxpasta_standard.tsv`**
```tsv
taxonomy_id     sample1     sample2     sample3     taxonomy_name
562             26200       31450       18900       Escherichia coli
1280            8450        12300       5600        Staphylococcus aureus
1773            3200        2800        4100        Mycobacterium tuberculosis
```

**Columns:**
- `taxonomy_id` - NCBI taxonomy identifier
- `<sample>` - Read count per sample
- `taxonomy_name` - Scientific name

**`taxpasta_standard.biom`** (if `--taxpasta_format biom`)
- Binary format for metagenomics tools
- Compatible with QIIME2, phyloseq
- Includes taxonomy hierarchy

**Use Cases:**
- Multi-sample comparisons
- Statistical analysis (DESeq2, edgeR)
- Visualization (phyloseq, microbiomeSeq)
- Meta-analysis integration

### BLAST (Validation - Optional)

**Purpose**: Sequence-level validation of specific taxa

**Enabled with:** `--blast_validation --blast_db /path/to/db`

**Key Files:**

**`<sample>_validation.blastn.txt`**
```
Query_id        Subject_id              %identity   length  mismatches  gaps    qstart  qend    sstart  send    evalue      bitscore
read_001        NC_000913.3_E.coli     98.5        1250    18          1       1       1250    450000  451249  0.0         2145
read_002        NC_000913.3_E.coli     97.2        980     27          0       1       980     123000  123979  0.0         1680
```

**Interpretation:**
- **%identity >95%** - Strong species confirmation
- **%identity 90-95%** - Genus-level confirmation
- **%identity <90%** - Distant match, review taxonomy
- **E-value <1e-10** - Statistically significant

### MultiQC (Comprehensive Report)

**Purpose**: Aggregated quality metrics across all samples

**Key File:**

**`multiqc_report.html`**

**Sections:**
1. **General Statistics** - Sample overview table
2. **FASTP** - Quality filtering summary
3. **NanoPlot** - Read length and quality distributions
4. **Kraken2** - Taxonomic composition
5. **Software Versions** - Tool versions used

**Key Metrics to Check:**

| Metric | Good | Warning | Critical |
|--------|------|---------|----------|
| Mean Quality Score | >12 | 10-12 | <10 |
| % Reads Passing Filter | >90% | 80-90% | <80% |
| Classification Rate | >70% | 50-70% | <50% |
| Mean Read Length | >2kb | 1-2kb | <1kb |

## Dorado Basecalling Outputs

### Basecalling Mode

**`dorado/basecalls/<sample>.fastq.gz`**

Standard FASTQ format with quality scores:
```
@read_id runid=abc123 sampleid=sample1 read=123 ch=456 start_time=2024-09-12T14:00:01Z model_version_id=2023-08-01_dna_r10.4.1_e4.3_400bps_hac@v5.0.0
ACGTACGTACGTACGTACGTACGTACGTACGT...
+
!"#$%&'()*+,-./0123456789:;<=>?@AB...
```

**Header Fields:**
- `runid` - Sequencing run identifier
- `sampleid` - Sample name
- `read` - Read number
- `ch` - Channel number
- `start_time` - Sequencing timestamp
- `model_version_id` - Basecalling model used

**`dorado/sequencing_summary.txt`**
```tsv
read_id     channel start_time  duration    num_events  passes_filtering    template_start  template_duration   mean_qscore_template
read_001    456     140001      2.450       12450       TRUE                0.125           2.325               12.8
read_002    789     140003      3.120       15890       TRUE                0.098           3.022               13.2
```

**Key Columns:**
- `mean_qscore_template` - Average quality score (filter with `--min_qscore`)
- `passes_filtering` - Quality filter status
- `duration` - Sequencing duration (seconds)

### Demultiplexing Mode (Barcode Kit Specified)

**Enabled with:** `--barcode_kit SQK-NBD114-24`

**`dorado_demux/barcode01/reads.fastq.gz`**
- Reads assigned to barcode01
- Barcode sequences trimmed if `--trim_barcodes`
- Ready for downstream analysis

**`dorado_demux/barcode02/reads.fastq.gz`**
- Reads assigned to barcode02

**`dorado_demux/unclassified/reads.fastq.gz`**
- Reads without confident barcode assignment
- Review if >20% of total reads
- May indicate barcode issues

**`dorado_demux/demux_summary.txt`**
```tsv
barcode_id      read_count      total_bases     mean_length     mean_qscore
barcode01       45230           135690000       3000            12.8
barcode02       38950           116850000       3000            13.1
barcode03       41200           123600000       3000            12.9
unclassified    16620           49860000        3000            11.5
```

**Expected Results:**
- **Balanced barcode distribution** - Similar read counts per barcode
- **Low unclassified rate** (<10%) - Good barcode quality
- **Similar mean quality** - Consistent sequencing across barcodes

## Real-time Processing Outputs

### Real-time Statistics

**`realtime_stats/snapshots/stats_<timestamp>.json`**

Time-series snapshots captured at each batch interval:

```json
{
  "timestamp": "2025-09-12T14:03:01Z",
  "batch_number": 5,
  "files_processed": 50,
  "total_reads": 710000,
  "total_bases": 2130000000,
  "quality_metrics": {
    "mean_quality": 12.8,
    "mean_length": 3000,
    "n50": 4200
  },
  "classification_summary": {
    "classified_reads": 505000,
    "classification_rate": 71.1,
    "top_taxa": [
      {"taxid": 562, "name": "Escherichia coli", "reads": 185000, "percentage": 26.1},
      {"taxid": 1280, "name": "Staphylococcus aureus", "reads": 120000, "percentage": 16.9}
    ]
  },
  "performance_metrics": {
    "processing_rate": 14200,
    "files_per_minute": 10,
    "avg_batch_duration": 45.2
  }
}
```

**`realtime_stats/cumulative/cumulative_stats.json`**

Aggregated statistics across entire run:

```json
{
  "session_id": "run_20250912_140001",
  "start_time": "2025-09-12T14:00:01Z",
  "last_update": "2025-09-12T15:30:01Z",
  "total_batches": 18,
  "total_files": 180,
  "total_reads": 2556000,
  "total_bases": 7668000000,
  "cumulative_quality": {
    "mean_quality": 12.8,
    "quality_trend": "stable",
    "quality_alerts": []
  },
  "cumulative_classification": {
    "total_classified": 1820000,
    "classification_rate": 71.2,
    "species_detected": 45,
    "dominant_taxa": [
      {"taxid": 562, "name": "Escherichia coli", "reads": 665000, "percentage": 26.0}
    ]
  },
  "session_summary": {
    "avg_processing_rate": 14300,
    "total_runtime_minutes": 90,
    "data_generation_rate": 85200000
  }
}
```

**`realtime_stats/performance/throughput_history.json`**

Processing performance over time:

```json
{
  "measurements": [
    {
      "timestamp": "2025-09-12T14:05:01Z",
      "reads_per_second": 14200,
      "bases_per_second": 42600000,
      "files_processed": 10,
      "batch_duration_seconds": 42.3
    },
    {
      "timestamp": "2025-09-12T14:10:01Z",
      "reads_per_second": 14500,
      "bases_per_second": 43500000,
      "files_processed": 10,
      "batch_duration_seconds": 41.1
    }
  ],
  "performance_summary": {
    "mean_throughput": 14300,
    "peak_throughput": 15800,
    "throughput_stability": 0.92
  }
}
```

### Real-time Reports

**`realtime_reports/realtime_dashboard.html`**

Interactive HTML dashboard with:
- **Live Statistics Panel** - Current batch metrics
- **Taxonomic Composition** - Real-time species detection
- **Quality Trends** - Quality score over time
- **Throughput Graph** - Processing rate visualization
- **Alert Panel** - Quality or performance warnings

**Use Cases:**
- Monitor sequencing quality during run
- Early pathogen detection
- Identify technical issues in real-time
- Decide when to stop sequencing

**`realtime_reports/quality_dashboard.html`**

Quality-focused dashboard:
- Read length distribution over time
- Quality score trends by barcode
- Classification rate evolution
- Data yield projections

## Resource Monitoring Outputs

**Enabled with:** `--enable_performance_logging`

### System Resource Metrics

**`resource_monitoring/system_metrics.json`**

```json
{
  "measurements": [
    {
      "timestamp": "2025-09-12T14:00:01Z",
      "cpu_percent": 45.2,
      "memory_gb_used": 12.8,
      "memory_gb_available": 19.2,
      "disk_io_read_mbps": 450,
      "disk_io_write_mbps": 120
    }
  ],
  "resource_summary": {
    "peak_cpu_usage": 78.5,
    "peak_memory_gb": 15.6,
    "mean_cpu_usage": 52.3,
    "mean_memory_gb": 13.2
  }
}
```

### Process Resource Usage

**`resource_monitoring/process_metrics.json`**

Per-process resource consumption:

```json
{
  "processes": [
    {
      "process_name": "KRAKEN2",
      "task_id": "task_123",
      "sample": "sample1",
      "cpu_hours": 2.5,
      "peak_memory_gb": 12.0,
      "duration_minutes": 15.3,
      "exit_status": 0
    },
    {
      "process_name": "DORADO_BASECALLER",
      "task_id": "task_456",
      "sample": "sample2",
      "cpu_hours": 8.2,
      "peak_memory_gb": 8.5,
      "duration_minutes": 45.7,
      "gpu_utilization": 95.2,
      "exit_status": 0
    }
  ],
  "optimization_recommendations": {
    "kraken2": "Consider increasing CPU allocation for faster processing",
    "dorado": "GPU utilization optimal"
  }
}
```

### Dynamic Resource Allocation

**Enabled with:** `--optimization_profile auto`

**`resource_monitoring/resource_predictions.json`**

ML-based resource predictions:

```json
{
  "input_analysis": {
    "total_input_size_gb": 45.2,
    "estimated_read_count": 2500000,
    "file_count": 180,
    "input_type": "fastq_realtime"
  },
  "resource_predictions": {
    "kraken2": {
      "predicted_cpu": 16,
      "predicted_memory_gb": 14.5,
      "predicted_runtime_minutes": 18.2,
      "confidence": 0.89
    },
    "dorado_basecaller": {
      "predicted_cpu": 8,
      "predicted_memory_gb": 10.2,
      "predicted_runtime_minutes": 52.3,
      "gpu_recommended": true,
      "confidence": 0.92
    }
  },
  "optimization_profile_selected": "high_throughput",
  "safety_factor_applied": 0.8
}
```

## Pipeline Execution Reports

### Nextflow Execution Reports

**`pipeline_info/execution_report_*.html`**

Comprehensive execution summary:
- **Summary** - Pipeline completion status
- **Resources** - CPU/memory usage by process
- **Tasks** - Individual task execution details
- **Timeline** - Process execution visualization

**Key Metrics:**
- Total CPU hours consumed
- Peak memory usage
- Failed/cached/completed tasks
- Execution duration

**`pipeline_info/execution_timeline_*.html`**

Interactive Gantt chart:
- Process execution timeline
- Parallel execution visualization
- Identify bottlenecks

**`pipeline_info/execution_trace_*.txt`**

Detailed task-level metrics:

```tsv
task_id hash    native_id   name        status  exit    submit              duration    realtime    %cpu    peak_rss    peak_vmem   rchar       wchar
1       a1/b2c3 12345       FASTP       COMPLETED   0   2025-09-12 14:00:01 45s         43s         98.2%   2.1 GB      4.2 GB      15.8 GB     12.3 GB
2       d4/e5f6 12346       KRAKEN2     COMPLETED   0   2025-09-12 14:00:46 3m 15s      3m 12s      92.5%   13.8 GB     16.2 GB     45.2 GB     2.1 GB
```

**Columns:**
- `duration` - Wall-clock time
- `realtime` - Actual computation time
- `%cpu` - CPU efficiency (>90% is good)
- `peak_rss` - Maximum memory used
- `rchar/wchar` - I/O operations

**`pipeline_info/params_*.json`**

Complete parameter record for reproducibility:

```json
{
  "input": "samplesheet.csv",
  "outdir": "results",
  "kraken2_db": "/databases/k2_standard",
  "use_dorado": false,
  "realtime_mode": true,
  "batch_size": 10,
  "optimization_profile": "auto",
  "max_cpus": 16,
  "max_memory": "32.GB",
  "pipeline_version": "1.0.0",
  "nextflow_version": "24.10.5"
}
```

## Output Files by Execution Mode

### Mode 1: Standard FASTQ Processing

```
results/
├── fastp/              ✓ Quality filtered reads
├── nanoplot/           ✓ QC visualizations
├── kraken2/            ✓ Taxonomic classification
├── taxpasta/           ✓ Standardized taxonomy
├── multiqc/            ✓ Comprehensive report
└── pipeline_info/      ✓ Execution metadata
```

### Mode 2: Pre-demultiplexed Barcode Directories

```
results/
├── fastp/              ✓ Per-barcode QC
│   ├── barcode01_*.fastp.fastq.gz
│   ├── barcode02_*.fastp.fastq.gz
│   └── unclassified_*.fastp.fastq.gz
├── nanoplot/           ✓ Per-barcode plots
├── kraken2/            ✓ Per-barcode classification
├── taxpasta/           ✓ Combined barcode taxonomy
├── multiqc/            ✓ All barcodes aggregated
└── pipeline_info/      ✓ Execution metadata
```

### Mode 3: Singleplex POD5 Basecalling

```
results/
├── dorado/             ✓ Basecalled reads
│   ├── basecalls/
│   └── sequencing_summary.txt
├── fastp/              ✓ Quality filtering
├── nanoplot/           ✓ QC visualizations
├── kraken2/            ✓ Taxonomic classification
├── multiqc/            ✓ Comprehensive report
└── pipeline_info/      ✓ Execution metadata
```

### Mode 4: Multiplex POD5 with Demultiplexing

```
results/
├── dorado/             ✓ Initial basecalling
├── dorado_demux/       ✓ Barcode separation
│   ├── barcode01/
│   ├── barcode02/
│   ├── unclassified/
│   └── demux_summary.txt
├── fastp/              ✓ Per-barcode QC
├── kraken2/            ✓ Per-barcode classification
├── taxpasta/           ✓ Combined taxonomy
├── multiqc/            ✓ All barcodes + basecalling
└── pipeline_info/      ✓ Execution metadata
```

### Mode 5: Real-time FASTQ Monitoring

```
results/
├── realtime_stats/     ✓ Live statistics
│   ├── snapshots/
│   ├── cumulative/
│   └── performance/
├── realtime_reports/   ✓ Interactive dashboards
│   ├── realtime_dashboard.html
│   └── quality_dashboard.html
├── fastp/              ✓ Batch-processed QC
├── kraken2/            ✓ Batch-processed classification
├── multiqc/            ✓ Comprehensive report
└── pipeline_info/      ✓ Execution metadata
```

### Mode 6: Real-time POD5 Processing

```
results/
├── dorado/             ✓ Real-time basecalling
├── dorado_demux/       ✓ Real-time demultiplexing (if barcoded)
├── realtime_stats/     ✓ Live statistics
├── realtime_reports/   ✓ Interactive dashboards
├── fastp/              ✓ Batch-processed QC
├── kraken2/            ✓ Batch-processed classification
├── multiqc/            ✓ Comprehensive report
└── pipeline_info/      ✓ Execution metadata
```

### Mode 7: Dynamic Resource Optimization

```
results/
├── resource_monitoring/        ✓ Resource metrics
│   ├── system_metrics.json
│   ├── process_metrics.json
│   └── resource_predictions.json
├── [standard outputs based on input type]
└── pipeline_info/              ✓ Enhanced execution metadata
```

## File Format Reference

### FASTQ Format

```
@read_identifier [optional description]
SEQUENCE
+[optional repeated identifier]
QUALITY_SCORES
```

**Quality Score Encoding**: Phred+33 (Sanger format)
- Character `!` = Q0 (lowest quality)
- Character `~` = Q93 (highest quality)
- Minimum acceptable quality typically Q7-Q10 for nanopore

### TSV Format (Tab-separated values)

Used in:
- `NanoStats.txt`
- `sequencing_summary.txt`
- `taxpasta_standard.tsv`
- `demux_summary.txt`

**Parsing:**
```bash
# Extract column 2 from TSV
cut -f2 file.tsv

# Filter rows
awk '$3 > 10' file.tsv

# Convert to CSV
sed 's/\t/,/g' file.tsv > file.csv
```

### JSON Format

Used in:
- Real-time statistics
- Resource monitoring
- FASTP metrics
- Parameter records

**Parsing:**
```bash
# Using jq
jq '.quality_metrics.mean_quality' stats.json

# Extract array elements
jq '.top_taxa[].name' stats.json

# Pretty print
jq '.' stats.json
```

### Kraken2 Report Format

Custom tabular format (space-separated):

```
percentage  clade_reads  taxon_reads  rank  taxid  scientific_name
```

**Parsing:**
```bash
# Extract species-level classifications
awk '$4 == "S"' report.txt

# Get top 10 species by read count
awk '$4 == "S"' report.txt | sort -k3 -nr | head -10

# Calculate total classified reads
awk '$4 != "U" {sum += $3} END {print sum}' report.txt
```

### BIOM Format (if enabled)

Binary format for metagenomics:

**Convert to JSON:**
```bash
biom convert -i taxpasta_standard.biom -o output.json --to-json
```

**Convert to TSV:**
```bash
biom convert -i taxpasta_standard.biom -o output.tsv --to-tsv
```

**Use in R (phyloseq):**
```r
library(phyloseq)
biom_data <- import_biom("taxpasta_standard.biom")
```

## Common Analysis Workflows

### Extract Top Species from Kraken2

```bash
# Top 10 species by read count
for report in results/kraken2/*.report.txt; do
    echo "=== $(basename $report) ==="
    awk '$4 == "S" {printf "%.2f%%\t%d reads\t%s\n", $1, $3, $6}' "$report" | \
    sort -k2 -nr | head -10
done
```

### Calculate Classification Rate

```bash
# Overall classification rate
for report in results/kraken2/*.report.txt; do
    total=$(awk '{sum += $3} END {print sum}' "$report")
    classified=$(awk '$4 != "U" {sum += $3} END {print sum}' "$report")
    rate=$(echo "scale=2; ($classified / $total) * 100" | bc)
    echo "$(basename $report): ${rate}% classified"
done
```

### Monitor Real-time Statistics

```bash
# Watch latest cumulative statistics
watch -n 5 'jq -r ".cumulative_classification.dominant_taxa[0] | \
    \"\(.name): \(.reads) reads (\(.percentage)%)\"" \
    results/realtime_stats/cumulative/cumulative_stats.json'
```

### Extract Quality Metrics

```bash
# Get mean quality from all samples
for json in results/fastp/*.json; do
    mean_q=$(jq -r '.summary.after_filtering.q30_rate' "$json")
    echo "$(basename $json .json): Q30 rate = ${mean_q}"
done
```

### Aggregate Barcode Statistics

```bash
# Summarize demultiplexing results
if [ -f results/dorado_demux/demux_summary.txt ]; then
    echo "Barcode Distribution:"
    awk 'NR>1 {printf "%-15s %10d reads (%d Mb)\n", $1, $2, $3/1000000}' \
        results/dorado_demux/demux_summary.txt
fi
```

## Troubleshooting Output Issues

### No Kraken2 Outputs

**Check:**
1. Was `--kraken2_db` specified?
2. Does database path exist?
3. Check `pipeline_info/execution_trace_*.txt` for errors

```bash
# Verify database
ls -lh /path/to/kraken2_db/
# Should contain: hash.k2d, opts.k2d, taxo.k2d
```

### Empty Real-time Statistics

**Check:**
1. Was `--realtime_mode` enabled?
2. Were files detected in monitored directory?
3. Check batch interval hasn't expired

```bash
# Test file pattern matching
find /monitored/dir -name "*.fastq.gz"
```

### Missing MultiQC Report

**Check:**
1. Were any analysis modules run?
2. Check `multiqc/multiqc_data/multiqc.log`
3. Verify module outputs exist

```bash
# Check for analysis outputs
ls -l results/fastp/
ls -l results/kraken2/
```

### Low Classification Rate (<30%)

**Possible causes:**
1. **Wrong database** - Use appropriate database for sample type
2. **Low quality reads** - Check NanoPlot quality metrics
3. **Novel organisms** - Expected for environmental samples
4. **Host contamination** - Use host genome removal

**Solutions:**
```bash
# Try different database
--kraken2_db /databases/k2_pluspf  # Includes protozoa/fungi

# Increase quality filtering
--fastp_qualified_quality 20
--fastp_length_required 2000
```

## Next Steps

- **Interpret Results**: See [QC Guide](qc_guide.md) for detailed metric interpretation
- **Advanced Analysis**: Downstream statistical analysis with R/Python
- **Share Results**: MultiQC reports are self-contained and portable
- **Troubleshoot Issues**: Check [Usage Guide](usage.md#troubleshooting) for common problems

---

**Need help?** Open an issue: https://github.com/foi-bioinformatics/nanometanf/issues
