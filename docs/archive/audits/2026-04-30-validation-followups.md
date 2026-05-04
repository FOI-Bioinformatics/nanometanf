# Validation follow-ups -- 2026-04-30

End-to-end testing of the validation flow (against
`/tmp/validation-e2e-test/` derived from the scenario5 fixture)
landed two pipeline fixes today:

- `f88a933` -- coerce ``taxids_to_validate`` to string before
  `.split()` in the validation subworkflow (fixes single-taxid
  invocations from the GUI).
- `a9caf24` (merged in `df10112`) -- double-escape ``\\n`` in
  MINIMAP2_VALIDATION's awk JSON writer (fixes 100% of minimap2
  validation runs; without it every minimap2 process exited code 2
  and the Coverage sub-tab in the dashboard was always empty).

Both are in `dev`. The following items surfaced during the same
audit but are scoped as follow-ups rather than blocking fixes:

## P1 -- BLAST hit_rate semantic mismatch

**File:** `modules/local/blastn_validation/main.nf:113-128`

**Symptom:** the BLAST module computes
``hit_rate = hits / total_reads`` where ``hits`` is the number of
HSP lines in the blastn `-outfmt 6` output. Because blastn keeps
unlimited HSPs per query by default, a single read can contribute
multiple hits, so ``hit_rate`` can exceed 1.0. In the e2e test it
reached 1.31 (654 HSPs from 499 reads).

The dashboard parser at
`nanometa_live/core/parsers/blast_validation_parser.py:441` does:

```python
percent_validated = hit_rate * 100 if hit_rate <= 1.0 else hit_rate
```

So a BLAST result with ``hit_rate=1.31`` lands in the GUI as
**"1.3% Confirmed"** -- a confirmed status with what looks like
a tiny percentage. Operators would interpret this as a near-failure
when the underlying signal is the opposite (every read had at least
one strong hit, plus some had multiple).

minimap2 is not affected because the awk script deduplicates by
read name (`if (!(qname in seen))` at lines 87-89 of
`modules/local/minimap2_validation/main.nf`).

**Recommended fix in nanometanf:** dedupe by qseqid in the BLAST
module so ``hits`` matches the minimap2 semantic. Replace
lines 113-128 with:

```python
hits = 0
seen = set()
identities = []
coverages = []
evalues = []

with open(blast_file) as f:
    for line in f:
        cols = line.strip().split('\t')
        if len(cols) >= 15:
            qseqid = cols[0]
            if qseqid in seen:
                continue
            seen.add(qseqid)
            hits += 1
            identities.append(float(cols[2]))
            coverages.append(float(cols[14]) / 100.0)
            evalues.append(float(cols[10]))
```

This makes ``hit_rate`` always in [0, 1] and the GUI display
correct without any front-end change.

**Test impact:** the existing nf-test snapshots for
BLASTN_VALIDATION may need refresh because the stats JSON values
will change for any test data with multi-HSP queries.

## P2 -- "Query Coverage (%)" column header in BLAST stats table

**File:** `nanometa_live/app/layouts/validation_layout.py:198`

The column header "Query Coverage (%)" maps to BLAST's `qcovs`
field (per-query coverage), but the same header is used for the
minimap2 coverage value (which is `span / qlen` from the PAF
output). The two metrics aren't strictly the same.

**Recommended fix:** either rename to "Match coverage" (method-
agnostic) or split into two method-specific columns shown
conditionally. Lower urgency than the hit_rate issue because
the contract is at least documented in `qcovs`'s definition.

## P2 -- Coverage threshold default

**File:** `nanometa_live/app/components/coverage_plots.py:25`

`create_coverage_depth_figure` defaults `threshold=10` (10x
depth). For small references (e.g. the 2.7 kb test reference) or
amplicon protocols with low expected depth, 10x may always be
satisfied trivially -- the dashed threshold line then conveys no
actionable signal. For very deep WGS runs the same line is below
the noise floor.

**Recommended fix:** make the threshold operator-controllable via
a numeric input next to the existing MAPQ filter, or auto-scale
to ~25th percentile of observed depth.

## P2 -- "Alignment Score" microcopy

**File:** `nanometa_live/app/layouts/validation_layout.py:626-633`

The result-card 4th metric flips between "Query Coverage" (BLAST)
and "Alignment Score" (minimap2). The minimap2 value is `avg_mapq`
on the 0-60 scale where 30+ is conventionally "good", but the
"Score" label doesn't communicate the scale. An operator without
bioinformatics background sees "39.3" and has no anchor.

**Recommended fix:** rename to "Mapping Confidence" with a tooltip
"0-60 scale; 20+ is good, 30+ is reliable". Or render as a
qualitative badge ("Reliable", "Good", "Low") computed from the
numeric value.

## Verified working today

The following are confirmed working end-to-end after the two
merges:

- BLAST validation: 654 HSPs, status confirmed, populates card +
  identity plot + stats table
- minimap2 validation: 329/499 reads mapped, mapq 39.33,
  identity 98.57%, status confirmed, populates card + PAF +
  stats JSON + coverage plots
- Cumulative pathogen_genomes.json behaviour: `pathogen_genomes
  .json` accumulates taxids across calls; nanometa_live's
  `validate_via_nanometanf` writes atomically.
- Resume cache: `nextflow run -resume --taxids_to_validate=A,B`
  after `A` skips the cached A pairs (verified `cached: 2`
  in the per-process executor output) and only B runs end-to-end.
- View Coverage button → switches sub-tabs and pre-populates the
  species selector.
- Empty/disabled/awaiting states all render distinct icons + copy.

The validation flow is production-ready for the BLAST + minimap2
methods; the P1 hit_rate fix above is the only remaining bug
that affects clinical interpretation.
