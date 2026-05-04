# Quick Start Tutorial

A short walkthrough using example datasets.

## Prerequisites

```bash
# Required
- Nextflow >= 25.10.0
- Conda (recommended), or Docker / Singularity
- Java 11+ (for Nextflow)

# Set up Java environment (if using Conda)
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH
```

## Which Mode Should I Use?

Answer these questions to find the right execution mode:

```
What is your input data?
|
+-- FASTQ files
|   |
|   +-- Already have a samplesheet? --> Scenario 1 (Basic FASTQ)
|   |
|   +-- Pre-demultiplexed barcode folders? --> Use --input_dir
|   |
|   +-- Need real-time analysis during sequencing? --> Scenario 5 (Real-time)
|
+-- POD5 files (raw signal data)
    |
    +-- Single sample (no barcodes)? --> Scenario 2 (POD5 Basecalling)
    |
    +-- Multiple barcoded samples? --> Scenario 3 (Multiplex)
    |
    +-- Need real-time basecalling? --> Scenario 5 with --use_dorado
```

**Quick reference:**

| I have...         | I want...                | Use this                              |
| ----------------- | ------------------------ | ------------------------------------- |
| FASTQ files       | QC reports               | `--input samplesheet.csv`             |
| FASTQ files       | Taxonomic classification | Add `--kraken2_db /path/to/db`        |
| POD5 files        | Basecalling + QC         | `--use_dorado --pod5_input_dir /path` |
| Barcoded POD5     | Demultiplexing           | Add `--barcode_kit SQK-NBD114-24`     |
| Active sequencing | Live results             | Add `--realtime_mode`                 |

---

## Scenario 1: Basic FASTQ Analysis (3 minutes)

**Use case**: You have FASTQ files from nanopore sequencing and want QC reports.

```bash
# 1. Create samplesheet
cat > samplesheet.csv << EOF
sample,fastq,barcode
Sample1,/path/to/sample1.fastq.gz,
Sample2,/path/to/sample2.fastq.gz,BC01
EOF

# 2. Run pipeline
nextflow run foi-bioinformatics/nanometanf \
    --input samplesheet.csv \
    --outdir results \
    -profile conda

# 3. View results
open results/multiqc/multiqc_report.html
```

**Expected outputs**:

- `results/qc/` - NanoPlot QC reports
- `results/multiqc/` - Combined MultiQC report
- `results/pipeline_info/` - Execution reports

---

## Scenario 2: POD5 Basecalling with Dorado (5 minutes)

**Use case**: You have raw POD5 files and need basecalling + QC.

```bash
# 1. Set Dorado path (macOS example)
export DORADO_PATH=/path/to/dorado

# 2. Run basecalling
nextflow run foi-bioinformatics/nanometanf \
    --use_dorado \
    --pod5_input_dir /path/to/pod5/ \
    --dorado_model dna_r10.4.1_e4.3_400bps_hac \
    --min_qscore 9 \
    --trim_adapters \
    --outdir results \
    -profile conda

# 3. Check basecalling summary
cat results/dorado/*/summary.txt
```

**What happens**:

1. Dorado downloads the specified model
2. Basecalls all POD5 files to FASTQ
3. Trims adapters automatically
4. Runs QC on basecalled reads
5. Generates MultiQC report

---

## Scenario 3: Multiplex Demultiplexing (7 minutes)

**Use case**: You have barcoded samples in POD5 files.

```bash
nextflow run foi-bioinformatics/nanometanf \
    --use_dorado \
    --pod5_input_dir /path/to/pod5/ \
    --barcode_kit SQK-NBD114-24 \
    --trim_barcodes \
    --outdir results \
    -profile conda

# Results organized by barcode
ls results/demultiplexing/
# barcode01/ barcode02/ ... unclassified/
```

**Automatic features**:

- Detects barcodes using specified kit
- Demultiplexes into separate FASTQ files
- Trims barcode sequences
- Runs QC on each barcode separately

---

## Scenario 4: Taxonomic Classification (10 minutes)

**Use case**: Metagenomic sample needing species identification.

```bash
# 1. Download Kraken2 database (one-time setup)
wget https://genome-idx.s3.amazonaws.com/kraken/k2_standard_20240904.tar.gz
tar xzf k2_standard_20240904.tar.gz -C kraken2_db/

# 2. Run classification
nextflow run foi-bioinformatics/nanometanf \
    --input samplesheet.csv \
    --kraken2_db kraken2_db/ \
    --enable_krona_plots \
    --outdir results \
    -profile conda

# 3. View taxonomic results
open results/taxonomy/*/krona.html
```

**Outputs**:

- `results/taxonomy/*/kraken2_report.txt` - Text report
- `results/taxonomy/*/krona.html` - Interactive visualization
- Integrated into MultiQC report

---

## Scenario 5: Real-time Monitoring (Advanced)

**Use case**: Live sequencing run, analyze data as it's generated.

```bash
# Start monitoring directory
nextflow run foi-bioinformatics/nanometanf \
    --realtime_mode \
    --nanopore_output_dir /var/nanopore/output \
    --file_pattern "**/*.fastq.gz" \
    --batch_size 10 \
    --batch_interval "5min" \
    --outdir results \
    -profile conda \
    -bg  # Run in background

# Monitor progress
tail -f results/realtime_reports/progress.txt
```

**How it works**:

- Watches directory for new files
- Processes files in batches every 5 minutes
- Generates incremental reports
- Continues until manually stopped

---

## Common Options Reference

```bash
# Input modes (choose one)
--input samplesheet.csv                    # Pre-processed FASTQ
--pod5_input_dir /path/to/pod5/           # POD5 basecalling
--input_dir /path/to/barcodes/            # Pre-demuxed barcodes (auto-detects structure)
--realtime_mode                           # Live monitoring

# Quality control
--skip_fastp              # Skip read filtering
--skip_nanoplot           # Skip QC plots
--min_qscore 9           # Basecalling quality filter

# Adapter/barcode trimming
--trim_adapters          # Trim adapters (default: true)
--trim_barcodes          # Trim barcodes (default: true)

# Analysis options
--kraken2_db /path/db/   # Enable taxonomic classification
--blast_validation       # Enable BLAST validation

# Performance
--enable_dynamic_resources        # Dynamic per-task resource allocation
```

---

## Testing Your Installation

```bash
# Quick test with stub mode (< 1 minute)
nextflow run foi-bioinformatics/nanometanf \
    -profile test,docker \
    -stub \
    --outdir test_results

# Full test with nf-core test data (~ 5 minutes; CI uses docker per nf-core convention)
nextflow run foi-bioinformatics/nanometanf \
    -profile test,docker \
    --outdir test_results
```

---

## Troubleshooting

**Pipeline won't start**:

```bash
# Check Nextflow version
nextflow -version  # Must be >= 25.10.0

# Check Java
java -version      # Must be 11+
```

**Dorado not found**:

```bash
# Set dorado path explicitly
nextflow run ... --dorado_path /full/path/to/dorado
```

**Out of memory**:

```bash
# Reduce resource allocation
nextflow run ... --max_memory 8.GB --max_cpus 4
```

For more troubleshooting, see [Troubleshooting Guide](troubleshooting.md).

---

## Next Steps

- **Full documentation**: See [Usage Guide](../usage.md)
- **QC interpretation**: See [QC Guide](qc_guide.md)
- **Production deployment**: See [Production Deployment](../development/production_deployment.md)
- **Performance tuning**: See [Performance Tuning](performance_tuning.md)
- **Best practices**: See [Best Practices](best_practices.md)
