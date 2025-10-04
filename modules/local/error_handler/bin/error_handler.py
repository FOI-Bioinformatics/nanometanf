#!/usr/bin/env python3

"""
Comprehensive Error Handler for nanometanf Pipeline
===================================================

Provides intelligent error analysis, categorization, and recovery planning
for production environments.
"""

import json
import sys
import argparse
import re
import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional

class ErrorAnalyzer:
    """Advanced error analysis and categorization system."""
    
    def __init__(self):
        self.error_patterns = {
            'memory': [
                r'OutOfMemoryError',
                r'Cannot allocate memory',
                r'Java heap space',
                r'virtual memory exhausted',
                r'killed.*memory',
                r'MemoryError'
            ],
            'disk_space': [
                r'No space left on device',
                r'Disk quota exceeded',
                r'No such file or directory.*tmp',
                r'failed to write.*disk full'
            ],
            'permissions': [
                r'Permission denied',
                r'Access denied',
                r'Operation not permitted',
                r'cannot create directory'
            ],
            'network': [
                r'Connection refused',
                r'Host is unreachable',
                r'Temporary failure in name resolution',
                r'Connection timed out',
                r'SSL certificate verify failed'
            ],
            'missing_files': [
                r'No such file or directory',
                r'File not found',
                r'cannot stat.*No such file',
                r'does not exist'
            ],
            'format_errors': [
                r'Invalid.*format',
                r'Malformed.*file',
                r'Corrupt.*file',
                r'unexpected end of file',
                r'not a valid.*file'
            ],
            'dependency_errors': [
                r'command not found',
                r'No module named',
                r'ImportError',
                r'library not found',
                r'executable not found'
            ],
            'resource_limits': [
                r'Resource temporarily unavailable',
                r'Too many open files',
                r'Process limit exceeded',
                r'ulimit.*exceeded'
            ]
        }
        
        self.severity_indicators = {
            'critical': ['killed', 'fatal', 'abort', 'crash', 'segmentation fault'],
            'error': ['error', 'failed', 'exception', 'cannot'],
            'warning': ['warning', 'warn', 'deprecated', 'skipping']
        }
    
    def analyze_error(self, error_content: str, context: Dict[str, Any]) -> Dict[str, Any]:
        """Perform comprehensive error analysis."""
        
        analysis = {
            'timestamp': datetime.datetime.now().isoformat(),
            'sample_id': context.get('sample_id', 'unknown'),
            'error_category': self._categorize_error(error_content),
            'severity': self._assess_severity(error_content),
            'description': self._extract_error_description(error_content),
            'potential_causes': self._identify_causes(error_content),
            'affected_processes': self._identify_affected_processes(error_content),
            'resource_impact': self._assess_resource_impact(error_content),
            'recovery_difficulty': self._assess_recovery_difficulty(error_content)
        }
        
        return analysis
    
    def _categorize_error(self, error_content: str) -> str:
        """Categorize error based on content patterns."""
        error_lower = error_content.lower()
        
        for category, patterns in self.error_patterns.items():
            for pattern in patterns:
                if re.search(pattern, error_lower, re.IGNORECASE):
                    return category
        
        return 'unknown'
    
    def _assess_severity(self, error_content: str) -> str:
        """Assess error severity level."""
        error_lower = error_content.lower()
        
        for severity, indicators in self.severity_indicators.items():
            for indicator in indicators:
                if indicator in error_lower:
                    return severity
        
        return 'unknown'
    
    def _extract_error_description(self, error_content: str) -> str:
        """Extract human-readable error description."""
        lines = error_content.split('\n')
        
        # Look for common error message patterns
        error_lines = []
        for line in lines:
            line = line.strip()
            if any(keyword in line.lower() for keyword in ['error', 'failed', 'exception', 'fatal']):
                error_lines.append(line)
        
        if error_lines:
            return '; '.join(error_lines[:3])  # First 3 error lines
        
        # Fallback to first non-empty lines
        non_empty_lines = [line.strip() for line in lines if line.strip()]
        return '; '.join(non_empty_lines[:2]) if non_empty_lines else 'Unknown error'
    
    def _identify_causes(self, error_content: str) -> List[str]:
        """Identify potential root causes."""
        causes = []
        error_lower = error_content.lower()
        
        cause_mappings = {
            'memory': ['Insufficient memory allocation', 'Memory leak in process', 'Large input files'],
            'disk_space': ['Insufficient disk space', 'Temporary directory full', 'Output directory space'],
            'permissions': ['File/directory permissions', 'User access rights', 'SELinux/security policies'],
            'network': ['Network connectivity issues', 'Firewall restrictions', 'DNS resolution problems'],
            'missing_files': ['Input file not found', 'Incorrect file paths', 'Previous process failure'],
            'format_errors': ['Corrupted input files', 'Incorrect file format', 'Incomplete file transfer'],
            'dependency_errors': ['Missing software dependencies', 'Version conflicts', 'Environment issues'],
            'resource_limits': ['System resource limits', 'Process quotas', 'Ulimit restrictions']
        }
        
        category = self._categorize_error(error_content)
        if category in cause_mappings:
            causes.extend(cause_mappings[category])
        
        return causes
    
    def _identify_affected_processes(self, error_content: str) -> List[str]:
        """Identify which processes were affected."""
        processes = []
        
        # Common nanometanf processes
        process_patterns = [
            r'DORADO_BASECALLER',
            r'KRAKEN2_KRAKEN2',
            r'FASTP',
            r'NANOPLOT',
            r'BLAST_BLASTN',
            r'MULTIQC'
        ]
        
        for pattern in process_patterns:
            if re.search(pattern, error_content, re.IGNORECASE):
                processes.append(pattern)
        
        return processes
    
    def _assess_resource_impact(self, error_content: str) -> Dict[str, Any]:
        """Assess impact on system resources."""
        impact = {
            'memory_related': 'memory' in self._categorize_error(error_content),
            'disk_related': 'disk_space' in self._categorize_error(error_content),
            'network_related': 'network' in self._categorize_error(error_content),
            'cpu_intensive': any(keyword in error_content.lower() for keyword in ['timeout', 'slow', 'performance'])
        }
        
        return impact
    
    def _assess_recovery_difficulty(self, error_content: str) -> str:
        """Assess how difficult recovery will be."""
        category = self._categorize_error(error_content)
        severity = self._assess_severity(error_content)
        
        if severity == 'critical':
            return 'high'
        elif category in ['memory', 'disk_space', 'resource_limits']:
            return 'medium'
        elif category in ['permissions', 'missing_files', 'dependency_errors']:
            return 'low'
        else:
            return 'unknown'

