# Developer API Documentation

Technical reference for extending and customizing nanometanf.

## Architecture Overview

```
nanometanf/
├── main.nf                    # Entry point
├── workflows/
│   └── nanometanf.nf          # Main workflow orchestration
├── subworkflows/local/        # Pipeline subworkflows
├── modules/local/             # Custom modules
├── modules/nf-core/           # nf-core modules
├── conf/                      # Configuration files
└── bin/                       # Auxiliary scripts
```

---

## Adding Custom Modules

### Module Structure

**Standard module template**:
```groovy
// modules/local/custom_tool/main.nf

process CUSTOM_TOOL {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' ?
        'https://depot.galaxyproject.org/singularity/tool:version' :
        'biocontainers/tool:version' }"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("*.output"), emit: results
    path "versions.yml"              , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    custom_tool \\
        --input $input_file \\
        --output ${prefix}.output \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        custom_tool: \$(custom_tool --version)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.output

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        custom_tool: 1.0.0
    END_VERSIONS
    """
}
```

### Module Testing

**Create test file**:
```groovy
// modules/local/custom_tool/tests/main.nf.test

nextflow_process {
    name "Test Process CUSTOM_TOOL"
    script "../main.nf"
    process "CUSTOM_TOOL"

    test("Should process test data successfully") {
        when {
            process {
                """
                input[0] = [
                    [id: 'test'],
                    file(params.test_data['test_file'], checkIfExists: true)
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
}
```

**Run tests**:
```bash
nf-test test modules/local/custom_tool/tests/main.nf.test
```

---

## Creating Subworkflows

### Subworkflow Template

```groovy
// subworkflows/local/custom_analysis/main.nf

include { CUSTOM_TOOL     } from '../../modules/local/custom_tool/main'
include { POSTPROCESS     } from '../../modules/local/postprocess/main'
include { GENERATE_REPORT } from '../../modules/local/generate_report/main'

workflow CUSTOM_ANALYSIS {
    take:
    ch_input  // channel: [ val(meta), path(fastq) ]

    main:
    ch_versions = Channel.empty()

    // Step 1: Run custom tool
    CUSTOM_TOOL (
        ch_input
    )
    ch_versions = ch_versions.mix(CUSTOM_TOOL.out.versions)

    // Step 2: Post-process results
    POSTPROCESS (
        CUSTOM_TOOL.out.results
    )
    ch_versions = ch_versions.mix(POSTPROCESS.out.versions)

    // Step 3: Generate report
    GENERATE_REPORT (
        POSTPROCESS.out.processed
    )
    ch_versions = ch_versions.mix(GENERATE_REPORT.out.versions)

    emit:
    results  = POSTPROCESS.out.processed
    reports  = GENERATE_REPORT.out.html
    versions = ch_versions
}
```

### Integrating Subworkflow

```groovy
// workflows/nanometanf.nf

include { CUSTOM_ANALYSIS } from '../subworkflows/local/custom_analysis/main'

workflow NANOMETANF {
    // ... existing code ...

    // Add custom analysis
    if (params.enable_custom_analysis) {
        CUSTOM_ANALYSIS (
            ch_fastq
        )
        ch_multiqc_files = ch_multiqc_files.mix(
            CUSTOM_ANALYSIS.out.reports.collect{it[1]}
        )
    }
}
```

---

## Configuration API

### Process Configuration

**Configure resources**:
```groovy
// conf/custom.config

process {
    withName: 'CUSTOM_TOOL' {
        cpus   = 8
        memory = 16.GB
        time   = 4.h

        // Tool-specific arguments
        ext.args = '--option1 --option2'

        // Conditional execution
        ext.when = { params.enable_custom_analysis }

        // Custom prefix
        ext.prefix = { "${meta.id}.custom" }
    }
}
```

**Use custom config**:
```bash
nextflow run ... -c conf/custom.config
```

---

### Parameter Schema

