# Canonical output specification

This document is the source of truth for the contents of
`outdir/canonical/`, the tool-agnostic output layer that downstream
consumers (Nanometa Live and any other frontend or analysis script)
should read from. It supersedes the prose scattered across inline
comments in `bin/*_to_canonical.py`, `modules/local/canonical_*` and
the high-level summary in `CLAUDE.md`.

The layer was introduced because raw tool outputs change format
between releases (Kraken2 report versions, FASTP JSON keys, BLAST
column orders) and the frontend used to break every time a tool
changed. Canonical outputs decouple consumers from tool internals:
every category has a fixed JSON or TSV schema, a sidecar with tool
provenance, and an authoritative `_manifest.json` index at the top of
the canonical tree.

## Directory layout

```
outdir/canonical/
|-- _manifest.json
|-- classification/
|   |-- <sample>.classification.json          # Contract A body
|   `-- <sample>.classification.sidecar.json
|-- qc/
|   |-- <sample>.qc.json                       # Contract B body
|   `-- <sample>.qc.sidecar.json
|-- validation/
|   |-- <sample>.<taxid>.alignment.tsv         # Contract C body
|   `-- <sample>.<taxid>.alignment.sidecar.json
`-- assembly/
    |-- <sample>.assembly.json                 # Contract D body
    `-- <sample>.assembly.sidecar.json