class RecoveryPlanner:
    """Generate intelligent recovery plans based on error analysis."""
    
    def generate_plan(self, analysis: Dict[str, Any]) -> Dict[str, Any]:
        """Generate comprehensive recovery plan."""
        
        plan = {
            'timestamp': datetime.datetime.now().isoformat(),
            'sample_id': analysis['sample_id'],
            'error_category': analysis['error_category'],
            'immediate_actions': self._get_immediate_actions(analysis),
            'parameter_adjustments': self._get_parameter_adjustments(analysis),
            'resource_modifications': self._get_resource_modifications(analysis),
            'retry_strategy': self._get_retry_strategy(analysis),
            'escalation_criteria': self._get_escalation_criteria(analysis),
            'monitoring_recommendations': self._get_monitoring_recommendations(analysis)
        }
        
        return plan
    
    def _get_immediate_actions(self, analysis: Dict[str, Any]) -> List[str]:
        """Get immediate remedial actions."""
        category = analysis['error_category']
        actions = []
        
        action_map = {
            'memory': [
                'Increase memory allocation for affected processes',
                'Check for memory leaks in running processes',
                'Clear temporary files and caches'
            ],
            'disk_space': [
                'Check available disk space on all mounted filesystems',
                'Clean up temporary and intermediate files',
                'Verify output directory permissions and space'
            ],
            'permissions': [
                'Verify file and directory permissions',
                'Check user/group ownership',
                'Review SELinux/security policy restrictions'
            ],
            'network': [
                'Test network connectivity',
                'Verify DNS resolution',
                'Check firewall rules and proxy settings'
            ],
            'missing_files': [
                'Verify input file paths and existence',
                'Check previous process completion',
                'Validate file integrity and format'
            ],
            'dependency_errors': [
                'Verify software installation and paths',
                'Check environment variables and modules',
                'Validate container/conda environment'
            ]
        }
        
        if category in action_map:
            actions.extend(action_map[category])
        
        return actions
    
    def _get_parameter_adjustments(self, analysis: Dict[str, Any]) -> Dict[str, Any]:
        """Suggest parameter adjustments."""
        category = analysis['error_category']
        adjustments = {}
        
        if category == 'memory':
            adjustments.update({
                'memory_multiplier': 2.0,
                'max_retries': 2,
                'memory_efficiency_mode': True
            })
        elif category == 'resource_limits':
            adjustments.update({
                'cpu_multiplier': 0.5,
                'memory_multiplier': 1.5,
                'time_multiplier': 2.0
            })
        elif category == 'disk_space':
            adjustments.update({
                'cleanup_intermediate': True,
                'compress_outputs': True,
                'stream_processing': True
            })
        
        return adjustments
    
    def _get_resource_modifications(self, analysis: Dict[str, Any]) -> Dict[str, Any]:
        """Suggest resource modifications."""
        modifications = {
            'cpu_adjustment': 0,
            'memory_adjustment': 0,
            'time_adjustment': 0,
            'disk_cleanup': False
        }
        
        if analysis['resource_impact']['memory_related']:
            modifications['memory_adjustment'] = 50  # Increase by 50%
            
        if analysis['resource_impact']['cpu_intensive']:
            modifications['cpu_adjustment'] = 25  # Increase by 25%
            modifications['time_adjustment'] = 100  # Double time limit
            
        if analysis['resource_impact']['disk_related']:
            modifications['disk_cleanup'] = True
        
        return modifications
    
    def _get_retry_strategy(self, analysis: Dict[str, Any]) -> Dict[str, Any]:
        """Define retry strategy."""
        difficulty = analysis['recovery_difficulty']
        
        if difficulty == 'low':
            return {
                'max_retries': 3,
                'retry_delay': '5min',
                'exponential_backoff': True,
                'retry_with_modifications': True
            }
        elif difficulty == 'medium':
            return {
                'max_retries': 2,
                'retry_delay': '10min',
                'resource_adjustment': True,
                'manual_intervention_after': 1
            }
        else:  # high or unknown
            return {
                'max_retries': 1,
                'require_manual_review': True,
                'escalate_immediately': True
            }
    
    def _get_escalation_criteria(self, analysis: Dict[str, Any]) -> List[str]:
        """Define when to escalate."""
        criteria = []
        
        if analysis['severity'] == 'critical':
            criteria.append('Immediate escalation due to critical severity')
            
        if analysis['recovery_difficulty'] == 'high':
            criteria.append('Complex recovery process requires expert intervention')
            
        if len(analysis['affected_processes']) > 3:
            criteria.append('Multiple processes affected - system-wide issue suspected')
        
        criteria.extend([
            'After 2 failed retry attempts',
            'If resource adjustments exceed 200% of original allocation',
            'If error persists across different input samples'
        ])
        
        return criteria
    
    def _get_monitoring_recommendations(self, analysis: Dict[str, Any]) -> List[str]:
        """Recommend monitoring strategies."""
        recommendations = [
            'Monitor resource usage trends during retry attempts',
            'Track error frequency and patterns across samples',
            'Implement proactive alerts for similar error patterns'
        ]
        
        if analysis['resource_impact']['memory_related']:
            recommendations.append('Implement memory usage monitoring and alerting')
            
        if analysis['resource_impact']['disk_related']:
            recommendations.append('Monitor disk space usage in real-time')
            
        return recommendations

