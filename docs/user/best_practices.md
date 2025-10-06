# Best Practices

Production-tested recommendations for running nanometanf reliably and efficiently.

## Data Organization

### Samplesheet Best Practices

**DO**:
```csv
sample,fastq,barcode
Sample001_Treatment_Rep1,/data/nanopore/sample001.fastq.gz,BC01
Sample002_Treatment_Rep2,/data/nanopore/sample002.fastq.gz,BC02
Sample003_Control_Rep1,/data/nanopore/sample003.fastq.gz,BC03
```
- ✅ Use absolute paths
- ✅ Descriptive sample names
- ✅ Consistent naming scheme
- ✅ Include replicates/conditions in names

**DON'T**:
```csv
sample,fastq,barcode
s1,../data/file.fq,
sample 2,file2.fastq.gz,
```
- ❌ Relative paths
- ❌ Spaces in names
- ❌ Inconsistent naming
- ❌ Ambiguous identifiers

---

### Directory Structure

**Recommended layout**:
```
project/
├── raw_data/
│   ├── pod5/              # Raw POD5 files
│   └── fastq/             # Pre-basecalled FASTQ
├── databases/
│   ├── kraken2/           # Taxonomic databases
│   └── blast/             # Validation databases
├── samplesheets/
│   ├── batch1.csv
│   └── batch2.csv
├── scripts/
│   └── run_pipeline.sh
└── results/
    ├── batch1/
    └── batch2/
```

---

## Workflow Design

### Input Type Selection

**Choose the right input mode**:

| Input Mode | Use When | Pros | Cons |
|------------|----------|------|------|
| `--input samplesheet.csv` | Standard FASTQ analysis | Fast, flexible | Manual samplesheet |
| `--pod5_input_dir` | Raw POD5 basecalling | Full control over models | Slower (basecalling) |
| `--barcode_input_dir` | Pre-demuxed folders | Auto-discovery | Requires standard structure |
| `--realtime_mode` | Live sequencing | Real-time results | Complex setup |

**Example decision tree**:
```
Do you have POD5 files?
├─ Yes → Use --use_dorado --pod5_input_dir
│   └─ Are they barcoded?
│       ├─ Yes → Add --barcode_kit
│       └─ No → Singleplex mode
└─ No → Have FASTQ files?
    ├─ Yes → Use --input samplesheet.csv
    └─ No → Check input type
```

---

## Quality Control

### QC Thresholds

**Recommended filters**:
```bash
# Basecalling
nextflow run ... \
    --min_qscore 9              # ONT recommendation: Q9+

# Read filtering (FASTP)
nextflow run ... \
    -c <(cat << 'EOF'
process {
    withName:FASTP {
        ext.args = '--length_required 500 --qualified_quality_phred 9'
    }
}
EOF
)
```

**Quality flags to monitor**:
- Mean Q-score < 9 → Check basecalling settings
- N50 < 1kb (genomics) → Fragmented DNA
- <50% pass filter → Sample quality issues

---

### QC Report Review

**Red flags in MultiQC**:
1. **Bimodal quality distribution** → Mixed sample quality
2. **Low N50 + high read count** → Excessive fragmentation
3. **Unclassified rate > 90%** → Wrong database or contamination
4. **Adapter content > 10%** → Trimming not working

**Action items**:
```bash
# If quality issues detected
1. Check NanoPlot report for sample-specific issues
2. Review basecalling settings if POD5 input
3. Verify adapter trimming enabled (--trim_adapters)
4. Consider stricter filters if needed
```

---

## Resource Management

### Memory Planning

**Calculate required memory**:
```
Total Memory = (
    Kraken2_DB_size × 1.2 +
    Dorado_GPU_RAM +
    Nextflow_overhead (2-4GB) +
    Safety_margin (20%)
)
```

**Example** (50GB Kraken2 DB + A100 GPU):
```
= (50GB × 1.2) + 80GB + 4GB + 10GB safety
= 154GB total system RAM recommended
```

---

### Disk Space Planning

