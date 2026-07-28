# Testing Guide for nanometanf Pipeline

## Quick Reference

### Most Common Commands
```bash
# Setup (required once per session)
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH

# Run all tests
nf-test test --verbose

# Run specific test types
nf-test test --tag module           # Module tests only
nf-test test --tag subworkflow      # Subworkflow tests
nf-test test --tag pipeline         # Integration tests

# Run by feature area
nf-test test --tag realtime         # Real-time processing tests
nf-test test --tag qc               # QC tests
nf-test test --tag classification   # Classification tests

# Run by criticality and speed
nf-test test --tag core --tag fast # Quick critical tests (CI)

# Run single test file
nf-test test modules/local/kraken2_optimized/tests/main.nf.test

# Update snapshots
nf-test test --update-snapshot path/to/test.nf.test

# Clean and rerun
nf-test clean
nf-test test --verbose
```

`bin/run-nf-tests.sh` is a thin wrapper that exports `NXF_OFFLINE=true`
and forwards every argument verbatim to `nf-test`, so
`bin/run-nf-tests.sh test --profile test` is equivalent to the
corresponding bare `nf-test` invocation with the offline default applied.

### Test by Component
```bash
# Module tests
nf-test test modules/local/*/tests/main.nf.test --verbose      # All local modules
nf-test test modules/nf-core/*/tests/main.nf.test --verbose    # All nf-core modules

# Subworkflow tests
nf-test test subworkflows/local/*/tests/main.nf.test --verbose # All local subworkflows

# Pipeline tests
nf-test test tests/nanoseq_test.nf.test --verbose               # Basic pipeline
nf-test test tests/realtime_classification.nf.test --verbose    # Real-time mode (local only, see note)
```

**Real-time tests are excluded from CI.** The `tests/realtime_*.nf.test`
cases exercise `watchPath`, which still leaks an Apache commons-io
`FileAlterationMonitor` non-daemon thread on the GitHub `ubuntu-latest`
runner and hangs the job past its 45 min cap. The leak no longer
reproduces locally under Nextflow 26.04.0, but that verification was on
macOS/arm64 only, so the fix is treated as platform-specific rather than
general. `.github/workflows/nf-test.yml` therefore lists the tests it runs
explicitly and omits the realtime cases; real-time coverage is a local
development run. Background:
[`docs/upstream-issues/26-watchpath-cleanup-hang.md`](../upstream-issues/26-watchpath-cleanup-hang.md).

### Advanced Options
```bash
# Parallel execution (faster)
nf-test test --parallel 4 --verbose

# Debug mode
nf-test test tests/failing_test.nf.test --debug --verbose

# Stub tests only
nf-test test --tag stub

# Specific profile
NXF_PROFILE=docker nf-test test --verbose
```

---

