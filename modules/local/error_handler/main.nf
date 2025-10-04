#!/usr/bin/env nextflow

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ERROR HANDLING MODULE FOR NANOMETANF
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Comprehensive error handling, recovery, and validation system
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

process ERROR_HANDLER {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.9--1':
        'biocontainers/python:3.9--1' }"

    input:
    tuple val(meta), path(error_files)
    val error_context

    output:
    tuple val(meta), path("*.error_analysis.json"), emit: analysis
    tuple val(meta), path("*.recovery_plan.json"), emit: recovery
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    error_handler.py \\
        --sample_id "${meta.id}" \\
        --error_files ${error_files.join(' ')} \\
        --error_context "${error_context}" \\
        --output_prefix "${prefix}" \\
        --analysis_level comprehensive \\
        --generate_recovery_plan \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
        error_handler: 1.0.0
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Create comprehensive error analysis JSON
    cat > ${prefix}.error_analysis.json << 'EOF'
{
    "sample_id": "${meta.id}",
    "error_context": "${error_context}",
    "analysis_timestamp": "\$(date -Iseconds)",
    "error_classification": {
        "error_type": "stub_test_error",
        "severity": "low",
        "category": "validation",
        "is_recoverable": true
    },
    "error_details": {
        "affected_files": ["stub_error_file.txt"],
        "error_message": "Stub mode error simulation",
        "stack_trace": "N/A - stub mode",
        "process_exit_code": 0
    },
    "impact_analysis": {
        "data_loss_risk": "none",
        "pipeline_impact": "minimal",
        "downstream_effects": [],
        "estimated_recovery_time_minutes": 5
    },
    "root_cause_analysis": {
        "probable_cause": "test_mode_execution",
        "contributing_factors": ["stub_execution"],
        "similar_errors_count": 0
    },
    "recommendations": [
        "Review error context",
        "Check input file integrity",
        "Verify process configuration"
    ]
}
EOF

    # Create comprehensive recovery plan JSON
    cat > ${prefix}.recovery_plan.json << 'EOF'
{
    "sample_id": "${meta.id}",
    "recovery_timestamp": "\$(date -Iseconds)",
    "recovery_strategy": {
        "strategy_type": "automatic_retry",
        "confidence_score": 0.95,
        "estimated_success_probability": 0.98
    },
    "recovery_steps": [
        {
            "step_number": 1,
            "action": "validate_input_files",
            "description": "Verify all input files are accessible and valid",
            "estimated_duration_seconds": 30,
            "required_resources": {"cpu": 1, "memory_mb": 512}
        },
        {
            "step_number": 2,
            "action": "retry_failed_process",
            "description": "Re-execute failed process with validated inputs",
            "estimated_duration_seconds": 120,
            "required_resources": {"cpu": 2, "memory_mb": 2048}
        },
        {
            "step_number": 3,
            "action": "verify_outputs",
            "description": "Validate generated outputs meet quality criteria",
            "estimated_duration_seconds": 60,
            "required_resources": {"cpu": 1, "memory_mb": 1024}
        }
    ],
    "fallback_options": [
        {
            "option": "alternative_tool",
            "tool_name": "backup_validator",
            "applicability": "high"
        },
        {
            "option": "manual_intervention",
            "required_expertise": "moderate",
            "estimated_manual_time_minutes": 30
        }
    ],
    "resource_requirements": {
        "total_cpu_cores": 2,
        "total_memory_mb": 4096,
        "estimated_total_time_minutes": 5,
        "disk_space_mb": 500
    },
    "monitoring_checkpoints": [
        "input_validation_complete",
        "process_execution_started",
        "outputs_generated",
        "quality_checks_passed"
    ]
}
EOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python --version | sed 's/Python //g')
        error_handler: 1.0.0
    END_VERSIONS
    """
}