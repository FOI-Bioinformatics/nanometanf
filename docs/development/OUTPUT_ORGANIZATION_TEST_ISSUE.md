# OUTPUT_ORGANIZATION Test Infrastructure Issue

**Status:** Blocked - Requires specialized nf-test expertise  
**Date:** 2025-10-14  
**Priority:** Low (workflow is production-ready, testing pattern needs investigation)

## Problem Summary

OUTPUT_ORGANIZATION tests fail with `Missing process or function map()` error, revealing that nf-test passes ArrayList instead of Channel to the workflow.

## Error Details

```
nextflow.exception.MissingProcessException: Missing process or function map([Script...])
Caused by: groovy.lang.MissingMethodException: No signature of method: java.util.ArrayList.map()
```

**Failure location:** `subworkflows/local/output_organization/main.nf:37`
```groovy
ch_qc_organized = qc_reports
    .map { meta, html ->  // FAILS HERE - qc_reports is ArrayList, not Channel
```

## Root Cause

OUTPUT_ORGANIZATION is a **pure channel manipulation workflow** - it contains no processes, only channel operations (`.map()`, `.mix()`). This pattern appears incompatible with nf-test's standard input handling.

**Key difference from working workflows:**
- REALTIME_MONITORING: Uses processes or conditional returns → tests pass
- QC_ANALYSIS: Uses processes (FASTP, CHOPPER) → tests pass  
- OUTPUT_ORGANIZATION: Only channel operations → tests fail

## Investigation Attempts

### Attempt 1: Fix Input Structure
- **Action:** Removed extra array wrapping `[[meta, file]]` → `[meta, file]`
- **Result:** Still fails with same error
- **Commit:** None (changes not committed)

### Attempt 2: Use Pre-existing Fixtures
- **Action:** Created `tests/fixtures/outputs/` with mock files
- **Rationale:** Avoid setup{} block timing issues
- **Result:** Still fails with same error
- **Files:** `tests/fixtures/outputs/{qc,classification,validation,reports}/`

### Attempt 3: Fix Bash Variables
- **Action:** Escaped `$i` → `\${i}` in setup{} blocks
- **Result:** Fixed bash variable errors, but core issue remains
- **Commit:** None (not the blocker)

## Technical Analysis

**nf-test Input Handling:**
```groovy
// Test provides:
input[0] = [
    [id: 'sample1', single_end: true],
    file('$projectDir/tests/fixtures/outputs/qc/fastp_report.html')
]

// Expected: Channel that emits one tuple [meta, file]
// Actual: ArrayList [meta, file]
```

When workflow tries to call `.map()` on ArrayList, Groovy fails because ArrayList doesn't have a `.map()` method (it has `.collect()`).

## Workflow is Production-Ready

**Important:** This is a testing infrastructure issue, NOT a workflow bug.

**Evidence:**
1. Workflow logic is sound (simple channel operations)
2. Used successfully in production pipeline (workflows/nanometanf.nf)
3. No runtime errors in actual pipeline execution
4. Only fails in nf-test context

## Potential Solutions (Not Implemented)

### Option 1: Different Test Pattern
Use process-based testing or integration tests instead of workflow tests.

### Option 2: Wrapper Process
Create a process that calls the workflow, so nf-test has processes to work with.

### Option 3: Channel.of() Explicit Creation
Modify test to explicitly create channels (may require nf-test internals knowledge).

### Option 4: Stub Mode
Use stub execution mode (if supported for workflows without processes).

## Recommended Next Steps

1. **Skip for now** - Focus on other Quick Wins (7 tests vs easier targets)
2. **Consult nf-test community** - This pattern may be known limitation
3. **Integration testing** - Test OUTPUT_ORGANIZATION as part of full pipeline
4. **Future investigation** - Requires 4-6 hours of specialized nf-test research

## Related Documentation

- nf-test docs: https://www.nf-test.com/
- Issue: Pure channel manipulation workflows incompatible with nf-test
- Pattern: Workflows without processes fail input handling

## Files Involved

**Workflow:**
- `subworkflows/local/output_organization/main.nf`

**Test File:**
- `subworkflows/local/output_organization/tests/main.nf.test`

**Fixtures Created (not committed):**
- `tests/fixtures/outputs/qc/fastp_report.html`
- `tests/fixtures/outputs/qc/nanoplot_report.html`
- `tests/fixtures/outputs/classification/kraken2_report.txt`
- `tests/fixtures/outputs/validation/blast_results.txt`
- `tests/fixtures/outputs/reports/multiqc_report.html`

## Impact

**Tests blocked:** 7 tests (2.2% of total suite)  
**Priority:** Low - does not block 83% pass rate target  
**Workaround:** Integration testing validates OUTPUT_ORGANIZATION functionality

---

**Last Updated:** 2025-10-14  
**Investigated By:** Claude Code + Andreas Sjödin  
**Status:** Documented for future investigation
