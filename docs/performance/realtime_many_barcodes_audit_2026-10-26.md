# Real-time capacity audit: many barcodes, fast-arriving data, late start

**Date:** 2026-10-26
**Branch audited:** `claude/nanometanf-realtime-capacity-audit-ym5hhz` at `5faa8dc` (v1.11.0)
**Question:** can a real-time run keep up with a fast producer across 24-96
barcodes without stalling, and without showing only one sample at first,
particularly when the run is started _after_ sequencing began so a large
backlog already sits in the watch directory?

**Method.** Static read of the real-time path, plus one executed measurement
of the two interleavers (`docs/performance/scripts/realtime_fairness_probe.groovy`).
Nextflow is not installed in the audit container, so **no pipeline run was
executed**. Every claim below is labelled `measured`, `read` (traced in the
source, line cited) or `reasoned` (an inference from operator semantics that
was not executed). No timing figure is this audit's own; the few that appear
are quoted from in-repo audit comments and attributed.

---

## Summary

The live classification path does not deadlock. There is **no blocking
`collect()` or `groupTuple()` between `watchPath` and the classifier** (read:
`qc_analysis/main.nf:227` -> `workflows/nanometanf.nf:359` -> `:468`, per-file
throughout). The stalls reported by operators are resource contention and
end-of-session gating, not a channel that never fires.

Two separate things produce "only one sample at first":

1. **For a MinKNOW per-barcode directory layout, intake fairness is correct**
   and measured correct. Every barcode has a first file within the first 24
   files of a 24-barcode backlog.
2. **For every other supported layout it collapses completely** (measured, F1).
   Both interleavers key on the parent directory name, while
   `InputDetector.extractSampleId` derives the sample from the _filename_ in
   three of its four rules.

Then, for all layouts, the fairness that intake establishes is **never
re-established downstream**, and the throughput budget is allocated against
it: the classifier is capped at 4 forks while every QC process is uncapped and
sits upstream of it (F2-F6).

Finally, a **late start is a batch-shaped workload handed to the real-time
path**, which deliberately has none of batch mode's mitigations for exactly
this case (F7).

---

## F1. Fairness collapsed when the sample id was not the parent directory name

`measured` - severity: high - **FIXED 2026-10-27**

`lib/BatchUtils.groovy:165` and `lib/CrossBatchInterleaver.groovy:41` both
group by `it?.parent?.name`. `BatchUtils.groovy:166-168` short-circuits to a
plain name sort when there is only one group.

`lib/InputDetector.groovy:85-125` resolves the sample id by four rules. Only
rule 1 (parent matches `^barcode\d+$` or `unclassified`) and rule 1b (a custom
folder directly under the input root) agree with the interleavers' key. Rule 2
(`--sample_regex` on the filename), rule 3 (`BarcodeUtils` barcode-from-filename
when the parent is `fastq_pass` or `output`, `:116-121`) and rule 4 (filename
stem, `:124`) all derive the sample from the **filename**, leaving every file
in one parent directory and therefore in one interleaver group.

Measured with `docs/performance/scripts/realtime_fairness_probe.groovy`,
24 barcodes x 20 files = 480 files, `batch_size = 10`, filesystem order
shuffled:

| Layout                                  | Samples / parent dirs | Files before every sample has one result | Distinct samples in first 10 files |
| --------------------------------------- | --------------------- | ---------------------------------------- | ---------------------------------- |
| `fastq_pass/barcodeNN/reads_F.fastq.gz` | 24 / 24               | **24** of 480                            | **10**                             |
| `fastq_pass/barcodeNN_F.fastq.gz`       | 24 / 1                | **461** of 480                           | **1**                              |

The second row is the operator's report, exactly: the first ten files
classified are all one barcode, and the last barcode's first result arrives
after 96% of the backlog. This is a `--sample_regex` layout, or a MinKNOW
`fastq_pass/` with barcodes in filenames rather than subdirectories.

### Fix, 2026-10-27

Both interleavers now take the sample-id resolver as a required parameter and
resolve through one door, `BatchUtils.sampleKeyOf`:

- `BatchUtils.interleaveFilesByParentDir(files)` became
  `interleaveFilesBySample(files, sampleKey)`.
- `CrossBatchInterleaver` takes the same closure in its constructor.
- `realtime_monitoring/main.nf` defines **one** memoized resolver over
  `InputDetector.extractSampleId` and uses it for the start-up interleave, the
  cross-batch interleave and `meta.id`, so the key the ordering is computed on
  and the key the processes see cannot drift.

There is no parent-directory default. The two keys agree only when the sample
is a directory, so a default would have reintroduced the defect silently for
every future caller.

Groups are now also drained in sample-id order rather than in the order
`groupBy` happened to see the files, so the result no longer depends on how the
filesystem listed the backlog.

Re-measured on the same 480-file backlog with
`docs/performance/scripts/realtime_fairness_probe.groovy`, which reports both
keys in one run:

| Layout                      | Files before every sample has one result | Samples in first 10 files |
| --------------------------- | ---------------------------------------- | ------------------------- |
| `barcodeNN/` subdirectories | 24, was 24                               | 10, was 10                |
| flat, barcode in filename   | **24, was 461**                          | **10, was 1**             |

Every file is still emitted exactly once in both layouts. The
per-barcode-directory layout is unchanged, as predicted: `InputDetector` rule 1
returns the parent name there, so the new key equals the old one.

Coverage added: the flat-layout collapse, a 12-sample first-round assertion,
the listing-order independence and the `sampleKeyOf` fallback contract, in
`tests/lib/batch_utils.nf.test`, `tests/lib/batch_utils_sample_key.nf.test` and
`tests/lib/cross_batch_interleaver.nf.test`. The existing nine cases are
unchanged and still pass.

## F2. The opening burst submits one NanoPlot per barcode

`read` - severity: high - **BOUNDED 2026-10-27**

`qc_analysis/main.nf:354-371`: in real time, NanoPlot gets a per-sample index
from `nanoplot_counters[meta.id]` starting at 0, and `:369` keeps indices where
`idx % nanoplot_batch_interval == 0`. **Index 0 always passes.** So the first
file of _every_ barcode is a NanoPlot milestone.

