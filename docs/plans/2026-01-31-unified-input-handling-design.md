# Unified Input Handling and Timeout-Based Batching

**Date:** 2026-01-31
**Status:** Proposed
**Scope:** Real-time monitoring, scan mode, input detection, batching

---

## Problem

The pipeline has several input handling gaps:

1. **Real-time FASTQ monitoring does not support barcode subdirectories.** The default
   file pattern `*.fastq{,.gz}` is non-recursive, so files in `barcode01/`, `barcode02/`
   are not detected. The POD5 monitor uses `**/*.pod5` (recursive) but FASTQ does not.

2. **No custom sample grouping.** Files with custom prefixes (e.g., `sampleA_001.fastq`,
   `sampleB_001.fastq`) cannot be grouped by sample in real-time mode.

3. **Batch flushing is count-only.** `collate(batch_size)` blocks until N files
   accumulate. During slow sequencing periods, partial batches sit indefinitely.

4. **Fragmented input paths.** Separate parameters (`--barcode_input_dir`,
   `--nanopore_output_dir`, `--input`) handle overlapping scenarios with different
   code paths.

## Design

### 1. Auto-Detection of Folder Structure

A shared utility (`lib/InputDetector.groovy`) detects folder structure and extracts
sample IDs. Used by both real-time and scan modes.

**Detection priority:**

1. If input directory contains `barcode*/` subdirectories with target files -->
   multiplexed, subdirectory-based grouping
2. If `--sample_regex` is provided --> apply regex to filename, use first capture group
3. If filename contains `barcodeNN` --> use BarcodeUtils (existing)
4. Otherwise --> single sample (use `--sample_name` or directory name)

```groovy
class InputDetector {
    static String detectStructure(Path dir, List extensions) {
        def barcodeDirs = dir.listFiles()?.findAll {
            it.isDirectory() && it.name =~ /^barcode\d+$/
        }
        if (barcodeDirs?.any { hasTargetFiles(it, extensions) }) {
            return 'barcode_subdirs'
        }
        return 'flat'
    }

    static String extractSampleId(Path file, String sampleRegex, String sampleName) {
        if (file.parent.name =~ /^barcode\d+$/) return file.parent.name
        if (sampleRegex) {
            def m = file.name =~ sampleRegex
            if (m.find()) return m.group(1)
        }
        def barcode = BarcodeUtils.extractBarcodeFromFilename(file.baseName)
        if (barcode) return barcode
        return sampleName ?: file.baseName
    }
}
```

### 2. Timeout-Based Batch Flushing

Replace `collate(batch_size)` in the real-time monitor with a custom Groovy operator
that emits a batch when either the count threshold or a timeout is reached.

**Parameters:**

- `--batch_size` (default: 10) -- existing, emit when N files accumulate
- `--batch_timeout` (default: 60) -- new, emit partial batch after N seconds of inactivity

**Implementation** in `lib/BatchUtils.groovy`:

```groovy
import java.util.concurrent.*

class BatchUtils {
    static def batchWithTimeout(ch_input, int batchSize, int timeoutSeconds) {
        def output = Channel.create()
        def buffer = Collections.synchronizedList([])
        def scheduler = Executors.newSingleThreadScheduledExecutor()
        def flushTask = null

        def flush = {
            synchronized(buffer) {
                if (buffer.size() > 0) {
                    output.bind(new ArrayList(buffer))
                    buffer.clear()
                }
            }
        }

        def resetTimer = {
            flushTask?.cancel(false)
            flushTask = scheduler.schedule(
                flush, timeoutSeconds, TimeUnit.SECONDS
            )
        }

        ch_input.subscribe(
            onNext: { item ->
                synchronized(buffer) {
                    buffer.add(item)
                    if (buffer.size() >= batchSize) {
                        flush()
                    } else {
                        resetTimer()
                    }
                }
            },
            onComplete: {
                flush()
                scheduler.shutdown()
                output.bind(Channel.STOP)
            }
        )
        return output
    }
}
```

### 3. Unified Scan Mode (INPUT_SCANNER)

New subworkflow `subworkflows/local/input_scanner/main.nf` replaces `BARCODE_DISCOVERY`
for directory-based input.

