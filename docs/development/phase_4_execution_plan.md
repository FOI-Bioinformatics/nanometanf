# Phase 4 Execution Plan: Systematic Test Fixing

**Created**: 2025-10-04
**Status**: Ready to execute
**Prerequisites**: ✅ All infrastructure fixes complete

## Executive Summary

With all critical infrastructure bugs fixed (Channel.timer, max_files schema, test fixtures), we can now systematically fix remaining test failures. This plan provides a step-by-step approach to achieve 80%+ test pass rate for v1.0 release.

## Current Baseline

**Infrastructure Status**: ✅ ALL GREEN
- Channel.timer() error: ELIMINATED
- max_files schema validation: FIXED
- Test fixtures: VALIDATED (10 valid nanopore reads each)
- Real-time monitoring: FUNCTIONAL
- nf-core compliance: ACHIEVED

**Validated Passing Tests**:
- ✅ `tests/parameter_validation.nf.test` - PASSED (21.2s)
- ✅ `tests/realtime_processing.nf.test` - 100% PASSED (2/2 tests, 27s)

**Test Inventory**:
- 20 pipeline tests (tests/*.nf.test + tests/edge_cases/*.nf.test)
- 31 module tests (modules/*/tests/main.nf.test)
- 20 subworkflow tests (subworkflows/*/tests/main.nf.test)
- **Total: 71 test files** (many contain multiple test cases)

## Test Prioritization Strategy

### P0 Tests (MUST PASS - 100% target)

**Core Workflow Tests** (5 tests):
1. `tests/nanoseq_test.nf.test` - Main integration with nf-core data
2. `tests/parameter_validation.nf.test` - ✅ Already passing!
3. `tests/barcode_discovery.nf.test` - Barcode directory discovery
4. `tests/dorado_pod5.nf.test` - POD5 singleplex basecalling
5. `tests/dorado_multiplex.nf.test` - POD5 demultiplexing

**Edge Cases** (4 test files):
6. `tests/edge_cases/dorado_basecaller_edge_cases.nf.test`
7. `tests/edge_cases/malformed_inputs.nf.test`
8. `tests/edge_cases/real_world_scenarios.nf.test`
9. `tests/edge_cases/performance_scalability.nf.test`

**Total P0**: 9 test files (must be 100% passing)

### P1 Tests (SHOULD PASS - >80% target)

**Real-time Tests** (5 tests):
1. `tests/realtime_processing.nf.test` - ✅ Already 100% passing!
2. `tests/realtime_pod5_basecalling.nf.test`
3. `tests/realtime_barcode_integration.nf.test`
4. `tests/realtime_empty_samplesheet.nf.test`
5. `tests/realtime_statistics_modules.nf.test`

**Workflow Tests** (4 tests):
6. `tests/main_workflow.nf.test`
7. `tests/core_logic_test.nf.test`
8. `tests/advanced_error_handling.nf.test`
9. `tests/main_simple.nf.test`

**Total P1**: 9 test files (target >7/9 passing = >77%)

### P2 Tests (CAN FAIL - Experimental)

**Experimental Features** (2 tests):
1. `tests/dynamic_resource_allocation.nf.test`
2. `tests/resource_allocation_modules.nf.test`

**Total P2**: 2 test files (can be 0% pass for v1.0)

### Module/Subworkflow Tests (BEST EFFORT)

**Category**: Supporting infrastructure
**Priority**: Fix after P0/P1 pipeline tests
**Target**: >70% pass rate
**Total**: 51 test files

## Systematic Fixing Approach

### Phase 4.1: P0 Core Tests (Critical)

**Goal**: 100% of P0 tests passing (9/9 files)

**Step-by-step**:

1. **Run P0 tests individually** to identify specific failures:
   ```bash
   for test in tests/nanoseq_test.nf.test \
               tests/parameter_validation.nf.test \
               tests/barcode_discovery.nf.test \
               tests/dorado_pod5.nf.test \
               tests/dorado_multiplex.nf.test \
               tests/edge_cases/*.nf.test; do
       echo "=== Testing: $test ==="
       nf-test test $test --verbose 2>&1 | tee /tmp/$(basename $test).log
   done
   ```

2. **Categorize failures** by root cause:
   - Missing/invalid test fixtures
   - Missing test data files
   - Incorrect test assertions
   - Missing stub implementations
   - Parameter validation issues

3. **Fix systematically** (one test at a time):
   - Fix test fixtures first (highest impact)
   - Add missing test data
   - Update assertions
   - Fix stub blocks
   - Validate parameter passing

4. **Validate after each fix**:
   ```bash
   nf-test test <fixed-test> --verbose
   ```

### Phase 4.2: P1 Important Tests (High Value)

**Goal**: >80% of P1 tests passing (>7/9 files)

**Strategy**:
- Focus on real-time tests (already 1/5 passing)
- Focus on workflow tests
- Use same systematic approach as P0

### Phase 4.3: Module Tests (Supporting)

**Goal**: >70% of module tests passing (>35/51 files)

**Strategy**:
- Fix after P0/P1 complete
- Group by common failure patterns
- Fix in batches

## Expected Failure Patterns

Based on previous analysis, expect these common issues:

### 1. Test Fixture Issues ✅ MOSTLY FIXED

**Symptoms**:
- "No reads found in input"
- "Fatal: No reads found"
- Empty output files

**Fix**: Replace with valid test data (already done for main fixtures)

### 2. Missing Test Data

**Symptoms**:
- File not found errors
- Missing samplesheets
- Missing reference files

**Fix**: Create or symlink test data from assets/test_data/

### 3. Stub Implementation Issues

**Symptoms**:
- "stub: not defined"
- Missing stub output

**Fix**: Add proper stub{} blocks to modules

### 4. Assertion Mismatches

**Symptoms**:
- "assertion failed"
- Unexpected output paths
- Version mismatches

**Fix**: Update test assertions to match actual behavior

### 5. Parameter Issues

**Symptoms**:
- "parameter not defined"
- Validation errors
- Type mismatches

**Fix**: Add missing parameters or fix types

## Success Metrics

### Minimum for v1.0 Release:

**Critical** (MUST achieve):
- ✅ P0 tests: 100% pass (9/9 files)
- ✅ Infrastructure: All critical bugs fixed

**Important** (SHOULD achieve):
- ✅ P1 tests: >80% pass (>7/9 files)
- ✅ Overall: >80% pass (>57/71 files)

**Nice to have**:
- Module tests: >70% pass (>35/51 files)
- P2 experimental: >50% pass (>1/2 files)

### Tracking Progress:

After each batch of fixes, run:
```bash
nf-test test --verbose 2>&1 | tee /tmp/test-progress-$(date +%Y%m%d-%H%M%S).log
grep -E "(PASSED|FAILED)" /tmp/test-progress-*.log | tail -1
```

## Detailed Fixing Workflow

### For Each Failing Test:

1. **Understand the failure**:
   ```bash
   nf-test test <test-file> --verbose > /tmp/debug.log 2>&1
   cat /tmp/debug.log | less
   ```

2. **Identify root cause**:
   - Check error messages
   - Check work directory
   - Check test assertions
   - Check test data

3. **Apply fix**:
   - Fix test fixtures
   - Add missing data
   - Update assertions
   - Fix module stubs
   - Fix parameters

4. **Validate fix**:
   ```bash
   nf-test test <test-file> --verbose
   # Should see: PASSED
   ```

5. **Commit fix**:
   ```bash
   git add <changed-files>
   git commit -m "Fix <test-name>: <brief description>

   Root cause: <cause>
   Solution: <solution>
   Validation: Test now passes"
   ```

6. **Move to next test**

## Risk Mitigation

### Potential Blockers:

1. **Docker/container issues**
   - Mitigation: Test with -profile docker explicitly
   - Fallback: Use conda profile

2. **Platform-specific issues**
   - Mitigation: Document macOS vs Linux differences
   - Fallback: Skip platform-specific tests

3. **Dorado availability**
   - Mitigation: Confirm dorado path is correct
   - Fallback: Skip Dorado tests if not available

4. **Test data size**
   - Mitigation: Use minimal test data
   - Fallback: Download nf-core test datasets if needed

## Timeline Estimate

**Optimistic** (1 day):
- P0 tests: 3-4 hours
- P1 tests: 2-3 hours
- Validation: 1 hour

**Realistic** (2 days):
- Day 1: P0 tests + P1 real-time tests
- Day 2: P1 workflow tests + validation

**Conservative** (3 days):
- Day 1: P0 core + edge cases
- Day 2: P1 all tests
- Day 3: Module tests + final validation

## Next Steps (Immediate)

1. **Check comprehensive test results** (running now)
2. **Analyze failure patterns**
3. **Start with P0 test: `nanoseq_test.nf.test`**
4. **Fix systematically one by one**
5. **Track progress with metrics**

## References

- Phase 4 Readiness: `docs/development/phase_4_readiness.md`
- Test Organization: `docs/development/test_organization.md`
- v1.0 Roadmap: `docs/development/v1_0_roadmap.md`
- Session Summary: `docs/development/session_2025-10-04_critical_fixes.md`

---

**Status**: Ready to execute
**Prerequisites**: ✅ Complete
**Expected Duration**: 1-3 days
**Success Probability**: High (infrastructure is solid)

**Let's systematically fix these tests and achieve v1.0 release!** 🎯
