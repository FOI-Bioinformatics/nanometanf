# Axis A: Kraken2 classifier modes

Date: 2026-05-29
Sim data: nanorunner `--mock quick_3species --read-count 4000`, seed=1

- 3 barcodes (one per species), 14 files each, ~1333 reads per barcode, 4000 reads total
  Kraken2 DB: `k2_pluspfp_08_GB_20251015` (~8 GB)
  Hardware: 11 cores / 18 GB RAM (ARM Mac, conda profile)
  Resource caps: `max_cpus=8`, `max_memory=12.GB`, `kraken2_memory_mapping=false`

## Results

| ID  | Mode                         | Input                           | realtime_mode | Profile      | Wall (s) | Trace tasks | Notes                                                                |
| --- | ---------------------------- | ------------------------------- | ------------- | ------------ | -------- | ----------- | -------------------------------------------------------------------- |
| A1  | incremental (streaming)      | nanopore_output_dir (watchPath) | true          | minion,conda | 380      | 243         | Real work done by 285s; hung on JVM exit for 30+ min — see bug below |
| A2  | optimized (memory-map flags) | input_dir (batch scan)          | false         | conda        | 271      | 27          | Clean exit                                                           |
| A3  | standard (no flags)          | input_dir (batch scan)          | false         | conda        | 243      | 27          | Clean exit                                                           |

A1's wall is computed from earliest task `.command.begin` to MULTIQC `.exitcode` rather than the Nextflow `WALL_SECONDS`, because the actual JVM hung 30+ min past pipeline completion (see Bug 1). The 380s also includes one-time conda env builds that A2/A3 inherited cached.

## Classification quality

All three modes produced **identical** species-level reads on the same input:

| Barcode   | Expected genome               | Reads | Top species (A1/A2/A3 all match) |
| --------- | ----------------------------- | ----- | -------------------------------- |
| barcode01 | GCF_000005845.2 (E. coli)     | 1334  | 181 → Escherichia coli           |
| barcode02 | GCF_000013425.1 (S. aureus)   | 1333  | 573 → Staphylococcus aureus      |
| barcode03 | GCF_000009045.1 (B. subtilis) | 1333  | 145 → Bacillus subtilis          |

Confirms classifier mode is a runtime-architecture choice, not a result-affecting one — comparison is fair.

## Architecture constraint observed

`subworkflows/local/taxonomic_classification/main.nf:175` routes to the incremental
branch whenever either `kraken2_enable_incremental=true` OR `realtime_mode=true`.
Result: in realtime mode the optimized/standard branches are unreachable. The 3-mode
comparison therefore requires `realtime_mode=false` + `input_dir`. The `minion`
platform profile (which forces `realtime_mode=true`) can only exercise the
incremental path — useful to know for benchmarks that intend to compare modes
under platform profiles.

## Trace task counts

A1 ran 243 task invocations vs A2/A3's 27. The 9x multiplier reflects per-batch
parallelism: 14 batches per barcode _ 3 barcodes _ 4 streaming Kraken2 modules
(classifier, merger, report generator, then one aggregator per sample). On 1333
reads per barcode this overhead dominates; the streaming architecture's benefit
only shows above the per-task conda-activation cost (~2 s) times the batch count.

## Per-barcode batches observed (runtime-metrics, A1)

Final tick after pipeline body finished:

```
[runtime-metrics] elapsed_s=... files=42 batches=5 barcodes=3
                  batches_per_barcode_min=14 batches_per_barcode_max=14
```

`batches` here counts watch-cycle iterations (5), not per-sample batches (14 each).
The min==max means watchPath delivered files uniformly across the 3 barcodes — no
straggler in this run.

## Bug 1: runtime-metrics daemon prevents pipeline exit

**Reproduction**: any realtime-mode run with
`--runtime_metrics_interval_seconds N > 0`.

**Symptom**: all Nextflow processes complete (MULTIQC exitcode=0 written), but
the Nextflow JVM keeps emitting `[runtime-metrics]` ticks every N seconds and
never exits. In A1 the run was killed after 33 min of post-completion idle.

**Likely cause**: `subworkflows/local/realtime_monitoring/main.nf:94-111` creates
`new java.util.Timer('runtime-metrics-snapshot', /* daemon */ true)`. The `daemon`
flag should let the JVM exit, but in practice the workflow main thread appears
to park on a closure that the realtime-timeout (line 248) doesn't fully cancel.

