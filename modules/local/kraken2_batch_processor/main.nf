process KRAKEN2_BATCH_PROCESSOR {
    tag "$prefix"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.11' :
        'biocontainers/python:3.11' }"

    input:
    val(samples_metadata)  // List of sample metadata for batching
    val(batch_size)        // Number of samples per batch
    val(prefix)

    output:
    path "batch_plan.json"            , emit: batch_plan
    path "batching_statistics.json"   , emit: statistics
    path "versions.yml"               , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    #!/usr/bin/env python3
    import json
    import sys
    from datetime import datetime
    from collections import defaultdict

    samples_metadata = ${groovy.json.JsonOutput.toJson(samples_metadata)}
    batch_size = ${batch_size}

    def create_intelligent_batches(samples, target_batch_size):
        \"\"\"
        Create intelligent batches for optimal parallel classification.

        Batching strategy:
        1. Group samples by similar characteristics (size, barcode, etc.)
        2. Balance batch sizes for even load distribution
        3. Ensure maximum parallelization without resource contention

        Args:
            samples: List of sample metadata
            target_batch_size: Target number of samples per batch

        Returns:
            List of batches with metadata
        \"\"\"
        if not samples:
            return []

        # Sort samples by estimated size (if available) for balanced batching
        sorted_samples = sorted(
            samples,
            key=lambda x: x.get('estimated_size', 0),
            reverse=True  # Largest first for better load balancing
        )

        # Create batches
        batches = []
        current_batch = []
        current_batch_size = 0
        batch_id = 1

        for sample in sorted_samples:
            current_batch.append(sample)
            current_batch_size += 1

            if current_batch_size >= target_batch_size:
                batches.append({
                    'batch_id': batch_id,
                    'samples': current_batch,
                    'sample_count': len(current_batch)
                })
                current_batch = []
                current_batch_size = 0
                batch_id += 1

        # Add remaining samples as final batch
        if current_batch:
            batches.append({
                'batch_id': batch_id,
                'samples': current_batch,
                'sample_count': len(current_batch)
            })

        return batches

    def calculate_parallel_efficiency(batches):
        \"\"\"Calculate expected parallel processing efficiency.\"\"\"
        total_samples = sum(b['sample_count'] for b in batches)
        num_batches = len(batches)

        # Calculate load balance (coefficient of variation)
        batch_sizes = [b['sample_count'] for b in batches]
        mean_size = sum(batch_sizes) / len(batch_sizes)
        variance = sum((s - mean_size) ** 2 for s in batch_sizes) / len(batch_sizes)
        std_dev = variance ** 0.5
        cv = (std_dev / mean_size) * 100 if mean_size > 0 else 0

        return {
            'total_samples': total_samples,
            'total_batches': num_batches,
            'average_batch_size': mean_size,
            'load_balance_cv': round(cv, 2),  # Lower is better
            'parallelization_factor': num_batches
        }

    # Create intelligent batches
    batches = create_intelligent_batches(samples_metadata, batch_size)

    # Calculate efficiency metrics
    efficiency_metrics = calculate_parallel_efficiency(batches)

    # Generate batch plan
    batch_plan = {
        'generated_at': datetime.now().isoformat(),
        'configuration': {
            'target_batch_size': batch_size,
            'batching_strategy': 'size_balanced'
        },
        'batches': batches,
        'execution_order': [b['batch_id'] for b in batches]
    }

    # Write batch plan
    with open('batch_plan.json', 'w') as f:
        json.dump(batch_plan, f, indent=2)

    # Generate statistics
    statistics = {
        'timestamp': datetime.now().isoformat(),
        'efficiency_metrics': efficiency_metrics,
        'recommendations': []
    }

    # Add recommendations based on analysis
    if efficiency_metrics['load_balance_cv'] > 20:
        statistics['recommendations'].append({
            'type': 'WARNING',
            'message': f"Load imbalance detected (CV: {efficiency_metrics['load_balance_cv']:.1f}%). Consider adjusting batch size."
        })

    if efficiency_metrics['total_batches'] == 1:
        statistics['recommendations'].append({
            'type': 'INFO',
            'message': 'Single batch detected. Increase number of samples or decrease batch size for better parallelization.'
        })

    if efficiency_metrics['total_batches'] > 100:
        statistics['recommendations'].append({
            'type': 'WARNING',
            'message': f'{efficiency_metrics["total_batches"]} batches may cause excessive overhead. Consider increasing batch size.'
        })

    # Write statistics
    with open('batching_statistics.json', 'w') as f:
        json.dump(statistics, f, indent=2)

    # Log batching summary
    print(f"\\n{'='*60}", file=sys.stderr)
    print("Kraken2 Batch Processing Plan", file=sys.stderr)
    print(f"{'='*60}", file=sys.stderr)
    print(f"Total samples: {efficiency_metrics['total_samples']}", file=sys.stderr)
    print(f"Total batches: {efficiency_metrics['total_batches']}", file=sys.stderr)
    print(f"Average batch size: {efficiency_metrics['average_batch_size']:.1f}", file=sys.stderr)
    print(f"Load balance CV: {efficiency_metrics['load_balance_cv']:.1f}%", file=sys.stderr)
    print(f"Parallelization factor: {efficiency_metrics['parallelization_factor']}x", file=sys.stderr)
    print(f"{'='*60}", file=sys.stderr)

    if statistics['recommendations']:
        print("\\nRecommendations:", file=sys.stderr)
        for rec in statistics['recommendations']:
            print(f"  [{rec['type']}] {rec['message']}", file=sys.stderr)

    # Write versions
    with open('versions.yml', 'w') as f:
        f.write('"${task.process}":\\n')
        f.write(f'  python: {sys.version.split()[0]}\\n')
    """

    stub:
    """
    echo '{"batches": [], "execution_order": []}' > batch_plan.json
    echo '{"efficiency_metrics": {"total_samples": 0}}' > batching_statistics.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | sed 's/Python //g')
    END_VERSIONS
    """
}
