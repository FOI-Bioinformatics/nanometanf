# Test Tagging Guide

## Quick Reference

Each test needs 2 required tags and optionally a feature tag:

```groovy
nextflow_pipeline {
    tag "core"      // REQUIRED: criticality (core or extended)
    tag "fast"      // REQUIRED: speed (fast or slow)
    tag "qc"        // OPTIONAL: feature area

    test("...") { ... }
}
```

## Required Tags

| Tag        | Purpose            | CI Usage                |
| ---------- | ------------------ | ----------------------- |
| `core`     | Must-pass tests    | `--tag core`            |
| `extended` | Nice-to-pass tests | Release only            |
| `fast`     | < 1 minute         | `--tag core --tag fast` |
| `slow`     | > 1 minute         | Full suite              |

## Optional Feature Tags

- `realtime` - Real-time processing
- `basecalling` - Dorado basecalling
- `qc` - Quality control
- `classification` - Taxonomic classification
- `barcode_discovery` - Barcode detection

## Optional Structure Tags

- `pipeline` - Full pipeline tests
- `module` - Individual module tests
- `integration` - Integration tests

## Running Tests

```bash
# Quick validation
nf-test test --tag core --tag fast

# All core tests
nf-test test --tag core

# Specific feature
nf-test test --tag qc

# Full suite
nf-test test
```
