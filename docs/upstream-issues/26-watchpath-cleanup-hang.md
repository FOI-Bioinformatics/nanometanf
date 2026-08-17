# Upstream issue: watchPath cleanup leaves a non-daemon FileAlterationMonitor thread

> **Status: resolved in Nextflow 26.04.0.** Verification on 2026-05-10
> ran the realtime nf-test against the real Kraken2 DB under
> Nextflow 26.04.0 and the JVM exited cleanly through the failure
> path in 55 s (no leaked thread). The `NXF_VER=25.04.7` workaround
> pin in `bin/run-nf-tests.sh` and `.github/workflows/nf-test.yml`
> has been removed; `nextflow.config` floor is now `>=26.04.0`.
>
> **Not resolved on the GitHub Actions ubuntu runner.** The 2026-05-10
> verification was on macOS/arm64 only. On the runner image the monitor
> thread still leaks and the job runs past the 45 min cap, so
> `.github/workflows/nf-test.yml` continues to exclude every
> `tests/realtime_*.nf.test` case from the ubuntu test job. Since
> 2026-08-17 the realtime + validation e2e (tag `real_execution`,
> `tests/realtime_validation_e2e.nf.test`) runs in CI on a macOS/arm64
> runner (the `realtime-e2e` job), where clean JVM exit is verified; the
> rest of the realtime suite remains a local development run. Treat
> "resolved" as platform-specific: the ubuntu exclusion stands until a
> green realtime run exists on that runner image.
>
> Re-verified 2026-07-29 on macOS/arm64, Nextflow 26.04.0: the manual test
> `subworkflows/local/taxonomic_classification/tests/realtime_cumulative_emit.nf.test`
> was run against a real Kraken2 database (8 GB PlusPFP) with live watchPath,
> `max_files=2`, `realtime_timeout_minutes=1`. It completed and exited cleanly
> in 235 s. That is a second independent data point for macOS; the GitHub
> runner behaviour above is unchanged and still the reason CI excludes the
> realtime suite.
>
> The historical issue text below is retained for context.

