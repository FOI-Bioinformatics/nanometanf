process ERROR_CLASSIFIER {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'biocontainers/python:3.11' }"

    input:
    tuple val(meta), val(error_message), val(error_type)

    output:
    tuple val(meta), val(error_message), env(ERROR_CATEGORY), env(RETRY_RECOMMENDED), emit: classified_error
    path "error_report.json", emit: error_report
    path "versions.yml"     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    #!/usr/bin/env python3
    import json
    import re
    import os
    import sys

    # Error classification rules
    RETRYABLE_PATTERNS = {
        'file_io': [
            r'Permission denied',
            r'Resource temporarily unavailable',
            r'No such file or directory',
            r'File is locked',
            r'File still being written',
            r'Connection timed out',
            r'Network is unreachable'
        ],
        'resource_exhaustion': [
            r'Out of memory',
            r'Disk quota exceeded',
            r'No space left on device',
            r'Too many open files'
        ],
        'transient_network': [
            r'Connection refused',
            r'Connection reset',
            r'Temporary failure',
            r'Service unavailable'
        ]
    }

    FATAL_PATTERNS = {
        'data_corruption': [
            r'Invalid.*format',
            r'Corrupted.*file',
            r'Checksum.*failed',
            r'Unexpected end of file'
        ],
        'configuration': [
            r'Invalid parameter',
            r'Missing required',
            r'Configuration error',
            r'Schema validation failed'
        ],
        'unsupported': [
            r'Unsupported.*version',
            r'Incompatible.*format',
            r'Feature not available'
        ]
    }

    error_message = """${error_message}"""
    error_type = "${error_type}"

    def classify_error(message, err_type):
        \"\"\"
        Classify error as RETRYABLE or FATAL based on pattern matching.
        Returns: (category, is_retryable, confidence, reason)
        \"\"\"
        # Check retryable patterns
        for category, patterns in RETRYABLE_PATTERNS.items():
            for pattern in patterns:
                if re.search(pattern, message, re.IGNORECASE):
                    return (category, True, 0.9, f"Matched retryable pattern: {pattern}")

        # Check fatal patterns
        for category, patterns in FATAL_PATTERNS.items():
            for pattern in patterns:
                if re.search(pattern, message, re.IGNORECASE):
                    return (category, False, 0.95, f"Matched fatal pattern: {pattern}")

        # Default classification based on error type
        if err_type in ['IOException', 'FileNotFoundError', 'PermissionError']:
            return ('file_io', True, 0.7, "Error type suggests transient I/O issue")
        elif err_type in ['ValueError', 'TypeError', 'KeyError']:
            return ('configuration', False, 0.8, "Error type suggests configuration problem")
        else:
            return ('unknown', False, 0.5, "Unable to classify - defaulting to FATAL for safety")

    # Classify the error
    category, is_retryable, confidence, reason = classify_error(error_message, error_type)

    # Generate error report
    error_report = {
        'sample_id': "${meta.id}",
        'error_message': error_message,
        'error_type': error_type,
        'classification': {
            'category': category,
            'is_retryable': is_retryable,
            'confidence': confidence,
            'reason': reason
        },
        'metadata': ${groovy.json.JsonOutput.toJson(meta)}
    }

    # Write JSON report
    with open('error_report.json', 'w') as f:
        json.dump(error_report, f, indent=2)

    # Export classification for Nextflow
    with open(os.environ.get('NXF_TASK_WORKDIR', '.') + '/.command.env', 'w') as f:
        f.write(f"ERROR_CATEGORY={category}\\n")
        f.write(f"RETRY_RECOMMENDED={'YES' if is_retryable else 'NO'}\\n")

    # Log classification
    if is_retryable:
        print(f"🔄 RETRYABLE ERROR: {category} (confidence: {confidence:.0%})", file=sys.stderr)
        print(f"   Reason: {reason}", file=sys.stderr)
    else:
        print(f"❌ FATAL ERROR: {category} (confidence: {confidence:.0%})", file=sys.stderr)
        print(f"   Reason: {reason}", file=sys.stderr)

    # Write versions
    with open('versions.yml', 'w') as f:
        f.write('"${task.process}":\\n')
        f.write(f'  python: {sys.version.split()[0]}\\n')
    """

    stub:
    """
    echo "ERROR_CATEGORY=unknown" > .command.env
    echo "RETRY_RECOMMENDED=NO" >> .command.env
    echo '{"sample_id": "${meta.id}", "classification": {"category": "unknown", "is_retryable": false}}' > error_report.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/Python //g')
    END_VERSIONS
    """
}
