process CIRCUIT_BREAKER {
    tag "$prefix"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'biocontainers/python:3.11' }"

    input:
    val(failure_history)  // List of [sample_id, error_category, timestamp] tuples
    val(failure_threshold)  // Number of failures before circuit opens (default: 5)
    val(time_window)        // Time window in seconds for failure counting (default: 300 = 5 min)
    val(prefix)

    output:
    env(CIRCUIT_STATE)           , emit: circuit_state
    path "circuit_breaker_report.json", emit: breaker_report
    path "versions.yml"                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def threshold = failure_threshold ?: 5
    def window = time_window ?: 300
    """
    #!/usr/bin/env python3
    import json
    import os
    import sys
    from datetime import datetime, timedelta
    from collections import Counter

    failure_history = ${groovy.json.JsonOutput.toJson(failure_history)}
    failure_threshold = ${threshold}
    time_window = ${window}

    def analyze_circuit_breaker(failures, threshold, window_seconds):
        \"\"\"
        Analyze failure patterns and determine circuit breaker state.

        Circuit states:
        - CLOSED: Normal operation, requests pass through
        - OPEN: Too many failures, stop processing
        - HALF_OPEN: Testing recovery after cooldown period

        Args:
            failures: List of failure records with timestamps
            threshold: Number of failures to trigger OPEN state
            window_seconds: Time window for counting failures

        Returns:
            state, metrics, recommendation
        \"\"\"
        if not failures:
            return 'CLOSED', {}, 'No failures detected - circuit is healthy'

        # Parse timestamps and filter to time window
        now = datetime.now()
        cutoff_time = now - timedelta(seconds=window_seconds)

        recent_failures = []
        for failure in failures:
            try:
                failure_time = datetime.fromisoformat(failure.get('timestamp', ''))
                if failure_time >= cutoff_time:
                    recent_failures.append(failure)
            except (ValueError, TypeError):
                continue

        failure_count = len(recent_failures)

        # Analyze failure patterns
        error_categories = Counter(f.get('error_category', 'unknown') for f in recent_failures)
        affected_samples = set(f.get('sample_id', 'unknown') for f in recent_failures)

        metrics = {
            'total_failures': failure_count,
            'failure_threshold': threshold,
            'time_window_seconds': window_seconds,
            'error_categories': dict(error_categories),
            'affected_samples': list(affected_samples),
            'failure_rate': failure_count / window_seconds if window_seconds > 0 else 0
        }

        # Determine circuit state
        if failure_count >= threshold:
            state = 'OPEN'
            recommendation = f"Circuit OPEN: {failure_count} failures in {window_seconds}s exceeds threshold of {threshold}. Stop processing to prevent cascading failures."
        elif failure_count >= threshold * 0.7:
            state = 'HALF_OPEN'
            recommendation = f"Circuit HALF_OPEN: {failure_count} failures approaching threshold ({threshold}). Proceed with caution."
        else:
            state = 'CLOSED'
            recommendation = f"Circuit CLOSED: {failure_count} failures within acceptable limits. Continue normal processing."

        return state, metrics, recommendation

    # Analyze circuit breaker state
    circuit_state, metrics, recommendation = analyze_circuit_breaker(
        failure_history,
        failure_threshold,
        time_window
    )

    # Generate circuit breaker report
    breaker_report = {
        'timestamp': datetime.now().isoformat(),
        'circuit_state': circuit_state,
        'metrics': metrics,
        'recommendation': recommendation,
        'configuration': {
            'failure_threshold': failure_threshold,
            'time_window_seconds': time_window
        }
    }

    # Write JSON report
    with open('circuit_breaker_report.json', 'w') as f:
        json.dump(breaker_report, f, indent=2)

    # Export circuit state for Nextflow
    with open(os.environ.get('NXF_TASK_WORKDIR', '.') + '/.command.env', 'w') as f:
        f.write(f"CIRCUIT_STATE={circuit_state}\\n")

    # Log circuit breaker decision
    if circuit_state == 'OPEN':
        print(f"🚨 CIRCUIT BREAKER OPEN: {metrics['total_failures']} failures detected", file=sys.stderr)
        print(f"   {recommendation}", file=sys.stderr)
    elif circuit_state == 'HALF_OPEN':
        print(f"⚠️  CIRCUIT BREAKER HALF-OPEN: Approaching failure threshold", file=sys.stderr)
        print(f"   {recommendation}", file=sys.stderr)
    else:
        print(f"✅ CIRCUIT BREAKER CLOSED: System healthy ({metrics['total_failures']} failures)", file=sys.stderr)

    # Write versions
    with open('versions.yml', 'w') as f:
        f.write('"${task.process}":\\n')
        f.write(f'  python: {sys.version.split()[0]}\\n')
    """

    stub:
    """
    echo "CIRCUIT_STATE=CLOSED" > .command.env
    echo '{"timestamp": "2025-01-01T00:00:00", "circuit_state": "CLOSED", "metrics": {"total_failures": 0}}' > circuit_breaker_report.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/Python //g')
    END_VERSIONS
    """
}