def main():
    parser = argparse.ArgumentParser(description='Comprehensive Error Handler for nanometanf')
    parser.add_argument('--sample_id', required=True, help='Sample identifier')
    parser.add_argument('--error_files', nargs='+', required=True, help='Error log files')
    parser.add_argument('--error_context', required=True, help='Error context information')
    parser.add_argument('--output_prefix', required=True, help='Output file prefix')
    parser.add_argument('--analysis_level', default='comprehensive', help='Analysis detail level')
    parser.add_argument('--generate_recovery_plan', action='store_true', help='Generate recovery plan')
    
    args = parser.parse_args()
    
    # Initialize analyzers
    analyzer = ErrorAnalyzer()
    planner = RecoveryPlanner()
    
    # Collect error content
    error_content = ""
    for error_file in args.error_files:
        try:
            with open(error_file, 'r') as f:
                error_content += f.read() + "\n"
        except FileNotFoundError:
            print(f"Warning: Error file {error_file} not found", file=sys.stderr)
    
    # Prepare context
    context = {
        'sample_id': args.sample_id,
        'error_context': args.error_context,
        'analysis_level': args.analysis_level
    }
    
    # Perform analysis
    analysis = analyzer.analyze_error(error_content, context)
    
    # Save analysis
    analysis_file = f"{args.output_prefix}.error_analysis.json"
    with open(analysis_file, 'w') as f:
        json.dump(analysis, f, indent=2)
    
    print(f"Error analysis saved to: {analysis_file}")
    
    # Generate recovery plan if requested
    if args.generate_recovery_plan:
        recovery_plan = planner.generate_plan(analysis)
        
        plan_file = f"{args.output_prefix}.recovery_plan.json"
        with open(plan_file, 'w') as f:
            json.dump(recovery_plan, f, indent=2)
        
        print(f"Recovery plan saved to: {plan_file}")
        
        # Print summary to stdout
        print(f"\nError Summary for {args.sample_id}:")
        print(f"Category: {analysis['error_category']}")
        print(f"Severity: {analysis['severity']}")
        print(f"Recovery Difficulty: {analysis['recovery_difficulty']}")
        print(f"Immediate Actions: {len(recovery_plan['immediate_actions'])} recommended")

if __name__ == '__main__':
    main()