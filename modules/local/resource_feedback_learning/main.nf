process COLLECT_PERFORMANCE_FEEDBACK {
    tag "$meta.id"
    label 'process_single'
    publishDir "${params.outdir}/resource_analysis/feedback", mode: 'copy'

    input:
    tuple val(meta), path(predictions), path(allocations), path(actual_metrics)
    val learning_config

    output:
    tuple val(meta), path("${meta.id}_feedback_data.json"), emit: feedback
    path "performance_learning_update.json", emit: learning_update
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    #!/usr/bin/env python3
    
    import json
    import os
    import math
    import numpy as np
    from datetime import datetime, timedelta
    from pathlib import Path
    
    # Load input data
    meta = ${groovy.json.JsonBuilder(meta).toString()}
    learning_config = ${groovy.json.JsonBuilder(learning_config).toString()}
    
    # Load prediction, allocation, and actual performance data
    with open('${predictions}', 'r') as f:
        predictions = json.load(f)
    
    with open('${allocations}', 'r') as f:
        allocations = json.load(f)
    
    with open('${actual_metrics}', 'r') as f:
        actual_metrics = json.load(f)
    
    def calculate_prediction_accuracy(predictions, actual_metrics):
        \"\"\"Calculate accuracy of resource predictions vs actual usage\"\"\"
        
        accuracy_metrics = {
            'cpu_accuracy': {},
            'memory_accuracy': {},
            'runtime_accuracy': {},
            'overall_accuracy': {}
        }
        
        # CPU accuracy
        predicted_cpu = predictions.get('predictions', {}).get('cpu_requirements', {}).get('predicted_cores', 1)
        actual_cpu = actual_metrics.get('resource_usage', {}).get('peak_cpu_cores', predicted_cpu)
        
        cpu_error = abs(predicted_cpu - actual_cpu) / max(predicted_cpu, 1)
        accuracy_metrics['cpu_accuracy'] = {
            'predicted': predicted_cpu,
            'actual': actual_cpu,
            'error_percentage': round(cpu_error * 100, 2),
            'accuracy_score': round(max(0, 1 - cpu_error), 3)
        }
        
        # Memory accuracy
        predicted_memory = predictions.get('predictions', {}).get('memory_requirements', {}).get('predicted_memory_gb', 4)
        actual_memory = actual_metrics.get('resource_usage', {}).get('peak_memory_gb', predicted_memory)
        
        memory_error = abs(predicted_memory - actual_memory) / max(predicted_memory, 1)
        accuracy_metrics['memory_accuracy'] = {
            'predicted': predicted_memory,
            'actual': actual_memory,
            'error_percentage': round(memory_error * 100, 2),
            'accuracy_score': round(max(0, 1 - memory_error), 3)
        }
        
        # Runtime accuracy
        predicted_runtime = predictions.get('predictions', {}).get('runtime_estimates', {}).get('predicted_runtime_hours', 1)
        actual_runtime = actual_metrics.get('timing', {}).get('total_runtime_hours', predicted_runtime)
        
        runtime_error = abs(predicted_runtime - actual_runtime) / max(predicted_runtime, 0.1)
        accuracy_metrics['runtime_accuracy'] = {
            'predicted': predicted_runtime,
            'actual': actual_runtime,
            'error_percentage': round(runtime_error * 100, 2),
            'accuracy_score': round(max(0, 1 - runtime_error), 3)
        }
        
        # Overall accuracy (weighted average)
        weights = {'cpu': 0.3, 'memory': 0.4, 'runtime': 0.3}
        overall_score = (
            weights['cpu'] * accuracy_metrics['cpu_accuracy']['accuracy_score'] +
            weights['memory'] * accuracy_metrics['memory_accuracy']['accuracy_score'] +
            weights['runtime'] * accuracy_metrics['runtime_accuracy']['accuracy_score']
        )
        
        accuracy_metrics['overall_accuracy'] = {
            'score': round(overall_score, 3),
            'level': 'high' if overall_score > 0.8 else 'medium' if overall_score > 0.6 else 'low'
        }
        
        return accuracy_metrics
    
    def analyze_resource_efficiency(allocations, actual_metrics):
        \"\"\"Analyze how efficiently allocated resources were used\"\"\"
        
        efficiency_metrics = {
            'cpu_efficiency': {},
            'memory_efficiency': {},
            'resource_waste': {},
            'optimization_opportunities': []
        }
        
        # CPU efficiency
        allocated_cpu = allocations.get('optimized_allocation', {}).get('cpu_cores', 1)
        actual_peak_cpu = actual_metrics.get('resource_usage', {}).get('peak_cpu_cores', allocated_cpu)
        avg_cpu_usage = actual_metrics.get('resource_usage', {}).get('avg_cpu_utilization_percent', 50) / 100.0
        
        cpu_utilization = actual_peak_cpu / max(allocated_cpu, 1)
        efficiency_metrics['cpu_efficiency'] = {
            'allocated_cores': allocated_cpu,
            'peak_used_cores': actual_peak_cpu,
            'average_utilization': round(avg_cpu_usage * 100, 1),
            'peak_utilization': round(cpu_utilization * 100, 1),
            'efficiency_score': round(min(cpu_utilization, 1.0), 3)
        }
        
        # Memory efficiency
        allocated_memory = allocations.get('optimized_allocation', {}).get('memory_gb', 4)
        actual_peak_memory = actual_metrics.get('resource_usage', {}).get('peak_memory_gb', allocated_memory)
        avg_memory_usage = actual_metrics.get('resource_usage', {}).get('avg_memory_utilization_percent', 50) / 100.0
        
        memory_utilization = actual_peak_memory / max(allocated_memory, 1)
        efficiency_metrics['memory_efficiency'] = {
            'allocated_gb': allocated_memory,
            'peak_used_gb': actual_peak_memory,
            'average_utilization': round(avg_memory_usage * 100, 1),
            'peak_utilization': round(memory_utilization * 100, 1),
            'efficiency_score': round(min(memory_utilization, 1.0), 3)
        }
        
        # Resource waste analysis
        cpu_waste = max(0, allocated_cpu - actual_peak_cpu)
        memory_waste = max(0, allocated_memory - actual_peak_memory)
        
        efficiency_metrics['resource_waste'] = {
            'cpu_cores_wasted': round(cpu_waste, 1),
            'memory_gb_wasted': round(memory_waste, 1),
            'cpu_waste_percentage': round((cpu_waste / max(allocated_cpu, 1)) * 100, 1),
            'memory_waste_percentage': round((memory_waste / max(allocated_memory, 1)) * 100, 1)
        }
        
        # Optimization opportunities
        if cpu_waste > allocated_cpu * 0.3:
            efficiency_metrics['optimization_opportunities'].append(
                f"CPU over-allocation: {cpu_waste:.1f} cores wasted ({(cpu_waste/allocated_cpu)*100:.1f}%)"
            )
        
        if memory_waste > allocated_memory * 0.3:
            efficiency_metrics['optimization_opportunities'].append(
                f"Memory over-allocation: {memory_waste:.1f} GB wasted ({(memory_waste/allocated_memory)*100:.1f}%)"
            )
        
        if avg_cpu_usage < 0.3:
            efficiency_metrics['optimization_opportunities'].append(
                f"Low CPU utilization: {avg_cpu_usage*100:.1f}% average usage"
            )
        
        if avg_memory_usage < 0.3:
            efficiency_metrics['optimization_opportunities'].append(
                f"Low memory utilization: {avg_memory_usage*100:.1f}% average usage"
            )
        
        return efficiency_metrics
    
    def generate_learning_insights(accuracy_metrics, efficiency_metrics, predictions, actual_metrics):
        \"\"\"Generate insights for improving future predictions\"\"\"
        
        learning_insights = {
            'prediction_adjustments': {},
            'optimization_recommendations': [],
            'tool_specific_learnings': {},
            'pattern_recognition': {}
        }
        
        tool_name = predictions.get('tool_context', {}).get('tool_name', 'unknown')
        
        # Prediction adjustments based on accuracy
        cpu_accuracy = accuracy_metrics['cpu_accuracy']['accuracy_score']
        memory_accuracy = accuracy_metrics['memory_accuracy']['accuracy_score']
        runtime_accuracy = accuracy_metrics['runtime_accuracy']['accuracy_score']
        
        if cpu_accuracy < 0.7:
            cpu_ratio = accuracy_metrics['cpu_accuracy']['actual'] / max(accuracy_metrics['cpu_accuracy']['predicted'], 1)
            learning_insights['prediction_adjustments']['cpu_scaling_factor'] = round(cpu_ratio, 2)
        
        if memory_accuracy < 0.7:
            memory_ratio = accuracy_metrics['memory_accuracy']['actual'] / max(accuracy_metrics['memory_accuracy']['predicted'], 1)
            learning_insights['prediction_adjustments']['memory_scaling_factor'] = round(memory_ratio, 2)
        
        if runtime_accuracy < 0.7:
            runtime_ratio = accuracy_metrics['runtime_accuracy']['actual'] / max(accuracy_metrics['runtime_accuracy']['predicted'], 0.1)
            learning_insights['prediction_adjustments']['runtime_scaling_factor'] = round(runtime_ratio, 2)
        
        # Tool-specific learnings
        input_size_gb = predictions.get('input_characteristics_summary', {}).get('total_size_gb', 1)
        
        learning_insights['tool_specific_learnings'][tool_name] = {
            'input_size_gb': input_size_gb,
            'cpu_cores_per_gb': round(accuracy_metrics['cpu_accuracy']['actual'] / max(input_size_gb, 1), 2),
            'memory_gb_per_input_gb': round(accuracy_metrics['memory_accuracy']['actual'] / max(input_size_gb, 1), 2),
            'runtime_hours_per_gb': round(accuracy_metrics['runtime_accuracy']['actual'] / max(input_size_gb, 1), 2),
            'efficiency_notes': efficiency_metrics.get('optimization_opportunities', [])
        }
        
        # Pattern recognition
        data_complexity = predictions.get('input_characteristics_summary', {}).get('complexity_score', 1.0)
        
        learning_insights['pattern_recognition'] = {
            'data_complexity_factor': data_complexity,
            'performance_correlation': {
                'complexity_vs_cpu': round(data_complexity * accuracy_metrics['cpu_accuracy']['actual'], 2),
                'complexity_vs_memory': round(data_complexity * accuracy_metrics['memory_accuracy']['actual'], 2),
                'complexity_vs_runtime': round(data_complexity * accuracy_metrics['runtime_accuracy']['actual'], 2)
            }
        }
        
        return learning_insights
    
    def create_feedback_summary(meta, accuracy_metrics, efficiency_metrics, learning_insights):
        \"\"\"Create comprehensive feedback summary\"\"\"
        
        feedback_summary = {
            'sample_id': meta['id'],
            'feedback_timestamp': datetime.now().isoformat(),
            'tool_context': predictions.get('tool_context', {}),
            'performance_summary': {
                'prediction_accuracy': accuracy_metrics['overall_accuracy'],
                'resource_efficiency': {
                    'cpu_efficiency': efficiency_metrics['cpu_efficiency']['efficiency_score'],
                    'memory_efficiency': efficiency_metrics['memory_efficiency']['efficiency_score'],
                    'overall_efficiency': round((
                        efficiency_metrics['cpu_efficiency']['efficiency_score'] +
                        efficiency_metrics['memory_efficiency']['efficiency_score']
                    ) / 2, 3)
                }
            },
            'detailed_analysis': {
                'accuracy_breakdown': accuracy_metrics,
                'efficiency_breakdown': efficiency_metrics,
                'learning_insights': learning_insights
            },
            'actionable_recommendations': [],
            'confidence_level': 'high' if accuracy_metrics['overall_accuracy']['score'] > 0.8 else 'medium'
        }
        
        # Generate actionable recommendations
        if accuracy_metrics['overall_accuracy']['score'] < 0.7:
            feedback_summary['actionable_recommendations'].append(
                "Prediction accuracy below threshold - review input characteristics analysis"
            )
        
        if efficiency_metrics['cpu_efficiency']['efficiency_score'] < 0.6:
            feedback_summary['actionable_recommendations'].append(
                "Low CPU efficiency detected - consider reducing CPU allocation for similar workloads"
            )
        
        if efficiency_metrics['memory_efficiency']['efficiency_score'] < 0.6:
            feedback_summary['actionable_recommendations'].append(
                "Low memory efficiency detected - consider reducing memory allocation for similar workloads"
            )
        
        if len(efficiency_metrics['optimization_opportunities']) > 0:
            feedback_summary['actionable_recommendations'].extend(efficiency_metrics['optimization_opportunities'])
        
        return feedback_summary
    
    def generate_learning_update(learning_insights, meta):
        \"\"\"Generate update for the learning system\"\"\"
        
        learning_update = {
            'update_timestamp': datetime.now().isoformat(),
            'sample_id': meta['id'],
            'tool_name': predictions.get('tool_context', {}).get('tool_name', 'unknown'),
            'learning_data': {
                'prediction_corrections': learning_insights.get('prediction_adjustments', {}),
                'tool_performance_data': learning_insights.get('tool_specific_learnings', {}),
                'pattern_data': learning_insights.get('pattern_recognition', {})
            },
            'update_confidence': 0.8,  # Could be calculated based on data quality
            'applicable_to_future': True
        }
        
        return learning_update
    
    # Main analysis workflow
    print(f"Collecting performance feedback for {meta['id']}")
    
    # Calculate prediction accuracy
    accuracy_metrics = calculate_prediction_accuracy(predictions, actual_metrics)
    print(f"Prediction accuracy: {accuracy_metrics['overall_accuracy']['score']:.3f} ({accuracy_metrics['overall_accuracy']['level']})")
    
    # Analyze resource efficiency
    efficiency_metrics = analyze_resource_efficiency(allocations, actual_metrics)
    print(f"Resource efficiency - CPU: {efficiency_metrics['cpu_efficiency']['efficiency_score']:.3f}, Memory: {efficiency_metrics['memory_efficiency']['efficiency_score']:.3f}")
    
    # Generate learning insights
    learning_insights = generate_learning_insights(accuracy_metrics, efficiency_metrics, predictions, actual_metrics)
    
    # Create comprehensive feedback
    feedback_data = create_feedback_summary(meta, accuracy_metrics, efficiency_metrics, learning_insights)
    
    # Generate learning system update
    learning_update = generate_learning_update(learning_insights, meta)
    
    # Save feedback data
    with open(f"{meta['id']}_feedback_data.json", 'w') as f:
        json.dump(feedback_data, f, indent=2)
    
    # Save learning update
    with open('performance_learning_update.json', 'w') as f:
        json.dump(learning_update, f, indent=2)
    
    print(f"Performance feedback collection completed for {meta['id']}")
    print(f"Recommendations generated: {len(feedback_data['actionable_recommendations'])}")
    
    # Generate versions file
    with open('versions.yml', 'w') as f:
        f.write('''\"${task.process}\":
    python: \"3.9\"
    numpy: \"1.21.0\"
    performance_feedback: \"1.0\"''')
    """

    stub:
    """
    echo '{"sample_id": "${meta.id}", "stub": true, "performance_summary": {"prediction_accuracy": {"score": 0.8}}}' > ${meta.id}_feedback_data.json
    echo '{"update_timestamp": "stub", "learning_data": {}}' > performance_learning_update.json
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.9"
        performance_feedback: "1.0"
    END_VERSIONS
    """
}

process UPDATE_LEARNING_MODEL {
    tag "learning_model_update"
    label 'process_single'
    publishDir "${params.outdir}/resource_analysis/learning", mode: 'copy'

    input:
    path feedback_updates
    path historical_data
    val learning_config

    output:
    path "updated_learning_model.json", emit: model
    path "learning_statistics.json", emit: statistics
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    #!/usr/bin/env python3
    
    import json
    import os
    import math
    import numpy as np
    from datetime import datetime, timedelta
    from pathlib import Path
    from collections import defaultdict
    
    learning_config = ${groovy.json.JsonBuilder(learning_config).toString()}
    
    def load_all_feedback_data(feedback_files):
        \"\"\"Load and aggregate all feedback data\"\"\"
        all_feedback = []
        
        for feedback_file in feedback_files:
            try:
                with open(feedback_file, 'r') as f:
                    feedback_data = json.load(f)
                    all_feedback.append(feedback_data)
            except Exception as e:
                print(f"Warning: Could not load feedback file {feedback_file}: {e}")
        
        return all_feedback
    
    def analyze_learning_patterns(feedback_data):
        \"\"\"Analyze patterns in the feedback data to improve predictions\"\"\"
        
        patterns = {
            'tool_patterns': defaultdict(list),
            'size_scaling_patterns': defaultdict(list),
            'complexity_patterns': defaultdict(list),
            'efficiency_patterns': defaultdict(list)
        }
        
        for feedback in feedback_data:
            tool_name = feedback.get('tool_context', {}).get('tool_name', 'unknown')
            
            # Tool-specific patterns
            learning_data = feedback.get('detailed_analysis', {}).get('learning_insights', {})
            tool_learning = learning_data.get('tool_specific_learnings', {}).get(tool_name, {})
            
            if tool_learning:
                patterns['tool_patterns'][tool_name].append(tool_learning)
            
            # Size scaling patterns
            input_size = tool_learning.get('input_size_gb', 0)
            if input_size > 0:
                patterns['size_scaling_patterns'][tool_name].append({
                    'input_size_gb': input_size,
                    'cpu_cores_per_gb': tool_learning.get('cpu_cores_per_gb', 0),
                    'memory_gb_per_input_gb': tool_learning.get('memory_gb_per_input_gb', 0),
                    'runtime_hours_per_gb': tool_learning.get('runtime_hours_per_gb', 0)
                })
            
            # Complexity patterns
            complexity_data = learning_data.get('pattern_recognition', {})
            if complexity_data:
                patterns['complexity_patterns'][tool_name].append(complexity_data)
            
            # Efficiency patterns
            efficiency = feedback.get('performance_summary', {}).get('resource_efficiency', {})
            if efficiency:
                patterns['efficiency_patterns'][tool_name].append(efficiency)
        
        return patterns
    
    def calculate_improved_scaling_factors(patterns):
        \"\"\"Calculate improved scaling factors based on observed patterns\"\"\"
        
        improved_factors = {}
        
        for tool_name, size_data in patterns['size_scaling_patterns'].items():
            if len(size_data) < 2:
                continue
            
            # Calculate average scaling factors
            cpu_factors = [d['cpu_cores_per_gb'] for d in size_data if d['cpu_cores_per_gb'] > 0]
            memory_factors = [d['memory_gb_per_input_gb'] for d in size_data if d['memory_gb_per_input_gb'] > 0]
            runtime_factors = [d['runtime_hours_per_gb'] for d in size_data if d['runtime_hours_per_gb'] > 0]
            
            improved_factors[tool_name] = {
                'cpu_scaling_factor': round(np.mean(cpu_factors), 3) if cpu_factors else 1.0,
                'memory_scaling_factor': round(np.mean(memory_factors), 3) if memory_factors else 1.0,
                'runtime_scaling_factor': round(np.mean(runtime_factors), 3) if runtime_factors else 1.0,
                'confidence': min(len(size_data) / 10.0, 1.0),  # Higher confidence with more data points
                'sample_count': len(size_data)
            }
        
        return improved_factors
    
    def update_prediction_algorithms(patterns, historical_model):
        \"\"\"Update prediction algorithms based on learning patterns\"\"\"
        
        updated_algorithms = historical_model.get('prediction_algorithms', {})
        
        # Update tool-specific algorithms
        improved_factors = calculate_improved_scaling_factors(patterns)
        
        for tool_name, factors in improved_factors.items():
            if factors['confidence'] > 0.3:  # Only update if we have sufficient confidence
                if tool_name not in updated_algorithms:
                    updated_algorithms[tool_name] = {}
                
                # Apply weighted update (new data weighted by confidence)
                old_cpu = updated_algorithms[tool_name].get('cpu_scaling_factor', 1.0)
                old_memory = updated_algorithms[tool_name].get('memory_scaling_factor', 1.0)
                old_runtime = updated_algorithms[tool_name].get('runtime_scaling_factor', 1.0)
                
                weight = factors['confidence']
                
                updated_algorithms[tool_name].update({
                    'cpu_scaling_factor': round(old_cpu * (1 - weight) + factors['cpu_scaling_factor'] * weight, 3),
                    'memory_scaling_factor': round(old_memory * (1 - weight) + factors['memory_scaling_factor'] * weight, 3),
                    'runtime_scaling_factor': round(old_runtime * (1 - weight) + factors['runtime_scaling_factor'] * weight, 3),
                    'last_updated': datetime.now().isoformat(),
                    'update_confidence': factors['confidence'],
                    'training_samples': factors['sample_count']
                })
        
        return updated_algorithms
    
    def generate_learning_statistics(feedback_data, patterns):
        \"\"\"Generate comprehensive learning statistics\"\"\"
        
        stats = {
            'learning_summary': {
                'total_feedback_samples': len(feedback_data),
                'tools_analyzed': len(patterns['tool_patterns']),
                'learning_period_days': 30,  # Could be calculated from timestamps
                'last_update': datetime.now().isoformat()
            },
            'accuracy_trends': {},
            'efficiency_trends': {},
            'improvement_metrics': {}
        }
        
        # Calculate accuracy trends by tool
        for tool_name, tool_data in patterns['tool_patterns'].items():
            accuracies = []
            efficiencies = []
            
            for feedback in feedback_data:
                if feedback.get('tool_context', {}).get('tool_name') == tool_name:
                    accuracy = feedback.get('performance_summary', {}).get('prediction_accuracy', {}).get('score', 0)
                    efficiency = feedback.get('performance_summary', {}).get('resource_efficiency', {}).get('overall_efficiency', 0)
                    
                    if accuracy > 0:
                        accuracies.append(accuracy)
                    if efficiency > 0:
                        efficiencies.append(efficiency)
            
            if accuracies:
                stats['accuracy_trends'][tool_name] = {
                    'average_accuracy': round(np.mean(accuracies), 3),
                    'accuracy_std': round(np.std(accuracies), 3),
                    'sample_count': len(accuracies),
                    'trend': 'improving' if len(accuracies) > 1 and accuracies[-1] > accuracies[0] else 'stable'
                }
            
            if efficiencies:
                stats['efficiency_trends'][tool_name] = {
                    'average_efficiency': round(np.mean(efficiencies), 3),
                    'efficiency_std': round(np.std(efficiencies), 3),
                    'sample_count': len(efficiencies),
                    'trend': 'improving' if len(efficiencies) > 1 and efficiencies[-1] > efficiencies[0] else 'stable'
                }
        
        return stats
    
    # Load all feedback data
    feedback_files = ['${feedback_updates}'.replace(' ', '').split(',') if '${feedback_updates}' != 'NO_FILE' else []]
    all_feedback = load_all_feedback_data(feedback_files) if feedback_files else []
    
    # Load historical learning model
    historical_model = {}
    if os.path.exists('${historical_data}') and '${historical_data}' != 'NO_FILE':
        try:
            with open('${historical_data}', 'r') as f:
                historical_model = json.load(f)
        except:
            print("No historical data available, starting fresh")
    
    if all_feedback:
        print(f"Processing {len(all_feedback)} feedback samples for learning model update")
        
        # Analyze patterns in feedback data
        patterns = analyze_learning_patterns(all_feedback)
        
        # Update prediction algorithms
        updated_algorithms = update_prediction_algorithms(patterns, historical_model)
        
        # Generate learning statistics
        learning_stats = generate_learning_statistics(all_feedback, patterns)
        
        # Create updated learning model
        updated_model = {
            'model_version': historical_model.get('model_version', 0) + 1,
            'last_updated': datetime.now().isoformat(),
            'prediction_algorithms': updated_algorithms,
            'learning_patterns': {
                'tool_patterns': dict(patterns['tool_patterns']),
                'pattern_summary': {
                    'tools_learned': list(patterns['tool_patterns'].keys()),
                    'total_patterns': sum(len(v) for v in patterns['tool_patterns'].values())
                }
            },
            'model_confidence': learning_stats.get('improvement_metrics', {}).get('overall_confidence', 0.7),
            'training_history': {
                'total_samples': len(all_feedback),
                'last_training_date': datetime.now().isoformat()
            }
        }
        
        print(f"Learning model updated successfully:")
        print(f"  Model version: {updated_model['model_version']}")
        print(f"  Tools with updated algorithms: {len(updated_algorithms)}")
        print(f"  Training samples: {len(all_feedback)}")
        
    else:
        print("No feedback data available for learning model update")
        updated_model = historical_model or {'model_version': 1, 'prediction_algorithms': {}}
        learning_stats = {'learning_summary': {'total_feedback_samples': 0}}
    
    # Save updated model
    with open('updated_learning_model.json', 'w') as f:
        json.dump(updated_model, f, indent=2)
    
    # Save learning statistics
    with open('learning_statistics.json', 'w') as f:
        json.dump(learning_stats, f, indent=2)
    
    print("Learning model update completed")
    
    # Generate versions file
    with open('versions.yml', 'w') as f:
        f.write('''\"${task.process}\":
    python: \"3.9\"
    numpy: \"1.21.0\"
    learning_model: \"1.0\"''')
    """

    stub:
    """
    echo '{"model_version": 1, "prediction_algorithms": {}}' > updated_learning_model.json
    echo '{"learning_summary": {"total_feedback_samples": 0}}' > learning_statistics.json
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: "3.9"
        learning_model: "1.0"
    END_VERSIONS
    """
}