At a late start the backlog delivers the first file of all 96 barcodes within
the opening seconds, so 96 NanoPlot tasks become runnable at the same moment as
each barcode's first classification. NanoPlot reserves 2 CPUs and 8 GB
(`conf/modules.config:470,477`) with **no `maxForks`**.

`conf/modules.config:471-476` records that this is the cost the 2026-09-07
time-to-first-result work removed: _"the four reserved CPUs were the cost, not
the runtime - on an 11-CPU host they were taken from the classifier while
samples were still waiting for their first report"_. That fix reduced NanoPlot
to 2 CPUs and grouped it to one task per sample - but the grouping is gated on
`is_chunked_batch`, which is `false` by construction in real time
(`qc_analysis/main.nf:82`). Real time kept the per-file cadence, and on 96
barcodes the burst is larger than the case that motivated the fix.

### Fix, 2026-10-27

NANOPLOT now carries `maxForks = params.max_nanoplot_forks ?: 2`
(`conf/modules.config`), with the parameter declared in `nextflow.config` and
`nextflow_schema.json`. Param-driven rather than a literal, because
`modules.config` is included after the platform profiles and a constant there
could not be overridden by one; a parameter can be set by a profile or on the
command line.

**The index-0 deferral was considered and rejected.** It would bound the burst,
but a real-time run never knows which batch is a sample's last, so any barcode
that receives a single file for the whole run would then get no NanoPlot at
all -- and a one-file barcode is the low-yield one an operator most wants to
look at. The reasoning is recorded at the filter in
`subworkflows/local/qc_analysis/main.nf` so it is not re-introduced as a fix.
The cap costs no coverage, so it is the whole of what was done.

Note what this does and does not do. It bounds the number of NanoPlot tasks
_running_ at once; it does not reduce how many become _runnable_, and it does
not make the classifier win a contended slot, because Nextflow has no task
priority. On the audit's 11-CPU reference host the opening burst goes from 96
simultaneous 2-CPU tasks to 2, which leaves the classifier's four forks the
CPU budget they were sized for. Unmeasured: this is scheduling arithmetic, and
the audit has no NanoPlot timing of its own -- the roughly 15 s per task figure
quoted above is from `conf/modules.config:471-476`, not from this work.

The underlying asymmetry in F3 is untouched: every other QC process is still
uncapped.

## F3. QC is uncapped; the classifier is capped

`read` - severity: high

`maxForks` appears in `conf/modules.config` only at `:337` (incremental
classifier), `:378` (output merger), `:411` (report generator), `:621/:637/:663`
(validation aggregators) and `:738` (assembly). **No QC process has one** -
not CHOPPER, SEQKIT_STATS, NANOPLOT, FASTQC or FASTP_STREAMING - and there is
no `process.maxForks` in `nextflow.config` or any profile.

QC sits upstream of classification in the DAG, so on a backlog every arriving
file submits a QC task before that file can be classified at all. A hard cap on
the consumer and no cap on the producer is the structural cause: the classifier
cannot use its 4 slots because QC has already committed the CPU and memory.

## F4. Two QC processes inherited resource labels far above their real cost

`read` - severity: high - **FIXED 2026-10-27**

| Process         | Label            | Reserves                                                 | Source                                                               |
| --------------- | ---------------- | -------------------------------------------------------- | -------------------------------------------------------------------- |
| SEQKIT_STATS    | `process_low`    | 2 CPU, **12 GB**                                         | `modules/nf-core/seqkit/stats/main.nf:3`, `conf/base.config:50-54`   |
| FASTP_STREAMING | `process_medium` | 6 CPU, **36 GB** (clamped to the 16 GB `resourceLimits`) | `modules/local/fastp_streaming/main.nf:12`, `conf/base.config:55-59` |

`conf/modules.config:65-108` sets only `ext.prefix` and `publishDir` for
SEQKIT_STATS, so nothing overrides the label. CHOPPER and FASTQC each received
an explicit "reduce memory for development/testing" override; SEQKIT_STATS was
missed, and it is the one QC process that runs on **every single file** in real
time. `withName:'FASTP'` in `conf/base.config:95-99` does not match
`FASTP_STREAMING` (`withName` is a full-string match), so with
`--qc_tool fastp` one task at a time saturates a 16 GB ceiling and the whole
real-time QC stage serialises per file.

### Fix, 2026-10-27

Both got a `withName` block in **`conf/base.config`**, not
`conf/modules.config`. That is the load-bearing detail: `base.config` is
included before the profiles and `modules.config` after them, so a default set
in `base.config` is overridable by a platform profile while one set in
`modules.config` silently is not. Putting these in `modules.config` would have
made every profile's `SEQKIT_STATS` block dead code, which is the F4c defect
this repo already carries for CHOPPER and NANOPLOT.

Each platform profile also gained a `FASTP_STREAMING` block mirroring its
`FASTP` one. No profile governed the streaming wrapper before, so a
`-profile field` run on a field laptop was sized by `process_medium` rather
than by the profile it was given.

Resolved reservations, checked against the include order:

|                          | SEQKIT_STATS  | FASTP_STREAMING                 |
| ------------------------ | ------------- | ------------------------------- |
| no profile, before       | 2 CPU / 12 GB | 6 CPU / 36 GB, clamped to 16 GB |
| no profile, after        | 1 CPU / 2 GB  | 4 CPU / 8 GB                    |
| `-profile field`, before | 1 CPU / 1 GB  | 6 CPU / 36 GB, clamped          |
| `-profile field`, after  | 1 CPU / 1 GB  | 2 CPU / 2 GB                    |

`conf/modules.config` sets no resources for either process, so nothing above
is shadowed.

This is reservation arithmetic, not a measured speedup, and it is what
schedules rather than what runs. On the audit's reference 11-CPU / 18 GB
laptop with no profile it is the difference between one concurrent QC task and
two, and between CHOPPER plus SEQKIT_STATS being co-schedulable (8 + 2 GB) and
not (8 + 12 GB against 18 GB physical). The 1-in-10 NanoPlot burst (F2) and
the classifier's own reservation (F5) are untouched by it.