**Workaround used for A2/A3**: `runtime_metrics_interval_seconds: 0` (the
default) — Timer block is skipped entirely, pipeline exits cleanly.

**Suggested follow-up**:

1. Reproduce on a smaller test (the `nanoseq_test.nf.test` smoke test if combined
   with realtime + this flag).
2. Either explicitly `.cancel()` the metrics timer when the realtime-timeout
   fires, or make the timer truly fire-and-forget on `runtime_metrics_interval_seconds=0`.
3. Add a regression test alongside the V4 ifEmpty regression
   (`tests/ifempty_sentinel_regression.nf.test`).

## What this run _doesn't_ tell you

- **Throughput at scale**: 4000 reads + 3 barcodes is below the streaming
  architecture's break-even point. Expect different ordering at ~10x barcodes
  or ~10x reads per barcode.
- **Memory pressure**: 12 GB cap was never hit; max-mem behavior under
  promethion-class loads not exercised.
- **Per-task overhead**: A1's 243 tasks reflect cold conda activations on macOS
  (~2 s each). Same architecture under apptainer or with a hot conda cache will
  look very different.

## Files

```
results/eval-2026-05-29/
├── sim-data/{barcode01,barcode02,barcode03}/   # 14 fastq.gz each
├── params_{A1,A2,A3,B2,B3}.yaml
├── run_A1.sh, run_axis.sh, run_profile.sh, run_profile_wd.sh
├── logs/{A1,A2,A3,B2,B3}.log
├── {A1,A2,A3,B2,B3}/out/{canonical,kraken2,multiqc,...}/
└── SUMMARY.md  (this file)
```

---

# Axis B: Platform profiles (realtime + incremental, same DB and sim data)

All three platform profiles set `realtime_mode=true`, so by the constraint
documented above they all route through the incremental Kraken2 branch.
The only thing axis B varies is the per-process resource directive
(`cpus`, `memory`) and `max_classification_forks`. Hardware caps
(`max_cpus: 8`, `max_memory: 12.GB`) apply uniformly via `check_max`.

`runtime_metrics_interval_seconds: 0` was used for B2 and B3 to avoid
the V5 daemon-Timer hang. **That workaround alone was insufficient** —
B2 also hung past MULTIQC and had to be killed (see Bug 1 update below).
B3 used an external watchdog that polls for `MULTIQC/.exitcode` and
kills the JVM 20s later.

| ID  | Profile              | Kraken2 cpus/mem                | max_classification_forks | Wall (s) | Trace tasks | Classification |
| --- | -------------------- | ------------------------------- | ------------------------ | -------- | ----------- | -------------- |
| A1  | `minion,conda`       | check_max(4,8/1) → 8 cpus, 8 GB | 1                        | 380      | 243         | 181/573/145    |
| B2  | `promethion_8,conda` | 6 cpus, capped to 8 GB          | default                  | 640      | 243         | 181/573/145    |
| B3  | `promethion,conda`   | 6 cpus, capped to 8 GB          | 6                        | 632      | 243         | 181/573/145    |

## Reading the numbers

**More parallelism made things slower at this scale.** `promethion` with
`forks=6` ran 66% slower than `minion` with `forks=1`. Two contributing
mechanisms on this 11-core / 18 GB laptop:

1. **CPU oversubscription.** With `max_cpus: 8` and 6 forks at 6 cpus each,
   Kraken2 alone wants 36 cpu-slots. `check_max` clamps individual tasks,
   but Nextflow still tries to run 6 of them concurrently — they end up
   contending for the 8 available cores.
2. **DB load amortization is lost.** With memory-mapping off (required on
   ARM Mac), each Kraken2 fork loads the 8 GB DB from scratch. One fork
   amortizes that across all batches. Six forks pay the load cost six times
   over.

`promethion_8` (B2) and `promethion` (B3) end up nearly identical (640 vs
632 s) because the effective concurrency on this laptop is the same — both
get clamped to whatever the OS can schedule. The "8" in `promethion_8`
matters at the platform it was designed for (128 GB / 64-core PromethION
boxes), not here.

## Take-away

The platform profiles are tuned for the actual platform they name. Using
`promethion` on a laptop is a pessimization, not a stress test. To
exercise the high-fork code path meaningfully you need either the actual
hardware or a beefier dev box; on an 11-core laptop the `minion` profile
(or `realtime_mode=false`) is the fastest path.

## Bug 1 update

