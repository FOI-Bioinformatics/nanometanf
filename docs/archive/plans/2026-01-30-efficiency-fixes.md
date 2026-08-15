# Efficiency Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement six efficiency improvements identified in the efficiency audit of nanometanf v1.5.

**Architecture:** Config-only changes first (Finding 2), then correctness fixes in the streaming subscribe block (Findings 4, 5), then aggregator robustness (Finding 6), then QC redundancy removal (Finding 3), then intermediate validation (Finding 1).

**Tech Stack:** Nextflow DSL2, Groovy, Python 3, nf-test

---

### Task 1: Reduce KRAKEN2_REPORT_GENERATOR memory allocation

**Files:**

- Modify: `conf/modules.config:137-142`

**Step 1: Change memory and CPU allocation**

In `conf/modules.config`, change lines 140-141 from:

```groovy
        memory = { 6.GB * task.attempt }
        cpus = 2
```

to:

```groovy
        memory = { 1.GB * task.attempt }
        cpus = 1
```

**Step 2: Run existing tests to verify no regression**

Run: `nf-test test tests/resource_allocation_modules.nf.test --verbose`
Expected: PASS (resource values may appear in snapshots; update if needed)

**Step 3: Commit**

```bash
git add conf/modules.config
git commit -m "fix: reduce KRAKEN2_REPORT_GENERATOR memory from 6GB to 1GB

Lightweight text-parsing module was over-allocated. Frees ~80GB scheduler
headroom across 16 concurrent forks."
```

---

### Task 2: Fix race condition in progressive reporting

**Files:**

- Modify: `subworkflows/local/taxonomic_classification/main.nf:183-236`

**Step 1: Move file read inside synchronized block**

In `subworkflows/local/taxonomic_classification/main.nf`, change lines 184-189 from:

```groovy
                KRAKEN2_REPORT_GENERATOR.out.taxid_counts
                    .subscribe { meta, taxid_file ->
                        try {
                            def sample_id = meta.id
                            def batch_counts = new groovy.json.JsonSlurper().parseText(taxid_file.text)

                            synchronized(cumulative_taxa_state) {
```

to:

```groovy
                KRAKEN2_REPORT_GENERATOR.out.taxid_counts
                    .subscribe { meta, taxid_file ->
                        try {
                            def sample_id = meta.id

                            synchronized(cumulative_taxa_state) {
                                def batch_counts = new groovy.json.JsonSlurper().parseText(taxid_file.text)
```

This moves the JSON parse (`taxid_file.text`) inside the `synchronized` block so that file read and state update are atomic per-sample.

**Step 2: Run existing tests**

Run: `nf-test test tests/core_logic_test.nf.test --verbose`
Expected: PASS

**Step 3: Commit**

```bash
git add subworkflows/local/taxonomic_classification/main.nf
git commit -m "fix: move file read inside synchronized block in progressive reporting

Prevents potential ordering inconsistency when two batches for the same
sample emit near-simultaneously."
```

---

### Task 3: Add buffered writes to progressive reporting

**Files:**

- Modify: `subworkflows/local/taxonomic_classification/main.nf:179-236`
- Modify: `nextflow.config:99-103`

**Step 1: Add parameter to nextflow.config**

After line 103 in `nextflow.config`, add:

```groovy
    report_write_interval      = 5           // Write progressive cumulative report every N batches (0 = every batch)
```

**Step 2: Add batch counter and conditional write logic**

In `subworkflows/local/taxonomic_classification/main.nf`, after line 181 (after `cumulative_taxa_state` definition), add:

```groovy
                def batch_write_counter = [:].withDefault { 0 }
                def write_interval = params.report_write_interval ?: 5
```

Then wrap the file-write section (lines 207-229) in a conditional. After line 205 (`state.unclassified_reads += ...`), replace lines 207-229 with:

