# Stub Kraken2 Test Database

This directory contains **stub files** for Kraken2 database testing. These are minimal placeholder files that allow tests to pass parameter validation, but they do NOT contain actual classification data.

## Files

- `hash.k2d` - Stub hash table file (27 bytes)
- `opts.k2d` - Stub options file (21 bytes)
- `taxo.k2d` - Stub taxonomy file (22 bytes)

## Usage

These stub files are used for:

1. **Parameter validation tests** - Verify that the pipeline correctly handles the `kraken2_db` parameter
2. **Workflow structure tests** - Test that process connections work correctly
3. **Stub-mode testing** - Tests using `stub:` blocks don't need real data

## Limitations

- Tests using this database will NOT produce meaningful classification results
- For tests requiring actual Kraken2 output, use pre-created fixture data in `tests/fixtures/validation/`
- The stub database cannot be used for functional classification testing

## For Functional Testing

If you need to test actual Kraken2 classification:

1. Use a small real database (e.g., minikraken2 or a custom minimal database)
2. Use pre-generated Kraken2 output files as test fixtures
3. Mock the Kraken2 output in test setup blocks

## Related Fixtures

- `tests/fixtures/validation/test_kraken_output.txt` - Pre-generated Kraken2 output for validation tests
- `tests/fixtures/validation/test_genomes.json` - Genome mappings for validation
