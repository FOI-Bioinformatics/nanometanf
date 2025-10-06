# Output API Documentation

Integration guide for consuming nanometanf outputs programmatically, specifically designed for Nanometa Live frontend integration.

## Overview

nanometanf produces structured outputs in standardized formats suitable for real-time monitoring, visualization, and downstream analysis. This document describes the output file structure, JSON schemas, and integration patterns.

---

## Output Directory Structure

```
results/
├── pipeline_info/               # Pipeline execution metadata
│   ├── software_versions.yml   # Tool versions (YAML)
│   ├── execution_report.html   # Nextflow execution report
│   ├── execution_trace.txt     # Process execution details
│   └── pipeline_dag.svg        # Workflow diagram
│
├── fastq/                       # Basecalled FASTQ files (if Dorado used)
│   └── {sample_id}.fastq.gz
│
├── qc/                          # Quality control outputs
│   ├── nanoplot/
│   │   ├── {sample_id}/
│   │   │   ├── NanoStats.txt        # Tab-delimited statistics
│   │   │   ├── NanoPlot-report.html # Interactive report
│   │   │   └── *.png                # Quality plots
│   │   └── summary/
│   │       └── nanoplot_summary.json # Aggregated QC metrics (JSON)
│   │
│   ├── fastp/
│   │   ├── {sample_id}.fastp.json   # Per-sample QC (JSON)
│   │   └── {sample_id}.fastp.html   # Interactive report
│   │
│   └── multiqc/
│       ├── multiqc_report.html      # Aggregated report
│       └── multiqc_data/
│           ├── multiqc_data.json    # Machine-readable summary (JSON)
│           └── multiqc_sources.txt  # Data provenance
│
├── taxonomy/                    # Taxonomic classification (if Kraken2 enabled)
│   ├── {sample_id}.kraken2.txt     # Raw Kraken2 output
│   ├── {sample_id}.kraken2_report.txt # Kraken2 report format
│   └── krona/
│       └── {sample_id}_krona.html  # Interactive Krona chart
│
├── validation/                  # BLAST validation (if enabled)
│   └── {sample_id}_blast.txt       # BLAST results
│
└── realtime/                    # Real-time monitoring outputs (if enabled)
    ├── batch_stats/
    │   ├── batch_{timestamp}.json   # Per-batch processing statistics
    │   └── cumulative_stats.json    # Cumulative statistics
    │
    ├── resource_metrics/
    │   ├── resource_predictions.json # Dynamic resource predictions
    │   └── system_metrics.json       # System resource usage
    │
    └── monitoring/
        ├── file_discovery.log       # File detection log
        ├── processing_queue.json    # Current processing queue
        └── error_reports.json       # Error tracking
```

---

## JSON Schemas

### 1. MultiQC Data (`multiqc_data.json`)

**Location**: `results/qc/multiqc/multiqc_data/multiqc_data.json`

**Schema**:
```json
{
  "report_general_stats_data": [
    {
      "sample": "sample_id",
      "percent_duplicates": 12.3,
      "median_read_length": 1523.0,
      "mean_quality": 12.5,
      "total_reads": 125000,
      "total_bases": 156000000
    }
  ],
  "report_plot_data": {
    "nanoplot-read-lengths": {
      "sample_id": {
        "x": [100, 200, ...],  // Read length bins
        "y": [50, 120, ...]    // Read counts
      }
    },
    "nanoplot-quality-scores": {
      "sample_id": {
        "x": [5, 6, 7, ...],   // Quality score bins
        "y": [10, 50, ...]     // Read counts
      }
    }
  }
}
```

**Usage Example**:
```python
import json

# Load MultiQC data
with open('results/qc/multiqc/multiqc_data/multiqc_data.json') as f:
    mqc_data = json.load(f)

# Extract general statistics
for sample in mqc_data['report_general_stats_data']:
    print(f"{sample['sample']}: {sample['total_reads']} reads, "
          f"N50={sample.get('median_read_length', 'N/A')} bp")

# Extract quality distribution for plotting
quality_plot = mqc_data['report_plot_data']['nanoplot-quality-scores']
for sample_id, data in quality_plot.items():
    # data['x'] = quality bins, data['y'] = counts
    plot_quality_histogram(sample_id, data['x'], data['y'])
```

---

### 2. FASTP JSON (`{sample_id}.fastp.json`)

**Location**: `results/qc/fastp/{sample_id}.fastp.json`