## F5. With memory mapping on, every fork still reserves the whole database

`measured` - severity: high - **FIXED 2026-10-27**

`conf/modules.config:329-335` reserves `kraken2_task_memory_gb` only when it is
non-null:

```groovy
(task.attempt == 1 && mmap && task_gb != null) ? task_gb.GB : full.GB * task.attempt
```

`params.kraken2_task_memory_gb` defaults to `null` (`nextflow.config:65`) and
**no profile sets it** (checked across every `conf/*.config`). Memory mapping
defaults to `true` (`nextflow.config:55`), which is the configuration where the
hash table lives in the shared page cache and the private per-task footprint is
small - yet each fork reserves the full `kraken2_memory_gb` anyway: 12 GB
default, 32 GB under `promethion`, 40 GB under `promethion_8`, 64 GB under
`minion`.

`conf/promethion.config:26` describes the intended arithmetic
(_"6 forks with mmap: ~8GB shared db + 6x2GB overhead"_); the reservation
actually requested is 6 x 32 GB. On a memory-capped executor this silently
holds effective concurrency below `max_classification_forks`.

### Measured and fixed, 2026-10-27

The audit said to set this "to match the arithmetic their comments already
describe" but could not name a value. Measured with
`docs/performance/scripts/kraken2_fork_memory_probe.py` against two real
databases, page cache warmed as `KRAKEN2_DB_PRELOAD` warms it, sampling
`/proc/<pid>/smaps_rollup` across concurrent forks:

| database      | hash   | taxa   | marginal per extra fork, 1 thread | at 4 threads |
| ------------- | ------ | ------ | --------------------------------- | ------------ |
| viral         | 619 MB | 27,069 | 54 MB                             | 139 MB       |
| standard_08gb | 8.0 GB | 50,333 | 54 MB                             | 149 MB       |

**Flat across a 13x larger index**: about 50 MB plus 25 MB per thread,
independent of index size, because the index is shared and the private part is
read buffers and per-thread state. Without memory mapping one fork took 7.7 GB
private, the whole index -- which is the cost the unscaled reservation is sized
for, and is correct only then.

Two measurement traps worth recording, because the first result was wrong until
both were handled: with ONE process, file-backed mapped pages count as private
(nothing else maps them), so sharing is invisible below two concurrent forks;
and RSS counts a shared page once per process, so summing RSS multiply-counts
the index. PSS is the metric.

`kraken2_task_memory_gb = 2` is therefore set in the four profiles that run a
classifier against a shared page cache. That is 4-13x the measured marginal at
each profile's thread count. Verified by evaluating the directive from
`conf/modules.config` with each profile's parameters:

| profile        | forks x threads | per fork          | demand           | forks admitted | free for other tasks |
| -------------- | --------------- | ----------------- | ---------------- | -------------- | -------------------- |
| `minion`       | 1 x 16          | 64 GB -> **2 GB** | 64 -> 2 of 64    | 1 (unchanged)  | **0 -> 62 GB**       |
| `promethion_8` | 4 x 6           | 40 GB -> **2 GB** | 160 -> 8 of 128  | **3 -> 4**     | 8 -> 120 GB          |
| `promethion`   | 6 x 10          | 32 GB -> **2 GB** | 192 -> 12 of 256 | 6 (unchanged)  | 64 -> 244 GB         |
| `server`       | 8 x 4           | 12 GB -> **2 GB** | 96 -> 16 of 128  | 8 (unchanged)  | 32 -> 112 GB         |

Two effects, and the second is the one the audit under-rated. `promethion_8`
asked for four forks and the executor admitted **three**. And `minion` reserved
its entire 64 GB budget for one classifier, leaving **nothing** for QC, so QC
and classification could not overlap at all -- a single-sample profile where
the two stages were serialised by a reservation rather than by any real
constraint.

**Scoping, deliberately.** The global default stays `null` and `field` is left
alone. On an executor with cgroup limits, memory-mapped page cache is charged
to the cgroup, so reserving the whole index is correct there; these are
platform profiles for local sequencer-attached machines, which is where the
sharing is real. `field` runs one fork against a 10 GB reservation of a 128 GB
budget, so nothing is starved and its conservative sizing is left as designed.

**Caveats.** `max_memory` must still leave room for the index in page cache,
since the reservation no longer covers it; the preload already skips when the
hash exceeds 70% of available memory, which is the guard for an index that does
not fit. Measured only for indexes that fit in page cache -- the host had 15 GB
of RAM and the largest index tested was 8 GB -- which is the condition memory
mapping is for, but it means the thrashing regime beyond that is unmeasured.
The attempt-2 retry path, which drops memory mapping and asks for the full
size, is unchanged.

## F6. Raising `max_classification_forks` past `max_cpus / 4` buys nothing

`read` - severity: medium

`conf/modules.config:336`:

```groovy
cpus = { Math.max(4, ((params.max_cpus ?: 16) as int).intdiv(Math.max(1, (params.max_classification_forks ?: 1) as int))) }
```

The **floor of 4** means the per-task CPU request stops shrinking once forks
exceed `max_cpus / 4`. With the default `max_cpus = 16`, forks above 4 request
more total CPU than exists and the local executor admits 4 regardless.

`realtime_monitoring/main.nf:50-54` advises operators to _"raise
`max_classification_forks` proportionally to the number of barcodes - e.g. on a
24-plex run set forks to at least 6"_. That advice is incomplete: without
raising `--max_cpus` in the same proportion it has no effect. The log line and
the docs should say so.

## F7. A late start gets none of batch mode's mitigations

`read` - severity: high - **PARTLY FIXED 2026-10-27**

`workflows/nanometanf.nf:276` gates chunking on `!params.realtime_mode`, and
`qc_analysis/main.nf:82` gates the per-sample QC grouping on the same
expression. So a real-time run never reaches:

- `BatchChunkPlanner.chunk` - geometric chunking, so one task covers many files
  instead of one task per file;
