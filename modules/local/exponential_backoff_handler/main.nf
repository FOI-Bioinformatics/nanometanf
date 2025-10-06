process EXPONENTIAL_BACKOFF_HANDLER {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'biocontainers/python:3.11' }"

    input:
    tuple val(meta), val(retry_count)
    val(base_delay)      // Base delay in seconds (default: 2)
    val(max_delay)       // Maximum delay in seconds (default: 300 = 5 minutes)
    val(backoff_factor)  // Exponential backoff factor (default: 2.0)

    output:
    tuple val(meta), env(DELAY_SECONDS), env(SHOULD_RETRY), emit: backoff_decision
    path "backoff_report.json", emit: backoff_report
    path "versions.yml"        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def base = base_delay ?: 2
    def max = max_delay ?: 300
    def factor = backoff_factor ?: 2.0
    """
    #!/usr/bin/env python3
    import json
    import math
    import os
    import sys
    from datetime import datetime, timedelta

    retry_count = ${retry_count}
    base_delay = ${base}
    max_delay = ${max}
    backoff_factor = ${factor}

    def calculate_exponential_backoff(attempt, base=2, factor=2.0, max_delay=300):
        \"\"\"
        Calculate exponential backoff delay with jitter.

        Formula: delay = min(base * (factor ** attempt), max_delay)

        Args:
            attempt: Retry attempt number (0-indexed)
            base: Base delay in seconds
            factor: Exponential growth factor
            max_delay: Maximum delay cap in seconds

        Returns:
            delay_seconds: Calculated delay
        \"\"\"
        # Calculate exponential delay
        delay = base * (factor ** attempt)

        # Cap at max_delay
        delay = min(delay, max_delay)

        # Add jitter (±10%) to prevent thundering herd
        import random
        jitter = delay * random.uniform(-0.1, 0.1)
        delay_with_jitter = delay + jitter

        return max(0, delay_with_jitter)  # Ensure non-negative

    # Calculate backoff delay
    delay_seconds = calculate_exponential_backoff(
        retry_count,
        base_delay,
        backoff_factor,
        max_delay
    )

    # Determine if we should continue retrying
    max_retries = 10  # Hard limit on retry attempts
    should_retry = retry_count < max_retries

    # Calculate next retry time
    next_retry_time = datetime.now() + timedelta(seconds=delay_seconds)

    # Generate backoff report
    backoff_report = {
        'sample_id': "${meta.id}",
        'retry_count': retry_count,
        'delay_seconds': round(delay_seconds, 2),
        'should_retry': should_retry,
        'next_retry_time': next_retry_time.isoformat(),
        'backoff_config': {
            'base_delay': base_delay,
            'max_delay': max_delay,
            'backoff_factor': backoff_factor,
            'max_retries': max_retries
        },
        'metadata': ${groovy.json.JsonOutput.toJson(meta)}
    }

    # Write JSON report
    with open('backoff_report.json', 'w') as f:
        json.dump(backoff_report, f, indent=2)

    # Export decision for Nextflow
    with open(os.environ.get('NXF_TASK_WORKDIR', '.') + '/.command.env', 'w') as f:
        f.write(f"DELAY_SECONDS={int(delay_seconds)}\\n")
        f.write(f"SHOULD_RETRY={'YES' if should_retry else 'NO'}\\n")

    # Log backoff decision
    if should_retry:
        print(f"⏱️  BACKOFF: Retry {retry_count + 1} scheduled in {delay_seconds:.1f}s", file=sys.stderr)
        print(f"   Next attempt: {next_retry_time.strftime('%Y-%m-%d %H:%M:%S')}", file=sys.stderr)
    else:
        print(f"🛑 MAX RETRIES: Stopping after {retry_count} attempts", file=sys.stderr)

    # Write versions
    with open('versions.yml', 'w') as f:
        f.write('"${task.process}":\\n')
        f.write(f'  python: {sys.version.split()[0]}\\n')
    """

    stub:
    """
    echo "DELAY_SECONDS=5" > .command.env
    echo "SHOULD_RETRY=YES" >> .command.env
    echo '{"sample_id": "${meta.id}", "retry_count": ${retry_count}, "delay_seconds": 5, "should_retry": true}' > backoff_report.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/Python //g')
    END_VERSIONS
    """
}
