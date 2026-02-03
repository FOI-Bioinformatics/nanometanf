# Unified Input Handling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Unify input detection for real-time and scan modes, add timeout-based batching, and support barcode subdirectories and custom sample regex in real-time FASTQ monitoring.

**Architecture:** A shared `InputDetector.groovy` handles folder structure detection and sample ID extraction. A `BatchUtils.groovy` provides count-or-timeout batching. A new `INPUT_SCANNER` subworkflow replaces `BARCODE_DISCOVERY` for unified scan-mode input. The real-time monitor gains recursive file patterns and per-sample grouping.

**Tech Stack:** Nextflow DSL2, Groovy, nf-test

**Design document:** `docs/plans/2026-01-31-unified-input-handling-design.md`

**Worktree:** `.worktrees/unified-input` (branch: `feature/unified-input-handling`)

**Testing:** nf-test requires conda env `nf-core`:
```bash
eval "$(~/miniforge3/bin/conda shell.bash hook)" && conda activate nf-core
export JAVA_HOME=$CONDA_PREFIX/lib/jvm && export PATH=$JAVA_HOME/bin:$PATH
```

---

### Task 1: Create InputDetector.groovy

**Files:**
- Create: `lib/InputDetector.groovy`

**Step 1: Create the utility class**

```groovy
/*
 * Shared utility for detecting input directory structure and extracting sample IDs.
 * Used by both real-time monitoring and scan-mode subworkflows.
 */
class InputDetector {

    static final List FASTQ_EXTENSIONS = ['.fastq', '.fastq.gz', '.fq', '.fq.gz']
    static final List POD5_EXTENSIONS = ['.pod5']

    /**
     * Detect whether a directory uses barcode subdirectories or flat layout.
     *
     * @param dir Path to the input directory
     * @param extensions List of file extensions to look for
     * @return 'barcode_subdirs' or 'flat'
     */
    static String detectStructure(java.nio.file.Path dir, List extensions = FASTQ_EXTENSIONS) {
        def dirFile = dir.toFile()
        if (!dirFile.isDirectory()) return 'flat'

        def children = dirFile.listFiles()
        if (children == null) return 'flat'

        def hasBarcodeDirs = children.any { child ->
            child.isDirectory() &&
            child.name =~ /^barcode\d+$/ &&
            hasTargetFiles(child, extensions)
        }

        return hasBarcodeDirs ? 'barcode_subdirs' : 'flat'
    }

    /**
     * Extract sample ID from a file path using a priority chain:
     * 1. Parent directory name if it matches barcode pattern
     * 2. User-provided regex applied to filename
     * 3. BarcodeUtils extraction from filename
     * 4. Fallback to sample_name or filename stem
     *
     * @param filePath Path to the file
     * @param sampleRegex Optional regex with capture group for sample ID
     * @param sampleName Optional fallback sample name
     * @return Extracted sample ID string
     */
    static String extractSampleId(java.nio.file.Path filePath, String sampleRegex = null, String sampleName = null) {
        def parentName = filePath.parent?.fileName?.toString()
        def filename = filePath.fileName.toString()
        def stem = filename.replaceAll(/\.(fastq|fq)(\.gz)?$/, '')

        // 1. Subdirectory-based: parent is barcode dir
        if (parentName && parentName =~ /^barcode\d+$/) {
            return parentName
        }

        // 2. User-provided regex
        if (sampleRegex) {
            def m = filename =~ sampleRegex
            if (m.find() && m.groupCount() >= 1) {
                return m.group(1)
            }
        }

        // 3. BarcodeUtils extraction from filename
        def barcode = BarcodeUtils.extractBarcodeFromFilename(stem)
        if (barcode) {
            return barcode
        }

        // 4. Fallback
        return sampleName ?: stem
    }

    /**
     * Check if a directory contains files with any of the given extensions.
     */
    static boolean hasTargetFiles(File dir, List extensions) {
        def files = dir.listFiles()
        if (files == null) return false
        return files.any { f ->
            !f.isDirectory() && extensions.any { ext -> f.name.endsWith(ext) }
        }
    }
}
```