**Add new parameters**:
```json
// nextflow_schema.json

{
  "definitions": {
    "custom_analysis_options": {
      "title": "Custom Analysis Options",
      "type": "object",
      "properties": {
        "enable_custom_analysis": {
          "type": "boolean",
          "default": false,
          "description": "Enable custom analysis module"
        },
        "custom_tool_database": {
          "type": "string",
          "description": "Path to custom tool database",
          "format": "directory-path"
        }
      }
    }
  }
}
```

**Validate schema**:
```bash
nf-core schema lint
nf-core schema validate --params params.json
```

---

## Channel Manipulation

### Common Channel Operations

```groovy
// Split channel by condition
ch_input
    .branch {
        pass: it[0].qscore >= 10
        fail: it[0].qscore < 10
    }
    .set { ch_branched }

// Combine channels
ch_fastq
    .join(ch_metadata, by: [0])  // Join on meta.id
    .set { ch_combined }

// Group by barcode
ch_samples
    .groupTuple(by: [0])  // Group by meta
    .set { ch_grouped }

// Mix multiple channels
Channel.empty()
    .mix(ch_source1)
    .mix(ch_source2)
    .set { ch_mixed }

// Map to transform
ch_input
    .map { meta, file ->
        def new_meta = meta + [processed: true]
        [new_meta, file]
    }
    .set { ch_transformed }
```

### Meta Map Convention

**Standard meta map structure**:
```groovy
meta = [
    id: 'sample001',           // Required: unique identifier
    barcode: 'BC01',           // Optional: barcode ID
    single_end: false,         // Required for nf-core compatibility
    // Custom fields:
    qscore: 12.5,
    read_count: 1000000,
    condition: 'treatment'
]
```

---

## Testing Infrastructure

### nf-test Configuration

```groovy
// nf-test.config

config {
    testsDir "tests"
    workDir ".nf-test"
    configFile "nextflow.config"
    profile "docker"
}
```

### Snapshot Testing

```groovy
// Use snapshots for reproducible testing
test("Should produce consistent output") {
    when {
        process {
            """
            input[0] = [
                [id: 'test'],
                file('test_data.fastq')
            ]
            """
        }
    }

    then {
        assertAll(
            { assert process.success },
            // Snapshot entire output
            { assert snapshot(process.out).match() },
            // Or snapshot specific files
            { assert snapshot(
                file(process.out.results[0][1]).readLines()
            ).match() }
        )
    }
}
```

**Generate snapshots**:
```bash
nf-test test --update-snapshot
```

---

## MultiQC Integration

### Custom MultiQC Module

**Create custom content**:
```groovy
// modules/local/custom_mqc/main.nf

process CUSTOM_MQC {
    input:
    val(stats)

    output:
    path "*_mqc.json", emit: multiqc_files

    script:
    """
    #!/usr/bin/env python3
    import json

    data = {
        "id": "custom_stats",
        "section_name": "Custom Statistics",
        "plot_type": "table",
        "data": ${groovy.json.JsonOutput.toJson(stats)}
    }

    with open('custom_stats_mqc.json', 'w') as f:
        json.dump(data, f, indent=2)
    """
}
```

**MultiQC config**:
```yaml
# assets/multiqc_config.yml

custom_data:
  custom_stats:
    file_format: 'json'
    section_name: 'Custom Analysis'
    plot_type: 'table'

sp:
  custom_stats:
    fn: "*_custom_stats_mqc.json"
```

---

## Error Handling

### Retry Logic

```groovy
// conf/base.config

process {
    errorStrategy = { task.exitStatus in [143,137,104,134,139] ? 'retry' : 'finish' }
    maxRetries    = 2
    maxErrors     = '-1'

    // Exponential backoff
    time          = { check_max( 4.h * task.attempt, 'time' ) }
    memory        = { check_max( 8.GB * task.attempt, 'memory' ) }
}
```

### Custom Error Handling

```groovy
process CUSTOM_TOOL {
    errorStrategy { task.exitStatus == 2 ? 'ignore' : 'retry' }

    script:
    """
    set +e  // Don't exit on error

    custom_tool --input $input

    if [ \$? -eq 2 ]; then
        echo "Warning: Non-critical error occurred" >&2
        touch ${prefix}.empty.output
        exit 0
    fi
    """
}
```

