# Audit: tmp / scratch / workDir bugs in nanometanf

**Date:** 2026-04-29
**Trigger:** Operator reports of unspecified "tmp folder" errors during
pipeline execution.
**Method:** Four parallel agents (Nextflow config + module audit, Python
`bin/` audit, module shell-script audit, container/conda engine audit)
each searched a different layer of the stack and reported findings with
file:line citations.

## Headline

Nine concrete bugs are documented below. Two are run-blockers under
specific deployment profiles, four are reliability bugs, three are
polish. The most likely root cause of an operator-visible "tmp folder
error" stack trace is **F1** (canonical writers in `bin/` raising
`FileNotFoundError` from `tempfile.mkstemp` when the destination
directory does not exist).

**Status update (2026-04-29):** F1 was fixed in the original change
set. F2, F3, F4, F5, F6, F7, F11, F12, F13, F14 fixed in
`fix/tmp-folder-followups-2026-04-29` on nanometanf; F8 fixed in
`nanometa_live.core.workflow.nextflow_manager._build_nextflow_env`.
F9 was a stale citation -- the dorado basecaller module was removed
in an earlier cleanup pass and no module currently contains a
hardcoded `sort -T /tmp`; finding withdrawn.

## P0 (run-blocker on the affected profile)

### F2 -- `conf/cluster.config:208`: `${USER}` not interpolated in workDir

```groovy
workDir = '/scratch/${USER}/nanometanf_work'
```

Single-quoted Groovy strings are literal -- `${USER}` is not expanded.
Every cluster user collides on a path literally containing `${USER}`.
On filesystems where the literal `${USER}` segment is not creatable,
Nextflow fails at workDir creation, surfacing as a generic
"cannot create work directory" -- easy to misread as a tmp/scratch
fault.

**Fix:** Use a double-quoted GString and `System.getenv`:

```groovy
workDir = "/scratch/${System.getenv('USER')}/nanometanf_work"
```

### F3 -- `conf/cluster.config:206`: hard-coded `--bind /scratch:/scratch`

```groovy
runOptions = '--bind /tmp:/tmp --bind /scratch:/scratch'
```

On any host without a top-level `/scratch` (laptops, VMs, macOS, most
cloud images outside HPC), Singularity aborts at every container launch
with `mount source /scratch doesn't exist`. The message does not
mention nanometanf or any process name, so operators report it as
generic.

**Fix:** Make the bind conditional on the deployment, e.g. drive from
`params.scratch_dir` with a sane default of empty.

### F5 -- `conf/cloud.config:210`: placeholder S3 bucket shipped as literal

```groovy
workDir = 's3://your-nanometanf-work-bucket/work'
```

Same pattern at lines 215, 221, 226 for trace/timeline/report. First
invocation fails with `NoSuchBucket` or `AccessDenied`, logged by
Nextflow as "unable to initialize work directory".

**Fix:** Wrap in `params.s3_workdir ?: error('...')` so the failure is
explicit and named.

## P1 (reliability bugs that surface as tmp errors)

### F1 -- `bin/*_to_canonical.py`: missing `os.makedirs` before `mkstemp` -- FIXED IN THIS CHANGE SET

Three of four canonical writers omit a `makedirs` call that
`write_manifest.py` already has:

| File                           | Line |
| ------------------------------ | ---- |
| `bin/assembly_to_canonical.py` | 150  |
| `bin/qc_to_canonical.py`       | 182  |
| `bin/kreport_to_canonical.py`  | 97   |

Without it, `tempfile.mkstemp(dir=dir_name, suffix=".tmp")` raises
`FileNotFoundError` if the destination publishDir has not yet been
created. **This is the most plausible direct match for an operator
seeing a stack trace ending in `tempfile.mkstemp`.**

The fix adds `os.makedirs(dir_name, exist_ok=True)` before the
`mkstemp` call in each script and switches `os.rename` to
`os.replace` for symmetry (atomic same-filesystem replace, including
when the destination already exists).