**Step 2: Commit**

```bash
git add lib/InputDetector.groovy
git commit -m "feat: add InputDetector utility for folder structure detection"
```

---

### Task 2: Create BatchUtils.groovy

**Files:**
- Create: `lib/BatchUtils.groovy`

**Step 1: Create the timeout-based batching utility**

```groovy
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import groovyx.gpars.dataflow.DataflowVariable
import nextflow.Channel

/**
 * Utility for count-or-timeout batch flushing in real-time mode.
 *
 * Emits a batch (as a list) when either:
 * - batchSize files have accumulated, or
 * - timeoutSeconds have elapsed since the last file arrived
 *
 * This replaces collate(N) which has no timeout support.
 */
class BatchUtils {

    /**
     * Create a channel that batches items by count or timeout.
     *
     * @param ch_input Input channel of individual items
     * @param batchSize Max items per batch before forced emit
     * @param timeoutSeconds Seconds of inactivity before flushing partial batch
     * @return New channel emitting lists of items
     */
    static def batchWithTimeout(ch_input, int batchSize, int timeoutSeconds) {
        def output = Channel.create()
        def buffer = Collections.synchronizedList(new ArrayList())
        def scheduler = Executors.newSingleThreadScheduledExecutor({ r ->
            def t = new Thread(r, "batch-timeout-flush")
            t.daemon = true
            return t
        })
        def flushTaskRef = new java.util.concurrent.atomic.AtomicReference<ScheduledFuture>(null)

        def flush = {
            synchronized (buffer) {
                if (buffer.size() > 0) {
                    def batch = new ArrayList(buffer)
                    buffer.clear()
                    output.bind(batch)
                }
            }
        }

        def resetTimer = {
            def prev = flushTaskRef.get()
            if (prev != null) prev.cancel(false)
            def task = scheduler.schedule(flush, timeoutSeconds, TimeUnit.SECONDS)
            flushTaskRef.set(task)
        }

        ch_input.subscribe(
            onNext: { item ->
                synchronized (buffer) {
                    buffer.add(item)
                    if (buffer.size() >= batchSize) {
                        // Cancel pending timer and flush immediately
                        def prev = flushTaskRef.get()
                        if (prev != null) prev.cancel(false)
                        flush()
                    } else {
                        resetTimer()
                    }
                }
            },
            onComplete: {
                // Cancel any pending timer
                def prev = flushTaskRef.get()
                if (prev != null) prev.cancel(false)
                flush()
                scheduler.shutdown()
                output.bind(Channel.STOP)
            }
        )
        return output
    }
}
```

**Step 2: Commit**

```bash
git add lib/BatchUtils.groovy
git commit -m "feat: add BatchUtils with count-or-timeout batching"
```

---

### Task 3: Add new parameters to nextflow.config

**Files:**
- Modify: `nextflow.config:10-65` (params block)

**Step 1: Add new parameters**

Add after the `barcode_input_dir` line (line 63):

```groovy
    input_dir                  = null   // Unified scan-mode input directory (auto-detects structure)
    sample_regex               = null   // Regex with capture group for sample ID extraction from filenames
    batch_timeout              = 60     // Seconds before emitting partial batch in real-time mode
```

**Step 2: Commit**

```bash
git add nextflow.config
git commit -m "feat: add input_dir, sample_regex, and batch_timeout parameters"
```

---

### Task 4: Create INPUT_SCANNER subworkflow

**Files:**
- Create: `subworkflows/local/input_scanner/main.nf`

**Step 1: Create the subworkflow**