**Storage requirements** (per 1M reads):
```
Raw POD5:     ~15-20GB
FASTQ (gzip): ~2-5GB
Work files:   ~10-15GB (cleaned after)
Results:      ~500MB-1GB
```

**Best practices**:
```bash
# Use separate disks
-w /fast/local/work     # Fast disk for temporary files
--outdir /archive/results  # Archive storage for results

# Auto-cleanup work directory
nextflow run ... -resume
# After successful completion:
nextflow clean -after <run-name> -f
```

---

## Database Management

### Kraken2 Database Selection

**By use case**:
| Use Case | Database | Size | Accuracy |
|----------|----------|------|----------|
| Bacteria ID | Standard-8 | 8GB | 95% |
| Viral detection | Viral | 500MB | 99% (viruses) |
| Metagenomics | PlusPF | 75GB | 99% |
| Quick screening | MiniKraken | 8GB | 85% |
| Custom species | Custom build | Varies | Optimal |

**Downloading**:
```bash
# Standard database (recommended)
wget https://genome-idx.s3.amazonaws.com/kraken/k2_standard_20240904.tar.gz
mkdir kraken2_db
tar xzf k2_standard_20240904.tar.gz -C kraken2_db/

# Verify integrity
kraken2-inspect --db kraken2_db/ | head
```

**Optimization**:
```bash
# Preload to RAM disk (if sufficient RAM)
mkdir /dev/shm/kraken2_db
cp -r /path/to/kraken2_db/* /dev/shm/kraken2_db/
nextflow run ... --kraken2_db /dev/shm/kraken2_db/
```

---

## Reproducibility

### Version Control

**Always specify versions**:
```bash
# Pipeline version
nextflow run foi-bioinformatics/nanometanf \
    -r v1.0.0 \    # Specific release
    ...

# Container versions
-profile docker  # Uses pinned container versions

# Save full configuration
nextflow run ... -with-trace -with-report
```

**Document environment**:
```bash
# Save software versions
nextflow run ... -with-report report.html

# Report includes:
# - Nextflow version
# - Pipeline version
# - Container versions
# - All parameters used
```

---

### Parameter Files

**Create reusable parameter files**:
```yaml
# params.yaml
input: /data/samplesheet.csv
outdir: /results
kraken2_db: /databases/kraken2
optimization_profile: balanced
enable_dynamic_resources: true
```

**Use with**:
```bash
nextflow run ... -params-file params.yaml
```

---

## Production Workflows

### Standard Production Pipeline

**Template script**:
```bash
#!/bin/bash
# production_pipeline.sh

set -euo pipefail  # Exit on error

# Environment
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH
export NXF_OPTS='-Xms2g -Xmx8g'

# Validate inputs
if [ ! -f "$SAMPLESHEET" ]; then
    echo "Error: Samplesheet not found: $SAMPLESHEET"
    exit 1
fi

# Run pipeline
nextflow run foi-bioinformatics/nanometanf \
    -r v1.0.0 \
    --input "$SAMPLESHEET" \
    --outdir "$OUTDIR" \
    --kraken2_db "$DB_PATH" \
    \
    --enable_dynamic_resources \
    --optimization_profile balanced \
    \
    -profile docker \
    -w "$WORK_DIR" \
    \
    -with-report "$OUTDIR/report.html" \
    -with-timeline "$OUTDIR/timeline.html" \
    -with-trace "$OUTDIR/trace.txt" \
    \
    -resume \
    \
    --email "$ADMIN_EMAIL" \
    --email_on_fail "$ADMIN_EMAIL"

# Cleanup on success
if [ $? -eq 0 ]; then
    nextflow clean -after $(nextflow log -f name | tail -1) -f
    echo "Pipeline completed successfully"
else
    echo "Pipeline failed - check logs"
    exit 1
fi
```

---

### Batch Processing

**Process multiple batches efficiently**:
```bash
# Process in parallel (if resources available)
for batch in batch1 batch2 batch3; do
    nextflow run ... \
        --input samples/${batch}.csv \
        --outdir results/${batch} \
        -w work/${batch} \
        -bg  # Background execution
done

# Monitor all jobs
watch 'ps aux | grep nextflow'
```