### F4 -- `conf/production.config:178`: `${params.outdir}` used at config-load time

```groovy
workDir = "${params.outdir}/work"
```

`params.outdir` may not be bound when this profile config is parsed.
Result: workDir becomes `null/work` or `/work`. Combined with
`process.scratch = true` on line 75, scratch-to-work copy-back targets
a bogus path.

**Fix:** Use `params.outdir ?: './results'` and delay resolution via a
closure.

### F6 -- `conf/production.config:181`: `conda.cacheDir` collides with offline bundle

```groovy
conda.cacheDir = "${HOME}/.conda/envs"
```

Two problems:

1. `~/.conda/envs` is where conda itself stores user envs; Nextflow
   writes hash-named envs into it, polluting `conda env list`.
2. The offline bundle pre-warms envs into `~/.nanometa/work/conda/`
   (set via `NXF_CONDA_CACHEDIR` env in
   `nanometa_live.core.workflow.nextflow_manager._build_nextflow_env`).
   The two paths disagree, so pre-warmed envs are not reused on the
   field machine -- the operator's first run rebuilds every env from
   scratch, requiring network access. **This silently defeats offline
   mode.**

**Fix:** Drop the line, or set
`conda.cacheDir = "${projectDir}/work/conda"` and rely on the env
override from Nanometa Live.

### F7 -- `conf/cloud.config`: Docker missing `--tmpfs /tmp:size=`

```groovy
docker { enabled = true; runOptions = '-u $(id -u):$(id -g)' }
```

(`conf/cloud.config:195-203`.) Tools that spill to `/tmp` inside the
container (BLAST, samtools sort, FLYE, minimap2 indexing) write to the
container's overlay layer. Without `--tmpfs /tmp:size=`, multi-GB
spills exhaust the overlay and Docker exits with `no space left on
device` even when the host has terabytes free.

**Fix:** Add `--tmpfs /tmp:size=4g` (or document AWS Batch as the only
supported cloud executor and make `aws.batch.volumes = '/tmp'` the
single source of truth).

### F8 -- `nextflow.config` env block: `NXF_HOME` / `NXF_TEMP` not exported

The `env { ... }` block at `nextflow.config:362-367` exports
`PYTHONNOUSERSITE`, R/Julia paths, but never `NXF_HOME` or `NXF_TEMP`.
On a field machine where `~/.nextflow` is read-only or `~` is a
network share, plugin install, history file, and `.nextflow.log`
writes fail with `NoSuchFileException`. Nanometa Live's
`NextflowManager._build_nextflow_env` sets `NXF_PLUGINS_PATH` and
`NXF_CONDA_CACHEDIR` but not `NXF_HOME` or `NXF_TEMP` -- raw
`nextflow run` invocations on the field machine are exposed.

**Fix:** Export `NXF_HOME = "${projectDir}/.nextflow"` and
`NXF_TEMP = "${projectDir}/.nextflow_tmp"` in the env block (or
extend `_build_nextflow_env`).

### F9 -- `modules/local/dorado/basecaller/main.nf:106`: hardcoded `sort -T /tmp`

```bash
sort -T /tmp --parallel=${task.cpus} ...
```

Bypasses `$TMPDIR` and the workDir. On nodes with small `/tmp`
(particularly tmpfs-backed `/tmp`), sort fails with "No space left
on device" mid-basecalling. Latent for non-Dorado runs.

**Fix:** Use `sort -T "${TMPDIR:-.}"` so the workDir is preferred.

## P2 (polish; defer)

### F10 -- `cluster.config:206`: redundant `--bind /tmp:/tmp` exposes host /tmp to containers