```groovy
//
// Unified input directory scanner
// Auto-detects folder structure and groups files by sample
//

workflow INPUT_SCANNER {

    take:
    input_dir      // val: path to input directory
    sample_regex   // val: optional regex for sample ID extraction (null if not set)

    main:
    ch_versions = Channel.empty()

    def dir_path = file(input_dir).toPath()
    def structure = InputDetector.detectStructure(dir_path)
    log.info "Input directory structure detected: ${structure}"

    if (structure == 'barcode_subdirs') {
        //
        // Barcode subdirectory mode: one sample per barcode dir
        //
        ch_samples = Channel.fromPath("${input_dir}/barcode*", type: 'dir')
            .filter { it.isDirectory() }
            .map { barcode_dir ->
                def barcode = barcode_dir.getName()
                def fastq_files = []
                barcode_dir.eachFileMatch(~/.+\.(fastq|fastq\.gz|fq|fq\.gz)$/) { f ->
                    fastq_files.add(f)
                }
                if (fastq_files.size() > 0) {
                    def meta = [
                        id: barcode,
                        barcode: barcode,
                        single_end: true,
                        demultiplexed: true,
                        demux_source: "input_scanner"
                    ]
                    return [ meta, fastq_files ]
                }
                return null
            }
            .filter { it != null }

        // Also pick up unclassified directory
        ch_unclassified = Channel.fromPath("${input_dir}/unclassified", type: 'dir')
            .filter { it.isDirectory() }
            .map { unclass_dir ->
                def fastq_files = []
                unclass_dir.eachFileMatch(~/.+\.(fastq|fastq\.gz|fq|fq\.gz)$/) { f ->
                    fastq_files.add(f)
                }
                if (fastq_files.size() > 0) {
                    def meta = [
                        id: "unclassified",
                        barcode: "unclassified",
                        single_end: true,
                        demultiplexed: true,
                        demux_source: "input_scanner"
                    ]
                    return [ meta, fastq_files ]
                }
                return null
            }
            .filter { it != null }

        ch_all_samples = ch_samples.mix(ch_unclassified)

    } else {
        //
        // Flat directory mode: group by sample ID
        //
        ch_all_samples = Channel.fromPath("${input_dir}/**/*.{fastq,fastq.gz,fq,fq.gz}")
            .map { f ->
                def sample_id = InputDetector.extractSampleId(
                    f.toPath(),
                    sample_regex,
                    params.sample_name
                )
                def meta = [
                    id: sample_id,
                    single_end: true,
                    demux_source: "input_scanner"
                ]
                // Add barcode to meta if sample_id looks like a barcode
                if (sample_id =~ /^barcode\d+$/) {
                    meta.barcode = sample_id
                    meta.demultiplexed = true
                }
                return [ meta, f ]
            }
            .groupTuple(by: 0)
            .map { meta, files ->
                // groupTuple wraps files in extra list; flatten
                [ meta, files.flatten() ]
            }
    }

    emit:
    samples  = ch_all_samples   // channel: [ val(meta), [path(reads)] ]
    versions = ch_versions      // channel: [ path(versions.yml) ]
}
```

**Step 2: Commit**

```bash
git add subworkflows/local/input_scanner/main.nf
git commit -m "feat: add INPUT_SCANNER subworkflow for unified directory scanning"
```

---

### Task 5: Update REALTIME_MONITORING to use InputDetector and BatchUtils

**Files:**
- Modify: `subworkflows/local/realtime_monitoring/main.nf`

**Step 1: Replace collate with batchWithTimeout**

In `subworkflows/local/realtime_monitoring/main.nf`, replace the batching sections.

Change the collate calls (around lines 166-178). Replace:

```groovy
            ch_batched_files = ch_branched_files.priority
                .mix(ch_branched_files.normal)
                .collate(effective_batch_size, false)
```

with:

```groovy
            def batch_timeout_val = params.batch_timeout ?: 60
            ch_batched_files = BatchUtils.batchWithTimeout(
                ch_branched_files.priority.mix(ch_branched_files.normal),
                effective_batch_size,
                batch_timeout_val
            )
```

And replace the non-priority path (around line 176-177):

```groovy
            ch_batched_files = ch_input_files
                .collate(effective_batch_size, false)
```

with:

```groovy
            def batch_timeout_val = params.batch_timeout ?: 60
            ch_batched_files = BatchUtils.batchWithTimeout(
                ch_input_files,
                effective_batch_size,
                batch_timeout_val
            )
```

Add a log line after batch configuration logging (around line 40):

```groovy
        log.info "Batch timeout: ${params.batch_timeout ?: 60} seconds"
```