**Schema**:
```json
{
  "summary": {
    "before_filtering": {
      "total_reads": 100000,
      "total_bases": 150000000,
      "q20_bases": 140000000,
      "q30_bases": 120000000,
      "gc_content": 0.45
    },
    "after_filtering": {
      "total_reads": 95000,
      "total_bases": 145000000,
      "q20_bases": 140000000,
      "q30_bases": 120000000,
      "gc_content": 0.46
    }
  },
  "filtering_result": {
    "passed_filter_reads": 95000,
    "low_quality_reads": 3000,
    "too_short_reads": 2000
  },
  "adapter_cutting": {
    "adapter_trimmed_reads": 5000,
    "adapter_trimmed_bases": 125000
  }
}
```

**Usage Example**:
```python
import json

def get_fastp_metrics(sample_id, results_dir="results"):
    fastp_path = f"{results_dir}/qc/fastp/{sample_id}.fastp.json"

    with open(fastp_path) as f:
        data = json.load(f)

    return {
        'total_reads': data['summary']['after_filtering']['total_reads'],
        'total_bases': data['summary']['after_filtering']['total_bases'],
        'q20_rate': data['summary']['after_filtering']['q20_bases'] /
                    data['summary']['after_filtering']['total_bases'],
        'pass_rate': data['filtering_result']['passed_filter_reads'] /
                     data['summary']['before_filtering']['total_reads']
    }
```

---

### 3. NanoStats (`NanoStats.txt`)

**Location**: `results/qc/nanoplot/{sample_id}/NanoStats.txt`

**Format**: Tab-delimited key-value pairs

```
Mean read length:	1523.5
Mean read quality:	12.3
Median read length:	1450.0
Median read quality:	12.5
Number of reads:	125000
Read length N50:	2100
Total bases:	190437500
Number, percentage and megabases of reads above quality cutoffs
>Q5:	125000 (100.0%) 190.4Mb
>Q7:	120000 (96.0%) 182.9Mb
>Q10:	95000 (76.0%) 144.8Mb
>Q12:	50000 (40.0%) 76.2Mb
>Q15:	5000 (4.0%) 7.6Mb
Top 5 highest mean basecall quality scores and their read lengths
1:	15.2 (4521bp)
2:	14.8 (3892bp)
```

**Parsing Example**:
```python
def parse_nanostats(filepath):
    """Parse NanoStats.txt into a dictionary."""
    stats = {}

    with open(filepath) as f:
        for line in f:
            if ':' in line and not line.startswith('>Q'):
                key, value = line.strip().split(':', 1)
                # Try to convert to float, fallback to string
                try:
                    stats[key.strip()] = float(value.strip())
                except ValueError:
                    stats[key.strip()] = value.strip()

    return stats

# Usage
nanostats = parse_nanostats('results/qc/nanoplot/sample001/NanoStats.txt')
print(f"N50: {nanostats['Read length N50']}")
print(f"Mean quality: {nanostats['Mean read quality']}")
```

---

### 4. Kraken2 Report (`{sample_id}.kraken2_report.txt`)

**Location**: `results/taxonomy/{sample_id}.kraken2_report.txt`

**Format**: Tab-delimited

```
 70.50  141000  141000  U       0       unclassified
 29.50   59000       0  R       1       root
 29.00   58000      12  R1      131567    cellular organisms
 28.50   57000      25  D       2           Bacteria
 15.30   30600     150  P       1224          Pseudomonadota
 12.20   24400      89  C       28211           Alphaproteobacteria
  8.50   17000     500  O       204455            Rhizobiales
  5.30   10600      45  F       41294               Bradyrhizobiaceae
```

**Columns**:
1. Percentage of reads
2. Number of reads at this taxon
3. Number of reads assigned directly to this taxon
4. Rank code (U=unclassified, R=root, D=domain, P=phylum, C=class, O=order, F=family, G=genus, S=species)
5. NCBI taxonomy ID
6. Scientific name (indented by rank)

**Parsing Example**:
```python
def parse_kraken2_report(filepath, min_reads=100):
    """Parse Kraken2 report and return top taxa."""
    taxa = []

    with open(filepath) as f:
        for line in f:
            parts = line.strip().split('\t')
            percent = float(parts[0])
            reads = int(parts[1])
            rank = parts[3]
            taxid = parts[4]
            name = parts[5].strip()

            if reads >= min_reads and rank in ['S', 'G']:  # Species or genus
                taxa.append({
                    'name': name,
                    'taxid': taxid,
                    'reads': reads,
                    'percent': percent,
                    'rank': rank
                })

    return sorted(taxa, key=lambda x: x['reads'], reverse=True)

# Usage
top_species = parse_kraken2_report('results/taxonomy/sample001.kraken2_report.txt')
for taxon in top_species[:10]:  # Top 10
    print(f"{taxon['name']}: {taxon['percent']:.1f}% ({taxon['reads']} reads)")
```