## Table of Contents
- [Quick Reference](#quick-reference)
- [Overview](#overview)
- [Test Tag System](#test-tag-system)
- [Testing Standards](#testing-standards)
- [Running Tests](#running-tests)
- [Writing Tests](#writing-tests)
- [Best Practices](#best-practices)
- [Production Validation](#production-validation)
- [Continuous Integration](#continuous-integration)
- [Test Maintenance](#test-maintenance)
- [Troubleshooting](#troubleshooting)
- [Resources](#resources)

---

## Overview

The nanometanf pipeline uses **nf-test** as the testing framework, following nf-core best practices for pipeline testing. The test suite includes:

- **Module tests**: Unit tests for individual processes
- **Subworkflow tests**: Integration tests for subworkflows
- **Workflow tests**: End-to-end pipeline tests
- **Groovy unit tests**: Direct tests of the `lib/` helper classes

### Test Structure

Counts below were taken on 2026-07-28; re-derive with
`find . -name "*.nf.test" -not -path "./work/*" -not -path "./.nf-test/*"`.

```
83 nf-test files, 37 accompanying .snap snapshots

tests/                      19 pipeline-level tests
tests/lib/                   5 Groovy unit tests of lib/ helpers
modules/local/              25 module tests
modules/nf-core/            17 module tests
subworkflows/local/         12 subworkflow tests
subworkflows/nf-core/        5 subworkflow tests
```

---

## Test Tag System

The nanometanf pipeline uses a comprehensive hierarchical tag system for organizing and selectively executing tests. This system enables efficient CI/CD optimization, targeted test execution during development, and clear test categorization.

### Quick Start

**For developers writing tests**, see the [Quick Tagging Guide](../../tests/TAGGING_GUIDE.md) with examples and decision trees.

**For comprehensive tag reference**, see the [Tag System Specification](../../tests/tags.yml) with all categories and definitions.

### Tag Categories (Required)

Every test must have these 5 tags:

1. **Level** - Test scope: `module`, `subworkflow`, `workflow`, `pipeline`, `integration`
2. **Component Name** - Specific name: `kraken2`, `qc_analysis`, `realtime_monitoring`
3. **Feature Area** - Functional area: `realtime`, `qc`, `classification`, `validation`, `assembly`, `canonical`
4. **Speed** - Execution time: `fast` (<30s), `medium` (30s-5min), `slow` (>5min)
5. **Criticality** - Importance: `core` (must pass), `extended` (should pass), `experimental` (may fail)

### Example Tag Usage

**Module test:**
```groovy
nextflow_process {
    tag "module"
    tag "kraken2_incremental_classifier"
    tag "classification"
    tag "fast"
    tag "core"
    tag "stub"                    // Optional: test uses stub mode

    script "../main.nf"
    process "KRAKEN2_INCREMENTAL_CLASSIFIER"
    ...
}
```

**Subworkflow test:**
```groovy
nextflow_workflow {
    tag "subworkflow"
    tag "qc_analysis"
    tag "qc"
    tag "medium"
    tag "core"
    tag "edge_case"              // Optional: includes edge cases

    script "../main.nf"
    workflow "QC_ANALYSIS"
    ...
}
```

**Pipeline test:**
```groovy
nextflow_pipeline {
    tag "pipeline"
    tag "integration"
    tag "realtime"
    tag "fast"
    tag "core"
    tag "error_handling"         // Optional: tests error scenarios

    script "../main.nf"
    ...
}
```

### Common Tag Combinations for Development

```bash
# Quick CI validation (< 5 minutes)
nf-test test --tag core --tag fast

# Standard CI testing (< 30 minutes)
nf-test test --tag core

# Pre-release comprehensive testing
nf-test test --tag core --tag extended

# Quick realtime feature testing
nf-test test --tag realtime --tag fast

# All classification tests
nf-test test --tag classification

# Run stub tests only
nf-test test --tag stub

# Run specific module tests
nf-test test --tag module --tag kraken2
```

### Tag System Benefits

1. **CI/CD Optimization**: Run only critical fast tests in quick validation, full suite in pre-release
2. **Developer Productivity**: Test only relevant features during development
3. **Test Organization**: Clear categorization of the 83 test files
4. **Selective Execution**: Target specific features, platforms, or test types
5. **Documentation**: Self-documenting test purpose and requirements

### Migration to New Tag System

If you encounter tests with old tags (e.g., `modules`, `modules_local`), please update them following the [TAGGING_GUIDE.md](../../tests/TAGGING_GUIDE.md). The migration guide provides step-by-step instructions.

**Old tags (deprecated):**
```groovy
tag "modules"
tag "modules_local"
tag "process_name"
```

**New tags (required):**
```groovy
tag "module"
tag "process_name"
tag "feature_area"
tag "speed"
tag "criticality"
```

### Tag Validation

```bash
# List all available tags
nf-test list --tags

# Verify your tags work
nf-test test --tag your_new_tag --dry-run

# Find all tests with a specific tag
grep -r "tag \"your_tag\"" tests/
```

---

## Testing Standards

### 1. All Tests Must Follow This Structure

```groovy
nextflow_process {  // or nextflow_workflow, nextflow_pipeline

    name "Test PROCESS_NAME"
    script "../main.nf"
    process "PROCESS_NAME"

    // REQUIRED: Add descriptive tags (see Test Tag System section)
    tag "module"            // Level: module, subworkflow, pipeline
    tag "process_name"      // Component name
    tag "feature_area"      // Feature: realtime, qc, classification, etc.
    tag "speed"             // Speed: fast, medium, slow
    tag "criticality"       // Criticality: core, extended, experimental

    test("Should process valid input successfully") {

        when {
            process {
                """
                input[0] = [
                    [ id:'test', single_end:true ],
                    file(params.modules_testdata_base_path + 'path/to/data')
                ]
                """
            }
        }

        then {
            assertAll(
                { assert process.success },
                { assert snapshot(process.out).match() }
            )
        }
    }

    test("Should handle errors gracefully") {

        when {
            process {
                """
                input[0] = [ [ id:'test' ], [] ]  // Invalid input
                """
            }
        }

        then {
            assert process.failed
            assert process.errorMessage.contains("Expected error message")
        }
    }

    test("Should run in stub mode") {

        tag "stub"
        options "-stub"

        when {
            process {
                """
                input[0] = [ [ id:'stub' ], [] ]
                """
            }
        }

        then {
            assertAll(
                { assert process.success },
                { assert snapshot(process.out).match() }
            )
        }
    }
}
```

### 2. Use Snapshot Testing

**REQUIRED for all local modules** following nf-core best practices:

```groovy
then {
    assertAll(
        { assert process.success },
        { assert snapshot(
            process.out.reads,
            process.out.versions
        ).match() }
    )
}
```

**Benefits:**
- Catches unexpected output changes
- Easier test maintenance
- Better regression detection
- Consistent with nf-core standards

**Generate snapshots:**
```bash
nf-test test --update-snapshot path/to/test.nf.test
```

### 3. Avoid These Anti-Patterns

#### Avoid: Tautological Assertions (FIXED)
```groovy
// WRONG - Always passes
assert workflow.success || workflow.failed

// CORRECT
assert workflow.success
```

#### Avoid: Hardcoded Paths (FIXED)
```groovy
// WRONG - Not portable
kraken2_db = '/Users/username/Downloads/k2_standard'

// CORRECT - Parameterized, resolved relative to the project
kraken2_db = params.kraken2_db ?: "$projectDir/tests/fixtures/kraken2_db"
```

#### Avoid: Incomplete Assertions
```groovy
// WRONG - Only checks success
assert process.success

// CORRECT - Validates outputs
assertAll(
    { assert process.success },
    { assert snapshot(process.out).match() }
)
```

#### Avoid: Missing Stub Tests
```groovy
// WRONG - No stub test
test("Should process data") { /* ... */ }

// CORRECT - Include stub test
test("Should process data") { /* ... */ }
test("Should run in stub mode") {
    options "-stub"
    /* ... */
}
```

---

## Running Tests

### Run All Tests
```bash
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH
nf-test test
```

### Run Specific Test Types
```bash
# Module tests only
nf-test test --tag module

# Subworkflow tests
nf-test test --tag subworkflow

# Integration tests
nf-test test --tag pipeline

# By feature area
nf-test test --tag qc                  # All QC tests
nf-test test --tag realtime            # All real-time tests
nf-test test --tag classification      # All classification tests
nf-test test --tag validation          # All validation tests

# By criticality
nf-test test --tag core                # Critical tests (CI required)
nf-test test --tag extended            # Extended tests (nice to have)

# By speed
nf-test test --tag fast                # Fast tests (< 30s)
nf-test test --tag medium              # Medium tests (30s-5min)
nf-test test --tag slow                # Slow tests (> 5min)

# Combined tags
nf-test test --tag core --tag fast    # Quick CI validation
nf-test test --tag realtime --tag core # Critical real-time tests
nf-test test --tag module --tag qc     # Module-level QC tests
```

### Run Single Test File
```bash
nf-test test modules/local/kraken2_optimized/tests/main.nf.test
```

### Run with Verbose Output
```bash
nf-test test --verbose
```

### Update Snapshots
```bash
# Update all snapshots
nf-test test --update-snapshot

# Update specific test snapshots
nf-test test --update-snapshot path/to/test.nf.test
```

### Run Stub Tests Only
```bash
nf-test test --tag stub
```

### Parallel Testing
```bash
# Run tests in parallel (faster execution)
nf-test test --parallel 4 --verbose

# Limit parallel tests for resource-constrained environments
nf-test test --parallel 2 --verbose
```

### Clean and Fresh Testing
```bash
# Clean test cache before running
nf-test clean
nf-test test --verbose

# Force clean and rerun
nf-test clean --all
nf-test test tests/nanoseq_test.nf.test --verbose
```

### Debug Mode
```bash
# Run test with debug output
nf-test test tests/qc_tool_integration.nf.test --debug --verbose

# Run test with trace
nf-test test tests/parameter_validation.nf.test --trace --verbose
```

### Specific Environment Testing
```bash
# Test with specific profile
NXF_PROFILE=docker nf-test test --verbose

# Test with conda
NXF_PROFILE=conda nf-test test tests/nanoseq_test.nf.test --verbose

# Test with singularity
NXF_PROFILE=singularity nf-test test --verbose
```

---

## Writing Tests

### Module Test Template

Create: `modules/local/MODULE_NAME/tests/main.nf.test`

```groovy
nextflow_process {

    name "Test MODULE_NAME"
    script "../main.nf"
    process "MODULE_NAME"

    tag "modules"
    tag "modules_local"
    tag "module_name"

    test("Should process valid input successfully") {

        tag "happy_path"

        when {
            process {
                """
                input[0] = [
                    [ id:'test_sample', single_end:true ],
                    file('$projectDir/tests/fixtures/fastq/test_sample.fastq.gz')
                ]
                """
            }
        }

        then {
            assertAll(
                { assert process.success },
                { assert snapshot(process.out).match() }
            )
        }
    }

    test("Should handle empty input") {

        tag "edge_case"

        when {
            process {
                """
                input[0] = [ [ id:'empty' ], [] ]
                """
            }
        }

        then {
            assert process.failed
            assert process.errorMessage.contains("Empty input")
        }
    }

    test("Should run in stub mode") {

        tag "stub"
        options "-stub"

        when {
            process {
                """
                input[0] = [ [ id:'stub' ], [] ]
                """
            }
        }

        then {
            assertAll(
                { assert process.success },
                { assert snapshot(process.out).match() }
            )
        }
    }
}
```

### Subworkflow Test Template

Create: `subworkflows/local/SUBWORKFLOW_NAME/tests/main.nf.test`

```groovy
nextflow_workflow {

    name "Test SUBWORKFLOW_NAME"
    script "../main.nf"
    workflow "SUBWORKFLOW_NAME"

    tag "subworkflows"
    tag "subworkflows_local"
    tag "subworkflow_name"

    test("Should process complete workflow") {

        tag "integration"

        when {
            workflow {
                """
                input[0] = Channel.of([
                    [ id:'test', single_end:true ],
                    file('$projectDir/tests/fixtures/fastq/test_sample.fastq.gz')
                ])
                """
            }
        }

        then {
            assertAll(
                { assert workflow.success },
                { assert snapshot(
                    workflow.out.reads,
                    workflow.out.qc
                ).match() }
            )
        }
    }
}
```

### Pipeline Integration Test Template

Create: `tests/TEST_NAME.nf.test`

```groovy
nextflow_pipeline {

    name "Test WORKFLOW_NAME"
    script "main.nf"

    tag "pipeline"
    tag "integration"

    test("Should complete full pipeline") {

        tag "end_to_end"

        when {
            params {
                input = "$projectDir/tests/samplesheet.csv"
                outdir = "$outputDir"

                // Minimal resources for fast testing
                max_cpus = 2
                max_memory = '4.GB'
                max_time = '5.min'
            }
        }

        then {
            assert workflow.success
            assert snapshot(
                path("$outputDir/fastp").list(),
                path("$outputDir/multiqc").list()
            ).match()
        }
    }

    test("Should fail with invalid input") {

        tag "negative"

        when {
            params {
                input = "/nonexistent/file.csv"
                outdir = "$outputDir"
            }
        }

        then {
            assert workflow.failed
            assert workflow.errorMessage.contains("Input samplesheet not found")
        }
    }
}
```

---

## Best Practices

### 1. Test Data Management

#### Use Test Fixtures

Fixtures live under `tests/fixtures/`, grouped by kind (`fastq/`, `fasta/`,
`kraken2_db/`, `samplesheets/`, `edge_cases/`, `realtime/`, ...). See
`tests/fixtures/README.md` for the current inventory and
`tests/fixtures/generate_fixtures.py` for how they are produced.

```
tests/
  fixtures/
    fastq/             # Valid, empty and malformed FASTQ inputs
    kraken2_db/        # Minimal Kraken2 database
    samplesheets/      # Samplesheet variants
    edge_cases/        # Boundary-condition inputs
```

#### Reference with $projectDir
```groovy
file('$projectDir/tests/fixtures/fastq/test_sample.fastq.gz')
```

#### Create Minimal Test Data
```bash
# Create small FASTQ for testing (100 reads)
seqtk sample -s100 large.fastq.gz 100 | gzip > tests/fixtures/fastq/test.fastq.gz
```

### 2. Test Organization

#### Tag Hierarchy
```groovy
// Level 1: Type
tag "modules"           // or "subworkflows", "pipeline"

// Level 2: Scope
tag "modules_local"     // or "modules_nfcore", "subworkflows_local"

// Level 3: Component
tag "kraken2_optimized" // specific module/subworkflow name

// Level 4: Test Type (in individual tests)
tag "happy_path"        // or "edge_case", "negative", "stub"
```

#### File Structure
```
modules/local/MODULE_NAME/
  main.nf
  meta.yml
  environment.yml
  tests/
    main.nf.test
    main.nf.test.snap
```

### 3. Assertion Best Practices

#### Use assertAll for Multiple Checks
```groovy
then {
    assertAll(
        { assert process.success },
        { assert process.out.reads.size() == 1 },
        { assert snapshot(process.out).match() }
    )
}
```

#### Validate Error Messages
```groovy
then {
    assert process.failed
    assert process.errorMessage.contains("Expected error")
    assert process.exitStatus == 1
}
```

#### Check Meta Propagation
```groovy
then {
    def (meta, file) = process.out.reads[0]
    assert meta.id == 'expected_id'
    assert meta.single_end == true
    assert snapshot(process.out).match()
}
```

### 4. Performance Testing

#### Set Resource Limits
```groovy
when {
    params {
        max_cpus = 2
        max_memory = '4.GB'
        max_time = '5.min'
    }
}
```

#### Test Execution Time
```groovy
then {
    assert workflow.success
    assert workflow.duration.toMillis() < 60000  // Under 1 minute
}
```

### 5. Negative Testing

#### Test Error Conditions
```groovy
test("Should fail with missing required parameter") {
    tag "negative"

    when {
        params {
            input = null  // Missing required param
        }
    }

    then {
        assert workflow.failed
        assert workflow.errorMessage.contains("input is required")
    }
}
```

#### Test Invalid Data
```groovy
test("Should handle corrupted input gracefully") {
    tag "edge_case"

    when {
        process {
            """
            input[0] = [
                [ id:'corrupted' ],
                file('$projectDir/tests/fixtures/corrupted.fastq.gz')
            ]
            """
        }
    }

    then {
        assert process.failed
        assert process.errorMessage.contains("Invalid FASTQ format")
    }
}
```

---

## Production Validation

### Pre-deployment Testing

#### 1. Complete Test Suite
```bash
# Export Java environment (required)
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH

# Run comprehensive test suite
nf-test test --verbose --parallel 2
```

#### 2. Platform Profile Testing
```bash
# Test with platform profile
nextflow run . \
    --input tests/test_samplesheet.csv \
    --outdir test_production_output \
    -profile test,minion

# Test real-time mode
nextflow run . \
    --realtime_mode \
    --nanopore_output_dir tests/fixtures \
    --outdir test_realtime_output \
    -profile test
```

#### 3. Canonical Output Validation
```bash
# Verify canonical output layer
nf-test test --tag canonical --verbose
```

### Performance Benchmarking

#### 1. Speed Benchmarks
```bash
# Time complete test suite
time nf-test test --verbose

# Benchmark specific workflows
time nf-test test tests/nanoseq_test.nf.test --verbose
time nf-test test tests/classification_real.nf.test --verbose
```

#### 2. Resource Usage
```bash
# Monitor resource usage during tests
htop &
nf-test test tests/classification_real.nf.test --verbose

# Memory usage monitoring
free -h && nf-test test tests/nanoseq_test.nf.test --verbose && free -h
```

#### 3. Scalability Testing
```bash
# Test with multiple samples
nf-test test tests/subworkflow_integration.nf.test --verbose

# Test real-time processing scalability (local only, excluded from CI)
nf-test test subworkflows/local/realtime_monitoring/tests/main.nf.test --verbose
nf-test test tests/realtime_input_modes.nf.test --verbose
```

---

## Continuous Integration

### GitHub Actions Integration

The pipeline uses automated CI/CD testing via GitHub Actions. See `.github/workflows/nf-test.yml` for complete configuration.

**Key workflows:**
- **nf-test.yml**: Runs the nf-test suite on push/PR under `-profile test,docker`
- **linting.yml**: Runs nf-core lint checks
- **ci.yml**: Comprehensive CI including multiple Nextflow versions

`nf-test.yml` does not run `nf-test test` unqualified: it lists the test
files to execute so the `tests/realtime_*.nf.test` cases stay out of CI for
the `watchPath` thread-leak reason described in
[Test by Component](#test-by-component). A new test file is therefore not
picked up by CI until it is added to that list.

### Automated Testing Commands

```bash
# Pre-commit testing
git add .
nf-test test tests/parameter_validation.nf.test --verbose
git commit -m "Update: validated changes"

# Pre-push testing
nf-test test --parallel 2 --verbose
git push origin feature-branch

# Release testing
nf-test test --verbose
nf-test clean --all
nf-test test --verbose
```

---

## Test Maintenance

### Regular Testing Schedule

**Daily:**
```bash
# Quick validation
nf-test test tests/parameter_validation.nf.test --verbose
```

**Weekly:**
```bash
# Complete module tests
nf-test test modules/local/*/tests/main.nf.test --verbose
```

**Monthly:**
```bash
# Full test suite
nf-test test --verbose --parallel 2
```

**Before Releases:**
```bash
# Comprehensive validation
nf-test clean --all
nf-test test --verbose
nf-test test --profile docker --verbose
nf-test test --profile conda --verbose
```

### Test Updates

```bash
# Update test data (if using nf-core test-datasets)
curl -L https://github.com/nf-core/test-datasets/archive/nanoseq.tar.gz | \
    tar -xz --strip-components=1 -C assets/test_data/

# Validate test updates
nf-test test tests/nanoseq_test.nf.test --verbose

# Update test expectations
nf-test test tests/updated_test.nf.test --update-snapshot --verbose
```

---

## Troubleshooting

### Common Issues

#### 1. Snapshot Mismatch
```
Error: Snapshot mismatch
```

**Solution:**
```bash
# Review changes
nf-test test path/to/test.nf.test

# If changes are expected, update snapshot
nf-test test --update-snapshot path/to/test.nf.test
```

#### 2. Missing Test Data
```
Error: File not found: /path/to/test/data
```

**Solution:**
```bash
# Check file exists
ls -la $projectDir/tests/fixtures/

# Use correct path format
file('$projectDir/tests/fixtures/fastq/test_sample.fastq.gz')
```

#### 3. Process Fails in Test
```
Error: Process failed with exit code 1
```

**Solution:**
```bash
# Run with verbose output
nf-test test --verbose path/to/test.nf.test

# Check process logs
cat .nf-test/tests/*/work/*/.command.log
```

#### 4. Stub Test Failures
```
Error: Stub mode failed
```

**Solution:**
- Ensure process has `stub:` block in main.nf
- Validate stub outputs match expected structure
- Use snapshot testing for stub validation

#### 5. Resource Issues
```bash
# Reduce parallel tests
nf-test test --parallel 1 --verbose

# Check system resources
free -h
df -h
ulimit -a
```

#### 6. Environment Issues
```bash
# Check Java environment
echo $JAVA_HOME
java -version

# Check Nextflow version
nextflow -version

# Check container availability
docker images | grep nanometanf
singularity --version
```

#### 7. Test Data Issues
```bash
# Verify test data integrity
md5sum tests/test_sample.fastq.gz
head -4 tests/test_sample.fastq.gz

# Regenerate test data if needed
curl -L https://github.com/nf-core/test-datasets/raw/nanoseq/testdata/fastq/sample_minimal.fastq.gz \
    -o tests/test_sample.fastq.gz
```

### Debug Mode Testing

```bash
# Enable debug mode
export NF_DEBUG=1
nf-test test tests/qc_tool_integration.nf.test --debug --verbose

# Trace execution
export NF_TRACE=1
nf-test test tests/nanoseq_test.nf.test --trace --verbose

# Keep work directories
nf-test test tests/parameter_validation.nf.test --verbose --keep-work-dir
```

### Debug Commands

```bash
# Show test details
nf-test test --verbose

# Show all test tags
nf-test list --tags

# Run single test with full output
nf-test test --verbose path/to/test.nf.test

# Clean test cache
rm -rf .nf-test/

# Validate test syntax
nf-test test --dry-run
```

---

## Test Coverage Goals

### Current Status (measured 2026-07-28)
- Module tests: all 25 local modules have a test file
- Snapshot coverage: 37 of 83 test files have a `.snap` (45%; target 80%+)

### Improvement Roadmap

**Phase 1: Critical Fixes (Completed)**
- Fix tautological assertions
- Remove hardcoded paths
- Add comprehensive tags

**Phase 2: Snapshot Testing (In Progress)**
- Add snapshots to canonical writer modules
- Add snapshots to remaining local modules

**Phase 3: Enhanced Coverage (Planned)**
- Add edge case tests for all modules
- Add negative tests for error conditions
- Add performance benchmarks

---

## Resources

### Documentation
- [nf-test documentation](https://www.nf-test.com/)
- [nf-core testing guidelines](https://nf-co.re/docs/contributing/modules#tests)
- [Nextflow testing patterns](https://www.nextflow.io/docs/latest/dsl2.html#testing)

### Examples
- See `modules/nf-core/*/tests/` for nf-core test examples
- See `modules/local/kraken2_optimized/tests/` for a local module test with snapshots
- See `tests/nanoseq_test.nf.test` for integration test examples
- See `tests/lib/batch_utils.nf.test` for a Groovy unit test of a `lib/` helper

### Support
- Pipeline issues: https://github.com/foi-bioinformatics/nanometanf/issues
- nf-test issues: https://github.com/askimed/nf-test/issues

---

**Last Updated:** 2025-11-04
**Version:** 1.1
**Maintainer:** foi-bioinformatics team

**Note**: This comprehensive testing guide should be followed rigorously before any production deployments. All tests must pass before considering the pipeline production-ready.