**Step 2: Replace sample ID extraction with InputDetector**

Replace the sample mapping block (lines 185-203). Change:

```groovy
        ch_samples = ch_batched_files
            .flatten()
            .map { file ->
                def meta = [:]
                def filename = file.baseName.replaceAll(/\.(fastq|fq)(\.gz)?$/, '')

                // Extract barcode if present in filename using shared utility
                def barcode = BarcodeUtils.extractBarcodeFromFilename(filename)
                if (barcode) {
                    meta.barcode = barcode
                }

                // Use params.sample_name for single-sample mode, otherwise use filename
                meta.id = params.sample_name ?: filename
                meta.single_end = true // Assume single-end for nanopore
                meta.batch_time = new Date().format('yyyy-MM-dd_HH-mm-ss')

                return [ meta, file ]
            }
```

to:

```groovy
        ch_samples = ch_batched_files
            .flatten()
            .map { file ->
                def meta = [:]

                // Use InputDetector priority chain for sample ID
                def sample_id = InputDetector.extractSampleId(
                    file.toPath(),
                    params.sample_regex,
                    params.sample_name
                )
                meta.id = sample_id

                // Add barcode metadata if applicable
                if (sample_id =~ /^barcode\d+$/) {
                    meta.barcode = sample_id
                }

                meta.single_end = true
                meta.batch_time = new Date().format('yyyy-MM-dd_HH-mm-ss')

                return [ meta, file ]
            }
```

**Step 3: Commit**

```bash
git add subworkflows/local/realtime_monitoring/main.nf
git commit -m "feat: use BatchUtils and InputDetector in real-time monitor"
```

---

### Task 6: Update default file_pattern to recursive

**Files:**
- Modify: `nextflow.config:18`

**Step 1: Change default pattern**

Replace:
```groovy
    file_pattern               = "*.fastq{,.gz}"  // Match FASTQ files in root directory (most common for nanopore)
```

with:
```groovy
    file_pattern               = "**/*.fastq{,.gz}"  // Match FASTQ files recursively (supports barcode subdirectories)
```

**Step 2: Commit**

```bash
git add nextflow.config
git commit -m "feat: change default file_pattern to recursive for barcode subdir support"
```

---

### Task 7: Wire INPUT_SCANNER into workflow orchestration

**Files:**
- Modify: `workflows/nanometanf.nf:1-30` (imports) and `workflows/nanometanf.nf:97-276` (routing)

**Step 1: Add import**

After the `BARCODE_DISCOVERY` import (line 17), add:

```groovy
include { INPUT_SCANNER              } from '../subworkflows/local/input_scanner'
```

**Step 2: Update routing logic**

Replace the `is_barcode_discovery` block (lines 197-205):

```groovy
    } else if (is_barcode_discovery) {
        //
        // PRE-DEMULTIPLEXED BARCODE DIRECTORIES
        //
        BARCODE_DISCOVERY (
            params.barcode_input_dir
        )
        ch_processed_samples = BARCODE_DISCOVERY.out.samples
        ch_versions = ch_versions.mix(BARCODE_DISCOVERY.out.versions)
```

with:

```groovy
    } else if (params.input_dir || is_barcode_discovery) {
        //
        // UNIFIED DIRECTORY SCAN (replaces BARCODE_DISCOVERY)
        //
        def effective_input_dir = params.input_dir ?: params.barcode_input_dir
        if (params.barcode_input_dir && !params.input_dir) {
            log.warn "DEPRECATED: --barcode_input_dir is deprecated. Use --input_dir instead."
        }
        INPUT_SCANNER (
            effective_input_dir,
            params.sample_regex
        )
        ch_processed_samples = INPUT_SCANNER.out.samples
        ch_versions = ch_versions.mix(INPUT_SCANNER.out.versions)
```

**Step 3: Commit**

```bash
git add workflows/nanometanf.nf
git commit -m "feat: wire INPUT_SCANNER into workflow, deprecate barcode_input_dir"
```

---

### Task 8: Create test fixtures

