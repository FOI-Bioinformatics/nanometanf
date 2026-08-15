# nf-core Module Maintenance Assessment

This document assesses the maintenance burden of the four locally-modified nf-core modules in
nanometanf. For each module the divergence from upstream is characterised, the justification for
the modification is evaluated, and a recommendation is given regarding the long-term maintenance
strategy.

Last reviewed: 2026-03-01
Actions completed: 2026-03-01

---

## Summary

| Module                    | Divergence                       | Can use ext.args | Status                                                                                          |
| ------------------------- | -------------------------------- | ---------------- | ----------------------------------------------------------------------------------------------- |
| `nf-core/fastp`           | Script logic (multi-file concat) | No               | DONE: Streaming logic moved to `modules/local/fastp_streaming`; upstream module restored        |
| `nf-core/blast/blastn`    | Environment variable export      | No               | DONE: Protected via `.nf-core.yml` update skip list; comment updated with re-apply instructions |
| `nf-core/kraken2/kraken2` | Container SHA + stub hardcoding  | N/A              | Pending: Run `nf-core modules update kraken2/kraken2`                                           |
| `nf-core/nanoplot`        | Stub hardcoding only             | N/A              | Pending: Run `nf-core modules update nanoplot`                                                  |

---

## Module: nf-core/fastp

### Local modification

The `adapter_fasta` parameter was moved into the first input tuple (matching the upstream
`meta.yml` interface), and a multi-file concatenation block was added to the `script` section.

Specifically, before each `fastp` invocation the script counts the number of input files and, if
more than one is present, concatenates them with `cat` before calling fastp:

```bash
if [ ${num_files} -gt 1 ]; then
    cat ${reads} > ${prefix}.fastq.gz
else
    [ ! -f ${prefix}.fastq.gz ] && ln -sf ${reads} ${prefix}.fastq.gz
fi
```

### What the upstream module provides

Inspection of the upstream `meta.yml` shows that the nf-core FASTP module already declares
`adapter_fasta` as part of the first input tuple. The local input signature therefore matches
upstream exactly. The divergence is confined to the script body.

### Can this be achieved with task.ext.args?

No. The multi-file concatenation is a shell-level pre-processing step that must execute before
fastp runs. There is no fastp CLI flag that accepts a list of input files and concatenates them.

### Maintenance burden

Medium. Every time nf-core updates the FASTP module (for example, to update the container, change
the script logic, or add new parameters), the concatenation block must be manually re-applied to
the updated script. The concatenation logic spans three conditional branches (interleaved,
single-end, and paired-end), which increases the merge effort.

### What happens on nf-core update

The concatenation block must be re-inserted into all three script branches. The stub block does
not require changes. The input/output signature is stable.

### Recommendation

Create a thin local pre-process module (for example `CONCATENATE_FASTQ_BATCHES`) that takes a
list of FASTQ files and emits a single FASTQ file. Call this module immediately before FASTP in
the streaming subworkflow, then pass the single output file to the unmodified upstream FASTP
module.

This eliminates the divergence from upstream entirely and makes future nf-core updates a
straightforward `nf-core modules update` operation.

---

## Module: nf-core/blast/blastn

### Local modification

A single line was added to the script section before the BLAST database discovery step:

```bash
export BLASTDB=${db}
```

### Why this is needed

The BLAST suite resolves database paths by consulting the `BLASTDB` environment variable in
addition to the path provided to `-db`. The upstream module uses `find` to locate the `.nal` or
`.nin` index files relative to the staged database directory. Setting `BLASTDB` to the staged
directory ensures that BLAST can resolve the database correctly when the database is a staged
symlink forest, as occurs in the nanometanf validation subworkflow.

### Can this be achieved with task.ext.args?

No. `BLASTDB` is an environment variable, not a blastn CLI argument. There is no way to set it
via `ext.args`.

A workaround using `ext.beforeScript` is possible in principle:

```groovy
ext.beforeScript = "export BLASTDB=\${db}"
```

However, `ext.beforeScript` receives the process working directory, not the staged path of the
`db` input. The staged path is only available inside the process script block, so `ext.beforeScript`
cannot be used here without additional scaffolding.

