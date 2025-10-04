# Test Fixtures

This directory contains persistent test data used by nf-test test cases.

## Purpose

These fixtures solve the timing issue where pipeline validation runs before nf-test `setup{}` blocks execute. By pre-creating test data, tests can reference existing files instead of generating them dynamically.

## Directory Structure

```
fixtures/
├── samplesheets/     # Pre-generated samplesheet CSV files
│   ├── minimal.csv           # Single sample, no barcode
│   ├── barcoded.csv          # Multiple samples with barcodes
│   ├── large_scale.csv       # Many samples for performance testing
│   └── edge_case.csv         # Edge cases and malformed data
├── fastq/            # Test FASTQ files (minimal size)
│   ├── test_sample.fastq.gz  # Generic test sample
│   ├── barcode01.fastq.gz    # Barcoded sample 1
│   └── barcode02.fastq.gz    # Barcoded sample 2
└── pod5/             # Test POD5 files (symlinks to assets)
    └── batch_0.pod5          # Minimal POD5 from nf-core test-datasets
```

## Usage in Tests

**Before (setup block - causes failures):**
```groovy
setup {
    """
    cat > $outputDir/test_samplesheet.csv << 'EOF'
sample,fastq,barcode
TEST,$outputDir/test.fastq.gz,
EOF
    """
}

when {
    params {
        input = "$outputDir/test_samplesheet.csv"  // FAILS - doesn't exist yet!
    }
}
```

**After (using fixtures - works):**
```groovy
when {
    params {
        input = "$projectDir/tests/fixtures/samplesheets/minimal.csv"  // EXISTS!
        outdir = "$outputDir"
    }
}
```

## File Paths

All samplesheet files use **absolute paths** to FASTQ/POD5 files to ensure they work regardless of test execution context.

## Updating Fixtures

To add new test data:

1. Create the data file in appropriate subdirectory
2. Create/update samplesheet in `samplesheets/` with absolute path
3. Document the fixture purpose in this README
4. Use in test with `$projectDir/tests/fixtures/...`

## Notes

- **Do NOT** use `setup{}` blocks to create samplesheets for workflow/pipeline tests
- **DO** use fixtures for all integration and workflow tests
- **Module tests** can still use `setup{}` since they don't trigger pipeline validation
- Keep fixture files minimal (< 1KB) to avoid repository bloat