```
INPUT_SCANNER(input_dir, sample_regex)
  |
  +--> detect structure (InputDetector)
  |
  +--> branch:
  |     barcode_subdirs   --> scan barcode*/ dirs, one sample per dir
  |     regex_grouped     --> scan flat dir, group by regex capture
  |     barcode_filenames --> scan flat dir, group by BarcodeUtils
  |     single_sample     --> all files = one sample
  |
  +--> emit: ch_samples [meta, [fastq_files]]
```

**Parameter changes:**

- New `--input_dir` -- unified scan mode entry point
- `--barcode_input_dir` becomes alias for `--input_dir` (deprecation warning)
- New `--sample_regex` -- optional, regex with capture group for sample ID extraction

### 4. Updated Real-Time Monitoring

Changes to `subworkflows/local/realtime_monitoring/main.nf`:

- Default `file_pattern` changes to `**/*.fastq{,.gz}` (recursive)
- Replace `collate(batch_size)` with `BatchUtils.batchWithTimeout()`
- Sample ID extraction uses `InputDetector.extractSampleId()`
- Per-sample grouping in the mapping step before downstream processing

### 5. Input Mode Detection

Updated decision tree in `workflows/nanometanf.nf`:

```
1. POD5 mode (--use_dorado && --pod5_input_dir)
   +-- realtime_mode --> REALTIME_POD5_MONITORING
   +-- static        --> INPUT_SCANNER --> DORADO_BASECALLING

2. FASTQ mode
   +-- realtime_mode --> REALTIME_MONITORING (batchWithTimeout, InputDetector)
   +-- --input_dir   --> INPUT_SCANNER (unified scan)
   +-- --input CSV   --> samplesheet parsing (unchanged)
```

### 6. Backward Compatibility

- `--barcode_input_dir` --> alias for `--input_dir`, emits deprecation warning
- `--nanopore_output_dir` --> unchanged (watch mode)
- `--file_pattern` --> still overridable, default now recursive
- `--input` CSV --> unchanged
- All downstream subworkflows unchanged

## New Parameters

| Parameter         | Default | Description                                                     |
| ----------------- | ------- | --------------------------------------------------------------- |
| `--input_dir`     | null    | Directory to scan for FASTQ/POD5 files (auto-detects structure) |
| `--sample_regex`  | null    | Regex with capture group to extract sample ID from filename     |
| `--batch_timeout` | 60      | Seconds before emitting partial batch in real-time mode         |

## New Files

| File                                       | Purpose                                                    |
| ------------------------------------------ | ---------------------------------------------------------- |
| `lib/InputDetector.groovy`                 | Shared folder structure detection and sample ID extraction |
| `lib/BatchUtils.groovy`                    | Timeout-based batch flushing operator                      |
| `subworkflows/local/input_scanner/main.nf` | Unified scan mode subworkflow                              |
| `tests/fixtures/minknow_output/`           | Barcode subdirectory test fixture                          |
| `tests/fixtures/flat_multisample/`         | Flat multi-sample test fixture                             |

## Modified Files

| File                                             | Change                                                  |
| ------------------------------------------------ | ------------------------------------------------------- |
| `subworkflows/local/realtime_monitoring/main.nf` | Recursive pattern, batchWithTimeout, InputDetector      |
| `workflows/nanometanf.nf`                        | Updated input mode detection, INPUT_SCANNER integration |
| `nextflow.config`                                | New parameters, default file_pattern change             |
| `nextflow_schema.json`                           | Schema for new parameters                               |

## Testing

**Unit tests:**

1. InputDetector.detectStructure() -- barcode subdirs, flat dir
2. InputDetector.extractSampleId() -- all four priority levels
3. batchWithTimeout() -- count emit, timeout emit, channel completion
4. INPUT_SCANNER subworkflow -- all structure types

**Integration tests:** 5. Real-time with barcode subdirectories 6. Real-time with flat directory + sample_regex 7. Scan mode with MinKNOW-style output 8. Backward compatibility: --barcode_input_dir alias

## References

- [EPI2ME real-time blog post](https://epi2me.nanoporetech.com/progressive-kraken2/)
- [epi2me-labs/wf-metagenomics](https://github.com/epi2me-labs/wf-metagenomics) -- current ingress pattern
- [Nextflow watchPath docs](https://www.nextflow.io/docs/latest/reference/channel.html)
- [watchPath termination issue](https://github.com/nextflow-io/nextflow/issues/735)