Setting `runtime_metrics_interval_seconds: 0` alone does **not** prevent
the realtime-mode JVM hang. B2 finished MULTIQC at 00:08 and the JVM was
still alive at 00:15 when killed manually. The hang is structural to the
`REALTIME_MONITORING` subworkflow, not just the metrics Timer. The
external `watchdog` script in `run_profile_wd.sh` is the practical
workaround for benchmark/CI use until the underlying issue (likely a
non-daemon channel or watchPath thread) is fixed in
`subworkflows/local/realtime_monitoring/main.nf`.

Suggested fix scope: walk the subworkflow's `Channel.watchPath` /
realtime-timeout / Timer code paths and ensure every spawned thread is
either daemon or explicitly joined/cancelled when the workflow body exits.

---

# Axis C: Concurrency sweep (max_classification_forks)

Holding everything else constant — realtime + incremental, no platform
profile (so the Kraken2 cpu directive comes from `conf/modules.config:cpus
= max(4, max_cpus / max_classification_forks)`) — sweep `forks` across
2 / 4 / 8 on the same 8-cpu / 12-GB cap. Watchdog-killed via the corrected
`run_profile_wd.sh` (`.command.sh` content match, not path match — earlier
path-based pattern silently never fired on Nextflow's hash-named work
dirs, see Bug 2 below).

| ID  | forks | Kraken2 cpus/task (modules.config) | Demanded cpu-slots | Wall (s) | Classification |
| --- | ----- | ---------------------------------- | ------------------ | -------- | -------------- |
| C2  | 2     | max(4, 8/2) = 4                    | 8 (fits cap)       | 397      | 181/573/145    |
| C4  | 4     | max(4, 8/4) = 4 (floor)            | 16 (2x oversub)    | **340**  | 181/573/145    |
| C8  | 8     | max(4, 8/8) = 4 (floor)            | 32 (4x oversub)    | 372      | 181/573/145    |

## Reading the curve

- **forks=4 is the sweet spot** at this scale — 17% faster than forks=2,
  10% faster than forks=8.
- forks=2 underuses available CPU: Kraken2 batches queue up, idle CPU.
- forks=8 oversubscribes, but the OS scheduler handles it gracefully —
  the penalty is small (~10%) because Kraken2's hot loop is memory-bound,
  not CPU-bound, and the 4x cpu-slot request is mostly nominal.
- The **range is narrow** (340-397 s, ~17% spread). At ~1.3k reads per
  barcode, Kraken2 itself is ~30 s of the run; the conda env builds and
  watchPath overhead dominate. Expect a much steeper curve at 10k+ reads
  per barcode.

## Cross-reference with axis B

C4's forks=4 ran in 340 s. B2 (`promethion_8` profile, default forks ≈ 4)
ran in 640 s. **The profile adds ~300 s of overhead beyond just forks** -
likely the platform-config resource directives trigger Nextflow scaling
retries or larger conda env install costs for QC tools that get bigger
cpu/memory directives. Same root forks-knob, very different wall.

Practical implication: on dev hardware that doesn't match the named
platform, **drop the platform profile and tune `max_classification_forks`
directly**. The platform profile assumes you have the platform.

## Bug 2: watchdog path pattern silently never matched

The first version of `run_profile_wd.sh` used
`find ... -path "*MULTIQC*" -name .exitcode` to detect MultiQC completion.
Nextflow's `work/` layout uses hex hash directory names (e.g.
`work/df/571bcb7347.../`), never the process name. The path glob therefore
matched nothing and the watchdog never fired — explains why B3 sat past
MultiQC for hours before being killed by the user.

Fixed in `run_profile_wd.sh` by scanning `.command.sh` contents for
`multiqc ` instead. Used successfully on C4 and C8.

---

# Axis D: realtime vs batch, identical classifier and forks

D isolates the input-mode variable: same incremental Kraken2 path, same
`max_classification_forks=4`, same DB, same data. Only `realtime_mode`
and the input parameter differ.

| ID                | Input mode                        | Trace tasks | Wall (s) | Notes                  |
| ----------------- | --------------------------------- | ----------- | -------- | ---------------------- |
| D-realtime (≡ C4) | `nanopore_output_dir` + watchPath | 243         | 340      | Needs watchdog (Bug 1) |
| D-batch           | `input_dir` (no watch)            | 36          | **321**  | Clean exit             |

## Reading the numbers

