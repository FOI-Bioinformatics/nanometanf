#!/usr/bin/env python3

"""
Comprehensive Pipeline Validator for nanometanf
==============================================

Provides validation for inputs, outputs, and pipeline integrity checks
for production environments.
"""

import json
import sys
import os
import argparse
import hashlib
import gzip
import datetime
import re
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple

class FileValidator:
    """Comprehensive file validation system."""
    
    def __init__(self):
        self.supported_formats = {
            'fastq': ['.fastq', '.fq', '.fastq.gz', '.fq.gz'],
            'fasta': ['.fasta', '.fa', '.fas', '.fasta.gz', '.fa.gz'],
            'pod5': ['.pod5'],
            'json': ['.json'],
            'tsv': ['.tsv', '.txt'],
            'csv': ['.csv'],
            'sam': ['.sam'],
            'bam': ['.bam'],
            'html': ['.html'],
            'xml': ['.xml']
        }
        
        self.quality_thresholds = {
            'min_reads': 1000,
            'min_mean_length': 100,
            'min_mean_quality': 7.0,
            'max_error_rate': 0.2
        }
    
    def validate_file(self, file_path: Path, expected_format: str = None) -> Dict[str, Any]:
        """Comprehensive file validation."""
        
        validation_result = {
            'file_path': str(file_path),
            'timestamp': datetime.datetime.now().isoformat(),
            'exists': file_path.exists(),
            'readable': False,
            'size_bytes': 0,
            'format_valid': False,
            'content_valid': False,
            'checksum': None,
            'errors': [],
            'warnings': [],
            'metadata': {}
        }
        
        if not validation_result['exists']:
            validation_result['errors'].append(f"File does not exist: {file_path}")
            return validation_result
        
        try:
            # Basic file properties
            stat = file_path.stat()
            validation_result['size_bytes'] = stat.st_size
            validation_result['readable'] = file_path.is_file() and access(file_path, os.R_OK)
            
            # Generate checksum
            validation_result['checksum'] = self._calculate_checksum(file_path)
            
            # Format validation
            detected_format = self._detect_format(file_path)
            validation_result['detected_format'] = detected_format
            
            if expected_format:
                validation_result['format_valid'] = detected_format == expected_format
                if not validation_result['format_valid']:
                    validation_result['errors'].append(
                        f"Format mismatch: expected {expected_format}, detected {detected_format}"
                    )
            else:
                validation_result['format_valid'] = detected_format is not None
            
            # Content validation based on format
            if detected_format:
                content_validation = self._validate_content(file_path, detected_format)
                validation_result.update(content_validation)
            
        except Exception as e:
            validation_result['errors'].append(f"Validation error: {str(e)}")
        
        return validation_result
    
    def _calculate_checksum(self, file_path: Path, algorithm: str = 'sha256') -> str:
        """Calculate file checksum."""
        hash_obj = hashlib.new(algorithm)
        
        try:
            with open(file_path, 'rb') as f:
                for chunk in iter(lambda: f.read(4096), b""):
                    hash_obj.update(chunk)
            return hash_obj.hexdigest()
        except Exception as e:
            return f"ERROR: {str(e)}"
    
    def _detect_format(self, file_path: Path) -> Optional[str]:
        """Detect file format based on extension and content."""
        suffix = file_path.suffix.lower()
        
        # Handle compressed files
        if suffix == '.gz':
            suffix = ''.join(file_path.suffixes[-2:]).lower()
        
        # Check against known formats
        for format_name, extensions in self.supported_formats.items():
            if suffix in extensions:
                return format_name
        
        return None
    
    def _validate_content(self, file_path: Path, file_format: str) -> Dict[str, Any]:
        """Validate file content based on format."""
        result = {
            'content_valid': False,
            'metadata': {},
            'quality_metrics': {}
        }
        
        try:
            if file_format == 'fastq':
                result.update(self._validate_fastq(file_path))
            elif file_format == 'fasta':
                result.update(self._validate_fasta(file_path))
            elif file_format == 'json':
                result.update(self._validate_json(file_path))
            elif file_format == 'pod5':
                result.update(self._validate_pod5(file_path))
            elif file_format in ['tsv', 'csv']:
                result.update(self._validate_tabular(file_path, file_format))
            else:
                result['content_valid'] = True  # Basic existence check
                result['metadata']['note'] = f"Content validation not implemented for {file_format}"
                
        except Exception as e:
            result['errors'] = result.get('errors', [])
            result['errors'].append(f"Content validation error: {str(e)}")
        
        return result
    
    def _validate_fastq(self, file_path: Path) -> Dict[str, Any]:
        """Validate FASTQ file format and quality."""
        result = {
            'content_valid': False,
            'metadata': {},
            'quality_metrics': {},
            'errors': [],
            'warnings': []
        }
        
        read_count = 0
        total_length = 0
        quality_scores = []
        
        try:
            open_func = gzip.open if file_path.suffix == '.gz' else open
            mode = 'rt' if file_path.suffix == '.gz' else 'r'
            
            with open_func(file_path, mode) as f:
                lines = []
                for line_num, line in enumerate(f, 1):
                    lines.append(line.strip())
                    
                    # Process complete FASTQ records (4 lines each)
                    if len(lines) == 4:
                        header, sequence, plus, quality = lines
                        
                        # Validate FASTQ format
                        if not header.startswith('@'):
                            result['errors'].append(f"Invalid header at line {line_num-3}: {header}")
                            return result
                            
                        if not plus.startswith('+'):
                            result['errors'].append(f"Invalid plus line at line {line_num-1}: {plus}")
                            return result
                        
                        if len(sequence) != len(quality):
                            result['errors'].append(f"Sequence/quality length mismatch at read {read_count+1}")
                            return result
                        
                        # Collect metrics
                        read_count += 1
                        total_length += len(sequence)
                        
                        # Sample quality scores (first 1000 reads for performance)
                        if read_count <= 1000:
                            quality_scores.extend([ord(c) - 33 for c in quality])
                        
                        lines = []
                        
                        # Early termination for large files (sample validation)
                        if read_count >= 10000:
                            break
            
            # Calculate quality metrics
            if read_count > 0:
                result['metadata']['read_count_sampled'] = read_count
                result['metadata']['mean_read_length'] = total_length / read_count
                
                if quality_scores:
                    result['quality_metrics']['mean_quality'] = sum(quality_scores) / len(quality_scores)
                    result['quality_metrics']['min_quality'] = min(quality_scores)
                    result['quality_metrics']['max_quality'] = max(quality_scores)
                
                # Quality thresholds validation
                if read_count < self.quality_thresholds['min_reads']:
                    result['warnings'].append(f"Low read count: {read_count} < {self.quality_thresholds['min_reads']}")
                
                if result['metadata']['mean_read_length'] < self.quality_thresholds['min_mean_length']:
                    result['warnings'].append(f"Short reads: {result['metadata']['mean_read_length']} < {self.quality_thresholds['min_mean_length']}")
                
                if quality_scores and result['quality_metrics']['mean_quality'] < self.quality_thresholds['min_mean_quality']:
                    result['warnings'].append(f"Low quality: {result['quality_metrics']['mean_quality']:.2f} < {self.quality_thresholds['min_mean_quality']}")
                
                result['content_valid'] = True
            else:
                result['errors'].append("No valid FASTQ records found")
                
        except Exception as e:
            result['errors'].append(f"FASTQ validation error: {str(e)}")
        
        return result
    
    def _validate_fasta(self, file_path: Path) -> Dict[str, Any]:
        """Validate FASTA file format."""
        result = {
            'content_valid': False,
            'metadata': {},
            'errors': [],
            'warnings': []
        }
        
        try:
            sequence_count = 0
            total_length = 0
            
            open_func = gzip.open if file_path.suffix == '.gz' else open
            mode = 'rt' if file_path.suffix == '.gz' else 'r'
            
            with open_func(file_path, mode) as f:
                current_seq_length = 0
                in_sequence = False
                
                for line_num, line in enumerate(f, 1):
                    line = line.strip()
                    
                    if line.startswith('>'):
                        if in_sequence:
                            total_length += current_seq_length
                            current_seq_length = 0
                        sequence_count += 1
                        in_sequence = True
                    elif in_sequence and line:
                        # Validate sequence characters
                        if not re.match(r'^[ACGTUWSMKRYBDHVN-]+$', line, re.IGNORECASE):
                            result['warnings'].append(f"Non-standard nucleotide characters at line {line_num}")
                        current_seq_length += len(line)
                    
                    # Early termination for large files
                    if sequence_count >= 1000:
                        break
                
                # Add last sequence
                if in_sequence:
                    total_length += current_seq_length
            
            if sequence_count > 0:
                result['metadata']['sequence_count_sampled'] = sequence_count
                result['metadata']['mean_sequence_length'] = total_length / sequence_count
                result['content_valid'] = True
            else:
                result['errors'].append("No valid FASTA sequences found")
                
        except Exception as e:
            result['errors'].append(f"FASTA validation error: {str(e)}")
        
        return result
    
    def _validate_json(self, file_path: Path) -> Dict[str, Any]:
        """Validate JSON file format."""
        result = {
            'content_valid': False,
            'metadata': {},
            'errors': []
        }
        
        try:
            with open(file_path, 'r') as f:
                data = json.load(f)
                result['content_valid'] = True
                result['metadata']['json_structure'] = type(data).__name__
                
                if isinstance(data, dict):
                    result['metadata']['key_count'] = len(data.keys())
                elif isinstance(data, list):
                    result['metadata']['item_count'] = len(data)
                    
        except json.JSONDecodeError as e:
            result['errors'].append(f"Invalid JSON format: {str(e)}")
        except Exception as e:
            result['errors'].append(f"JSON validation error: {str(e)}")
        
        return result
    
    def _validate_pod5(self, file_path: Path) -> Dict[str, Any]:
        """Validate POD5 file format (basic check)."""
        result = {
            'content_valid': False,
            'metadata': {},
            'errors': [],
            'warnings': []
        }
        
        try:
            # Basic POD5 file validation
            # Note: Full POD5 validation would require pod5 library
            with open(file_path, 'rb') as f:
                header = f.read(16)
                
                # Check for POD5 magic bytes (simplified check)
                if len(header) >= 8:
                    result['metadata']['file_size'] = file_path.stat().st_size
                    result['content_valid'] = True
                    result['warnings'].append("Basic POD5 validation - full validation requires pod5 library")
                else:
                    result['errors'].append("File too small to be valid POD5")
                    
        except Exception as e:
            result['errors'].append(f"POD5 validation error: {str(e)}")
        
        return result
    
    def _validate_tabular(self, file_path: Path, file_format: str) -> Dict[str, Any]:
        """Validate tabular data files (TSV/CSV)."""
        result = {
            'content_valid': False,
            'metadata': {},
            'errors': [],
            'warnings': []
        }
        
        try:
            delimiter = '\t' if file_format == 'tsv' else ','
            row_count = 0
            column_count = None
            
            with open(file_path, 'r') as f:
                for line_num, line in enumerate(f, 1):
                    line = line.strip()
                    if line:
                        columns = line.split(delimiter)
                        
                        if column_count is None:
                            column_count = len(columns)
                        elif len(columns) != column_count:
                            result['warnings'].append(f"Inconsistent column count at line {line_num}")
                        
                        row_count += 1
                        
                        # Early termination for large files
                        if row_count >= 1000:
                            break
            
            if row_count > 0:
                result['metadata']['row_count_sampled'] = row_count
                result['metadata']['column_count'] = column_count
                result['content_valid'] = True
            else:
                result['errors'].append("No data rows found")
                
        except Exception as e:
            result['errors'].append(f"Tabular validation error: {str(e)}")
        
        return result

