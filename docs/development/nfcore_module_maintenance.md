# nf-core Module Maintenance

How the nf-core modules installed under `modules/nf-core/` are kept current, which ones
carry a local modification, and how that modification survives an update.

Last reviewed: 2026-10-29 (all modules at nf-core/modules `7b3452a`, 2026-10-27)

---

## Summary

| Module          | Local modification                            | Mechanism                                |
| --------------- | --------------------------------------------- | ---------------------------------------- |
| `filtlong`      | Multi-file input concatenated before filtlong | nf-core patch (`filtlong.diff`)          |
| `nanoplot`      | Inputs staged in indexed directories (`?/*`)  | nf-core patch (`nanoplot.diff`)          |
| all others (13) | None                                          | Plain upstream; `nf-core modules update` |

The patch files are recorded in `modules.json` (`patch` key) and re-applied by
`nf-core modules update`; when upstream changes the patched lines the update reports
"Failed to apply patch" and the modification has to be re-applied by hand, then recorded
again with `nf-core modules patch <module>`. There is no `.nf-core.yml` update skip list
and there never was one in effect: an earlier version of this document described one, but
the file only ever carried lint configuration.

---

## Module: nf-core/filtlong

### Local modification

filtlong accepts exactly one positional long-read file. A multi-file sample (every
barcode directory of a MinKNOW run, every chunk in chunked batch mode) is concatenated
into `${prefix}.concat_input.fq.gz` before the call and the concatenation is removed
afterwards; gzip members concatenate as a valid stream. Without this the extra files are
passed as positionals and filtlong exits 1 ("passed in argument, but no positional
arguments were ready to receive it"): Nanometa Live audit round 5, 2026-09-03, P1.

### Can this be achieved with task.ext.args?

No. The concatenation is a shell step before the tool runs.

### Maintenance burden

Low. The modification is five `def` lines plus two script lines around the `filtlong`
call. It had to be re-applied on 2026-10-29 because upstream added a stub block and
rewrote the script indentation; re-applying took minutes.

---

## Module: nf-core/nanoplot

### Local modification

`tuple val(meta), path(ontfile, stageAs: '?/*')`. In chunked batch mode one NanoPlot task
receives every chunk of a sample, and the chunks all carry the same file name, which
collides when staged flat. Indexed staging directories give each file its own directory.

### Maintenance burden

Negligible: one input line. fastqc needed the same change and upstream has since adopted
it (`stageAs: '?/*'` is in the upstream fastqc module as of `7b3452a`), so the fastqc patch
is gone. Proposing the same one-line change upstream for nanoplot would remove this patch
too.

---

## Modifications retired on 2026-10-29

- **`chopper` gzip pin and `gunzip -c`.** Added because the slim community image shipped
  chopper alone and macOS BSD `zcat` could not read `.fastq.gz`. Upstream now bundles
  `pigz` in both the conda environment and the Wave image and pipes through it, which
  covers both platforms, so the patch is dropped. The pipeline keeps its own
  `ext.prefix = "${meta.id}.chopped"` in `conf/modules.config`, so upstream's new default
  prefix (`${meta.id}.chopper`) changes no file name.
- **`fastqc` indexed staging.** Upstreamed (see above).
- **`nanoplot` hardcoded stub version.** Upstream's stub now hardcodes too.
- **`blast/blastn` `export BLASTDB=${db}` and `blast/makeblastdb`.** Both modules were
  installed but included by nothing: validation runs through the local
  `modules/local/blastn_validation` module, which has carried the `BLASTDB` export since
  it was written. Removed with `nf-core modules remove`.
- **`tag "fast"` / `tag "stub"` added to upstream module tests** (porechop, flye,
  minimap2/align, seqkit/stats, taxpasta/\*). These tags selected the upstream module
  tests under `tests/run_tests.sh fast`. They are not in the CI allowlist (excluded in
  `tests/ci_excluded_tests.txt` with reason `nf-core`: upstream maintains them), so the
  tags bought nothing in CI and cost a patch file per module. Run an upstream module's
  own tests directly: `nf-test test modules/nf-core/<module>/tests/main.nf.test`.
- **`miniasm` stub snapshot edits.** Upstream's snapshot is authoritative again.

---

## Version emission: topic channels

As of `7b3452a` every installed nf-core module emits its tool version as
`tuple val(process), val(tool), eval(cmd), topic: versions` and no longer writes
`versions.yml`. The pipeline collects both styles in `workflows/nanometanf.nf`
(`Channel.topic('versions')` beside the legacy `ch_versions`), so a module switching
style needs one change: delete the `ch_versions.mix(MODULE.out.versions)` line in the
subworkflow that calls it, or Nextflow fails at parse time with "no such output".
The 2026-10-29 update switched FILTLONG, PORECHOP_PORECHOP, NANOPLOT and
TAXPASTA_STANDARDISE; the lines are replaced by a comment naming the pattern, as the
earlier switches (FASTP, FASTQC, SEQKIT_STATS, KRAKEN2_KRAKEN2, CHOPPER) were.

---

## Updating

```bash
nf-core modules list local                      # installed versions and dates
nf-core modules update --all --save-diff u.diff # dry run: review u.diff, nothing applied
nf-core modules update --all                    # apply; patches re-applied where they fit
nf-core modules lint --all                      # patch_reversible, version topic, containers
nf-core modules patch <module>                  # re-record a modification you re-applied
```

Checklist after an update:

1. Read the "Failed to apply patch" warnings. For each, re-apply the modification by
   hand from the table above, then `nf-core modules patch <module>`. Delete any stale
   `.diff` left behind for a module whose modification is gone, and its `patch` key in
   `modules.json`, or `nf-core modules lint` fails `patch_reversible`.
2. `grep -rn '\.out\.versions' subworkflows/local workflows` for every module the update
   moved to topic emission.
3. Check `ext.prefix` defaults: an upstream prefix change renames published files unless
   `conf/modules.config` pins the prefix.
4. Run the subworkflow and pipeline nf-tests that include the module (the real-execution
   ones need `--profile test,docker` or `test,conda`; stub tests need neither).
5. The regenerated `conf/containers_*.config` files change whenever a container
   reference does; `nf-core pipelines lint` rewrites them.

Running several `nf-core` commands at once against a fresh checkout corrupts their
shared clone of nf-core/modules (`~/.config/nfcore`): the symptom is
"Branch 'master' not found" on every module. Run them one after another.

---

## nf-core subworkflows: `utils_*` held back on purpose (2026-10-29)

`nf-core subworkflows update --all --save-diff` reports newer versions of all three
installed nf-core subworkflows, and they are not taken in the module update because they
are one change, not three, and it is a major one:

- `utils_nfschema_plugin` at `7b3452a` targets **nf-schema 3.0.0** (its test config pins
  `nf-schema@3.0.0`; the pipeline runs 2.6.1). It renames the plugin option keys
  (`parametersSchema` -> `parameters_schema`), changes the `paramsHelp` /
  `paramsSummaryLog` signatures, and adds a seventh `take` input, `cli_typecast`, so the
  call in `subworkflows/local/utils_nfcore_nanometanf_pipeline/main.nf` must change with
  it. nf-schema 3.0 also changes how CLI parameters are typecast, which is the contract
  Nanometa Live relies on when it launches with `-params-file`.
- `utils_nfcore_pipeline` drops `imNotification`, which the local pipeline-utils
  subworkflow imports and calls for `--hook_url`; the function would need to move into
  the local subworkflow or the feature be removed.
- `utils_nextflow_pipeline` changes `dumpParametersToJSON` to a typed JSON generator;
  harmless on its own.

Take all three together with the nf-schema bump, as `nf-core pipelines sync` would, and
re-run the GUI launch tests in nanometa_live (typed params through `-params-file`) before
merging. Until then `nf-core pipelines lint` and `nf-core subworkflows lint` report
`subworkflow_version: New version available` for the three; that warning is the record of
this decision, not an oversight.