**Sequential processing** (resource-constrained):
```bash
for batch in batch1 batch2 batch3; do
    nextflow run ... \
        --input samples/${batch}.csv \
        --outdir results/${batch} \
        -w work  # Shared work dir
        -resume  # Reuse cached results

    # Cleanup between batches
    nextflow clean -f -k
done
```

---

## Error Handling

### Resume Strategy

**Always use `-resume`**:
```bash
# Initial run
nextflow run ... -resume

# If it fails, just run again
nextflow run ... -resume  # Picks up where it left off
```

**When NOT to use resume**:
- Changed input files
- Changed parameters (except --outdir)
- Updated pipeline version

---

### Monitoring & Alerts

**Email notifications**:
```bash
nextflow run ... \
    --email user@institution.org \
    --email_on_fail admin@institution.org
```

**Custom monitoring**:
```bash
# Monitor progress file
tail -f results/pipeline_info/execution_trace.txt

# Check for errors
grep -i error .nextflow.log

# Monitor resource usage
nextflow run ... -with-trace
# Then: grep "process_name" trace.txt
```

---

## Security & Data Handling

### Sensitive Data

**DO**:
- Use encrypted storage for patient data
- Limit file permissions (`chmod 600`)
- Use secure transfer (scp, sftp, not HTTP)
- Clean temporary files after completion

**DON'T**:
- Store credentials in config files
- Use world-readable permissions
- Leave data in shared /tmp directories
- Include PHI in sample names

---

### Data Retention

**Recommended policy**:
```
Raw data (POD5):    Archive, 7+ years
FASTQ:              Archive, 3-5 years
Work directory:     Delete after validation
Results:            Archive, 5+ years
QC reports:         Archive, 10+ years
```

**Archival checklist**:
```bash
# Before archiving
✓ Verify all expected outputs present
✓ Check QC reports for issues
✓ Save execution reports (trace, timeline)
✓ Document pipeline version and parameters
✓ Compress large files (gzip, tar)
✓ Calculate checksums (md5sum)
```

---

## Testing Strategy

### Pre-Production Validation

**Test progression**:
```bash
# 1. Stub test (30 seconds)
nextflow run ... -profile test,docker -stub

# 2. Small test dataset (5 minutes)
nextflow run ... -profile test,docker

# 3. Representative sample (30 minutes)
nextflow run ... --input test_samples.csv -profile docker

# 4. Full production run
nextflow run ... --input production_samples.csv -profile docker
```

### Continuous Validation

**After pipeline updates**:
```bash
# Run test suite
nf-test test --verbose

# Run performance benchmarks
python bin/performance_regression_tester.py run --test-suite production

# Compare with baseline
python bin/performance_regression_tester.py compare \
    --baseline baseline.json \
    --current current.json
```

---

## Documentation Practices

### Per-Run Documentation

**Required documentation**:
```
results/
└── pipeline_info/
    ├── execution_report.html    # Nextflow report
    ├── execution_trace.txt      # Process details
    ├── parameters.json          # All parameters
    └── README.txt              # Custom notes
```

**README template**:
```
Project: [Project Name]
Date: [YYYY-MM-DD]
Operator: [Name]
Pipeline Version: v1.0.0

Samples: 96
Purpose: Metagenomic profiling of...

Parameters:
- Kraken2 DB: Standard (50GB)
- Min Q-score: 9
- Optimization: balanced

Notes:
- Samples collected on [date]
- Special processing: [any deviations]
- Issues encountered: [if any]

Contact: [email]
```

---

## Additional Resources

- [Quick Start Guide](quickstart.md) - Get started quickly
- [Troubleshooting](troubleshooting.md) - Solve common issues
- [Performance Tuning](performance_tuning.md) - Optimize for scale
- [QC Guide](qc_guide.md) - Interpret quality metrics
- [Production Deployment](../development/production_deployment.md) - Enterprise setup
