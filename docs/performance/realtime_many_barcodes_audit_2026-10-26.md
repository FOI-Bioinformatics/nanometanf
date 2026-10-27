# Real-time capacity audit: many barcodes, fast-arriving data, late start

**Date:** 2026-10-26
**Branch audited:** `claude/nanometanf-realtime-capacity-audit-ym5hhz` at `5faa8dc` (v1.11.0)
**Question:** can a real-time run keep up with a fast producer across 24-96
barcodes without stalling, and without showing only one sample at first,
particularly when the run is started *after* sequencing began so a large
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
   `InputDetector.extractSampleId` derives the sample from the *filename* in
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

| Layout | Samples / parent dirs | Files before every sample has one result | Distinct samples in first 10 files |
|---|---|---|---|
| `fastq_pass/barcodeNN/reads_F.fastq.gz` | 24 / 24 | **24** of 480 | **10** |
| `fastq_pass/barcodeNN_F.fastq.gz` | 24 / 1 | **461** of 480 | **1** |

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

| Layout | Files before every sample has one result | Samples in first 10 files |
|---|---|---|
| `barcodeNN/` subdirectories | 24, was 24 | 10, was 10 |
| flat, barcode in filename | **24, was 461** | **10, was 1** |

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
file of *every* barcode is a NanoPlot milestone.

At a late start the backlog delivers the first file of all 96 barcodes within
the opening seconds, so 96 NanoPlot tasks become runnable at the same moment as
each barcode's first classification. NanoPlot reserves 2 CPUs and 8 GB
(`conf/modules.config:470,477`) with **no `maxForks`**.

`conf/modules.config:471-476` records that this is the cost the 2026-09-07
time-to-first-result work removed: *"the four reserved CPUs were the cost, not
the runtime - on an 11-CPU host they were taken from the classifier while
samples were still waiting for their first report"*. That fix reduced NanoPlot
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
*running* at once; it does not reduce how many become *runnable*, and it does
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

| Process | Label | Reserves | Source |
|---|---|---|---|
| SEQKIT_STATS | `process_low` | 2 CPU, **12 GB** | `modules/nf-core/seqkit/stats/main.nf:3`, `conf/base.config:50-54` |
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

| | SEQKIT_STATS | FASTP_STREAMING |
|---|---|---|
| no profile, before | 2 CPU / 12 GB | 6 CPU / 36 GB, clamped to 16 GB |
| no profile, after | 1 CPU / 2 GB | 4 CPU / 8 GB |
| `-profile field`, before | 1 CPU / 1 GB | 6 CPU / 36 GB, clamped |
| `-profile field`, after | 1 CPU / 1 GB | 2 CPU / 2 GB |

`conf/modules.config` sets no resources for either process, so nothing above
is shadowed.

This is reservation arithmetic, not a measured speedup, and it is what
schedules rather than what runs. On the audit's reference 11-CPU / 18 GB
laptop with no profile it is the difference between one concurrent QC task and
two, and between CHOPPER plus SEQKIT_STATS being co-schedulable (8 + 2 GB) and
not (8 + 12 GB against 18 GB physical). The 1-in-10 NanoPlot burst (F2) and
the classifier's own reservation (F5) are untouched by it.

## F5. With memory mapping on, every fork still reserves the whole database
`read` - severity: high

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
(*"6 forks with mmap: ~8GB shared db + 6x2GB overhead"*); the reservation
actually requested is 6 x 32 GB. On a memory-capped executor this silently
holds effective concurrency below `max_classification_forks`.

**This is the single highest-leverage operator knob today, and nothing sets
it.** Passing `--kraken2_task_memory_gb` (a few GB above the per-task private
footprint) restores the parallelism the profiles were sized for.

## F6. Raising `max_classification_forks` past `max_cpus / 4` buys nothing
`read` - severity: medium

`conf/modules.config:336`:

```groovy
cpus = { Math.max(4, ((params.max_cpus ?: 16) as int).intdiv(Math.max(1, (params.max_classification_forks ?: 1) as int))) }
```

The **floor of 4** means the per-task CPU request stops shrinking once forks
exceed `max_cpus / 4`. With the default `max_cpus = 16`, forks above 4 request
more total CPU than exists and the local executor admits 4 regardless.

`realtime_monitoring/main.nf:50-54` advises operators to *"raise
`max_classification_forks` proportionally to the number of barcodes - e.g. on a
24-plex run set forks to at least 6"*. That advice is incomplete: without
raising `--max_cpus` in the same proportion it has no effect. The log line and
the docs should say so.

