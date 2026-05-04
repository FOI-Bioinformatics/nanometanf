# Archive

Historical documents from the development of nanometanf. These files
are preserved for reference but are not actively maintained. The
current state of the codebase is the source of truth; if an archive
document and the code disagree, trust the code.

## Layout

```
archive/
|-- README.md            (this file)
|-- audits/              Dated audit reports
|-- plans/               Design plans and implementation specs
|-- validation/          Historical version-specific testing plans
`-- *.md                 Other historical reference documents
```

Note: a separate archive at `docs/development/archive/` contains
development session notes, phase histories, and a `v1.3.3/` snapshot.
Both archives co-exist by intent: `archive/` here aggregates audits
and plans (matching the convention in the sister `nanometa_live` and
`nanorunner` repositories); `development/archive/` aggregates
development work logs.

## Audits (`audits/`)

| File                                              | Description |
|---------------------------------------------------|-------------|
| `2026-04-29-tmp-folder-bugs.md`                   | Catalog of nine tmp/scratch/workDir bugs (F1-F9) and follow-up polish items (F10-F14). Fixes shipped to the codebase. |
| `2026-04-30-validation-followups.md`              | Two pipeline fixes shipped 2026-04-30 plus four follow-up items. |
| `2026-05-02-backend.md`                           | Comprehensive backend audit scoring production-readiness 7.6/10 with 11 ranked recommendations. |

## Plans (`plans/`)

Design specifications and implementation plans, paired by date:

| File                                               | Description |
|----------------------------------------------------|-------------|
| `2026-01-30-efficiency-audit-design.md`            | Design spec for six efficiency improvements |
| `2026-01-30-efficiency-fixes.md`                   | Implementation tasks (Tasks 1-7) for the audit findings |
| `2026-01-31-unified-input-handling-design.md`      | Design spec for InputDetector, BatchUtils, INPUT_SCANNER subworkflow (now reality in v1.5+) |
| `2026-01-31-unified-input-implementation.md`       | 12-task implementation plan for unified input handling |
| `2026-02-03-documentation-update-design.md`        | Documentation alignment plan for v1.5.0 changes |

## Validation (`validation/`)

| File                          | Description |
|-------------------------------|-------------|
| `V1_3_0_TESTING_PLAN.md`      | Test plan for v1.3.0 real-data validation. v1.3.0 was published broken; superseded by the v1.3.1 hotfix and then v1.5.0. |

## Top-level archive files

| File                                  | Description |
|---------------------------------------|-------------|
| `OPTIMIZATIONS_QUICK_REFERENCE.md`    | v1.3-era summary of optional optimizations. Most are now defaults in v1.5+; superseded by the streaming classification architecture documented in `development/incremental_kraken2_implementation.md`. |