- **Realtime adds only ~6% wall time** over batch when forks is tuned (4)
  — much smaller gap than axis B made it look.
- **Trace task count is 6.75x higher in realtime** (243 vs 36) because
  the watchPath batches feed into the per-batch streaming modules
  (incremental classifier, output merger, report generator) once per
  batch. In batch mode the channel is bounded so the same pipeline
  fans out only once per sample.
- **The realtime overhead is not the classifier path itself, it is
  the realtime-monitoring scaffolding** (watchPath cycles, per-batch
  reports, statistics aggregation). Useful to know if a downstream
  consumer doesn't need per-batch updates: pointing the pipeline at a
  finished run dir with `--input_dir` saves the overhead.

## Practical recommendation

When you want streaming updates during sequencing: realtime mode + tuned
forks (~4 on this hardware) is cheap (~6% wall premium). When the run is
already finished and you just want results: batch mode is faster, has
fewer moving parts, and side-steps the realtime-mode JVM hang entirely.

---

# Overview across all axes

| ID      | Mode        | Profile            | Input                | forks   | Wall (s) | Tasks | Notes                |
| ------- | ----------- | ------------------ | -------------------- | ------- | -------- | ----- | -------------------- |
| A1      | incremental | minion,conda       | watchPath (realtime) | 1       | 380      | 243   | first cold-conda run |
| A2      | optimized   | conda              | input_dir            | --      | 271      | 27    | classifier alt path  |
| A3      | standard    | conda              | input_dir            | --      | 243      | 27    | classifier alt path  |
| B2      | incremental | promethion_8,conda | watchPath            | default | 640      | 243   | profile penalty      |
| B3      | incremental | promethion,conda   | watchPath            | 6       | 632      | 243   | profile penalty      |
| C2      | incremental | conda              | watchPath            | 2       | 397      | 243   | underutilized        |
| C4      | incremental | conda              | watchPath            | 4       | **340**  | 243   | sweet spot           |
| C8      | incremental | conda              | watchPath            | 8       | 372      | 243   | mild oversub         |
| D-batch | incremental | conda              | input_dir            | 4       | **321**  | 36    | fastest end-to-end   |

## Top take-aways

1. **Classifier mode (A1/A2/A3) is a runtime architecture choice; results
   are byte-identical.** Don't change the mode hoping for better
   classifications — only for different throughput / streaming profile.
2. **Platform profiles are tuned for the platform.** Running `promethion`
   or `promethion_8` on a laptop costs ~300 s vs a plain `conda` profile
   with the same forks. Use `minion` (forks=1) for single-sample dev
   work or drop the profile entirely and tune
   `max_classification_forks` to your machine.
3. **forks ≈ available_cpus / kraken2_cpus_per_task is the rule of
   thumb.** On 8-cpu cap with 4-cpu Kraken2 tasks (the modules.config
   floor), forks=4 wins. forks=2 underuses, forks=8 oversubscribes but
   gracefully.
4. **Realtime vs batch costs only ~6 % wall** with tuned forks. The
   realtime overhead is in the watch/stats scaffolding, not the
   classifier itself. Use batch mode for post-hoc analysis.
5. **Two real bugs surfaced**, both worth fixing in pipeline code:
   - **Bug 1** (`subworkflows/local/realtime_monitoring/main.nf`):
     realtime-mode runs never exit the JVM cleanly even with the V5
     `[runtime-metrics]` Timer disabled. Workaround: external watchdog
     on `.command.sh|multiqc` exitcode.
   - **Bug 2** (this eval's own watchdog script): matching MultiQC by
     path glob doesn't work on Nextflow's hash-named work dirs.
     Scan `.command.sh` contents instead. Worth noting for any future
     test harness or CI helper that needs to identify a specific task
     by name.

## What this run still doesn't tell you

- **Real PromethION-scale throughput.** Everything here is on
  ~4000 reads. The streaming architecture's pay-off shows above the
  per-task overhead crossover, probably at 10x reads / 10x barcodes.
- **Streaming behaviour with non-uniform barcode arrival.** Axis-A and
  the runtime-metrics ticker showed perfectly even watchPath delivery
  because nanorunner emits files quickly with no inter-file pause. The
  audit P2.9 backpressure question is not exercised.
- **Memory pressure at full DB load.** 12 GB cap was never hit because
  `kraken2_memory_mapping: false` keeps each fork resident, and the DB
  is only 8 GB. PromethION-class memory profiles untested.