---

## Hooks and Plugins

### Workflow Hooks

```groovy
// workflows/nanometanf.nf

workflow {
    workflow.onComplete {
        log.info """
        Pipeline execution summary
        ---------------------------
        Completed at: ${workflow.complete}
        Duration    : ${workflow.duration}
        Success     : ${workflow.success}
        Work Dir    : ${workflow.workDir}
        Exit status : ${workflow.exitStatus}
        """.stripIndent()
    }

    workflow.onError {
        log.error "Pipeline failed: ${workflow.errorMessage}"
        // Send notification
    }
}
```

### nf-core Plugins

```groovy
// nextflow.config

plugins {
    id 'nf-validation'
}

validation {
    parametersSchema = 'nextflow_schema.json'
}
```

---

## Performance Optimization

### Dynamic Resource Allocation

**Implement resource functions**:
```groovy
// lib/WorkflowNanometanf.groovy

class WorkflowNanometanf {
    public static Integer calculateMemory(Map meta, Integer base) {
        Integer multiplier = 1

        if (meta.read_count > 10000000) multiplier = 4
        else if (meta.read_count > 1000000) multiplier = 2

        return base * multiplier
    }

    public static Integer calculateCPUs(Map meta, Integer base) {
        return meta.containsKey('barcode') ? base * 2 : base
    }
}
```

**Use in process**:
```groovy
process ADAPTIVE_PROCESS {
    cpus { WorkflowNanometanf.calculateCPUs(meta, 4) }
    memory { WorkflowNanometanf.calculateMemory(meta, 8.GB) }

    script:
    """
    tool --threads ${task.cpus} --input $input
    """
}
```

---

## CI/CD Integration

### GitHub Actions Workflow

```yaml
# .github/workflows/ci.yml

name: nf-core CI
on:
  push:
    branches: [main, dev]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install Nextflow
        uses: nf-core/setup-nextflow@v1

      - name: Run pipeline tests
        run: |
          nf-test test --profile docker,test

      - name: Run nf-core linting
        run: |
          pip install nf-core
          nf-core lint
```

---

## Module Development Checklist

When creating a new module:

- [ ] Follow nf-core module template
- [ ] Include both `script` and `stub` sections
- [ ] Emit `versions.yml`
- [ ] Add conda `environment.yml`
- [ ] Specify container images
- [ ] Create nf-test test file
- [ ] Generate test snapshots
- [ ] Add documentation header
- [ ] Test with multiple inputs
- [ ] Verify resource requirements
- [ ] Check MultiQC integration

---

## API Reference

### Core Functions

**Available in workflows**:
```groovy
// Get pipeline version
WorkflowMain.initialise(workflow, params, log)

// Validate parameters
WorkflowNanometanf.initialise(params, log)

// Check maximum resources
check_max(value, type)  // type: 'memory', 'cpus', 'time'
```

### Channel Factories

```groovy
// From samplesheet
Channel
    .fromPath(params.input)
    .splitCsv(header:true)
    .map { row ->
        def meta = [id: row.sample, single_end: true]
        [meta, file(row.fastq)]
    }

// From directory
Channel
    .fromPath("${params.input_dir}/*.fastq.gz")
    .map { file ->
        def meta = [id: file.baseName]
        [meta, file]
    }
```

---

## Additional Resources

- **nf-core modules**: https://nf-co.re/modules
- **Nextflow patterns**: https://nextflow-io.github.io/patterns/
- **nf-test docs**: https://code.askimed.com/nf-test/
- **Pipeline template**: https://github.com/nf-core/tools

---

## Example: Complete Custom Module

See `modules/local/` for real examples:
- `dorado_basecaller/` - Complex GPU-aware module
- `multiqc_nanopore_stats/` - Python-based analysis
- `krona_kraken2/` - Data transformation module

For questions or contributions:
- Open an issue: https://github.com/foi-bioinformatics/nanometanf/issues
- Join nf-core Slack: https://nf-co.re/join
