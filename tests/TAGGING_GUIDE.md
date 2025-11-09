# Test Tagging Quick Reference Guide

**For developers: How to tag your nf-test tests**

## TL;DR - Quick Tagging Checklist

When writing a new test, add these tags (in order):

```groovy
tag "level"           // module, subworkflow, workflow, or pipeline
tag "name"            // The specific component name
tag "feature"         // Feature area (realtime, qc, basecalling, etc.)
tag "speed"           // fast, medium, or slow
tag "criticality"     // core, extended, or experimental
```

**Example:**
```groovy
nextflow_process {
    tag "module"
    tag "kraken2"
    tag "classification"
    tag "fast"
    tag "core"

    script "../main.nf"
    process "KRAKEN2"
    ...
}
```

---

## Tag Categories (In Priority Order)

### 1. Level (REQUIRED)
Pick ONE:
- `module` - Testing a single process
- `subworkflow` - Testing multiple coordinated processes
- `workflow` - Testing workflow logic
- `pipeline` - Testing complete pipeline
- `integration` - Testing component interactions

### 2. Component Name (REQUIRED)
Use the actual name:
- Module: `kraken2`, `dorado_basecaller`, `chopper`
- Subworkflow: `realtime_monitoring`, `qc_analysis`, `taxonomic_classification`
- Workflow: `nanometanf_workflow`

### 3. Feature Area (REQUIRED)
Pick the PRIMARY feature:
- `realtime` - Real-time processing
- `basecalling` - Dorado basecalling
- `qc` - Quality control
- `classification` - Taxonomic classification
- `validation` - BLAST validation
- `resource_allocation` - Dynamic resources (experimental)
- `error_handling` - Error handling
- `barcode_discovery` - Barcode discovery

### 4. Speed (REQUIRED)
- `fast` - < 30 seconds (use with stub mode)
- `medium` - 30s - 5 minutes
- `slow` - > 5 minutes (integration tests)

### 5. Criticality (REQUIRED)
- `core` - Must pass for release (CI required)
- `extended` - Should pass (nice to have)
- `experimental` - May fail (under development)

### 6. Optional Tags
Add these only when relevant:
- **Test Type:** `unit`, `integration`, `edge_case`, `performance`, `stub`, `snapshot`, `regression`
- **Platform:** `linux`, `macos`, `apple_silicon`, `gpu`, `docker`, `singularity`
- **Data:** `small_data`, `medium_data`, `large_data`, `requires_db`

---

## Common Tag Patterns

### Module Tests

```groovy
nextflow_process {
    tag "module"
    tag "kraken2"
    tag "classification"
    tag "fast"
    tag "core"
    tag "stub"              // If using stub mode

    script "../main.nf"
    process "KRAKEN2"
    ...
}
```

### Subworkflow Tests

```groovy
nextflow_workflow {
    tag "subworkflow"
    tag "realtime_monitoring"
    tag "realtime"
    tag "medium"
    tag "core"
    tag "integration"

    workflow "REALTIME_MONITORING"
    ...
}
```

### Pipeline Tests

```groovy
nextflow_pipeline {
    tag "pipeline"
    tag "integration"
    tag "realtime"
    tag "slow"
    tag "extended"

    when {
        params {
            ...
        }
    }
    ...
}
```

### Edge Case Tests

```groovy
nextflow_process {
    tag "module"
    tag "dorado_basecaller"
    tag "basecalling"
    tag "fast"
    tag "extended"
    tag "edge_case"         // Add edge_case type
    tag "error_handling"    // If testing error scenarios

    ...
}
```

---

## Tag Usage Examples

### Run all core tests (CI)
```bash
nf-test test --tag core
```

### Run fast tests for quick validation
```bash
nf-test test --tag fast
```

### Run all realtime feature tests
```bash
nf-test test --tag realtime
```

### Run Kraken2 module tests
```bash
nf-test test --tag kraken2
```

### Run core realtime tests (CI for realtime features)
```bash
nf-test test --tag core --tag realtime
```

### Run all module tests
```bash
nf-test test --tag module
```

### Run fast stub tests
```bash
nf-test test --tag fast --tag stub
```

---

## Decision Tree

**What are you testing?**

→ **A single process?**
  - Level: `module`
  - Name: Process name (e.g., `kraken2`)
  - Feature: What it does (e.g., `classification`)

→ **Multiple processes working together?**
  - Level: `subworkflow`
  - Name: Subworkflow name (e.g., `realtime_monitoring`)
  - Feature: Main functionality (e.g., `realtime`)