### Maintenance burden

Low. The modification is a single line inserted immediately before the `find` command. The rest of
the script is unchanged. On nf-core update, the single line must be re-applied, which is a minimal
effort.

### What happens on nf-core update

Re-insert `export BLASTDB=${db}` before the `find -L ./ -name "*.nal"` line. No other changes
are required.

### Recommendation

Keep the module as a local fork. The modification is minimal, well-isolated, and clearly
documented with the `// LOCAL MODIFICATION` comment. The risk of a merge conflict on nf-core
update is low.

Document the exact upstream commit against which the fork was made so that future diffs can be
generated automatically.

---

## Module: nf-core/kraken2/kraken2

### Local modification

Two changes were made:

1. The container SHA URLs in the `container` directive were updated to match the latest nf-core
   remote (this is a cosmetic sync, not a functional change).
2. The stub block was updated to use hardcoded version strings (`kraken2: 2.1.3`, `pigz: 2.8`)
   instead of calling the real binaries. This is now standard nf-core practice for stub blocks.

### Can this be achieved with task.ext.args?

Not applicable. Both changes are module-level and independent of the tool CLI.

### Maintenance burden

Very low. The container SHA change is a cosmetic sync that aligns with upstream. The stub
hardcoding change is a best practice improvement that nf-core itself applies to new modules. There
is no functional divergence from upstream behaviour.

### What happens on nf-core update

The container SHAs will be overwritten by `nf-core modules update`, which is the intended
behaviour. The stub hardcoding will also be overwritten, but nf-core stubs now follow the same
hardcoded convention, so the updated stub will be functionally equivalent.

### Recommendation

Re-sync with upstream using `nf-core modules update kraken2/kraken2`. The local modifications
will be superseded by the upstream versions, which is acceptable because neither change is
functionally required by nanometanf. Remove the `// LOCAL MODIFICATION` comment after re-sync to
keep the module clean.

---

## Module: nf-core/nanoplot

### Local modification

The stub block was updated to use a hardcoded version string (`nanoplot: 1.46.1`) instead of
calling `NanoPlot --version`.

### Can this be achieved with task.ext.args?

Not applicable.

### Maintenance burden

Negligible. The only divergence from upstream is the stub block. Stub blocks are never executed
in production runs. The hardcoded version may become outdated if the module is updated to a newer
NanoPlot version, but this causes no runtime impact.

### What happens on nf-core update

`nf-core modules update nanoplot` will overwrite the stub block. The updated stub block will
likely also hardcode the version (this is current nf-core convention) or may call the binary. In
either case no functional regression occurs.

### Recommendation

Re-sync with upstream using `nf-core modules update nanoplot`. Remove the `// LOCAL MODIFICATION`
comment after re-sync. This module requires no further attention.

---

## General Maintenance Guidance

### Tracking divergence

Each locally-modified module carries a header comment in `main.nf`:

```groovy
// LOCAL MODIFICATION: <description>
// Reason: <rationale>
// Last verified against nf-core remote: YYYY-MM-DD
```

Update the `Last verified` date whenever the module is manually re-examined against upstream,
even if no changes are made.

### Updating nf-core modules

For modules with no functional divergence (kraken2/kraken2, nanoplot):

```bash
cd /Users/andreassjodin/Code/nanometanf
nf-core modules update kraken2/kraken2
nf-core modules update nanoplot
```

Review the diff before committing to confirm no regression.

For modules with functional divergence (fastp, blast/blastn):

1. Run `nf-core modules update <module> --preview` to review upstream changes.
2. Apply the upstream changes manually, then re-apply the local modification.
3. Update the `Last verified` date in the header comment.
4. Run nf-test stub tests to confirm the module still behaves correctly.

### Reducing future maintenance burden

The highest-priority action for reducing maintenance burden is to eliminate the fastp divergence
by introducing a dedicated concatenation module. This converts a medium-maintenance fork into a
zero-maintenance upstream module plus a small, stable local module with no upstream dependency.

The blast/blastn fork is justified and low-maintenance. No structural change is recommended.
