#!/usr/bin/env python3
"""
Test Coverage Analyzer for nanometanf Pipeline

Analyzes test coverage across modules, subworkflows, and workflows.
Generates comprehensive coverage reports and identifies gaps.

Priority Levels:
- P0: Critical path functionality (must work for pipeline to function)
- P1: Important features (commonly used, impacts quality)
- P2: Edge cases and error handling (robustness)

Usage:
    python bin/test_coverage_analyzer.py [--format json|markdown|console]
"""

import os
import sys
import json
import glob
import re
from pathlib import Path
from typing import Dict, List, Tuple, Set
from collections import defaultdict


class TestCoverageAnalyzer:
    """Analyzes test coverage for Nextflow pipeline components."""

    # Priority classifications based on functionality
    P0_MODULES = {
        'dorado_basecaller', 'dorado_demux', 'fastp', 'kraken2/kraken2',
        'nanoplot', 'multiqc'
    }

    P1_MODULES = {
        'analyze_input_characteristics', 'predict_resource_requirements',
        'generate_realtime_report', 'blast/blastn', 'taxpasta/merge',
        'multiqc_nanopore_stats', 'krona_kraken2'
    }

    P0_SUBWORKFLOWS = {
        'qc_analysis', 'taxonomic_classification', 'dorado_basecalling',
        'demultiplexing'
    }

    P1_SUBWORKFLOWS = {
        'realtime_monitoring', 'realtime_pod5_monitoring', 'validation',
        'dynamic_resource_allocation', 'barcode_discovery'
    }

    def __init__(self, pipeline_dir: str = '.'):
        self.pipeline_dir = Path(pipeline_dir).resolve()
        self.modules = {}
        self.subworkflows = {}
        self.workflows = {}
        self.test_files = []
        self.coverage_data = {
            'modules': defaultdict(dict),
            'subworkflows': defaultdict(dict),
            'workflows': defaultdict(dict)
        }

    def scan_components(self):
        """Scan all pipeline components (modules, subworkflows, workflows)."""
        print("📊 Scanning pipeline components...")

        # Scan local modules
        modules_dir = self.pipeline_dir / 'modules' / 'local'
        if modules_dir.exists():
            for module_path in modules_dir.iterdir():
                if module_path.is_dir() and (module_path / 'main.nf').exists():
                    module_name = module_path.name
                    self.modules[module_name] = {
                        'path': module_path,
                        'main_nf': module_path / 'main.nf',
                        'test_dir': module_path / 'tests',
                        'has_tests': (module_path / 'tests' / 'main.nf.test').exists(),
                        'priority': self._get_priority(module_name, 'module')
                    }

        # Scan nf-core modules
        nfcore_modules_dir = self.pipeline_dir / 'modules' / 'nf-core'
        if nfcore_modules_dir.exists():
            for category_path in nfcore_modules_dir.iterdir():
                if category_path.is_dir():
                    for module_path in category_path.iterdir():
                        if module_path.is_dir() and (module_path / 'main.nf').exists():
                            module_name = f"{category_path.name}/{module_path.name}"
                            self.modules[module_name] = {
                                'path': module_path,
                                'main_nf': module_path / 'main.nf',
                                'test_dir': module_path / 'tests',
                                'has_tests': (module_path / 'tests' / 'main.nf.test').exists(),
                                'priority': self._get_priority(module_name, 'module'),
                                'nf_core': True
                            }

        # Scan subworkflows
        subworkflows_dir = self.pipeline_dir / 'subworkflows' / 'local'
        if subworkflows_dir.exists():
            for sw_path in subworkflows_dir.iterdir():
                if sw_path.is_dir() and (sw_path / 'main.nf').exists():
                    sw_name = sw_path.name
                    self.subworkflows[sw_name] = {
                        'path': sw_path,
                        'main_nf': sw_path / 'main.nf',
                        'test_dir': sw_path / 'tests',
                        'has_tests': (sw_path / 'tests' / 'main.nf.test').exists(),
                        'priority': self._get_priority(sw_name, 'subworkflow')
                    }

        # Scan workflows
        workflows_dir = self.pipeline_dir / 'workflows'
        if workflows_dir.exists():
            for wf_path in workflows_dir.glob('*.nf'):
                wf_name = wf_path.stem
                self.workflows[wf_name] = {
                    'path': wf_path,
                    'priority': 'P0'  # All workflows are P0
                }

        # Scan test files
        tests_dir = self.pipeline_dir / 'tests'
        if tests_dir.exists():
            self.test_files = list(tests_dir.glob('**/*.nf.test'))

        print(f"   Found {len(self.modules)} modules")
        print(f"   Found {len(self.subworkflows)} subworkflows")
        print(f"   Found {len(self.workflows)} workflows")
        print(f"   Found {len(self.test_files)} test files")

    def _get_priority(self, name: str, component_type: str) -> str:
        """Determine priority level for a component."""
        if component_type == 'module':
            if name in self.P0_MODULES or any(p in name for p in self.P0_MODULES):
                return 'P0'
            elif name in self.P1_MODULES or any(p in name for p in self.P1_MODULES):
                return 'P1'
            else:
                return 'P2'
        elif component_type == 'subworkflow':
            if name in self.P0_SUBWORKFLOWS:
                return 'P0'
            elif name in self.P1_SUBWORKFLOWS:
                return 'P1'
            else:
                return 'P2'
        return 'P2'

    def analyze_test_content(self):
        """Analyze test file content to determine what they cover."""
        print("\n🔍 Analyzing test content...")

        for test_file in self.test_files:
            with open(test_file, 'r') as f:
                content = f.read()

            # Extract test name
            test_match = re.search(r'nextflow_process\s*\{[\s\S]*?name\s+"([^"]+)"', content)
            if test_match:
                test_name = test_match.group(1)

                # Categorize test
                if 'edge' in str(test_file).lower() or 'error' in test_name.lower():
                    priority = 'P2'
                elif 'integration' in test_name.lower() or 'workflow' in test_name.lower():
                    priority = 'P0'
                else:
                    priority = 'P1'

                print(f"   Test: {test_file.name} ({priority})")

    def calculate_coverage(self) -> Dict:
        """Calculate coverage statistics."""
        print("\n📈 Calculating coverage statistics...")

        stats = {
            'modules': {'P0': {'total': 0, 'tested': 0},
                       'P1': {'total': 0, 'tested': 0},
                       'P2': {'total': 0, 'tested': 0}},
            'subworkflows': {'P0': {'total': 0, 'tested': 0},
                            'P1': {'total': 0, 'tested': 0},
                            'P2': {'total': 0, 'tested': 0}},
            'overall': {}
        }

        # Count modules
        for name, info in self.modules.items():
            priority = info['priority']
            stats['modules'][priority]['total'] += 1
            if info['has_tests']:
                stats['modules'][priority]['tested'] += 1

        # Count subworkflows
        for name, info in self.subworkflows.items():
            priority = info['priority']
            stats['subworkflows'][priority]['total'] += 1
            if info['has_tests']:
                stats['subworkflows'][priority]['tested'] += 1

        # Calculate percentages
        for component_type in ['modules', 'subworkflows']:
            for priority in ['P0', 'P1', 'P2']:
                total = stats[component_type][priority]['total']
                tested = stats[component_type][priority]['tested']
                if total > 0:
                    stats[component_type][priority]['percentage'] = (tested / total) * 100
                else:
                    stats[component_type][priority]['percentage'] = 0

        # Overall P0+P1 coverage
        p0_p1_total = (stats['modules']['P0']['total'] + stats['modules']['P1']['total'] +
                       stats['subworkflows']['P0']['total'] + stats['subworkflows']['P1']['total'])
        p0_p1_tested = (stats['modules']['P0']['tested'] + stats['modules']['P1']['tested'] +
                        stats['subworkflows']['P0']['tested'] + stats['subworkflows']['P1']['tested'])

        if p0_p1_total > 0:
            stats['overall']['p0_p1_coverage'] = (p0_p1_tested / p0_p1_total) * 100
        else:
            stats['overall']['p0_p1_coverage'] = 0

        # Overall coverage
        all_total = (stats['modules']['P0']['total'] + stats['modules']['P1']['total'] +
                     stats['modules']['P2']['total'] + stats['subworkflows']['P0']['total'] +
                     stats['subworkflows']['P1']['total'] + stats['subworkflows']['P2']['total'])
        all_tested = (stats['modules']['P0']['tested'] + stats['modules']['P1']['tested'] +
                      stats['modules']['P2']['tested'] + stats['subworkflows']['P0']['tested'] +
                      stats['subworkflows']['P1']['tested'] + stats['subworkflows']['P2']['tested'])

        if all_total > 0:
            stats['overall']['total_coverage'] = (all_tested / all_total) * 100
        else:
            stats['overall']['total_coverage'] = 0

        stats['overall']['integration_tests'] = len([t for t in self.test_files
                                                      if 'integration' in str(t).lower() or
                                                      'workflow' in str(t).lower()])
        stats['overall']['edge_case_tests'] = len([t for t in self.test_files
                                                   if 'edge' in str(t).lower()])

        return stats

    def identify_gaps(self, stats: Dict) -> Dict:
        """Identify components without tests."""
        gaps = {
            'P0_untested': [],
            'P1_untested': [],
            'P2_untested': []
        }

        # Check modules
        for name, info in self.modules.items():
            if not info['has_tests']:
                priority = info['priority']
                gaps[f'{priority}_untested'].append({
                    'type': 'module',
                    'name': name,
                    'path': str(info['path'])
                })

        # Check subworkflows
        for name, info in self.subworkflows.items():
            if not info['has_tests']:
                priority = info['priority']
                gaps[f'{priority}_untested'].append({
                    'type': 'subworkflow',
                    'name': name,
                    'path': str(info['path'])
                })

        return gaps

    def generate_report(self, stats: Dict, gaps: Dict, format: str = 'console'):
        """Generate coverage report in specified format."""
        if format == 'json':
            return self._generate_json_report(stats, gaps)
        elif format == 'markdown':
            return self._generate_markdown_report(stats, gaps)
        else:
            return self._generate_console_report(stats, gaps)

    def _generate_console_report(self, stats: Dict, gaps: Dict) -> str:
        """Generate console-formatted report."""
        report = []
        report.append("\n" + "="*80)
        report.append("TEST COVERAGE ANALYSIS REPORT")
        report.append("="*80)

        # Overall statistics
        report.append(f"\n📊 OVERALL COVERAGE:")
        report.append(f"   P0+P1 Coverage: {stats['overall']['p0_p1_coverage']:.1f}% (Target: 95%)")
        report.append(f"   Total Coverage: {stats['overall']['total_coverage']:.1f}% (Target: 80%)")
        report.append(f"   Integration Tests: {stats['overall']['integration_tests']}")
        report.append(f"   Edge Case Tests: {stats['overall']['edge_case_tests']}")

        # Modules breakdown
        report.append(f"\n📦 MODULES:")
        for priority in ['P0', 'P1', 'P2']:
            total = stats['modules'][priority]['total']
            tested = stats['modules'][priority]['tested']
            pct = stats['modules'][priority]['percentage']
            status = "✅" if pct >= 95 else "⚠️" if pct >= 80 else "❌"
            report.append(f"   {status} {priority}: {tested}/{total} ({pct:.1f}%)")

        # Subworkflows breakdown
        report.append(f"\n🔧 SUBWORKFLOWS:")
        for priority in ['P0', 'P1', 'P2']:
            total = stats['subworkflows'][priority]['total']
            tested = stats['subworkflows'][priority]['tested']
            pct = stats['subworkflows'][priority]['percentage']
            status = "✅" if pct >= 95 else "⚠️" if pct >= 80 else "❌"
            report.append(f"   {status} {priority}: {tested}/{total} ({pct:.1f}%)")

        # Coverage gaps
        report.append(f"\n🎯 COVERAGE GAPS:")

        if gaps['P0_untested']:
            report.append(f"\n   ❌ CRITICAL (P0) - {len(gaps['P0_untested'])} components without tests:")
            for item in gaps['P0_untested']:
                report.append(f"      - {item['type']}: {item['name']}")

        if gaps['P1_untested']:
            report.append(f"\n   ⚠️  IMPORTANT (P1) - {len(gaps['P1_untested'])} components without tests:")
            for item in gaps['P1_untested']:
                report.append(f"      - {item['type']}: {item['name']}")

        if gaps['P2_untested']:
            report.append(f"\n   📝 EDGE CASES (P2) - {len(gaps['P2_untested'])} components without tests:")
            for item in gaps['P2_untested'][:10]:  # Show first 10
                report.append(f"      - {item['type']}: {item['name']}")
            if len(gaps['P2_untested']) > 10:
                report.append(f"      ... and {len(gaps['P2_untested']) - 10} more")

        # Recommendations
        report.append(f"\n💡 RECOMMENDATIONS:")
        if stats['overall']['p0_p1_coverage'] < 95:
            report.append("   1. Add tests for all P0 components (critical path)")
            report.append("   2. Add tests for all P1 components (important features)")
        if stats['overall']['integration_tests'] < 5:
            report.append("   3. Create more integration tests for complete workflows")
        if stats['overall']['edge_case_tests'] < 10:
            report.append("   4. Add edge case tests for error handling and boundary conditions")

        report.append("\n" + "="*80 + "\n")

        return "\n".join(report)

    def _generate_markdown_report(self, stats: Dict, gaps: Dict) -> str:
        """Generate markdown-formatted report."""
        md = []
        md.append("# Test Coverage Analysis Report")
        md.append(f"\nGenerated: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

        md.append("\n## Overall Coverage")
        md.append(f"- **P0+P1 Coverage**: {stats['overall']['p0_p1_coverage']:.1f}% (Target: 95%)")
        md.append(f"- **Total Coverage**: {stats['overall']['total_coverage']:.1f}% (Target: 80%)")
        md.append(f"- **Integration Tests**: {stats['overall']['integration_tests']}")
        md.append(f"- **Edge Case Tests**: {stats['overall']['edge_case_tests']}")

        md.append("\n## Modules Coverage")
        md.append("| Priority | Tested | Total | Coverage |")
        md.append("|----------|--------|-------|----------|")
        for priority in ['P0', 'P1', 'P2']:
            total = stats['modules'][priority]['total']
            tested = stats['modules'][priority]['tested']
            pct = stats['modules'][priority]['percentage']
            md.append(f"| {priority} | {tested} | {total} | {pct:.1f}% |")

        md.append("\n## Subworkflows Coverage")
        md.append("| Priority | Tested | Total | Coverage |")
        md.append("|----------|--------|-------|----------|")
        for priority in ['P0', 'P1', 'P2']:
            total = stats['subworkflows'][priority]['total']
            tested = stats['subworkflows'][priority]['tested']
            pct = stats['subworkflows'][priority]['percentage']
            md.append(f"| {priority} | {tested} | {total} | {pct:.1f}% |")

        md.append("\n## Coverage Gaps")

        if gaps['P0_untested']:
            md.append(f"\n### ❌ Critical (P0) - {len(gaps['P0_untested'])} untested")
            for item in gaps['P0_untested']:
                md.append(f"- {item['type']}: `{item['name']}`")

        if gaps['P1_untested']:
            md.append(f"\n### ⚠️ Important (P1) - {len(gaps['P1_untested'])} untested")
            for item in gaps['P1_untested']:
                md.append(f"- {item['type']}: `{item['name']}`")

        return "\n".join(md)

    def _generate_json_report(self, stats: Dict, gaps: Dict) -> str:
        """Generate JSON-formatted report."""
        report = {
            'timestamp': __import__('datetime').datetime.now().isoformat(),
            'statistics': stats,
            'gaps': gaps,
            'modules': {name: {'has_tests': info['has_tests'], 'priority': info['priority']}
                       for name, info in self.modules.items()},
            'subworkflows': {name: {'has_tests': info['has_tests'], 'priority': info['priority']}
                            for name, info in self.subworkflows.items()}
        }
        return json.dumps(report, indent=2)

    def run_analysis(self, format: str = 'console') -> str:
        """Run complete coverage analysis."""
        self.scan_components()
        self.analyze_test_content()
        stats = self.calculate_coverage()
        gaps = self.identify_gaps(stats)
        return self.generate_report(stats, gaps, format)


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Analyze test coverage for nanometanf pipeline')
    parser.add_argument('--format', choices=['console', 'json', 'markdown'],
                       default='console', help='Output format')
    parser.add_argument('--output', '-o', help='Output file (default: stdout)')

    args = parser.parse_args()

    analyzer = TestCoverageAnalyzer()
    report = analyzer.run_analysis(format=args.format)

    if args.output:
        with open(args.output, 'w') as f:
            f.write(report)
        print(f"Report written to {args.output}")
    else:
        print(report)


if __name__ == '__main__':
    main()