→ **Complete pipeline?**
  - Level: `pipeline`
  - Name: Usually skip (use `integration` instead)
  - Feature: What you're testing (e.g., `realtime`)

**How fast does it run?**
- Stub mode or tiny data → `fast`
- Real processing, small data → `medium`
- Full integration test → `slow`

**How critical is it?**
- Core functionality → `core`
- Nice-to-have feature → `extended`
- Experimental/WIP → `experimental`

---

## Anti-Patterns (Don't Do This)

❌ **Don't use generic tags:**
```groovy
tag "test"       // Too generic
tag "quick"      // Use "fast" instead
tag "important"  // Use "core" instead
```

❌ **Don't skip required tags:**
```groovy
// Missing speed and criticality!
tag "module"
tag "kraken2"
tag "classification"
```

❌ **Don't over-tag:**
```groovy
// Too many tags!
tag "module"
tag "kraken2"
tag "classification"
tag "fast"
tag "core"
tag "unit"
tag "integration"
tag "snapshot"
tag "stub"
tag "regression"
tag "linux"
tag "docker"
tag "small_data"
// Only use what's truly relevant!
```

✅ **Do this instead:**
```groovy
tag "module"
tag "kraken2"
tag "classification"
tag "fast"
tag "core"
tag "stub"           // Only because it uses stub mode
```

---

## Special Cases

### Real-time Tests
Always include these tags:
```groovy
tag "realtime"
tag "integration"    // Real-time always involves multiple components
```

### Basecalling Tests
```groovy
tag "basecalling"
tag "dorado_basecaller"  // Or "dorado_demux"
```

### Edge Cases/Error Handling
```groovy
tag "edge_case"          // The test type
tag "error_handling"     // If testing error scenarios
```

### Performance Tests
```groovy
tag "performance"
tag "slow"               // Performance tests are usually slow
```

### Stub Mode Tests
Always add:
```groovy
tag "stub"
tag "fast"               // Stub tests are always fast
```

---

## Migration Guide

### Updating Existing Tests

1. **Identify the test level:**
   - Does it test a process? → `module`
   - Does it test a subworkflow? → `subworkflow`
   - Does it test complete pipeline? → `pipeline`

2. **Add component name:**
   - Look at the `script` or `workflow` directive
   - Use the actual process/workflow name

3. **Identify feature area:**
   - What functionality is being tested?
   - Real-time? QC? Classification?

4. **Estimate speed:**
   - Does it use stub? → `fast`
   - Does it process real data? → `medium`
   - Is it an integration test? → `slow`

5. **Determine criticality:**
   - Core functionality? → `core`
   - Nice-to-have? → `extended`
   - Experimental? → `experimental`

### Example Migration

**Before:**
```groovy
nextflow_process {
    script "../main.nf"
    process "KRAKEN2"
    ...
}
```

**After:**
```groovy
nextflow_process {
    tag "module"              // It's a process
    tag "kraken2"             // Process name
    tag "classification"      // It does taxonomic classification
    tag "fast"                // Uses stub mode
    tag "core"                // Critical functionality
    tag "stub"                // Uses stub blocks

    script "../main.nf"
    process "KRAKEN2"
    ...
}
```

---

## Tagging Script

For bulk tagging, use the helper script:
```bash
# Analyze test file and suggest tags
./tests/scripts/suggest_tags.sh tests/my_test.nf.test

# Auto-tag all untagged tests (with confirmation)
./tests/scripts/auto_tag.sh --dry-run
```

---

## Validation

After adding tags, verify:
```bash
# Check if your tags are recognized
nf-test test --tag your_new_tag --dry-run

# List all tests with your tag
grep -r "tag \"your_tag\"" tests/
```

---

## FAQ

**Q: Do I need to tag every test?**
A: Yes, at minimum: level, name, feature, speed, criticality.

**Q: Can I add multiple feature tags?**
A: Pick the PRIMARY feature. Add secondary features only if truly needed.

**Q: What if my test doesn't fit any category?**
A: Use the closest match, then document why in the test description.

**Q: Should I tag tests during development?**
A: Yes! Tag as you write. It helps with selective testing during development.

**Q: How do I find tests to work on?**
A: `grep -r "nextflow_" tests/ | grep -v "tag \"" | head` finds untagged tests.

---

## Resources

- **Full Tag Reference:** `tests/tags.yml`
- **Testing Guide:** `docs/development/TESTING.md`
- **Examples:** `tests/*/main.nf.test` (look for well-tagged tests)

---

**Last Updated:** 2025-11-05
**Maintainer:** foi-bioinformatics team (@andreassjodin)