---

### 5. Real-time Batch Statistics (`batch_{timestamp}.json`)

**Location**: `results/realtime/batch_stats/batch_{timestamp}.json`

**Schema**:
```json
{
  "batch_id": "batch_20250106_143025",
  "timestamp": "2025-01-06T14:30:25Z",
  "files_processed": 10,
  "total_reads": 125000,
  "total_bases": 156000000,
  "processing_time_seconds": 45.2,
  "samples": [
    {
      "sample_id": "sample001",
      "barcode": "BC01",
      "reads": 12500,
      "bases": 15600000,
      "mean_quality": 12.3,
      "n50": 1523
    }
  ],
  "errors": []
}
```

**Usage Example**:
```python
import json
from pathlib import Path
from datetime import datetime

def get_latest_batch_stats(results_dir="results"):
    """Get the most recent batch statistics."""
    batch_dir = Path(results_dir) / "realtime" / "batch_stats"

    # Find most recent batch file
    batch_files = sorted(batch_dir.glob("batch_*.json"))
    if not batch_files:
        return None

    with open(batch_files[-1]) as f:
        return json.load(f)

# Usage
latest = get_latest_batch_stats()
if latest:
    print(f"Latest batch: {latest['batch_id']}")
    print(f"Files processed: {latest['files_processed']}")
    print(f"Total reads: {latest['total_reads']:,}")
```

---

### 6. Cumulative Statistics (`cumulative_stats.json`)

**Location**: `results/realtime/batch_stats/cumulative_stats.json`

**Schema**:
```json
{
  "pipeline_start": "2025-01-06T12:00:00Z",
  "last_updated": "2025-01-06T14:30:25Z",
  "total_batches": 25,
  "total_files": 250,
  "total_reads": 3125000,
  "total_bases": 3906250000,
  "samples": {
    "sample001": {
      "reads": 125000,
      "bases": 156250000,
      "batches": 10,
      "mean_quality": 12.3,
      "n50": 1523
    }
  },
  "quality_distribution": {
    "Q5": 3125000,
    "Q7": 3000000,
    "Q10": 2500000,
    "Q12": 1250000,
    "Q15": 312500
  }
}
```

**Usage Example**:
```python
import json

def monitor_cumulative_progress(results_dir="results"):
    """Monitor cumulative pipeline progress."""
    stats_path = f"{results_dir}/realtime/batch_stats/cumulative_stats.json"

    with open(stats_path) as f:
        stats = json.load(f)

    # Calculate aggregated metrics
    total_samples = len(stats['samples'])
    avg_quality = sum(s['mean_quality'] for s in stats['samples'].values()) / total_samples

    return {
        'total_reads': stats['total_reads'],
        'total_samples': total_samples,
        'avg_quality': avg_quality,
        'q10_pass_rate': stats['quality_distribution']['Q10'] / stats['total_reads']
    }
```

---

## Integration Patterns

### Pattern 1: Real-time Dashboard Integration

**Polling Strategy**:
```python
import time
from pathlib import Path

class NanometanfMonitor:
    def __init__(self, results_dir="results"):
        self.results_dir = Path(results_dir)
        self.last_batch = None

    def poll_new_batches(self, callback, interval=5):
        """Poll for new batch statistics and trigger callback."""
        batch_dir = self.results_dir / "realtime" / "batch_stats"

        while True:
            batches = sorted(batch_dir.glob("batch_*.json"))

            if batches and batches[-1] != self.last_batch:
                with open(batches[-1]) as f:
                    batch_data = json.load(f)

                callback(batch_data)  # Trigger dashboard update
                self.last_batch = batches[-1]

            time.sleep(interval)

# Usage
def update_dashboard(batch_data):
    print(f"New batch: {batch_data['batch_id']}")
    print(f"Reads: {batch_data['total_reads']}")
    # Update Nanometa Live UI

monitor = NanometanfMonitor()
monitor.poll_new_batches(update_dashboard, interval=5)
```

---

### Pattern 2: File System Watcher

**Using `watchdog` for real-time updates**:
```python
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import json

class BatchStatsHandler(FileSystemEventHandler):
    def on_created(self, event):
        if event.src_path.endswith('.json') and 'batch_' in event.src_path:
            with open(event.src_path) as f:
                batch_data = json.load(f)

            # Process new batch
            self.process_batch(batch_data)

    def process_batch(self, data):
        print(f"Processing batch: {data['batch_id']}")
        # Update database, send notifications, etc.

# Setup watcher
observer = Observer()
handler = BatchStatsHandler()
observer.schedule(handler, "results/realtime/batch_stats", recursive=False)
observer.start()
```

