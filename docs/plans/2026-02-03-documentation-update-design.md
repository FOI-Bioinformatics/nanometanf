# Documentation Update Design

**Date:** 2026-02-03
**Status:** Implemented

## Overview

This document describes the documentation updates made to align with v1.5.0dev changes and fix accuracy issues.

## Changes Made

### CLAUDE.md (AI Development Guide)

1. **Updated test counts** - Changed from "18 pipeline + 30 module" to "17 pipeline + 38 module" tests
2. **Added INPUT_SCANNER subworkflow** - New unified input directory scanning
3. **Added Library Utilities section** - Documented InputDetector, BatchUtils, and other lib/ files
4. **Updated input modes** - Added `--input_dir` parameter, marked `barcode_input_dir` as deprecated
5. **Updated recent changes** - Added InputDetector, BatchUtils refactoring, test suite fixes

### README.md (User-Facing Overview)

1. **Updated test count** - Changed from "94 nf-tests" to "55 nf-tests"

### docs/README.md (Documentation Hub)

1. **Updated date** - Changed to 2026-02-03

### docs/development/README.md (Developer Hub)

1. **Added lib/ to key files table**
2. **Added Library Utilities section** - Documented InputDetector, BatchUtils
3. **Updated date** - Changed to 2026-02-03

## Design Principles Applied

### Single Source of Truth
- CLAUDE.md is the authoritative source for architecture details
- Other docs reference CLAUDE.md rather than duplicating content

### Non-Redundancy
- Brief summaries with links to detailed docs
- Architecture details live in CLAUDE.md only

### Accuracy
- Test counts reflect actual test files (17 + 38 = 55)
- Recent refactoring documented (InputDetector, BatchUtils)

## Files Modified

- `/CLAUDE.md`
- `/README.md`
- `/docs/README.md`
- `/docs/development/README.md`

## Verification

After these changes:
- Test counts match `find . -name "*.nf.test" | wc -l` results
- Recent commits (InputDetector, BatchUtils) are documented
- Dates are current (2026-02-03)
