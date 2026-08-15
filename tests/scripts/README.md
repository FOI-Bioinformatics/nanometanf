# Test Automation Scripts

Helper scripts for test management and migration.

## apply_tags.sh

Analyzes test files and suggests appropriate tags based on the new hierarchical tag system.

### Quick Start

```bash
# Analyze a single test file
./tests/scripts/apply_tags.sh --dry-run modules/local/kraken2/tests/main.nf.test

# Analyze all module tests
./tests/scripts/apply_tags.sh --batch-modules

# Analyze all subworkflow tests
./tests/scripts/apply_tags.sh --batch-subworkflows
```

### Features

- **Automatic detection** of test level (module/subworkflow/pipeline)
- **Component name extraction** from file path
- **Feature area inference** from component name
- **Speed estimation** based on stub mode and test level
- **Criticality assignment** based on feature importance
- **Optional tag detection** (stub, snapshot)

### Tag Detection Heuristics

**Level Detection:**

- Path contains `modules/` → `module`
- Path contains `subworkflows/` → `subworkflow`
- Path in `tests/` directory → `pipeline`

**Feature Area Detection:**

- Contains `kraken`, `classification` → `classification`
- Contains `qc`, `fastp`, `chopper`, `nanoplot` → `qc`
- Contains `realtime`, `monitoring` → `realtime`
- Contains `blast`, `validation` → `validation`
- Contains `barcode`, `demux` → `barcode_discovery`

**Speed Detection:**

- Uses `options "-stub"` → `fast`
- Contains `max_time = '1.min'` → `fast`
- Contains `max_time = '[2-5].min'` → `medium`
- Default for modules → `fast`
- Default for subworkflows → `medium`
- Default for pipelines → `slow`

**Criticality Detection:**

- Features: qc, classification, realtime → `core`
- Features: validation, barcode_discovery → `extended`
- Features: resource_allocation, error_handling → `experimental`

### Output Format

The script generates ready-to-paste Groovy tag blocks:

```groovy
// Test Level & Component
tag "module"
tag "kraken2"

// Feature Area
tag "classification"

// Execution Speed & Criticality
tag "fast"
tag "core"

// Test Type
tag "stub"
tag "snapshot"
```

### Limitations

- **Manual application required**: Script suggests tags but doesn't modify files automatically
- **Heuristic-based**: Tag suggestions may need manual adjustment
- **Feature detection**: Complex modules may require manual feature classification

### Workflow

1. Run script in dry-run mode to see suggestions
2. Review suggested tags for accuracy
3. Manually copy tag block to test file
4. Adjust tags if needed based on [TAGGING_GUIDE.md](../TAGGING_GUIDE.md)

### Future Enhancements

- Automatic tag insertion into test files
- Interactive tag selection
- Validation against tags.yml schema
- Batch processing with confirmation prompts

---

**Last Updated:** 2025-11-05
**Maintainer:** foi-bioinformatics team (@andreassjodin)