**Files:**
- Create: `tests/fixtures/minknow_output/barcode01/test_reads_barcode01.fastq.gz`
- Create: `tests/fixtures/minknow_output/barcode02/test_reads_barcode02.fastq.gz`
- Create: `tests/fixtures/flat_multisample/sampleA_001.fastq.gz`
- Create: `tests/fixtures/flat_multisample/sampleB_001.fastq.gz`

**Step 1: Create fixtures**

Use existing fixture FASTQs as source. Copy from existing barcode_structure fixtures:

```bash
mkdir -p tests/fixtures/minknow_output/barcode01
mkdir -p tests/fixtures/minknow_output/barcode02
cp tests/fixtures/barcode_structure/barcode01/*.fastq* tests/fixtures/minknow_output/barcode01/ 2>/dev/null || \
  cp tests/fixtures/fastq/barcode01.fastq.gz tests/fixtures/minknow_output/barcode01/
cp tests/fixtures/barcode_structure/barcode02/*.fastq* tests/fixtures/minknow_output/barcode02/ 2>/dev/null || \
  cp tests/fixtures/fastq/barcode02.fastq.gz tests/fixtures/minknow_output/barcode02/

mkdir -p tests/fixtures/flat_multisample
cp tests/fixtures/fastq/barcode01.fastq.gz tests/fixtures/flat_multisample/sampleA_001.fastq.gz
cp tests/fixtures/fastq/barcode02.fastq.gz tests/fixtures/flat_multisample/sampleB_001.fastq.gz
```

**Step 2: Commit**

```bash
git add tests/fixtures/minknow_output tests/fixtures/flat_multisample
git commit -m "test: add MinKNOW-style and flat multi-sample test fixtures"
```

---

### Task 9: Write nf-test for INPUT_SCANNER

**Files:**
- Create: `tests/input_scanner.nf.test`

**Step 1: Write tests**

```groovy
nextflow_workflow {

    name "Test INPUT_SCANNER subworkflow"
    script "../subworkflows/local/input_scanner/main.nf"
    workflow "INPUT_SCANNER"

    tag "subworkflow"
    tag "input_scanner"
    tag "fast"

    test("Should detect barcode subdirectories and create per-barcode samples") {

        when {
            workflow {
                """
                input[0] = "$projectDir/tests/fixtures/minknow_output"
                input[1] = null
                """
            }
        }

        then {
            assert workflow.success
            assert workflow.out.samples.size() >= 2
            // Check sample IDs include barcode names
            def sample_ids = workflow.out.samples.collect { it[0].id }
            assert sample_ids.contains("barcode01")
            assert sample_ids.contains("barcode02")
        }
    }

    test("Should group flat files by sample_regex") {

        when {
            workflow {
                """
                input[0] = "$projectDir/tests/fixtures/flat_multisample"
                input[1] = "(sample[A-Z])_"
                """
            }
        }

        then {
            assert workflow.success
            assert workflow.out.samples.size() >= 2
            def sample_ids = workflow.out.samples.collect { it[0].id }
            assert sample_ids.contains("sampleA")
            assert sample_ids.contains("sampleB")
        }
    }

    test("Should handle barcode_input_dir backward compatibility") {

        when {
            workflow {
                """
                input[0] = "$projectDir/tests/fixtures/barcode_structure"
                input[1] = null
                """
            }
        }

        then {
            assert workflow.success
            assert workflow.out.samples.size() >= 2
        }
    }
}
```

**Step 2: Run tests**

```bash
nf-test test tests/input_scanner.nf.test --verbose
```

Expected: All 3 tests PASS.

**Step 3: Commit**

```bash
git add tests/input_scanner.nf.test
git commit -m "test: add nf-test suite for INPUT_SCANNER subworkflow"
```

---

### Task 10: Write nf-test for InputDetector

**Files:**
- Create: `tests/lib/input_detector.nf.test`

**Step 1: Write Groovy unit tests via nf-test**

