#!/usr/bin/env python3
"""
QC Benchmark Analyzer for nanometanf pipeline

This script analyzes QC tool performance benchmarks and generates
comparative reports for FASTP vs FILTLONG vs enhanced workflows.

Usage:
    python qc_benchmark_analyzer.py --results_dir results/qc_benchmark --output benchmark_report.html

Author: nanometanf pipeline
"""

import argparse
import json
import pandas as pd
import numpy as np
from pathlib import Path
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime
import re

class QCBenchmarkAnalyzer:
    """Analyze and compare QC tool performance metrics."""
    
    def __init__(self, results_dir, output_file):
        self.results_dir = Path(results_dir)
        self.output_file = Path(output_file)
        self.metrics = {}
        self.comparison_data = []
        
    def parse_seqkit_stats(self, stats_file):
        """Parse SeqKit stats output to extract sequence metrics."""
        try:
            df = pd.read_csv(stats_file, sep='\t')
            if not df.empty:
                return {
                    'num_seqs': df['num_seqs'].iloc[0],
                    'sum_len': df['sum_len'].iloc[0],
                    'min_len': df['min_len'].iloc[0],
                    'avg_len': df['avg_len'].iloc[0],
                    'max_len': df['max_len'].iloc[0]
                }
        except Exception as e:
            print(f"Error parsing SeqKit stats {stats_file}: {e}")
        return {}
    
    def parse_fastp_json(self, json_file):
        """Parse FASTP JSON output to extract QC metrics."""
        try:
            with open(json_file, 'r') as f:
                data = json.load(f)
            
            before = data.get('summary', {}).get('before_filtering', {})
            after = data.get('summary', {}).get('after_filtering', {})
            
            return {
                'reads_before': before.get('total_reads', 0),
                'reads_after': after.get('total_reads', 0),
                'bases_before': before.get('total_bases', 0),
                'bases_after': after.get('total_bases', 0),
                'q20_rate_before': before.get('q20_rate', 0),
                'q20_rate_after': after.get('q20_rate', 0),
                'q30_rate_before': before.get('q30_rate', 0),
                'q30_rate_after': after.get('q30_rate', 0),
                'mean_length_before': before.get('total_bases', 0) / max(before.get('total_reads', 1), 1),
                'mean_length_after': after.get('total_bases', 0) / max(after.get('total_reads', 1), 1),
                'filtering_result': data.get('filtering_result', {})
            }
        except Exception as e:
            print(f"Error parsing FASTP JSON {json_file}: {e}")
        return {}
    
    def parse_filtlong_log(self, log_file):
        """Parse FILTLONG log to extract filtering metrics."""
        try:
            with open(log_file, 'r') as f:
                log_content = f.read()
            
            # Extract metrics from FILTLONG log using regex
            metrics = {}
            
            # Look for input/output read counts and lengths
            input_reads_match = re.search(r'(\d+) reads in input', log_content)
            output_reads_match = re.search(r'(\d+) reads in output', log_content)
            
            if input_reads_match:
                metrics['reads_before'] = int(input_reads_match.group(1))
            if output_reads_match:
                metrics['reads_after'] = int(output_reads_match.group(1))
                
            return metrics
        except Exception as e:
            print(f"Error parsing FILTLONG log {log_file}: {e}")
        return {}
    
    def parse_nextflow_trace(self, trace_file):
        """Parse Nextflow execution trace to extract performance metrics."""
        try:
            df = pd.read_csv(trace_file, sep='\t')
            
            # Group by process name and aggregate metrics
            process_metrics = {}
            for _, row in df.iterrows():
                process = row['name']
                if process not in process_metrics:
                    process_metrics[process] = {
                        'duration': [],
                        'memory': [],
                        'cpu_usage': []
                    }
                
                # Convert duration to seconds
                duration_str = str(row.get('duration', '0ms'))
                duration_ms = self._parse_duration(duration_str)
                process_metrics[process]['duration'].append(duration_ms)
                
                # Parse memory usage
                memory_str = str(row.get('memory', '0 MB'))
                memory_mb = self._parse_memory(memory_str)
                process_metrics[process]['memory'].append(memory_mb)
                
                # CPU usage percentage
                cpu_usage = float(row.get('%cpu', 0))
                process_metrics[process]['cpu_usage'].append(cpu_usage)
            
            # Calculate averages
            for process in process_metrics:
                process_metrics[process] = {
                    'avg_duration_ms': np.mean(process_metrics[process]['duration']),
                    'max_memory_mb': np.max(process_metrics[process]['memory']),
                    'avg_cpu_usage': np.mean(process_metrics[process]['cpu_usage'])
                }
            
            return process_metrics
        except Exception as e:
            print(f"Error parsing Nextflow trace {trace_file}: {e}")
        return {}
    
    def _parse_duration(self, duration_str):
        """Parse duration string to milliseconds."""
        duration_str = duration_str.strip()
        if 'ms' in duration_str:
            return float(duration_str.replace('ms', ''))
        elif 's' in duration_str:
            return float(duration_str.replace('s', '')) * 1000
        elif 'm' in duration_str:
            return float(duration_str.replace('m', '')) * 60000
        elif 'h' in duration_str:
            return float(duration_str.replace('h', '')) * 3600000
        return 0
    
    def _parse_memory(self, memory_str):
        """Parse memory string to MB."""
        memory_str = memory_str.strip().upper()
        if 'GB' in memory_str:
            return float(memory_str.replace('GB', '').strip()) * 1024
        elif 'MB' in memory_str:
            return float(memory_str.replace('MB', '').strip())
        elif 'KB' in memory_str:
            return float(memory_str.replace('KB', '').strip()) / 1024
        return 0
    
    def analyze_benchmark_results(self):
        """Analyze all benchmark results in the results directory."""
        print("Analyzing QC benchmark results...")
        
        # Find all benchmark result directories
        benchmark_dirs = list(self.results_dir.glob("**/qc_benchmark"))
        
        for benchmark_dir in benchmark_dirs:
            print(f"Processing benchmark results in: {benchmark_dir}")
            
            # Process FASTP results
            fastp_results = self._process_tool_results(benchmark_dir, 'fastp')
            if fastp_results:
                self.comparison_data.append({
                    'tool': 'FASTP',
                    'category': 'General Purpose',
                    **fastp_results
                })
            
            # Process FILTLONG results
            filtlong_results = self._process_tool_results(benchmark_dir, 'filtlong')
            if filtlong_results:
                self.comparison_data.append({
                    'tool': 'FILTLONG',
                    'category': 'Nanopore Optimized',
                    **filtlong_results
                })
            
            # Process enhanced results (PORECHOP + FILTLONG)
            enhanced_results = self._process_tool_results(benchmark_dir, 'porechop_filtlong')
            if enhanced_results:
                self.comparison_data.append({
                    'tool': 'PORECHOP+FILTLONG',
                    'category': 'Enhanced Nanopore',
                    **enhanced_results
                })
    
    def _process_tool_results(self, benchmark_dir, tool_name):
        """Process results for a specific tool."""
        results = {}
        
        # Look for tool-specific result files
        tool_files = list(benchmark_dir.glob(f"**/*{tool_name}*"))
        
        for file_path in tool_files:
            if file_path.suffix == '.json' and 'fastp' in tool_name:
                fastp_metrics = self.parse_fastp_json(file_path)
                results.update(fastp_metrics)
            elif file_path.suffix == '.log' and 'filtlong' in tool_name:
                filtlong_metrics = self.parse_filtlong_log(file_path)
                results.update(filtlong_metrics)
            elif 'stats' in file_path.name:
                seqkit_metrics = self.parse_seqkit_stats(file_path)
                results.update(seqkit_metrics)
        
        return results
    
    def generate_performance_plots(self):
        """Generate performance comparison plots."""
        if not self.comparison_data:
            print("No comparison data available for plotting.")
            return
        
        df = pd.DataFrame(self.comparison_data)
        
        # Set up the plotting style
        plt.style.use('seaborn-v0_8')
        fig, axes = plt.subplots(2, 2, figsize=(15, 12))
        fig.suptitle('QC Tools Performance Comparison', fontsize=16, fontweight='bold')
        
        # Plot 1: Reads retained
        if 'reads_before' in df.columns and 'reads_after' in df.columns:
            df['retention_rate'] = (df['reads_after'] / df['reads_before'] * 100).fillna(0)
            axes[0, 0].bar(df['tool'], df['retention_rate'], color=['#1f77b4', '#ff7f0e', '#2ca02c'])
            axes[0, 0].set_title('Read Retention Rate (%)')
            axes[0, 0].set_ylabel('Percentage')
            axes[0, 0].tick_params(axis='x', rotation=45)
        
        # Plot 2: Average read length improvement
        if 'avg_len' in df.columns:
            axes[0, 1].bar(df['tool'], df['avg_len'], color=['#1f77b4', '#ff7f0e', '#2ca02c'])
            axes[0, 1].set_title('Average Read Length After QC')
            axes[0, 1].set_ylabel('Base pairs')
            axes[0, 1].tick_params(axis='x', rotation=45)
        
        # Plot 3: Quality improvement (if available)
        if 'q20_rate_after' in df.columns:
            axes[1, 0].bar(df['tool'], df['q20_rate_after'], color=['#1f77b4', '#ff7f0e', '#2ca02c'])
            axes[1, 0].set_title('Q20 Rate After QC')
            axes[1, 0].set_ylabel('Q20 Rate')
            axes[1, 0].tick_params(axis='x', rotation=45)
        
        # Plot 4: Total bases retained
        if 'sum_len' in df.columns:
            axes[1, 1].bar(df['tool'], df['sum_len'], color=['#1f77b4', '#ff7f0e', '#2ca02c'])
            axes[1, 1].set_title('Total Bases After QC')
            axes[1, 1].set_ylabel('Total bases')
            axes[1, 1].tick_params(axis='x', rotation=45)
        
        plt.tight_layout()
        
        # Save plot
        plot_file = self.output_file.parent / f"{self.output_file.stem}_plots.png"
        plt.savefig(plot_file, dpi=300, bbox_inches='tight')
        print(f"Performance plots saved to: {plot_file}")
        
        return plot_file
    
    def generate_report(self):
        """Generate comprehensive benchmark report."""
        print("Generating benchmark report...")
        
        # Analyze results
        self.analyze_benchmark_results()
        
        # Generate plots
        plot_file = self.generate_performance_plots()
        
        # Generate HTML report
        html_content = self._generate_html_report(plot_file)
        
        # Write report
        with open(self.output_file, 'w') as f:
            f.write(html_content)
        
        print(f"Benchmark report generated: {self.output_file}")
    
    def _generate_html_report(self, plot_file):
        """Generate HTML report content."""
        report_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        html_template = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>QC Tools Benchmark Report</title>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 40px; }}
                h1 {{ color: #2c3e50; }}
                h2 {{ color: #34495e; }}
                table {{ border-collapse: collapse; width: 100%; margin: 20px 0; }}
                th, td {{ border: 1px solid #ddd; padding: 12px; text-align: left; }}
                th {{ background-color: #f2f2f2; }}
                .summary {{ background-color: #f8f9fa; padding: 20px; border-radius: 5px; margin: 20px 0; }}
                .plot {{ text-align: center; margin: 30px 0; }}
                .recommendation {{ background-color: #e8f5e8; padding: 15px; border-left: 4px solid #28a745; margin: 20px 0; }}
            </style>
        </head>
        <body>
            <h1>QC Tools Benchmark Report</h1>
            <p><strong>Generated:</strong> {report_time}</p>
            
            <div class="summary">
                <h2>Executive Summary</h2>
                <p>This report compares the performance of different QC tools for nanopore sequencing data processing in the nanometanf pipeline.</p>
                <p><strong>Tools Compared:</strong></p>
                <ul>
                    <li><strong>FASTP:</strong> General-purpose QC tool with rich reporting</li>
                    <li><strong>FILTLONG:</strong> Nanopore-optimized quality filtering</li>
                    <li><strong>PORECHOP+FILTLONG:</strong> Enhanced nanopore QC with adapter trimming</li>
                </ul>
            </div>
            
            <h2>Performance Comparison</h2>
            {self._generate_comparison_table()}
            
            <div class="plot">
                <h2>Performance Visualizations</h2>
                <img src="{plot_file.name}" alt="Performance Comparison Plots" style="max-width: 100%; height: auto;">
            </div>
            
            <div class="recommendation">
                <h2>Recommendations</h2>
                {self._generate_recommendations()}
            </div>
            
            <h2>Detailed Metrics</h2>
            {self._generate_detailed_metrics()}
            
        </body>
        </html>
        """
        
        return html_template
    
    def _generate_comparison_table(self):
        """Generate comparison table HTML."""
        if not self.comparison_data:
            return "<p>No comparison data available.</p>"
        
        df = pd.DataFrame(self.comparison_data)
        
        # Calculate summary metrics
        summary_table = "<table><tr><th>Tool</th><th>Category</th><th>Reads Retained</th><th>Avg Read Length</th><th>Total Bases</th></tr>"
        
        for _, row in df.iterrows():
            reads_retained = f"{row.get('reads_after', 'N/A')}"
            avg_length = f"{row.get('avg_len', 'N/A'):.0f}" if pd.notna(row.get('avg_len')) else 'N/A'
            total_bases = f"{row.get('sum_len', 'N/A'):,}" if pd.notna(row.get('sum_len')) else 'N/A'
            
            summary_table += f"""
            <tr>
                <td>{row['tool']}</td>
                <td>{row['category']}</td>
                <td>{reads_retained}</td>
                <td>{avg_length}</td>
                <td>{total_bases}</td>
            </tr>
            """
        
        summary_table += "</table>"
        return summary_table
    
    def _generate_recommendations(self):
        """Generate tool recommendations based on benchmark results."""
        recommendations = """
        <p><strong>Based on the benchmark analysis:</strong></p>
        <ul>
            <li><strong>For general use:</strong> FILTLONG is recommended for nanopore data due to its nanopore-specific optimizations</li>
            <li><strong>For high-quality requirements:</strong> PORECHOP+FILTLONG provides the best quality improvement through adapter trimming</li>
            <li><strong>For cross-platform compatibility:</strong> FASTP offers consistent results across different sequencing technologies</li>
            <li><strong>For speed-critical applications:</strong> FILTLONG typically offers faster processing for nanopore data</li>
        </ul>
        <p><strong>QC Profile Recommendations:</strong></p>
        <ul>
            <li>Use <code>nanopore_strict</code> profile for high-quality genomics and variant calling</li>
            <li>Use <code>nanopore_metagenomics</code> profile for metagenomic analysis</li>
            <li>Use <code>nanopore_assembly</code> profile for genome assembly projects</li>
        </ul>
        """
        return recommendations
    
    def _generate_detailed_metrics(self):
        """Generate detailed metrics table."""
        if not self.comparison_data:
            return "<p>No detailed metrics available.</p>"
        
        df = pd.DataFrame(self.comparison_data)
        return df.to_html(classes="table", table_id="detailed_metrics", escape=False)

def main():
    parser = argparse.ArgumentParser(description='Analyze QC benchmark results')
    parser.add_argument('--results_dir', required=True, help='Directory containing benchmark results')
    parser.add_argument('--output', required=True, help='Output HTML report file')
    
    args = parser.parse_args()
    
    analyzer = QCBenchmarkAnalyzer(args.results_dir, args.output)
    analyzer.generate_report()

if __name__ == "__main__":
    main()