```

`outdir` and `params.write_canonical` (default `true`) gate the whole
layer. Individual category directories are only populated when the
corresponding pipeline path runs (no `classification/` if
`--skip_kraken2 true`).

All files are written atomically: each writer stages a `.tmp` sibling
in the destination directory and `os.replace`s into place, so partial
writes are never visible to readers. The pattern lives in
`bin/<contract>_to_canonical.py:write_atomic`.

## Common sidecar schema

Every category emits a sidecar JSON next to the body. The sidecar
isolates provenance metadata from data so consumers can answer
"which tool wrote this, when, in what mode" without parsing the body.

```json
{
  "contract_version": "1.0.0",
  "category": "classification | qc | alignment | assembly_stats",
  "tool": { "name": "string", "version": "string" },
  "sample_id": "string",
  "timestamp": "ISO-8601 UTC, seconds precision (YYYY-MM-DDTHH:MM:SSZ)",
  "format_version": "matches the body's format_version",
  "source_files": ["base name of the upstream tool's raw output"]
}
```

Classification and QC sidecars also carry:

- `mode`: `"batch"` or `"realtime"`
- (classification only) `is_cumulative`: `true` for end-of-session
  aggregate reports, `false` for per-batch increments
- (classification only) `batch_id`: integer, present only in realtime
  per-batch sidecars

Sidecar `contract_version` and body `format_version` are independent.
`contract_version` is the schema of the sidecar itself; `format_version`
is the schema of the body. Both are currently `"1.0.0"`. Bump
`contract_version` when adding required sidecar fields, bump body
`format_version` when adding required body fields. Optional additions
do not require a bump but should be documented in this file's history.

## Contract A: classification body

File: `canonical/classification/<sample>.classification.json`

Produced by `CANONICAL_CLASSIFICATION_WRITER` from
`KRAKEN2_KRAKEN2.out.report` (batch mode) or
`KRAKEN2_FINAL_AGGREGATOR.out.cumulative_report` (streaming).

```json
{
  "format_version": "1.0.0",
  "sample_id": "string",
  "summary": {
    "total_reads": 0,
    "classified_reads": 0,
    "unclassified_reads": 0,
    "classification_rate": 0.0
  },
  "taxa": [
    {
      "taxid": 0,
      "parent_taxid": 0,
      "rank": "string (R | D | K | P | C | O | F | G | S | U or sub-ranks)",
      "name": "string",
      "depth": 0,
      "reads_direct": 0,
      "reads_cumulative": 0,
      "percentage": 0.0
    }
  ]
}
```

Notes:

- `parent_taxid` is reconstructed from kreport's indentation, which
  upstream tools do not encode explicitly. Frontends should walk the
  parent_taxid chain rather than re-deriving from indentation.
- `taxid = 0` is reserved for unclassified.
- `classification_rate` is `classified_reads / total_reads` rounded to
  six decimal places; `0.0` when `total_reads = 0`.

## Contract B: QC body

File: `canonical/qc/<sample>.qc.json`

Produced by `CANONICAL_QC_WRITER` from `FASTP.out.json`,
`FASTP_STREAMING.out.json`, or `SEQKIT_STATS.out.stats`. The writer
detects the input format and normalises both to the same body schema.

```json
{
  "format_version": "1.0.0",
  "sample_id": "string",
  "before_filtering": {
    "total_reads": 0,
    "total_bases": 0,
    "q20_rate": 0.0,
    "q30_rate": 0.0,
    "gc_content": 0.0,
    "read_length_mean": 0.0,
    "read_length_n50": 0
  },
  "after_filtering": {
    "total_reads": 0,
    "total_bases": 0,
    "q20_rate": 0.0,
    "q30_rate": 0.0,
    "gc_content": 0.0,
    "read_length_mean": 0.0,
    "read_length_n50": 0
  },
  "filtering_result": {
    "passed_filter_reads": 0,
    "low_quality_reads": 0,
    "too_short_reads": 0
  },
  "length_distribution": [{ "length": 0, "count": 0 }]
}
```

Notes:

- `filtering_result` and `length_distribution` are optional. CHOPPER /
  SEQKIT inputs that lack `filtering_result` data omit the key; FASTP
  inputs always populate it. Frontends must guard for absence.
- `read_length_n50` is computed from the `length_distribution`
  histogram when available, otherwise `null`. SeqKit's own N50 column
  is used directly if present.
- For SeqKit input the `before_filtering` and `after_filtering`
  blocks are identical (SeqKit reports post-tool counts only).

## Contract C: alignment body

File: `canonical/validation/<sample>.<taxid>.alignment.tsv`

Produced by `CANONICAL_VALIDATION_WRITER` from `MINIMAP2_VALIDATION`
PAF or `BLASTN_VALIDATION` outfmt-6 output.

Tab-separated, one alignment per row, with this header:

```
query_id  ref_name  ref_length  ref_start  ref_end  identity  mapq
alignment_length  evalue  bitscore  query_length  query_coverage
```

Notes:

- This is the only contract that ships as TSV, because validation
  callers stream it through standard alignment-table tools (cut /
  awk / pandas) that already expect tabular layouts.
- Empty alignment results still write the header row so consumers do
  not have to special-case missing files vs. zero hits.
- BLAST `evalue` survives untouched; minimap2 has no e-value and
  reports `NA`. Frontends parsing both must accept either.
- BLAST `mapq` is not part of outfmt-6; the writer fills `NA` for
  BLAST rows.

## Contract D: assembly body

File: `canonical/assembly/<sample>.assembly.json`

Produced by `CANONICAL_ASSEMBLY_WRITER` from Flye's
`assembly_info.txt`, optionally combined with the assembly FASTA for
per-contig GC.

```json
{
  "format_version": "1.0.0",
  "sample_id": "string",
  "summary": {
    "n_contigs": 0,
    "total_length": 0,
    "n50": 0,
    "largest_contig": 0,
    "gc_content": 0.0,
    "mean_coverage": 0.0
  },
  "contigs": [
    {
      "name": "string",
      "length": 0,
      "coverage": 0.0,
      "circular": false,
      "repeat": false,
      "multiplicity": 1,
      "graph_path": "string",
      "gc_content": 0.0
    }
  ]
}
```

Notes:

- `gc_content` is per-contig when the FASTA is supplied to the
  writer and per-assembly when only `assembly_info.txt` is available.
- `circular`, `repeat`, `multiplicity` and `graph_path` come from
  Flye and may be absent for non-Flye assemblers (Miniasm); the
  writer fills `false`, `1`, and `""` respectively.

## Manifest

File: `canonical/_manifest.json`

Produced by `MANIFEST_WRITER`, updated atomically every time a
canonical directory changes. The manifest is the only entry point
frontends should glob -- it lists every produced file by category so
consumers do not have to walk directories themselves.

```json
{
  "format_version": "1.0.0",
  "pipeline": {
    "name": "nanometanf",
    "version": "string",
    "session_id": "string"
  },
  "mode": "batch | realtime",
  "started_at": "ISO-8601 UTC",
  "last_updated": "ISO-8601 UTC",
  "tools": {
    "classifier": "kraken2 | centrifuge | \"\"",
    "qc_tool": "fastp | chopper | filtlong | seqkit | \"\"",
    "validator": "blast | minimap2 | \"\"",
    "assembler": "flye | miniasm | \"\""
  },
  "samples": ["string"],
  "files": {
    "classification": ["<sample>.classification.json", "..."],
    "qc": ["<sample>.qc.json", "..."],
    "validation": ["<sample>.<taxid>.alignment.tsv", "..."],
    "assembly": ["<sample>.assembly.json", "..."]
  }
}
```

Notes:

- `started_at` is preserved across writes; only `last_updated` and
  the file lists move on incremental updates.
- File lists are derived from the active `tools` + `samples` set
  rather than from a filesystem scan, because `MANIFEST_WRITER` runs
  in its own Nextflow work directory and cannot see the final
  publishDir. Consumers can safely treat the lists as the
  source-of-truth set.
- An empty list (`"classification": []`) means the category was not
  produced this run, not that the files are missing.

## Versioning

Canonical schemas follow semantic versioning per body:

- **Major** (`2.0.0`): break a required field. Consumers must
  migrate.
- **Minor** (`1.1.0`): add an optional field, change semantics of an
  existing field in a backwards-compatible way (e.g. round to more
  digits, narrow a value range).
- **Patch** (`1.0.1`): documentation or atomicity fixes only; bodies
  on disk are byte-identical to the previous patch level.

`contract_version` on the sidecar follows the same rules but for the
sidecar schema only. A body bump does not necessarily trigger a
sidecar bump.

When bumping any version, document the change in this file's
**History** section and add a regression test under the corresponding
`modules/local/canonical_*_writer/tests/` directory.

## History

| Date       | File               | Change               |
| ---------- | ------------------ | -------------------- |
| 2026-05-29 | this specification | Initial publication. |