```groovy
nextflow_function {

    name "Test InputDetector utility"
    script "lib/InputDetector.groovy"

    tag "unit"
    tag "fast"

    test("detectStructure should return barcode_subdirs for MinKNOW output") {

        when {
            function {
                """
                InputDetector.detectStructure(
                    java.nio.file.Paths.get("$projectDir/tests/fixtures/minknow_output")
                )
                """
            }
        }

        then {
            assert function.result == "barcode_subdirs"
        }
    }

    test("detectStructure should return flat for flat directory") {

        when {
            function {
                """
                InputDetector.detectStructure(
                    java.nio.file.Paths.get("$projectDir/tests/fixtures/flat_multisample")
                )
                """
            }
        }

        then {
            assert function.result == "flat"
        }
    }

    test("extractSampleId should use parent dir for barcode subdirs") {

        when {
            function {
                """
                InputDetector.extractSampleId(
                    java.nio.file.Paths.get("$projectDir/tests/fixtures/minknow_output/barcode01/test_reads.fastq.gz")
                )
                """
            }
        }

        then {
            assert function.result == "barcode01"
        }
    }

    test("extractSampleId should use regex when provided") {

        when {
            function {
                """
                InputDetector.extractSampleId(
                    java.nio.file.Paths.get("/tmp/sampleA_001.fastq.gz"),
                    "(sample[A-Z])_",
                    null
                )
                """
            }
        }

        then {
            assert function.result == "sampleA"
        }
    }

    test("extractSampleId should fall back to BarcodeUtils") {

        when {
            function {
                """
                InputDetector.extractSampleId(
                    java.nio.file.Paths.get("/tmp/reads_barcode05.fastq.gz"),
                    null,
                    null
                )
                """
            }
        }

        then {
            assert function.result == "barcode05"
        }
    }
}
```

**Step 2: Run tests**

```bash
nf-test test tests/lib/input_detector.nf.test --verbose
```

Expected: All 5 tests PASS.

**Step 3: Commit**

```bash
git add tests/lib/input_detector.nf.test
git commit -m "test: add unit tests for InputDetector utility"
```

---

### Task 11: Update nextflow_schema.json

**Files:**
- Modify: `nextflow_schema.json`

**Step 1: Add schema entries for new parameters**

Add `input_dir`, `sample_regex`, and `batch_timeout` to the appropriate sections in the schema JSON. `input_dir` goes in the input section near `barcode_input_dir`. `sample_regex` goes near `sample_name`. `batch_timeout` goes near `batch_size`.

For each parameter, add:

```json
"input_dir": {
    "type": "string",
    "format": "directory-path",
    "description": "Directory to scan for FASTQ or POD5 files. Auto-detects barcode subdirectories vs flat layout.",
    "help_text": "Replaces --barcode_input_dir with unified auto-detection. Supports barcode subdirectories (barcode01/, barcode02/), flat directories with barcodes in filenames, and flat directories with custom sample prefixes (use --sample_regex)."
},
"sample_regex": {
    "type": "string",
    "description": "Regex with capture group to extract sample ID from filenames.",
    "help_text": "Applied when files are in a flat directory without barcode subdirectories. The first capture group becomes the sample ID. Example: '(sample[A-Z]+)_' extracts 'sampleA' from 'sampleA_001.fastq.gz'."
},
"batch_timeout": {
    "type": "integer",
    "default": 60,
    "description": "Seconds of inactivity before emitting a partial batch in real-time mode.",
    "help_text": "In real-time mode, batches are normally emitted when batch_size files accumulate. This parameter adds a timeout: if no new files arrive within this many seconds, the current partial batch is emitted immediately. Set to 0 to disable timeout-based flushing."
}
```

**Step 2: Run schema lint**

```bash
nf-core schema lint
```

Expected: No errors for new parameters.

**Step 3: Commit**

```bash
git add nextflow_schema.json
git commit -m "feat: add schema entries for input_dir, sample_regex, batch_timeout"
```

---

### Task 12: Final integration test

**Step 1: Run full fast test suite**

```bash
nf-test test --tag fast --verbose
```

Expected: All existing tests still pass, new tests pass.

**Step 2: Run nf-core lint**

```bash
nf-core lint
```

Expected: No regressions from current 96/100 score.

**Step 3: If all passing, final commit for any remaining changes**

```bash
git status
# Stage and commit any remaining changes
```