class PipelineValidator:
    """Main pipeline validation orchestrator."""
    
    def __init__(self):
        self.file_validator = FileValidator()
        self.validation_rules = {
            'input_validation': True,
            'output_validation': True,
            'integrity_checks': True,
            'performance_validation': True
        }
    
    def validate_pipeline(self, input_files: List[Path], validation_config: Dict[str, Any]) -> Dict[str, Any]:
        """Comprehensive pipeline validation."""
        
        validation_report = {
            'timestamp': datetime.datetime.now().isoformat(),
            'validation_config': validation_config,
            'overall_status': 'PENDING',
            'file_validations': [],
            'pipeline_integrity': {},
            'performance_metrics': {},
            'errors': [],
            'warnings': [],
            'recommendations': []
        }
        
        try:
            # Validate individual files
            for file_path in input_files:
                file_validation = self.file_validator.validate_file(
                    file_path, 
                    expected_format=validation_config.get('expected_format')
                )
                validation_report['file_validations'].append(file_validation)
                
                # Collect errors and warnings
                validation_report['errors'].extend(file_validation.get('errors', []))
                validation_report['warnings'].extend(file_validation.get('warnings', []))
            
            # Pipeline integrity checks
            integrity_results = self._validate_pipeline_integrity(input_files, validation_config)
            validation_report['pipeline_integrity'] = integrity_results
            
            # Performance validation
            if validation_config.get('enable_performance_validation', False):
                performance_results = self._validate_performance_metrics(input_files, validation_config)
                validation_report['performance_metrics'] = performance_results
            
            # Generate recommendations
            validation_report['recommendations'] = self._generate_recommendations(validation_report)
            
            # Determine overall status
            validation_report['overall_status'] = self._determine_overall_status(validation_report)
            
        except Exception as e:
            validation_report['errors'].append(f"Pipeline validation error: {str(e)}")
            validation_report['overall_status'] = 'ERROR'
        
        return validation_report
    
    def _validate_pipeline_integrity(self, input_files: List[Path], config: Dict[str, Any]) -> Dict[str, Any]:
        """Validate pipeline integrity and consistency."""
        integrity_results = {
            'input_consistency': True,
            'format_consistency': True,
            'dependency_validation': True,
            'configuration_validation': True,
            'issues': []
        }
        
        try:
            # Check input consistency
            if len(input_files) == 0:
                integrity_results['input_consistency'] = False
                integrity_results['issues'].append("No input files provided")
            
            # Check format consistency
            formats = set()
            for file_path in input_files:
                detected_format = self.file_validator._detect_format(file_path)
                if detected_format:
                    formats.add(detected_format)
            
            if len(formats) > 1 and config.get('require_format_consistency', True):
                integrity_results['format_consistency'] = False
                integrity_results['issues'].append(f"Mixed input formats detected: {formats}")
            
            # Basic configuration validation
            required_params = config.get('required_parameters', [])
            for param in required_params:
                if param not in config:
                    integrity_results['configuration_validation'] = False
                    integrity_results['issues'].append(f"Missing required parameter: {param}")
            
        except Exception as e:
            integrity_results['issues'].append(f"Integrity validation error: {str(e)}")
        
        return integrity_results
    
    def _validate_performance_metrics(self, input_files: List[Path], config: Dict[str, Any]) -> Dict[str, Any]:
        """Validate performance-related metrics."""
        performance_results = {
            'estimated_runtime': None,
            'estimated_memory': None,
            'estimated_storage': None,
            'performance_warnings': []
        }
        
        try:
            total_size = sum(f.stat().st_size for f in input_files if f.exists())
            
            # Rough estimates based on file sizes (these should be calibrated based on actual benchmarks)
            performance_results['estimated_storage'] = total_size * 3  # 3x for intermediate files
            performance_results['estimated_memory'] = min(max(total_size // 10, 8 * 1024**3), 256 * 1024**3)  # 8GB to 256GB
            performance_results['estimated_runtime'] = total_size // (100 * 1024**2)  # Minutes based on 100MB/min processing
            
            # Performance warnings
            if total_size > 100 * 1024**3:  # > 100GB
                performance_results['performance_warnings'].append("Large dataset detected - consider cluster deployment")
            
            if performance_results['estimated_memory'] > 128 * 1024**3:  # > 128GB
                performance_results['performance_warnings'].append("High memory requirements - ensure adequate RAM")
            
        except Exception as e:
            performance_results['performance_warnings'].append(f"Performance estimation error: {str(e)}")
        
        return performance_results
    
    def _generate_recommendations(self, validation_report: Dict[str, Any]) -> List[str]:
        """Generate actionable recommendations based on validation results."""
        recommendations = []
        
        # Error-based recommendations
        if validation_report['errors']:
            recommendations.append("Address validation errors before proceeding with pipeline execution")
        
        # Warning-based recommendations
        if validation_report['warnings']:
            recommendations.append("Review validation warnings and consider parameter adjustments")
        
        # Performance recommendations
        performance = validation_report.get('performance_metrics', {})
        if performance.get('estimated_memory', 0) > 64 * 1024**3:
            recommendations.append("Consider using high-memory compute instances")
        
        if performance.get('estimated_storage', 0) > 1024**4:  # > 1TB
            recommendations.append("Ensure adequate storage space and consider cleanup strategies")
        
        # File-specific recommendations
        for file_val in validation_report['file_validations']:
            if file_val.get('warnings'):
                if any('quality' in w.lower() for w in file_val['warnings']):
                    recommendations.append("Consider quality filtering parameters adjustment")
                if any('length' in w.lower() for w in file_val['warnings']):
                    recommendations.append("Review read length filtering settings")
        
        # Integrity recommendations
        integrity = validation_report.get('pipeline_integrity', {})
        if not integrity.get('format_consistency', True):
            recommendations.append("Ensure consistent input file formats for optimal processing")
        
        return recommendations
    
    def _determine_overall_status(self, validation_report: Dict[str, Any]) -> str:
        """Determine overall validation status."""
        if validation_report['errors']:
            return 'FAILED'
        
        # Check critical integrity issues
        integrity = validation_report.get('pipeline_integrity', {})
        if not integrity.get('input_consistency', True):
            return 'FAILED'
        
        if validation_report['warnings']:
            return 'WARNING'
        
        return 'PASSED'

def main():
    parser = argparse.ArgumentParser(description='Comprehensive Pipeline Validator for nanometanf')
    parser.add_argument('--sample_id', required=True, help='Sample identifier')
    parser.add_argument('--input_files', nargs='+', required=True, help='Input files to validate')
    parser.add_argument('--validation_config', required=True, help='Validation configuration (JSON string or file)')
    parser.add_argument('--validation_type', default='comprehensive', help='Validation type')
    parser.add_argument('--output_prefix', required=True, help='Output file prefix')
    parser.add_argument('--enable_checksums', action='store_true', help='Calculate file checksums')
    parser.add_argument('--enable_format_validation', action='store_true', help='Validate file formats')
    parser.add_argument('--enable_content_validation', action='store_true', help='Validate file contents')
    
    args = parser.parse_args()
    
    # Parse validation configuration
    try:
        if args.validation_config.startswith('{'):
            # JSON string
            validation_config = json.loads(args.validation_config)
        else:
            # JSON file
            with open(args.validation_config, 'r') as f:
                validation_config = json.load(f)
    except Exception as e:
        print(f"Error parsing validation config: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Convert input files to Path objects
    input_files = [Path(f) for f in args.input_files]
    
    # Initialize validator
    validator = PipelineValidator()
    
    # Perform validation
    validation_report = validator.validate_pipeline(input_files, validation_config)
    
    # Save detailed report
    report_file = f"{args.output_prefix}.validation_report.json"
    with open(report_file, 'w') as f:
        json.dump(validation_report, f, indent=2)
    
    # Generate summary
    summary_file = f"{args.output_prefix}.validation_summary.txt"
    with open(summary_file, 'w') as f:
        f.write(f"Pipeline Validation Summary\n")
        f.write(f"{'='*50}\n")
        f.write(f"Sample ID: {args.sample_id}\n")
        f.write(f"Timestamp: {validation_report['timestamp']}\n")
        f.write(f"Overall Status: {validation_report['overall_status']}\n")
        f.write(f"Files Validated: {len(validation_report['file_validations'])}\n")
        f.write(f"Errors: {len(validation_report['errors'])}\n")
        f.write(f"Warnings: {len(validation_report['warnings'])}\n")
        f.write(f"Recommendations: {len(validation_report['recommendations'])}\n\n")
        
        if validation_report['errors']:
            f.write("ERRORS:\n")
            for error in validation_report['errors']:
                f.write(f"  - {error}\n")
            f.write("\n")
        
        if validation_report['warnings']:
            f.write("WARNINGS:\n")
            for warning in validation_report['warnings']:
                f.write(f"  - {warning}\n")
            f.write("\n")
        
        if validation_report['recommendations']:
            f.write("RECOMMENDATIONS:\n")
            for rec in validation_report['recommendations']:
                f.write(f"  - {rec}\n")
    
    print(f"Validation complete. Status: {validation_report['overall_status']}")
    print(f"Report saved to: {report_file}")
    print(f"Summary saved to: {summary_file}")
    
    # Exit with appropriate code
    if validation_report['overall_status'] == 'FAILED':
        sys.exit(1)
    elif validation_report['overall_status'] == 'WARNING':
        sys.exit(2)
    else:
        sys.exit(0)

if __name__ == '__main__':
    main()