- `BatchChunkPlanner.interleave` - a cross-sample chunk interleave keyed
  correctly on the **sample id**, which is what F1 is missing;
- `_groupPerSample` - one NanoPlot/FastQC task per sample instead of per file,
  which is what F2 is missing.

A backlog is, in every respect that matters to the scheduler, a batch workload.
Handing it to the real-time path converts it into one QC task plus one
classifier task per file, each classifier task paying a database load (F5), with
fairness applied only at intake and only by parent directory (F1).

`nanometa_live`'s `CLAUDE.md` already names real-time chunking as "a candidate
for a later plan". This audit is the argument for it: the late-start case is
not an edge case, it is how a field run begins whenever the operator opens the
dashboard after sequencing has started.

### Fix, 2026-10-27: the backlog is chunked

`params.realtime_backlog_chunking` (default true) plans the start-up listing
with `BatchChunkPlanner.planBySample`, the same planner batch mode uses, so
there is one definition of a chunk. The backlog is emitted on its own channel
as `[meta, files]` -- the shape batch chunking already emits -- so
DEMULTIPLEXING, QC_ANALYSIS and the classifier needed no change; CHOPPER
gunzips a file list into one stream.

**The live watcher stream is untouched and stays per file.** That was the
design constraint: the termination machinery (the timeout sentinel, the
`max_files` tap, three PoisonPill bindings) is delicate, and Issue #22 was a
hang caused by exactly that area.

Measured on `tests/fixtures/batch_chunking` (barcode01 x 3 files,
barcode02 x 1) in a real stub run, with a control case:

|                                     | QC tasks for 4 backlog files |
| ----------------------------------- | ---------------------------- |
| `realtime_backlog_chunking = false` | 4                            |
| `realtime_backlog_chunking = true`  | **3**                        |

Both samples appear in the trace, so chunk-0-first did not starve either.
`tests/realtime_backlog_chunking.nf.test` pins both numbers, and
`tests/lib/backlog_chunk_plan.nf.test` pins the plan itself, including that
11 files across 3 samples cost 6 chunks and that no file is dropped.

Two interactions are deliberate, and both are the reason this is only a
PARTIAL fix:

- **`max_files` disables it.** That cap is a per-file bound applied by
  `.take()` on the live stream, where a chunk is a single emission, so every
  bounded test would silently change meaning. Real runs bound by timeout get
  chunking; bounded tests do not.
- **No `batch_id` is pre-assigned.** The classifier honours a planned id only
  when `!realtime_mode`, deliberately: a Continue re-lists a SMALLER backlog
  because the ledger skips finished files, so chunk 0 of a second run holds
  different reads, and reusing the number would make the dashboard count the
  first run's reads twice. Fresh sequential ids from the head-process counter
  are the safe choice.

Still not done from F7: per-sample QC grouping in real time. NanoPlot and
FastQC remain per emission, so a chunk is one invocation rather than a sample
being one invocation. The NanoPlot burst is bounded by `max_nanoplot_forks`
(F2) instead. REALTIME_STATISTICS also does not see a chunked backlog: its
channel is built from the live batching operator, so the `[runtime-metrics]`
counters are fed explicitly instead.

### A compilation regression found by running it

Running this for the first time exposed that two earlier commits on this
branch broke the pipeline outright. The strict v2 parser, the default from
Nextflow 26, does not treat a local closure variable as callable:
`scan_existing(true)` and `resolve_sample_id(file)` fail the whole script with
"`scan_existing` is not defined", which takes down **every** pipeline that
includes this subworkflow, not only a real-time run. The rule was already
written down in this repo, at the `write_cumulative_report` closure in
`subworkflows/local/taxonomic_classification/main.nf`, and the F1 and F11
fixes violated it.

Nothing would have caught it: no realtime test runs on the ubuntu runner, and
the pure-function suites compile only their own harness. It is fixed by
invoking through `.call(...)`, with the rule recorded at the closures. The
lesson is the one F13 already states -- the suite that does not run is not a
safety net -- and it is why the audit now carries a measured toolchain recipe.

## F8. The canonical tier waits for the slowest barcode

`read` - severity: medium - **A WORSE BUG FOUND AND FIXED 2026-10-27**

`subworkflows/local/taxonomic_classification/main.nf:605` and `:613` apply
`groupTuple(by: 0)` with no `size:` to the output merger's two channels, so
they emit only when that channel closes - at the end of the whole session, for
every barcode at once. `KRAKEN2_FINAL_AGGREGATOR` and therefore TAXPASTA
(`:743`), `CANONICAL_CLASSIFICATION_WRITER` (`:764`) and MultiQC all sit behind
it.

The live tiers are the per-batch reports and the cumulative report written
directly by the head-process subscriber (`:462-532`, flushed on the first batch
and then every `report_write_interval` batches, default 1). Those do grow per
batch, so the dashboard's primary number is live. But
`results/canonical/classification/` - the documented tool-agnostic consumer
surface - is **empty for the entire run**, and one barcode still receiving
files holds it for all 96.

`KRAKEN2_FINAL_AGGREGATOR` also has no `maxForks` and reserves 8 GB
(`conf/modules.config:437-441`), so all 96 aggregators become runnable
simultaneously at session end.

### Investigated 2026-10-27, and it was worse than the timing

Chasing the timing turned up a correctness bug on the same surface, which
matters more than the latency.