```groovy
                                batch_write_counter[sample_id]++

                                // Write progressive report every N batches or on final batch
                                if (write_interval <= 0
                                    || batch_write_counter[sample_id] % write_interval == 0
                                    || meta.is_final_batch == true) {

                                    // Write progressive cumulative kreport for dashboard
                                    def outdir = new File("${params.outdir}/kraken2")
                                    outdir.mkdirs()
                                    def total = state.total_reads ?: 1

                                    def sb = new StringBuilder()
                                    state.taxa.sort { a, b ->
                                        (b.value.cumul as int) <=> (a.value.cumul as int) ?: a.key <=> b.key
                                    }.each { taxid, tdata ->
                                        def pct = String.format("%.2f", ((tdata.cumul as double) / total) * 100.0)
                                        sb.append("${pct}\t${tdata.cumul}\t${tdata.reads}\t${tdata.rank}\t${taxid}\t${tdata.name}\n")
                                    }

                                    // Atomic write: temp file then rename
                                    def temp = new File(outdir, "${sample_id}.cumulative.kraken2.report.txt.tmp")
                                    temp.text = sb.toString()
                                    def target = new File(outdir, "${sample_id}.cumulative.kraken2.report.txt")
                                    if (!temp.renameTo(target)) {
                                        target.text = temp.text
                                        temp.delete()
                                        log.debug "Progressive report: renameTo failed, used copy fallback for ${sample_id}"
                                    }

                                    log.debug "Progressive cumulative report updated for ${sample_id}: ${state.total_reads} reads, ${state.taxa.size()} taxa"
                                }
```

**Step 3: Run existing tests**

Run: `nf-test test tests/core_logic_test.nf.test --verbose`
Expected: PASS

**Step 4: Commit**

```bash
git add subworkflows/local/taxonomic_classification/main.nf nextflow.config
git commit -m "feat: buffer progressive report writes to every N batches

Reduces filesystem I/O by writing cumulative kreport every 5 batches
instead of every batch. Configurable via report_write_interval param.
write_interval=0 restores per-batch behavior."
```

---

### Task 4: Add batch count validation to final aggregator

**Files:**

- Modify: `modules/local/kraken2_final_aggregator/main.nf:25-126`
- Modify: `subworkflows/local/taxonomic_classification/main.nf` (groupTuple section ~247-270)

**Step 1: Pass batch_count through the channel**

In `subworkflows/local/taxonomic_classification/main.nf`, find the section where `ch_aggregator_input` is constructed (around lines 260-270). Change the map after `groupTuple` to include batch count in meta:

Find the existing `.map` that constructs the aggregator input tuple and change it so `meta` includes `batch_count: outputs.size()`. The exact change depends on the current code structure -- read the file to confirm.

**Step 2: Add validation to aggregator Python script**

In `modules/local/kraken2_final_aggregator/main.nf`, after line 44 (`print(f"  Found {len(batch_output_files)} ...`), add:

```python
    expected_batches = ${meta.batch_count ?: 0}
    if expected_batches > 0:
        if len(batch_output_files) != expected_batches:
            print(f"  WARNING: Expected {expected_batches} output files, found {len(batch_output_files)}", file=sys.stderr)
        if len(batch_report_files) != expected_batches:
            print(f"  WARNING: Expected {expected_batches} report files, found {len(batch_report_files)}", file=sys.stderr)
```

Add completeness flag to the stats dict (around line 103):

```python
    stats = {
        'sample_id': sample_id,
        'expected_batches': expected_batches,
        'total_batches': len(batch_output_files),
        'batches_complete': len(batch_output_files) == expected_batches if expected_batches > 0 else True,
        'total_reads': total_reads,
        'classified_reads': classified_reads,
        'unclassified_reads': total_reads - classified_reads,
        'classification_rate': classified_reads / total_reads if total_reads > 0 else 0,
        'unique_taxa': len(merged_taxa),
        'cumulative_output': cumulative_output_file,
        'cumulative_report': cumulative_report_file
    }
```

**Step 3: Run existing tests**

Run: `nf-test test tests/core_logic_test.nf.test --verbose`
Expected: PASS

**Step 4: Commit**

```bash
git add modules/local/kraken2_final_aggregator/main.nf subworkflows/local/taxonomic_classification/main.nf
git commit -m "fix: add batch count validation to final aggregator

Passes expected batch count from groupTuple and warns if staged files
don't match. Adds batches_complete flag to aggregation stats."
```

---

### Task 5: Remove FastQC redundancy in real-time mode

**Files:**

- Modify: `subworkflows/local/qc_analysis/main.nf` (lines ~110-157)
- Modify: `nextflow.config` (add `skip_fastqc_realtime` param)

**Step 1: Add parameter**

In `nextflow.config`, in the QC section (find by searching for `qc_tool`), add:

```groovy
    skip_fastqc_realtime       = true        // Skip FastQC in real-time mode (SeqKit provides JSON stats)
```

**Step 2: Guard FastQC calls behind realtime check**

In `subworkflows/local/qc_analysis/main.nf`, wrap each FASTQC call in a conditional. For the CHOPPER path (lines 146-150), change to:

```groovy
    // MODULE: Run FastQC on filtered reads (skip in real-time mode if configured)
    def run_fastqc = !(params.realtime_mode && params.skip_fastqc_realtime)
    if (run_fastqc) {
        FASTQC (
            CHOPPER.out.fastq
        )
        ch_versions = ch_versions.mix(FASTQC.out.versions)
        ch_fastqc_html = FASTQC.out.html
    }
```

Apply the same pattern to the FILTLONG path (lines 110-114).

Ensure `ch_fastqc_html` is initialized as an empty channel at the top of the workflow so downstream references don't fail when FastQC is skipped:

```groovy
    ch_fastqc_html = Channel.empty()
```

**Step 3: Run QC tests**

Run: `nf-test test tests/qc_tool_integration.nf.test --verbose`
Expected: PASS

**Step 4: Commit**

```bash
git add subworkflows/local/qc_analysis/main.nf nextflow.config
git commit -m "feat: skip FastQC in real-time mode to reduce QC compute

SeqKit Stats provides equivalent JSON statistics for dashboards.
FastQC remains available in batch mode and via skip_fastqc_realtime=false."
```

---

### Task 6: Add intermediate validation aggregation

This is the largest change. It requires a new module or reuse of the existing aggregation module with periodic input.

**Files:**

- Modify: `subworkflows/local/validation/main.nf:162-173`
- Modify: `nextflow.config` (add `validation_aggregate_interval` param)

**Step 1: Add parameter**

In `nextflow.config`, in the validation section, add:

```groovy
    validation_aggregate_interval = 0        // 0 = end-of-session only; >0 = emit intermediate validation every N results
```

**Step 2: Add intermediate aggregation in validation subworkflow**

In `subworkflows/local/validation/main.nf`, before the existing `AGGREGATE_VALIDATION_RESULTS` call (line 167), add a periodic aggregation branch:

```groovy
    // Intermediate validation aggregation for real-time dashboard
    def val_interval = params.validation_aggregate_interval ?: 0
    if (val_interval > 0) {
        // Buffer validation stats and emit periodically
        def ch_periodic_validation = ch_blast_stats
            .mix(ch_minimap2_stats)
            .buffer(size: val_interval, remainder: true)
            .map { stats_list ->
                // Write intermediate JSON
                stats_list
            }

        ch_periodic_validation.subscribe { stats_list ->
            try {
                def outdir = new File("${params.outdir}/validation")
                outdir.mkdirs()
                def intermediate = []
                stats_list.each { stats_file ->
                    def data = new groovy.json.JsonSlurper().parseText(stats_file.text)
                    intermediate.add(data)
                }
                def temp = new File(outdir, "intermediate_validation.json.tmp")
                temp.text = new groovy.json.JsonBuilder(intermediate).toPrettyString()
                def target = new File(outdir, "intermediate_validation.json")
                if (!temp.renameTo(target)) {
                    target.text = temp.text
                    temp.delete()
                }
                log.debug "Intermediate validation updated: ${intermediate.size()} results"
            } catch (Exception e) {
                log.warn "Intermediate validation aggregation failed: ${e.message}"
            }
        }
    }

    // Final end-of-session aggregation (unchanged)
    AGGREGATE_VALIDATION_RESULTS(
        ch_blast_stats.collect().ifEmpty([]),
        ch_minimap2_stats.collect().ifEmpty([]),
        ch_extraction_stats.collect().ifEmpty([]),
        ch_kraken_report_files.collect().ifEmpty([]),
        validation_method
    )
```

**Important:** This uses a `.subscribe` block (same pattern as progressive classification reporting) rather than a new Nextflow module. This avoids the need for a new process definition and keeps the intermediate output as a lightweight JVM-side operation.

**Step 3: Run validation tests**

Run: `nf-test test tests/pathogen_validation.nf.test --verbose`
Expected: PASS

**Step 4: Commit**

```bash
git add subworkflows/local/validation/main.nf nextflow.config
git commit -m "feat: add intermediate validation aggregation for real-time dashboard

Periodically writes intermediate_validation.json during streaming so the
dashboard can show validation progress before end-of-session. Disabled by
default (validation_aggregate_interval=0)."
```

---

### Task 7: Final verification

**Step 1: Run full test suite**

Run: `nf-test test --verbose`
Expected: All tests PASS

**Step 2: Run nf-core lint**

Run: `nf-core lint`
Expected: Score >= 96/100 (no regression)

**Step 3: Update CLAUDE.md if needed**

If new parameters were added, verify they are documented in the relevant sections of `CLAUDE.md`.

**Step 4: Final commit if any fixups needed**

```bash
git add -A
git commit -m "chore: post-audit fixups and documentation updates"
```
