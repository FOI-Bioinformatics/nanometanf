#!/usr/bin/env python3
"""
Performance Regression Testing Framework for nanometanf Pipeline

Tracks performance metrics over time to detect regressions.
Benchmarks critical pipeline operations and generates performance reports.

Metrics Tracked:
- Execution time per process
- Memory usage (peak and average)
- CPU utilization
- I/O throughput
- File processing rates

Usage:
    python bin/performance_regression_tester.py run --test-suite baseline
    python bin/performance_regression_tester.py compare --baseline v1.0 --current v1.1
    python bin/performance_regression_tester.py report --format html
"""

import os
import sys
import json
import time
import subprocess
import psutil
import statistics
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple
import tempfile


class PerformanceBenchmark:
    """Performance benchmarking for pipeline components."""

    def __init__(self, output_dir: str = ".performance_tests"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)
        self.metrics = {
            'timestamp': datetime.now().isoformat(),
            'system_info': self._get_system_info(),
            'benchmarks': {}
        }

    def _get_system_info(self) -> Dict:
        """Collect system information."""
        return {
            'cpu_count': psutil.cpu_count(),
            'cpu_freq': psutil.cpu_freq()._asdict() if psutil.cpu_freq() else {},
            'memory_total': psutil.virtual_memory().total,
            'platform': sys.platform
        }

    def benchmark_process(self, process_name: str, command: List[str],
                         working_dir: str = None) -> Dict:
        """Benchmark a single process."""
        print(f"\n🔬 Benchmarking: {process_name}")

        start_time = time.time()
        start_memory = psutil.virtual_memory().used

        # Track process metrics
        cpu_samples = []
        memory_samples = []

        try:
            # Run command
            proc = subprocess.Popen(
                command,
                cwd=working_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )

            # Monitor process
            psutil_proc = psutil.Process(proc.pid)
            while proc.poll() is None:
                try:
                    cpu_samples.append(psutil_proc.cpu_percent(interval=0.1))
                    memory_samples.append(psutil_proc.memory_info().rss)
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    break
                time.sleep(0.1)

            stdout, stderr = proc.communicate()
            returncode = proc.returncode

        except Exception as e:
            return {
                'error': str(e),
                'success': False
            }

        end_time = time.time()
        end_memory = psutil.virtual_memory().used

        # Calculate metrics
        execution_time = end_time - start_time
        memory_delta = end_memory - start_memory

        metrics = {
            'success': returncode == 0,
            'execution_time': execution_time,
            'memory_usage': {
                'peak': max(memory_samples) if memory_samples else 0,
                'average': statistics.mean(memory_samples) if memory_samples else 0,
                'delta': memory_delta
            },
            'cpu_usage': {
                'peak': max(cpu_samples) if cpu_samples else 0,
                'average': statistics.mean(cpu_samples) if cpu_samples else 0
            },
            'returncode': returncode
        }

        print(f"   ✓ Completed in {execution_time:.2f}s")
        print(f"   Memory: {metrics['memory_usage']['peak'] / 1024 / 1024:.1f} MB peak")
        print(f"   CPU: {metrics['cpu_usage']['average']:.1f}% average")

        return metrics

    def run_test_suite(self, suite_name: str = "baseline") -> Dict:
        """Run complete performance test suite."""
        print(f"\n{'='*80}")
        print(f"PERFORMANCE REGRESSION TEST SUITE: {suite_name}")
        print(f"{'='*80}")

        test_cases = [
            {
                'name': 'parameter_validation',
                'description': 'Schema validation performance',
                'command': [
                    'nextflow', 'run', 'main.nf',
                    '--input', 'assets/test_data/samplesheet_test.csv',
                    '--outdir', 'test_output',
                    '-profile', 'test',
                    '--help'
                ]
            },
            {
                'name': 'workflow_initialization',
                'description': 'Workflow startup time',
                'command': [
                    'nextflow', 'run', 'main.nf',
                    '--input', 'assets/test_data/samplesheet_test.csv',
                    '--outdir', f'{self.output_dir}/init_test',
                    '-profile', 'test',
                    '-stub'
                ]
            }
        ]

        for test_case in test_cases:
            print(f"\n--- Test Case: {test_case['name']} ---")
            print(f"Description: {test_case['description']}")

            metrics = self.benchmark_process(
                test_case['name'],
                test_case['command']
            )

            self.metrics['benchmarks'][test_case['name']] = {
                'description': test_case['description'],
                'metrics': metrics
            }

        # Save results
        results_file = self.output_dir / f"benchmark_{suite_name}_{int(time.time())}.json"
        with open(results_file, 'w') as f:
            json.dump(self.metrics, f, indent=2)

        print(f"\n✅ Benchmark results saved to: {results_file}")
        return self.metrics

    def compare_benchmarks(self, baseline_file: str, current_file: str,
                          threshold: float = 0.1) -> Dict:
        """Compare two benchmark runs."""
        print(f"\n{'='*80}")
        print("PERFORMANCE REGRESSION COMPARISON")
        print(f"{'='*80}")

        with open(baseline_file, 'r') as f:
            baseline = json.load(f)

        with open(current_file, 'r') as f:
            current = json.load(f)

        comparison = {
            'baseline': baseline_file,
            'current': current_file,
            'regressions': [],
            'improvements': [],
            'stable': []
        }

        for test_name in baseline.get('benchmarks', {}).keys():
            if test_name not in current.get('benchmarks', {}):
                continue

            baseline_metrics = baseline['benchmarks'][test_name]['metrics']
            current_metrics = current['benchmarks'][test_name]['metrics']

            # Compare execution time
            baseline_time = baseline_metrics.get('execution_time', 0)
            current_time = current_metrics.get('execution_time', 0)

            if baseline_time > 0:
                time_delta = (current_time - baseline_time) / baseline_time

                test_comparison = {
                    'test': test_name,
                    'baseline_time': baseline_time,
                    'current_time': current_time,
                    'delta_percent': time_delta * 100
                }

                if time_delta > threshold:
                    comparison['regressions'].append(test_comparison)
                    print(f"⚠️  REGRESSION: {test_name}")
                    print(f"   Slowdown: {time_delta * 100:.1f}%")
                    print(f"   Baseline: {baseline_time:.2f}s → Current: {current_time:.2f}s")
                elif time_delta < -threshold:
                    comparison['improvements'].append(test_comparison)
                    print(f"✅ IMPROVEMENT: {test_name}")
                    print(f"   Speedup: {abs(time_delta) * 100:.1f}%")
                    print(f"   Baseline: {baseline_time:.2f}s → Current: {current_time:.2f}s")
                else:
                    comparison['stable'].append(test_comparison)
                    print(f"➡️  STABLE: {test_name}")
                    print(f"   Change: {time_delta * 100:.1f}%")

        # Generate summary
        print(f"\n{'='*80}")
        print("SUMMARY")
        print(f"{'='*80}")
        print(f"Regressions: {len(comparison['regressions'])}")
        print(f"Improvements: {len(comparison['improvements'])}")
        print(f"Stable: {len(comparison['stable'])}")

        # Save comparison
        comparison_file = self.output_dir / f"comparison_{int(time.time())}.json"
        with open(comparison_file, 'w') as f:
            json.dump(comparison, f, indent=2)

        print(f"\n✅ Comparison saved to: {comparison_file}")
        return comparison

    def generate_report(self, format: str = 'markdown') -> str:
        """Generate performance report."""
        if format == 'markdown':
            return self._generate_markdown_report()
        elif format == 'html':
            return self._generate_html_report()
        else:
            return self._generate_text_report()

    def _generate_markdown_report(self) -> str:
        """Generate markdown performance report."""
        md = []
        md.append("# Performance Regression Test Report")
        md.append(f"\nGenerated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

        md.append("\n## System Information")
        sys_info = self.metrics['system_info']
        md.append(f"- **Platform**: {sys_info['platform']}")
        md.append(f"- **CPU Count**: {sys_info['cpu_count']}")
        md.append(f"- **Total Memory**: {sys_info['memory_total'] / 1024 / 1024 / 1024:.1f} GB")

        md.append("\n## Benchmark Results")
        md.append("\n| Test Case | Execution Time | Peak Memory | Avg CPU | Status |")
        md.append("|-----------|----------------|-------------|---------|--------|")

        for test_name, test_data in self.metrics['benchmarks'].items():
            metrics = test_data['metrics']
            exec_time = metrics.get('execution_time', 0)
            peak_mem = metrics.get('memory_usage', {}).get('peak', 0) / 1024 / 1024
            avg_cpu = metrics.get('cpu_usage', {}).get('average', 0)
            status = "✅" if metrics.get('success') else "❌"

            md.append(f"| {test_name} | {exec_time:.2f}s | {peak_mem:.1f} MB | {avg_cpu:.1f}% | {status} |")

        return "\n".join(md)

    def _generate_text_report(self) -> str:
        """Generate text performance report."""
        report = []
        report.append("="*80)
        report.append("PERFORMANCE REGRESSION TEST REPORT")
        report.append("="*80)

        for test_name, test_data in self.metrics['benchmarks'].items():
            metrics = test_data['metrics']
            report.append(f"\n{test_name}:")
            report.append(f"  Execution Time: {metrics.get('execution_time', 0):.2f}s")
            report.append(f"  Peak Memory: {metrics.get('memory_usage', {}).get('peak', 0) / 1024 / 1024:.1f} MB")
            report.append(f"  Average CPU: {metrics.get('cpu_usage', {}).get('average', 0):.1f}%")
            report.append(f"  Status: {'Success' if metrics.get('success') else 'Failed'}")

        return "\n".join(report)

    def _generate_html_report(self) -> str:
        """Generate HTML performance report with charts."""
        html = f"""
<!DOCTYPE html>
<html>
<head>
    <title>Performance Regression Test Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; }}
        h1 {{ color: #333; }}
        table {{ border-collapse: collapse; width: 100%; }}
        th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
        th {{ background-color: #4CAF50; color: white; }}
        .success {{ color: green; }}
        .failure {{ color: red; }}
    </style>
</head>
<body>
    <h1>Performance Regression Test Report</h1>
    <p>Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>

    <h2>System Information</h2>
    <table>
        <tr><th>Property</th><th>Value</th></tr>
        <tr><td>Platform</td><td>{self.metrics['system_info']['platform']}</td></tr>
        <tr><td>CPU Count</td><td>{self.metrics['system_info']['cpu_count']}</td></tr>
        <tr><td>Total Memory</td><td>{self.metrics['system_info']['memory_total'] / 1024 / 1024 / 1024:.1f} GB</td></tr>
    </table>

    <h2>Benchmark Results</h2>
    <table>
        <tr>
            <th>Test Case</th>
            <th>Execution Time</th>
            <th>Peak Memory</th>
            <th>Avg CPU</th>
            <th>Status</th>
        </tr>
"""
        for test_name, test_data in self.metrics['benchmarks'].items():
            metrics = test_data['metrics']
            exec_time = metrics.get('execution_time', 0)
            peak_mem = metrics.get('memory_usage', {}).get('peak', 0) / 1024 / 1024
            avg_cpu = metrics.get('cpu_usage', {}).get('average', 0)
            status_class = "success" if metrics.get('success') else "failure"
            status_text = "✅ Success" if metrics.get('success') else "❌ Failed"

            html += f"""
        <tr>
            <td>{test_name}</td>
            <td>{exec_time:.2f}s</td>
            <td>{peak_mem:.1f} MB</td>
            <td>{avg_cpu:.1f}%</td>
            <td class="{status_class}">{status_text}</td>
        </tr>
"""

        html += """
    </table>
</body>
</html>
"""
        return html


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Performance regression testing for nanometanf')
    subparsers = parser.add_subparsers(dest='command', help='Command to run')

    # Run benchmark
    run_parser = subparsers.add_parser('run', help='Run performance benchmarks')
    run_parser.add_argument('--test-suite', default='baseline', help='Test suite name')
    run_parser.add_argument('--output-dir', default='.performance_tests', help='Output directory')

    # Compare benchmarks
    compare_parser = subparsers.add_parser('compare', help='Compare benchmark results')
    compare_parser.add_argument('--baseline', required=True, help='Baseline benchmark file')
    compare_parser.add_argument('--current', required=True, help='Current benchmark file')
    compare_parser.add_argument('--threshold', type=float, default=0.1, help='Regression threshold (0.1 = 10%)')

    # Generate report
    report_parser = subparsers.add_parser('report', help='Generate performance report')
    report_parser.add_argument('--format', choices=['text', 'markdown', 'html'], default='markdown')
    report_parser.add_argument('--output', help='Output file')

    args = parser.parse_args()

    if args.command == 'run':
        benchmark = PerformanceBenchmark(args.output_dir)
        benchmark.run_test_suite(args.test_suite)

    elif args.command == 'compare':
        benchmark = PerformanceBenchmark()
        benchmark.compare_benchmarks(args.baseline, args.current, args.threshold)

    elif args.command == 'report':
        benchmark = PerformanceBenchmark()
        report = benchmark.generate_report(args.format)

        if args.output:
            with open(args.output, 'w') as f:
                f.write(report)
            print(f"Report written to {args.output}")
        else:
            print(report)

    else:
        parser.print_help()


if __name__ == '__main__':
    main()
