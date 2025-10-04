#!/usr/bin/env nextflow

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PIPELINE VALIDATION MODULE FOR NANOMETANF
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Comprehensive validation system for inputs, outputs, and pipeline integrity
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

process PIPELINE_VALIDATOR {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.9--1':
        'biocontainers/python:3.9--1' }"

    input:
    tuple val(meta), path(input_files)
    val validation_config

    output:
    tuple val(meta), path("*.validation_report.json"), emit: report
    tuple val(meta), path("*.validation_summary.txt"), emit: summary
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def validation_type = task.ext.validation_type ?: 'comprehensive'
    """
    pipeline_validator.py \\
        --sample_id "${meta.id}" \\
        --input_files ${input_files.join(' ')} \\
        --validation_config "${validation_config}" \\
        --validation_type "${validation_type}" \\
        --output_prefix "${prefix}" \\
        --enable_checksums \\
        --enable_format_validation \\
        --enable_content_validation \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
        pipeline_validator: 1.0.0
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Create comprehensive validation report matching real output structure
    cat > ${prefix}.validation_report.json << 'EOF'
{
    "sample_id": "${meta.id}",
    "validation_timestamp": "\$(date -Iseconds)",
    "validation_type": "comprehensive",
    "validation_results": {
        "overall_status": "passed",
        "total_checks": 15,
        "passed_checks": 14,
        "failed_checks": 1,
        "warnings": 2,
        "validation_score": 0.93
    },
    "input_validation": {
        "status": "passed",
        "checks_performed": {
            "file_existence": {
                "status": "passed",
                "files_checked": 3,
                "files_valid": 3,
                "missing_files": []
            },
            "file_format": {
                "status": "passed",
                "formats_validated": ["fastq", "pod5", "json"],
                "invalid_formats": []
            },
            "file_integrity": {
                "status": "passed",
                "checksums_verified": true,
                "corrupted_files": []
            },
            "file_size": {
                "status": "passed",
                "total_size_bytes": 52428800,
                "total_size_mb": 50.0,
                "size_warnings": []
            }
        }
    },
    "content_validation": {
        "status": "warning",
        "checks_performed": {
            "sequence_quality": {
                "status": "passed",
                "min_quality_score": 9,
                "avg_quality_score": 12.5,
                "low_quality_reads": 0
            },
            "read_count": {
                "status": "passed",
                "total_reads": 12500,
                "expected_min_reads": 1000,
                "read_count_sufficient": true
            },
            "sequence_length": {
                "status": "warning",
                "avg_read_length": 1500,
                "min_read_length": 100,
                "max_read_length": 50000,
                "short_reads_count": 150,
                "short_reads_warning": true
            },
            "data_completeness": {
                "status": "passed",
                "required_fields_present": true,
                "missing_metadata": []
            }
        }
    },
    "pipeline_integrity": {
        "status": "passed",
        "checks_performed": {
            "parameter_validation": {
                "status": "passed",
                "required_params_present": true,
                "invalid_params": [],
                "param_conflicts": []
            },
            "dependency_check": {
                "status": "passed",
                "all_dependencies_available": true,
                "missing_dependencies": []
            },
            "resource_availability": {
                "status": "passed",
                "cpu_available": true,
                "memory_sufficient": true,
                "disk_space_sufficient": true
            }
        }
    },
    "output_validation": {
        "status": "failed",
        "checks_performed": {
            "output_structure": {
                "status": "passed",
                "expected_outputs_present": true,
                "missing_outputs": []
            },
            "output_format": {
                "status": "failed",
                "format_compliance": false,
                "non_compliant_files": ["sample_taxonomy.txt"],
                "format_issues": ["Missing header in taxonomy file"]
            },
            "data_consistency": {
                "status": "passed",
                "internal_consistency": true,
                "cross_file_consistency": true
            }
        }
    },
    "validation_warnings": [
        {
            "type": "data_quality",
            "severity": "low",
            "message": "150 short reads detected (length < 500bp)",
            "recommendation": "Consider adjusting quality filtering parameters"
        },
        {
            "type": "output_format",
            "severity": "medium",
            "message": "Taxonomy output missing standard header",
            "recommendation": "Verify output format compliance"
        }
    ],
    "validation_errors": [
        {
            "type": "format_validation",
            "severity": "medium",
            "file": "sample_taxonomy.txt",
            "message": "Output file does not comply with expected format",
            "resolution": "Review file format and regenerate if necessary"
        }
    ],
    "recommendations": [
        "Address format compliance issue in taxonomy output",
        "Review short read filtering thresholds",
        "All other validation checks passed successfully"
    ]
}
EOF

    # Create comprehensive validation summary
    cat > ${prefix}.validation_summary.txt << 'EOF'
Pipeline Validation Summary for ${meta.id}
==========================================
Validation Timestamp: \$(date "+%Y-%m-%d %H:%M:%S")
Validation Type: Comprehensive

Overall Status: PASSED (with warnings)
Validation Score: 93%

Checks Summary:
  Total Checks:   15
  Passed:         14
  Failed:          1
  Warnings:        2

Input Validation: PASSED
  ✓ File existence checks
  ✓ File format validation
  ✓ File integrity (checksums verified)
  ✓ File size validation (50.0 MB total)

Content Validation: WARNING
  ✓ Sequence quality (avg Q12.5)
  ✓ Read count (12,500 reads)
  ⚠ Sequence length (150 short reads detected)
  ✓ Data completeness

Pipeline Integrity: PASSED
  ✓ Parameter validation
  ✓ Dependency availability
  ✓ Resource availability

Output Validation: FAILED
  ✓ Output structure complete
  ✗ Output format (taxonomy file format issue)
  ✓ Data consistency

Warnings:
  1. Low severity - 150 short reads detected
  2. Medium severity - Taxonomy output missing header

Errors:
  1. Format validation - sample_taxonomy.txt format non-compliant

Recommendations:
  • Address format compliance issue in taxonomy output
  • Review short read filtering thresholds
  • Re-run validation after corrections

Validation completed: \$(date "+%Y-%m-%d %H:%M:%S")
EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
        pipeline_validator: 1.0.0
    END_VERSIONS
    """
}