This document holds the issue text we want to file against
[nextflow-io/nextflow](https://github.com/nextflow-io/nextflow). Filing
the issue itself is a manual user action (the local workflow does not
have authorisation to open GitHub issues). Once filed, please update
`CHANGELOG.md` and `nf-test.config` with the issue URL.

Tracking ID locally: task #26.

---

## Title

watchPath does not release the Apache commons-io FileAlterationMonitor
non-daemon thread, blocking JVM shutdown after the channel completes

## Affected versions

| Component | Version                              |
| --------- | ------------------------------------ |
| Nextflow  | 25.04.7 and 25.10.4 (both reproduce) |
| nf-test   | 0.9.4                                |
| JVM       | OpenJDK 17.0.14+7-LTS                |
| Platform  | macOS Darwin 25.2.0 (Apple Silicon)  |

## Summary

When a `watchPath`-backed dataflow channel is terminated by either
`take(n)` or by a sentinel-driven `until { ... }` operator, the
underlying `org.apache.commons.io.monitor.FileAlterationMonitor`
thread is not interrupted. The thread is created with
`setDaemon(false)` (the commons-io default), so the JVM cannot exit
even after the workflow's main thread has reached
`Session.await > all barriers passed`. Operators that wait for the
JVM to exit (notably `nf-test`, but also CI runners using `timeout`)
hang until they are killed externally.

## Reproducer

The hang reproduces in the
[nanometanf](https://github.com/FOI-Bioinformatics/nanometanf)
real-time monitoring subworkflow, which lifts a `watchPath` channel
into the pipeline. A self-contained nf-test case lives at
`subworkflows/local/realtime_monitoring/tests/main.nf.test` under
the test name **"Should accept both realtime_timeout_minutes and
max_files (Task #10 regression)"** (tagged `task10`).

The relevant inputs:

```
input[0] = '$projectDir/tests/fixtures/watch_dirs/fastq'   // 1 file present
input[1] = '**/*.fastq{,.gz}'                              // pattern
input[2] = 1                                               // batch_size
input[3] = '30.sec'                                        // batch_interval

params.realtime_mode             = true
params.realtime_timeout_minutes  = 60
params.max_files                 = 1
```

Pipeline body (simplified):

```nextflow
def total_timeout_ms = (params.realtime_timeout_minutes as long) * 60 * 1000
def sentinel = Channel.fromTimer(total_timeout_ms)        // emits one tick

Channel
    .watchPath(watch_dir, 'create,modify')
    .filter { matches(file_pattern) }
    .until { it == SENTINEL }
    .take(params.max_files)
    .set { ch_files }
```

With `max_files = 1` and one file already present, `take(1)` fires
on the first emission and the merged channel signals completion.
Nextflow logs `Session await > all barriers passed`. The JVM does
not exit.

To reproduce locally (from a clone of the nanometanf repository):

```bash
conda activate nf-core
NXF_VER=25.04.7 NXF_OFFLINE=true \
  nf-test test \
  subworkflows/local/realtime_monitoring/tests/main.nf.test \
  --profile conda --tag task10
```

The test never returns; the wrapping shell `timeout` is required to
recover. The same reproducer behaves identically under
`NXF_VER=25.10.4`.

## Diagnostic evidence

`nextflow.log` records the workflow reaching its terminal state:

```
INFO  nextflow.Nextflow - Found 1 existing files - will process immediately
INFO  nextflow.Nextflow -   - sample3.fastq
DEBUG nextflow.file.DirWatcherV2 - Watch service for path=...; pattern=**/*.fastq{,.gz}; ...
INFO  nextflow.Nextflow - Real-time timeout enabled: stop after 60 minutes (idle) plus 5 minute grace period
INFO  nextflow.Nextflow - Total wall-clock budget: 3900000 ms
INFO  nextflow.Nextflow - Max files limit: 1
DEBUG nextflow.script.ScriptRunner - > Awaiting termination
DEBUG nextflow.Session - Session await
DEBUG nextflow.Session - Session await > all processes finished
DEBUG nextflow.Session - Session await > all barriers passed
```

After the last line is written the JVM stays alive indefinitely.

`jstack` of the live JVM (captured from the Nextflow process roughly
five minutes after the workflow logically completes; full dump in
the appendix) shows two non-daemon threads still running:

```
"main" #1 prio=5 ... waiting on condition
   java.lang.Thread.State: WAITING (parking)
        at java.util.concurrent.locks.LockSupport.park(LockSupport.java:341)
        at groovyx.gpars.dataflow.expression.DataflowExpression.getVal(DataflowExpression.java:261)
        at groovyx.gpars.actor.Actor.join(Actor.java:213)
        at groovyx.gpars.dataflow.operator.DataflowProcessor.join(DataflowProcessor.java:164)
        at nextflow.Session.joinAllOperators(Session.groovy:748)
        at nextflow.Session.await(Session.groovy:701)
        at nextflow.script.ScriptRunner.await(ScriptRunner.groovy:259)
        at nextflow.script.ScriptRunner.execute(ScriptRunner.groovy:145)
        at nextflow.cli.CmdRun.run(CmdRun.groovy:379)
        at nextflow.cli.Launcher.run(Launcher.groovy:513)
        at nextflow.cli.Launcher.main(Launcher.groovy:673)

"Thread-3" #32 prio=5 ... waiting on condition
   java.lang.Thread.State: TIMED_WAITING (sleeping)
        at java.lang.Thread.sleep(Native Method)
        at org.apache.commons.io.ThreadUtils.sleep(ThreadUtils.java:49)
        at org.apache.commons.io.monitor.FileAlterationMonitor.run(FileAlterationMonitor.java:150)
        at java.lang.Thread.run(Thread.java:840)
```

`Thread-3` is the non-daemon thread that prevents JVM exit. It is
spawned by `DirWatcherV2` to drive
`FileAlterationMonitor.checkAndNotify`, and is not interrupted when
the dataflow operator that consumes the watched channel completes.

The `main` thread is parked in `Session.joinAllOperators` waiting for
the operator graph to drain; the operator graph is in fact already
drained from the application's perspective, but `Session.await()`
does not return until the JVM exits cleanly, which requires the
commons-io thread to be released.

## Behaviour matrix observed locally

We have tested two of the termination paths and have indirect evidence
for the third:

| Termination path                                        | 25.04.7    | 25.10.4 |
| ------------------------------------------------------- | ---------- | ------- |
| `take(max_files)` fires before any timeout              | hangs      | hangs   |
| Sentinel-driven `until` fires before `take`             | clean exit | hangs   |
| Idle: nothing fires; JVM is killed by external watchdog | n/a        | n/a     |

The pin to 25.04.7 was adopted as a partial workaround in cycle 6
(2026-04-27, see `bin/run-nf-tests.sh`). It only helps the
sentinel-fires-first path. The take-fires-first path still hangs
under 25.04.7 because the same FileAlterationMonitor thread is
left running.

## Suggested fix

The `DirWatcherV2` should arrange for `FileAlterationMonitor.stop()`
to be invoked when the corresponding dataflow operator completes
(either via `take` short-circuit or via `until` sentinel). One
implementation option is to register a session shutdown hook on the
monitor in `DirWatcherV2.start()` so that
`Session.cleanup`/`Session.shutdown` interrupts any monitors that
outlive their channel. Alternatively, marking the watcher thread as
daemon (as commons-io permits via
`FileAlterationMonitor.setThreadFactory`) would unblock JVM exit at
the cost of dropping in-flight events, but would be a substantially
weaker contract and may surprise users who rely on
`watchPath`-driven side effects.

## Workarounds in the meantime

- `NXF_VER=25.04.7` cleans up the sentinel-fires-first path. A wrapper
  script (`bin/run-nf-tests.sh`) pins this for nf-test invocations.
- The take-fires-first path has no known workaround that does not
  require killing the JVM externally. The two affected nf-tests
  (`realtime_mode = true` cases in
  `subworkflows/local/realtime_monitoring/tests/main.nf.test`) are
  tagged `hangs-on-jvm-cleanup`. nf-test 0.9.4 does not expose an
  `--exclude-tag` flag (only an inclusive `--tag`), so the tag
  serves as documentation and as a hook for future tooling: a CI
  step or a wrapper can list the relevant test IDs and skip them
  by omitting their paths from `nf-test test`. Until such a
  mechanism lands upstream, operators running the realtime
  subworkflow's nf-tests must either accept the hang and kill the
  JVM externally or run the suite with the realtime test file
  omitted from the path arguments.

## Appendix: jstack capture

Captured 2026-04-26 09:21:49 from a Nextflow 25.04.7 JVM hung after
the task10 reproducer's `take(1)` had fired. Full dump retained
locally; the relevant thread frames are reproduced in the
"Diagnostic evidence" section above.