The canonical specification pairs two sidecar fields: `is_cumulative` ("true
for end-of-session aggregate reports, false for per-batch increments") and
`batch_id`. A consumer uses them to decide whether to **sum** these files as
increments or take the latest as a **snapshot**.

`meta.is_cumulative` was read in exactly one place,
`modules/local/canonical_classification_writer/main.nf:31`, and **set
nowhere**. So `--is-cumulative` was never passed, and every canonical
classification sidecar this pipeline has ever written said
`"is_cumulative": false` -- including the end-of-session aggregate from
`KRAKEN2_FINAL_AGGREGATOR`, which is the only canonical classification output a
real-time run produces. Verified both ways: by grep, and by reading a sidecar
from a real run.

A consumer that believed the field would have summed cumulative snapshots.
That is the same increment-against-snapshot confusion nanometa_live records as
its H27, where a barcode served 324 reads of 938.

**Fix.** The two fields imply each other, so one rule covers all four sources
of `ch_raw_reports`: a report with a `batch_id` is that batch's increment, one
without covers the whole sample. Derived at the single point where the
canonical writer is fed; an explicit `meta.is_cumulative` still wins. Confirmed
end to end on a real-time run: the sidecars now read `is_cumulative: true` with
no `batch_id`, where before they read `false`.

Covered by two real-run cases in
`modules/local/canonical_classification_writer/tests/main.nf.test` -- not
stubbed, because the stub writes no sidecar body and the body is what is under
test. That file already runs in CI.

The specification also said `batch_id` is "present only in realtime per-batch
sidecars", which is backwards and is corrected: a real-time run's canonical
classification comes from the end-of-session aggregator and carries no
`batch_id`, while chunked **batch** mode is the mode that emits per-batch
increments.

### The timing itself: not changed, deliberately

The end-of-session gating stands. Making the canonical tier live would mean
feeding the writer from the per-batch reports, which is one writer task per
batch per barcode -- 720 for a 24-barcode, 30-batch run -- added to exactly the
stage this audit found starved (F3). nanometa_live does not need it: it reads
the per-batch cumulative report, which the head process rewrites every batch,
and takes canonical JSON only when it is no older than that report. So the cost
would buy a consumer surface that the one known consumer does not use live.

If a future consumer does need live canonical output, the per-batch reports are
already on disk under `batch_reports/` and are the cheaper place to read.

`KRAKEN2_FINAL_AGGREGATOR`'s missing `maxForks` is unchanged: at a 128 GB
budget its 8 GB reservation already limits it to about 16 concurrent, so a cap
would mostly re-state that, and setting one without measuring the staging I/O
would repeat the F5 mistake.

## F9. Per-batch dashboard writes are serialised through one lock

`measured` - severity: medium, revised down - **MEASURED 2026-10-27**

`taxonomic_classification/main.nf:471` takes `BatchUtils.withLock(cumulative_taxa_state)`

- a single monitor - and holds it across the batch JSON parse (`:472`), the
  merge (`:479`), the ledger append (`:486-490`, itself `synchronized` in
  `lib/RealtimeResume.groovy:63`) and the full cumulative-report rebuild and
  atomic write (`:404-438`). At the default `report_write_interval = 1` that
  whole sequence runs on every batch of every barcode, so each barcode's
  dashboard update queues behind every other barcode's.

The batch-id assignment at `:305` takes a second global lock, and the first
file of each barcode performs a directory listing of the sample's published
batches while holding it (`:233-253`).

This is O(cumulative taxa) per batch per barcode on one thread, and the cost is
additive across barcodes because the lock is global.

### Measured, 2026-10-27

This audit called F9 "the most likely unmeasured ceiling on a high-diversity
96-barcode run". **That was too strong**, and the measurement revises it down.

Two measurements, both re-runnable:

**1. A real 12-barcode run** (60 files, real Kraken2 against the mini database
fixture, `--runtime_metrics_interval_seconds 15`), comparing
`report_write_interval = 1` against a value high enough that only each sample's
first batch flushes:

| `report_write_interval`      | wall clock |
| ---------------------------- | ---------- |
| 1 (default)                  | 158 s      |
| effectively first-batch-only | 155 s      |

A 2% difference, inside noise. At the mini database's handful of taxa the
serialised section costs almost nothing. The metrics line also showed
`batches_per_barcode_min=5 batches_per_barcode_max=5` across all 12 barcodes,
so the intake fairness holds exactly.

**2. The locked section itself**
(`docs/performance/scripts/cumulative_lock_probe.groovy`), driving the real
`KreportTree` and `RealtimeResume` at realistic diversity. Per-batch and
cumulative diversity are swept separately, because they scale different steps:

| cumulative taxa | taxa per batch | parse + merge | ledger | report rebuild | per batch |
| --------------- | -------------- | ------------- | ------ | -------------- | --------- |
| 1,000           | 100            | 3.9 ms        | 2.1 ms | 22.1 ms        | 28.1 ms   |
| 3,000           | 300            | 6.1 ms        | 0.6 ms | 23.4 ms        | 30.1 ms   |
| 3,000           | 3,000          | 54.8 ms       | 0.7 ms | 19.4 ms        | 74.8 ms   |
| 10,000          | 1,000          | 12.2 ms       | 0.6 ms | 40.5 ms        | 53.3 ms   |

Serialised across barcodes over a 20-batch run: about **14 s at 24 barcodes and
3,000 taxa**, about **26 s at 10,000 taxa**. Real but tens of seconds across a
whole run, not the minutes-scale ceiling the original wording implied.

**The useful part: 76-79% of it is the report rebuild, which
`report_write_interval` already thins.** So the knob that exists does address
the dominant term. The `nextflow.config` comment claimed raising it "saves only
a small file write"; that is now corrected with these figures, because it is in
fact most of a serialised section.

A caveat on method, and on a conclusion it changed: the first version of the
probe gave every batch the full cumulative diversity, which made parse-and-merge
look dominant and the knob look useless. Separating the two axes reversed that.
Treat the `3,000 / 3,000` row as the worst case, not the normal one -- a batch
carries the taxa in that batch, not the run's whole diversity.

Not measured: 96 barcodes, and a real database at GTDB or PlusPF scale. The
figures above are a model of the locked code at those taxon counts, driven by
the real classes, not a run of the pipeline at that scale.

## F10. A trailing partial batch waits up to 60 s

`measured` - severity: low - **WITHDRAWN 2026-10-27**

`lib/BatchUtils.groovy` schedules the flush timer with `scheduleAtFixedRate` at
a fixed period and does not reset it on flush, so a buffer that never reaches
`batch_size` waits for the next tick - `batch_timeout = 60` s by default
(`nextflow.config:43`). With 24 barcodes and `batch_size = 10` the backlog cuts
into 10 + 10 + 4, and the 4 remainder barcodes wait for a tick before their
first file is batched.

### Withdrawn on measurement, 2026-10-27

The finding above is accurate about the mechanism and **wrong about the
remedy**, which this audit recommended as "reset the `batch_timeout` timer on
each flush". Measured with
`docs/performance/scripts/batch_timeout_probe.groovy`, a 2 s period and one
item every 300 ms, count threshold never reached:

| Timer policy                             | mean wait | max wait |
| ---------------------------------------- | --------- | -------- |
| shipped: fixed-rate sampler, never reset | 1025 ms   | 1990 ms  |
| recommended: reset on flush              | 1262 ms   | 2200 ms  |

Resetting the clock is worse on both. A fixed-rate sampler already bounds the
wait at one period and averages half of it, because a pending item only pays
whatever remains of the current tick; a per-batch deadline makes every batch
pay the whole period. The original wording ("holds every trailing partial batch
up to 60 s") also reads as though 60 s were the typical wait, when it is the
maximum and 30 s is the mean.

What was genuinely wrong there was the docstring, which claimed
"timeoutSeconds have elapsed since the last flush" - describing neither the
code nor the better behaviour. It now states the sampler semantics, the
measured comparison, and that the lever for lower partial-batch latency is a
smaller `batch_timeout` rather than a different timer policy.

No timing behaviour was changed.

## F11. A 10-second sleep occupied a shared operator thread during the backlog

`reasoned` - severity: low - **FIXED 2026-10-27**

`realtime_monitoring/main.nf:161-164` runs the start-up listing twice via
`Channel.fromList([0, 1]).flatMap { ... Thread.sleep(10000) ... }`. The second
sweep is a deliberate and well-reasoned guard against a partial directory walk,
and its output is correctly interleaved (`:193` runs before the `sweep > 0`
branch at `:195`).

The cost is that the sleep runs on the shared GPars operator thread pool -
the pool every `mix`, `filter`, `map` and `subscribe` in the chain is dispatched
on - and `poolSize` is never configured, so it defaults to
`max(3, availableProcessors)`. On a 2-4 core field laptop one of three operator
threads is unavailable for 10 s at precisely the moment the whole backlog is
flowing through the chain. Task submission and execution are not blocked.

Unverified: the pool-size default is Nextflow's documented value, not read from
an installed Nextflow in this container.

### Fix, 2026-10-27

The second listing now runs on a daemon `Timer` that binds its files into a
`DataflowQueue` mixed into the stream, the idiom the realtime timeout sentinel
and `BatchUtils`' flush already use in the same file. No operator-pool thread
blocks.

Two things were preserved deliberately:

- **The first listing still runs from an igniter.** `Channel.fromList([0])`
  keeps it there. Moving it to script-evaluation time would have reopened the
  start-up blind window (nanometa_live round-4 audit, H4): the watcher takes
  the directory contents at igniter time as its never-reported baseline, so a
  scan taken earlier leaves everything in between in neither set.
- **The re-sweep is armed from inside that igniter**, so it is still measured
  from the first listing exactly as the sleep was, and the watcher's baseline
  is already taken when it runs.

The queue is closed with a `PoisonPill` on both the success and the failure
path, because the session waits on every upstream queue and an unclosed one
hangs the run. The two listings share one `scan_existing` closure, so they
cannot drift on which files they select; before, the selection logic was one
body with `sweep > 0` branches.

Also corrected while there: the `max_files` truncation warning counted
"included/excluded per directory" using the parent directory name. It now
counts per sample, the key the interleave is actually fair on (F1).

## F12. `max_concurrent_batches` is dead config

`read` - severity: low (documentation) - **DOCS FIXED 2026-10-27**

Every read site: `nextflow.config:78` (default 4), `:440` (a comment
justifying `queueSize`), `conf/server.config:55` (override to 8),
`nextflow_schema.json:786`, and `realtime_monitoring/main.nf:60-61` - which is
a `log.info` and nothing else. No per-barcode throttle or semaphore exists
anywhere; grep for `semaphore|throttle` returns only comments describing the
unbuilt feature (`lib/BatchUtils.groovy:153`, `realtime_monitoring/main.nf:47,49,61`).

`CLAUDE.md` is correct that it is advisory. **Two user-facing documents still
describe it as enforced** - `docs/user/realtime_processing.md:595` and
`docs/releases/v1.5.0.md:89`, both as "backpressure limit per sample".

The same two tables carry three further drifts from `nextflow.config`, all
verified:

| Doc claim                                                                               | Actual                                                                     |
| --------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `--max_classification_forks` default `8` (`realtime_processing.md:596`, `v1.5.0.md:90`) | `4` (`nextflow.config:79`)                                                 |
| `--kraken2_enable_incremental` default `true` (`v1.5.0.md:88`)                          | `false` (`nextflow.config:68`)                                             |
| `--kraken2_sync_interval` (`v1.5.0.md:91`)                                              | **No such parameter.** Not in `nextflow.config`, the schema, or any module |

An operator tuning a 96-barcode run from either table is reading wrong
defaults for the two parameters that matter most to it.

### Fix, 2026-10-27 (F12, F14 and F19)

Checked against git history first: `max_classification_forks` has held `4` and
`kraken2_enable_incremental` `false` since each was introduced, and
`kraken2_sync_interval` has never existed in `nextflow.config` or the schema.
So none of the three was a stale-but-once-true default; all three were simply
wrong, which is why the release note was corrected rather than left as a
record of its own time.

- `docs/user/realtime_processing.md` and `docs/releases/CURRENT_VERSION.md`
  now give the real defaults, mark `max_concurrent_batches` advisory, name
  `report_write_interval` as the knob `kraken2_sync_interval` was invented for,
  and state that raising `max_classification_forks` past `max_cpus / 4` is
  inert (F6).
- `docs/releases/v1.5.0.md` is corrected in place with a dated note saying what
  was wrong and that none of it was a later change, since an operator tuning a
  high-barcode run from that table would have set two parameters to values they
  never had and one that does not exist.
- F14: `CLAUDE.md` and `docs/integration/output_api.md` no longer show a
  per-sample `index.json` or cumulative `taxid_counts.json`. The trees now
  match what the modules publish, including the two byte-identical copies of
  each batch report -- `batch_<N>.kraken2.report.txt` from the merger and
  `{sample}_batch<N>.kraken2.report.txt` from the report generator -- which is
  the shape nanometa*live's `_deduplicate_batch_files` exists to handle, and
  `stats/batch*<N>\_taxid_counts.json` as a per-batch file rather than
  cumulative state. The two "Key Development Patterns" snippets that showed an
  atomic index update and a cumulative taxid state file now say where that
  accumulation actually lives: the classification subworkflow's head process,
  in memory, not a module.
- F19: the `fair` comment in `conf/modules.config` no longer claims the
  directive gave FIFO scheduling and a better page-cache hit rate. `fair`
  controls output emission order, not scheduling, so removing it changed
  nothing about which batch runs when.

Documentation only; no pipeline behaviour changes in this pass.

## F13. The configuration a field run uses is not tested

`read` - severity: high (process)

- **No realtime fixture exceeds 3 barcodes.** `tests/fixtures/barcode_structure`
  has barcode01, barcode02 and unclassified; `minknow_output` and
  `flat_multisample` have 2.
- **No test at any level asserts cross-barcode first-result order with a
  backlog.** `tests/lib/batch_utils.nf.test` and
  `tests/lib/cross_batch_interleaver.nf.test` are pure-function tests topping
  out at **2 barcodes**, and neither has a flat-multi-sample case - so F1 is
  invisible to them. `tests/lib/batch_chunk_planner.nf.test:60-82` does assert
  cross-sample chunk ordering for 3 samples, but against the batch-mode planner
  that the real-time path never reaches (F7).
- **The only 12/24-plex tests are batch mode**, stubbed, with
  `skip_kraken2 = true`, asserting task counts only
  (`tests/multiplex_scaling.nf.test:43-96`).
- **`enable_realtime_stats` defaults to `true` and `conf/production.config:32`
  sets it true, but every realtime test that exercises classification sets it
  `false`** (`realtime_classification.nf.test:48,103`,
  `realtime_input_modes.nf.test:37,71`,
  `realtime_timeout_exit_regression.nf.test:58,100`). The one test that enables
  it sets `skip_kraken2 = true` (`realtime_statistics_modules.nf.test:32-33`).
  The default production combination is never run.
- The one realtime test in CI (`realtime_validation_e2e.nf.test`, macOS job)
  uses `max_files = 1`, so it exercises a single batch.

No test would have caught F1, F2 or F13 itself.

### The mechanism, and a guard, 2026-10-27

Chasing F13 to its cause: `.github/workflows/nf-test.yml` runs an **explicit
allowlist** of test files. A newly added test file is therefore silent by
default -- committed, never executed, and nothing saying so. Counted on this
branch, **41 of the 101 `*.nf.test` files were referenced nowhere in CI.**

Two of them were pure-function suites excluded only because their filenames
begin with `realtime`: `tests/lib/realtime_intake.nf.test` and
`tests/lib/realtime_resume.nf.test` touch no `watchPath`, need no container,
and cover the start-up intake and the Continue ledger -- the two mechanisms
most load-bearing for a late start. The exclusion was about their names, not
their behaviour.

Six pure-function suites were verified by replaying their assertions against
the real `lib/` classes and added to the allowlist, taking CI from 60 to 66
test files: `batch_utils_sample_key`, `cumulative_batch_accumulator`,
`kreport_tree`, `realtime_intake`, `realtime_resume` and
`snapshot_accumulator_kraken_key`.

`tests/lib/tests_are_wired.py` now runs in CI before the suite and fails when a
test file is neither in the allowlist nor in `tests/ci_excluded_tests.txt` with
a reason code (`watchpath`, `nf-core` or `unverified`). It also fails on a
stale exclusion, on a path both excluded and referenced, and -- like its
sibling `fixtures_are_tracked.py` -- when it finds nothing to check, since an
empty scan is a broken scan rather than a clean bill of health. The 35 that
remain excluded are now 8 `watchpath`, 22 `nf-core` and **5 `unverified`**,
that last code meaning no reason to skip them has ever been established.

Two defects surfaced during that verification:

- `tests/lib/batch_utils_sample_key.nf.test`, added in the F1 fix the day
  before, declared `input[0]` for a harness function that takes no parameter,
  so nf-test would have called it with a stray argument. It was in no CI job,
  so nothing would have reported it. Fixed by having the harness take the path.
- `tests/lib/snapshot_accumulator_functions.nf` returned GStrings, which
  Groovy's `==` treats as equal to a String while `List.contains` does not, so
  two assertion styles disagreed about one value. The harness now returns plain
  Strings. Whether real nf-test hid this by serializing `function.result` was
  not determined, so treat that one as defensive rather than a fixed failure.

## Lower-severity items

- **F14 (documentation).** `CLAUDE.md`'s real-time output tree lists
  `index.json` and `taxid_counts.json` per sample. Neither is written by any
  module: the only state file is `batch_taxid_counts.json`, produced in the
  report generator's work directory
  (`modules/local/kraken2_report_generator/main.nf:108`) and published as
  `stats/batch_<id>_taxid_counts.json` (`conf/modules.config:420-424`).
  `docs/integration/output_api.md:16,65` carries the same stale names. The
  modules are genuinely stateless, which is better than documented - there is
  no persistent read-modify-write to race - but a consumer written against the
  documented paths reads nothing. nanometa_live reads the per-batch `stats/`
  path and is unaffected.
- **F15.** CHOPPER (`conf/modules.config:145-154`) and FASTP_STREAMING
  (`:130-134`) publish flat per-barcode filenames with no `batch_time`/`batch_id`
  stamp, so the published QC output for each barcode is the last file only.
  SEQKIT_STATS was already fixed for exactly this (`:88-99`). Channel-side it is
  harmless; the loss is in the results tree.
- **F16.** `EMIT_EMPTY_KRAKEN2_REPORT` runs per file, not per sample
  (`taxonomic_classification/main.nf:104-114,714`), is `process_single`
  (1 CPU, 6 GB) with no `maxForks`, and republishes one flat path per barcode
  (`conf/modules.config:259-268`). A run where many barcodes yield empty
  post-QC FASTQs spawns one 6 GB-reserving task per file. The branch also calls
  `exists()` and `size()` per file on the head-process thread.
- **F17 (robustness, not a live bug).** `taxonomic_classification/main.nf:167`
  assigns `ch_db_ready = KRAKEN2_DB_PRELOAD.out.db` with no `.first()`, while
  `:33` warns that this input must be a value channel. It is safe today because
  both call sites pass a value channel (`workflows/nanometanf.nf:452,465`) and
  a process invoked with only value-channel inputs emits value channels. Adding
  `.first()` is free and removes a silent one-task-per-session failure mode
  that currently depends on an implicit language rule.
- **F18 (operator trap).** A late start's backlog is old by definition. If
  `max_file_age_minutes` is set - the dashboard exposes it as "skip pre-existing
  files older than" - the whole backlog is excluded at
  `RealtimeIntake.excludedReason`, announced in one log line. The default is
  `null`, so this bites only a configured run, but it is the first thing to
  check when a late-started run shows almost nothing.
- **F19 (comment is wrong).** `conf/modules.config:340` says _"Removed
  fair=true: FIFO scheduling keeps same-sample batches together, improving OS
  page cache hit rate"_. `fair` controls output **emission** order, not
  scheduling, so removing it changed nothing about which task runs when. Worth
  correcting so nobody tunes on it.

---

## What an operator can do today, without a code change

Ordered by expected effect on a 96-barcode late start:

1. **Set `--kraken2_task_memory_gb`** to a few GB (F5). Nothing sets it, and
   with memory mapping on it is what stops the forks reserving the whole
   database each.
2. **Raise `--max_cpus` whenever raising `--max_classification_forks`** (F6).
   Forks alone stop helping above `max_cpus / 4`.
3. **Use a per-barcode directory layout** (`barcodeNN/` subdirectories) rather
   than a flat directory with barcodes in filenames (F1). This is the
   difference between 24 and 461 files to first-light across 24 barcodes.
4. **Set `--skip_nanoplot true`, or raise `--nanoplot_batch_interval`,** for the
   first pass of a large backlog (F2). It does not remove the index-0 burst, but
   it removes the repeat milestones behind it.
5. **Avoid `--qc_tool fastp`** on a memory-limited host (F4); one
   FASTP_STREAMING task saturates a 16 GB ceiling.
6. **Set `--realtime_timeout_minutes` and/or `--max_files`** so the session can
   close and the canonical tier, manifest and MultiQC are produced at all (F8).
7. **Collect evidence with `--runtime_metrics_interval_seconds 60`** before
   tuning further; F9 is the one ceiling that cannot be sized from source.

## Recommended fixes, ordered by value per unit of risk

| #   | Fix                                                                                                                                                                                                                                                                 | Addresses                 | Risk                                                                                                                                                                                                                                                                   |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | ~~Key both interleavers on the resolved sample id instead of `parent.name`~~ **done 2026-10-27**                                                                                                                                                                    | F1                        | Low; measured a no-op for per-barcode-directory layouts                                                                                                                                                                                                                |
| 2   | Add a realtime fixture with >= 12 barcodes and a test asserting first-result order across them                                                                                                                                                                      | F13                       | None; it is new coverage. Partly done 2026-10-27: the 12-sample first-round assertion is a pure-function test, and `tests_are_wired.py` now stops a test file going unrun, but the pipeline-level fixture is still missing and a watchPath test still cannot run in CI |
| 3   | ~~Give SEQKIT_STATS and FASTP_STREAMING `withName` resource overrides matching their real cost~~ **done 2026-10-27**                                                                                                                                                | F4                        | Low; set in `base.config` so profiles still override, and the profiles now cover `FASTP_STREAMING` too                                                                                                                                                                 |
| 4   | ~~Give NANOPLOT a `maxForks`~~ **done 2026-10-27** as `max_nanoplot_forks`. The index-0 deferral in the original wording was rejected: it would silently drop NanoPlot for any barcode that receives one file all run                                               | F2                        | Low                                                                                                                                                                                                                                                                    |
| 5   | ~~Default `kraken2_task_memory_gb` in the platform profiles~~ **done 2026-10-27** at 2 GB, measured: the marginal per fork is ~50 MB + 25 MB/thread and flat across a 13x larger index. `promethion_8` goes 3 forks to 4; `minion` goes from 0 GB free for QC to 62 | F5                        | Medium; measured first, and scoped to local-executor profiles only                                                                                                                                                                                                     |
| 6   | ~~Replace the `Thread.sleep(10000)` with the daemon-Timer idiom used elsewhere in the same file~~ **done 2026-10-27**                                                                                                                                               | F11                       | Low                                                                                                                                                                                                                                                                    |
| 7   | ~~Reset the `batch_timeout` timer on each flush~~ **withdrawn 2026-10-27**: measured worse on both mean and maximum wait. The docstring was corrected instead                                                                                                       | F10                       | -                                                                                                                                                                                                                                                                      |
| 8   | ~~Correct `max_concurrent_batches`, `index.json`/`taxid_counts.json` and the `fair` comment in the docs~~ **done 2026-10-27**, plus three wrong defaults and one parameter that never existed                                                                       | F12, F14, F19             | None                                                                                                                                                                                                                                                                   |
| 9   | ~~Extend real-time with the chunking...for the start-up backlog only~~ **chunking done 2026-10-27** as `realtime_backlog_chunking`, measured 4 files -> 3 tasks with a control case. Per-sample QC grouping in real time is still open                              | F7, and the root of F2/F3 | High; the live stream was deliberately left untouched                                                                                                                                                                                                                  |

Item 9 is the structural answer to the question this audit was asked. Items
1-4 are the ones that change a late-started 96-barcode run most for the least
risk; items 1, 3, 4, 5, 6, 8 and the chunking half of 9 are done, and item 7 was withdrawn on measurement.