Singularity already auto-mounts `/tmp` via `autoMounts = true` (see
`nextflow.config` singularity profile). The explicit bind shares one
host `/tmp` across all parallel containers, defeating per-container
isolation. Combined with FastQC's default `$TMPDIR` for unzipping
gzipped FASTQ, this is the most likely path to an opaque
"No space left on device" surfaced by Kraken2 / BLAST without naming
the offending module.

**Fix:** Drop the explicit bind, or switch to per-task tmpfs:
`runOptions = '-B "$PWD/tmp":/tmp'`.

### F11 -- `modules/nf-core/fastqc/main.nf:41-45`: missing `--dir .`

`fastqc` writes unzipped streams into `$TMPDIR` (defaults to `/tmp`)
when input is `.fastq.gz`. Long nanopore FASTQs commonly exceed
node-local `/tmp`. **Workaround:** Add
`ext.args = '--dir .'` for FASTQC in `conf/modules.config`.

### F12 -- `modules/nf-core/untar/main.nf:30-44`: helper buffers in `$TMPDIR`

GNU `tar -a` shells out to `gzip` / `xz` / `zstd` per archive; the
helper buffers a temp file under `$TMPDIR` if stdout is back-pressured
on multi-GB Kraken2 DBs. **Workaround:** Prepend `TMPDIR="$PWD"`
inside the script block.

### F13 -- `modules/nf-core/minimap2/align/main.nf:35`: `samtools sort` lacks `-T`

```bash
"-a | samtools sort -@ ${task.cpus-1} -o ${bam_index} ${args2}"
```

Currently latent -- assembly subworkflow calls with `bam_format = false`
so `samtools sort` is not executed. Becomes active P1 when BAM output
is enabled. **Workaround:** Append `-T ${prefix}.sort` when
`bam_format` is true.

### F14 -- `bin/performance_regression_tester.py:31`: dead `import tempfile`

Unused. Cosmetic.

## Clean (no findings)

- `bin/alignment_to_canonical.py` (no tempfile use)
- `bin/qc_benchmark_analyzer.py`, `bin/test_coverage_analyzer.py`
- All 23 `modules/local/*` `.nf` files (sampled in detail; no hardcoded
  `/tmp`, no unsafe `mktemp`, no `stageInMode 'copy'`,
  no module-local `scratch` directives, no unsafe `afterScript`
  cleanups)
- nf-core modules other than the four called out above
- `conf/base.config`, all `conf/test*.config`, `conf/minion.config`,
  `conf/promethion*.config`, `conf/qc_profiles.config`,
  `conf/error_isolation.config`, `conf/modules.config`

## Recommended fix order

1. **F1 (DONE in this change set):** `bin/*_to_canonical.py` add
   `os.makedirs` and switch to `os.replace`.
2. **F2:** Fix `${USER}` interpolation in `conf/cluster.config:208`.
3. **F3:** Conditional `/scratch` bind in `conf/cluster.config:206`.
4. **F5:** Replace placeholder S3 bucket in `conf/cloud.config` with
   `params`-driven config and an explicit "configure first" error.
5. **F6:** Drop `conda.cacheDir = "${HOME}/.conda/envs"` from
   `conf/production.config:181` to align with the offline bundle path.
6. **F4:** Add fallback default to `conf/production.config:178`
   `workDir`.
7. **F7:** Add `--tmpfs /tmp:size=4g` to Docker runOptions in
   `conf/cloud.config`.
8. **F9:** `sort -T "${TMPDIR:-.}"` in dorado basecaller.
9. **F8:** Export `NXF_HOME` / `NXF_TEMP` from the env block.
10. **F10-F13:** Defer; document as known polish items.

## Cross-reference

- Operator-side env injection in Nanometa Live:
  `nanometa_live/core/workflow/nextflow_manager.py:_build_nextflow_env`
- Offline bundle path conventions: `~/.nanometa/work/conda/`
  documented in `nanometa_live/CLAUDE.md`
- The four agent transcripts behind this synthesis are stored as
  Claude Code task output files; see git log for the change set
  introducing this audit.