---

### Pattern 3: RESTful API Wrapper

**Flask API for Nanometa Live**:
```python
from flask import Flask, jsonify
from pathlib import Path
import json

app = Flask(__name__)
RESULTS_DIR = Path("results")

@app.route('/api/status')
def get_status():
    """Get current pipeline status."""
    stats_path = RESULTS_DIR / "realtime/batch_stats/cumulative_stats.json"

    if not stats_path.exists():
        return jsonify({"status": "not_started"}), 404

    with open(stats_path) as f:
        stats = json.load(f)

    return jsonify({
        "status": "running",
        "total_reads": stats['total_reads'],
        "total_samples": len(stats['samples']),
        "last_updated": stats['last_updated']
    })

@app.route('/api/samples')
def get_samples():
    """Get all sample statistics."""
    stats_path = RESULTS_DIR / "realtime/batch_stats/cumulative_stats.json"

    with open(stats_path) as f:
        stats = json.load(f)

    return jsonify(stats['samples'])

@app.route('/api/taxonomy/<sample_id>')
def get_taxonomy(sample_id):
    """Get taxonomic classification for a sample."""
    kraken_report = RESULTS_DIR / "taxonomy" / f"{sample_id}.kraken2_report.txt"

    if not kraken_report.exists():
        return jsonify({"error": "Taxonomy data not available"}), 404

    taxa = parse_kraken2_report(kraken_report, min_reads=100)
    return jsonify(taxa)

if __name__ == '__main__':
    app.run(debug=True, port=5000)
```

---

## Error Handling

### Error Report Format

**Location**: `results/realtime/monitoring/error_reports.json`

**Schema**:
```json
{
  "errors": [
    {
      "timestamp": "2025-01-06T14:30:25Z",
      "sample_id": "sample001",
      "error_type": "BASECALLING_FAILED",
      "error_message": "Dorado basecalling failed: GPU out of memory",
      "severity": "ERROR",
      "retry_count": 0,
      "resolved": false
    }
  ]
}
```

**Monitoring Example**:
```python
def check_errors(results_dir="results"):
    """Check for unresolved errors."""
    error_path = Path(results_dir) / "realtime/monitoring/error_reports.json"

    if not error_path.exists():
        return []

    with open(error_path) as f:
        data = json.load(f)

    # Filter unresolved errors
    unresolved = [e for e in data['errors'] if not e['resolved']]

    return unresolved
```

---

## Best Practices

### 1. Polling Frequency
- **Development**: 1-2 seconds for testing
- **Production**: 5-10 seconds for real-time monitoring
- **Archive analysis**: Check completion status every 30-60 seconds

### 2. Data Validation
Always validate JSON structure before processing:
```python
from jsonschema import validate, ValidationError

def safe_load_stats(filepath, schema):
    """Safely load and validate JSON data."""
    try:
        with open(filepath) as f:
            data = json.load(f)
        validate(instance=data, schema=schema)
        return data
    except (json.JSONDecodeError, ValidationError) as e:
        logging.error(f"Invalid data in {filepath}: {e}")
        return None
```

### 3. Performance Optimization
- Cache frequently accessed files (e.g., cumulative_stats.json)
- Use file modification timestamps to detect changes
- Implement exponential backoff for failed reads
- Process batch files asynchronously

### 4. Error Resilience
```python
def resilient_file_read(filepath, max_retries=3):
    """Read file with retry logic for incomplete writes."""
    import time

    for attempt in range(max_retries):
        try:
            with open(filepath) as f:
                return json.load(f)
        except json.JSONDecodeError:
            if attempt < max_retries - 1:
                time.sleep(0.5)  # Wait for complete write
            else:
                raise
```

---

## Schema Updates

This API is versioned and follows semantic versioning. Breaking changes to JSON schemas will increment the major version.

**Current API Version**: 1.1.0

**Changelog**:
- **v1.1.0**: Added real-time monitoring JSON outputs
- **v1.0.0**: Initial stable release

---

## Support

For integration issues or feature requests, please open an issue at:
https://github.com/foi-bioinformatics/nanometanf/issues

For quick integration questions, see:
- [Quick Start Guide](../user/quickstart.md)
- [Best Practices](../user/best_practices.md)
- [Developer API](../development/developer_api.md)