## F7. A late start gets none of batch mode's mitigations
`read` - severity: high

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

nanometa_live's `CLAUDE.md` already names real-time chunking as *"a candidate
for a later plan"*. This audit is the argument for it: the late-start case is
not an edge case, it is how a field run begins whenever the operator opens the
dashboard after sequencing has started.

## F8. The canonical tier waits for the slowest barcode
`read` - severity: medium

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

## F9. Per-batch dashboard writes are serialised through one lock
`reasoned` - severity: medium

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

This is O(cumulative taxa) per batch per barcode on one thread. It is the most
likely **unmeasured** ceiling on a high-diversity 96-barcode run, and it cannot
be sized from source alone. `--runtime_metrics_interval_seconds` plus timing
around `:471-533` would settle it.

## F10. A trailing partial batch waits up to 60 s
`read` - severity: low

`lib/BatchUtils.groovy:99-109` schedules the flush timer with
`scheduleAtFixedRate` at a fixed period and **does not reset it on flush**, so
a buffer that never reaches `batch_size` waits for the next tick -
`batch_timeout = 60` s by default (`nextflow.config:43`). With 24 barcodes and
`batch_size = 10` the backlog cuts into 10 + 10 + 4, and the 4 remainder
barcodes pay a minute before their first file is even batched.

## F11. A 10-second sleep occupies a shared operator thread during the backlog
`reasoned` - severity: low

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

**Fix shape:** replace the sleep with the daemon-`Timer`-binding-into-a-queue
idiom already used twice in the same file (`:337-367`, `:107-112`).

## F12. `max_concurrent_batches` is dead config
`read` - severity: low (documentation)

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

| Doc claim | Actual |
|---|---|
| `--max_classification_forks` default `8` (`realtime_processing.md:596`, `v1.5.0.md:90`) | `4` (`nextflow.config:79`) |
| `--kraken2_enable_incremental` default `true` (`v1.5.0.md:88`) | `false` (`nextflow.config:68`) |
| `--kraken2_sync_interval` (`v1.5.0.md:91`) | **No such parameter.** Not in `nextflow.config`, the schema, or any module |

An operator tuning a 96-barcode run from either table is reading wrong
defaults for the two parameters that matter most to it.

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
- **F19 (comment is wrong).** `conf/modules.config:340` says *"Removed
  fair=true: FIFO scheduling keeps same-sample batches together, improving OS
  page cache hit rate"*. `fair` controls output **emission** order, not
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

| # | Fix | Addresses | Risk |
|---|---|---|---|
| 1 | ~~Key both interleavers on the resolved sample id instead of `parent.name`~~ **done 2026-10-27** | F1 | Low; measured a no-op for per-barcode-directory layouts |
| 2 | Add a realtime fixture with >= 12 barcodes and a test asserting first-result order across them | F13 | None; it is new coverage. Partly done 2026-10-27: the 12-sample first-round assertion is a pure-function test, and `tests_are_wired.py` now stops a test file going unrun, but the pipeline-level fixture is still missing and a watchPath test still cannot run in CI |
| 3 | ~~Give SEQKIT_STATS and FASTP_STREAMING `withName` resource overrides matching their real cost~~ **done 2026-10-27** | F4 | Low; set in `base.config` so profiles still override, and the profiles now cover `FASTP_STREAMING` too |
| 4 | ~~Give NANOPLOT a `maxForks`~~ **done 2026-10-27** as `max_nanoplot_forks`. The index-0 deferral in the original wording was rejected: it would silently drop NanoPlot for any barcode that receives one file all run | F2 | Low |
| 5 | Default `kraken2_task_memory_gb` in the platform profiles to match the arithmetic their comments already describe | F5 | Medium; it changes admitted concurrency on every run, so measure first |
| 6 | Replace the `Thread.sleep(10000)` with the daemon-Timer idiom used elsewhere in the same file | F11 | Low |
| 7 | Reset the `batch_timeout` timer on each flush | F10 | Low |
| 8 | Correct `max_concurrent_batches`, `index.json`/`taxid_counts.json` and the `fair` comment in the docs | F12, F14, F19 | None |
| 9 | Extend real-time with the chunking and per-sample QC grouping that batch mode already has, for the start-up backlog only | F7, and the root of F2/F3 | High; this is a design change and wants its own plan |

Item 9 is the structural answer to the question this audit was asked. Items
1-4 are the ones that change a late-started 96-barcode run most for the least
risk; items 1, 3 and 4 are done.
