#!/usr/bin/env python3
"""
Generate all test fixtures for the nanometanf pipeline test suite.

This script creates standardized, reusable test data fixtures to replace
inline data generation in test setup blocks.

Usage:
    python3 generate_fixtures.py [--output-dir path] [--fixtures type,type,...]

Examples:
    python3 generate_fixtures.py                        # Generate all fixtures
    python3 generate_fixtures.py --fixtures characteristics,predictions
    python3 generate_fixtures.py --output-dir custom/path
"""

import json
import gzip
import random
import argparse
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, List


class FixtureGenerator:
    """Generate standardized test fixtures for nanometanf pipeline."""

    def __init__(self, output_dir: Path):
        self.output_dir = output_dir
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def generate_all(self):
        """Generate all test fixtures."""
        print("🔧 Generating test fixtures for nanometanf pipeline...")
        print(f"📁 Output directory: {self.output_dir}")
        print()

        generators = [
            ("characteristics", self.generate_characteristics_fixtures),
            ("predictions", self.generate_prediction_fixtures),
            ("statistics", self.generate_statistics_fixtures),
            ("system_metrics", self.generate_system_metrics_fixtures),
            ("edge_cases", self.generate_edge_case_fixtures),
        ]

        total_files = 0
        for category, generator in generators:
            print(f"⚙️  Generating {category} fixtures...")
            count = generator()
            total_files += count
            print(f"   ✅ Generated {count} {category} fixtures\n")

        print(f"🎉 Successfully generated {total_files} fixture files!")
        self.generate_readme()

    def generate_characteristics_fixtures(self) -> int:
        """Generate input characteristics fixtures."""
        output_dir = self.output_dir / "characteristics"
        output_dir.mkdir(exist_ok=True)

        fixtures = {
            "small_fastq.json": {
                "sample_id": "small_test",
                "analysis_timestamp": "2024-01-15T10:00:00",
                "tool_context": {},
                "file_count": 1,
                "total_size_bytes": 10485760,
                "total_size_mb": 10.0,
                "total_size_gb": 0.01,
                "total_estimated_reads": 50000,
                "total_estimated_bases": 100000000,
                "average_file_size_mb": 10.0,
                "estimated_coverage": "1x",
                "complexity_metrics": {
                    "overall_complexity": 0.75,
                    "size_complexity": "low",
                    "read_complexity": "low"
                },
                "processing_hints": {
                    "recommended_parallelization": 2,
                    "memory_intensive": False,
                    "cpu_intensive": False,
                    "io_intensive": False,
                    "gpu_beneficial": False
                },
                "file_details": []
            },

            "medium_fastq.json": {
                "sample_id": "medium_test",
                "analysis_timestamp": "2024-01-15T10:00:00",
                "tool_context": {},
                "file_count": 1,
                "total_size_bytes": 104857600,
                "total_size_mb": 100.0,
                "total_size_gb": 0.1,
                "total_estimated_reads": 500000,
                "total_estimated_bases": 1000000000,
                "average_file_size_mb": 100.0,
                "estimated_coverage": "10x",
                "complexity_metrics": {
                    "overall_complexity": 0.80,
                    "size_complexity": "medium",
                    "read_complexity": "medium"
                },
                "processing_hints": {
                    "recommended_parallelization": 4,
                    "memory_intensive": False,
                    "cpu_intensive": True,
                    "io_intensive": False,
                    "gpu_beneficial": False
                },
                "file_details": []
            },

            "large_fastq.json": {
                "sample_id": "large_test",
                "analysis_timestamp": "2024-01-15T10:00:00",
                "tool_context": {},
                "file_count": 1,
                "total_size_bytes": 1073741824,
                "total_size_mb": 1024.0,
                "total_size_gb": 1.0,
                "total_estimated_reads": 5000000,
                "total_estimated_bases": 10000000000,
                "average_file_size_mb": 1024.0,
                "estimated_coverage": "100x",
                "complexity_metrics": {
                    "overall_complexity": 0.92,
                    "size_complexity": "high",
                    "read_complexity": "high"
                },
                "processing_hints": {
                    "recommended_parallelization": 8,
                    "memory_intensive": True,
                    "cpu_intensive": True,
                    "io_intensive": True,
                    "gpu_beneficial": True
                },
                "file_details": []
            },

            "pod5_typical.json": {
                "sample_id": "pod5_test",
                "analysis_timestamp": "2024-01-15T10:00:00",
                "tool_context": {"basecalling_required": True},
                "file_count": 10,
                "total_size_bytes": 536870912,
                "total_size_mb": 512.0,
                "total_size_gb": 0.5,
                "total_estimated_reads": 2500000,
                "total_estimated_bases": 5000000000,
                "average_file_size_mb": 51.2,
                "estimated_coverage": "50x",
                "complexity_metrics": {
                    "overall_complexity": 0.85,
                    "size_complexity": "high",
                    "read_complexity": "high"
                },
                "processing_hints": {
                    "recommended_parallelization": 6,
                    "memory_intensive": True,
                    "cpu_intensive": False,
                    "io_intensive": False,
                    "gpu_beneficial": True
                },
                "file_details": []
            },
        }

        # Edge case characteristics
        edge_cases = {
            "empty_file.json": {
                "sample_id": "empty_test",
                "analysis_timestamp": "2024-01-15T10:00:00",
                "tool_context": {},
                "file_count": 1,
                "total_size_bytes": 0,
                "total_size_mb": 0.0,
                "total_size_gb": 0.0,
                "total_estimated_reads": 0,
                "total_estimated_bases": 0,
                "average_file_size_mb": 0.0,
                "estimated_coverage": "0x",
                "complexity_metrics": {
                    "overall_complexity": 0.0,
                    "size_complexity": "none",
                    "read_complexity": "none"
                },
                "processing_hints": {
                    "recommended_parallelization": 1,
                    "memory_intensive": False,
                    "cpu_intensive": False,
                    "io_intensive": False,
                    "gpu_beneficial": False
                },
                "file_details": []
            },

            "minimal_file.json": {
                "sample_id": "minimal_test",
                "analysis_timestamp": "2024-01-15T10:00:00",
                "tool_context": {},
                "file_count": 1,
                "total_size_bytes": 1024,
                "total_size_mb": 0.001,
                "total_size_gb": 0.000001,
                "total_estimated_reads": 10,
                "total_estimated_bases": 20000,
                "average_file_size_mb": 0.001,
                "estimated_coverage": "0.0001x",
                "complexity_metrics": {
                    "overall_complexity": 0.5,
                    "size_complexity": "very_low",
                    "read_complexity": "very_low"
                },
                "processing_hints": {
                    "recommended_parallelization": 1,
                    "memory_intensive": False,
                    "cpu_intensive": False,
                    "io_intensive": False,
                    "gpu_beneficial": False
                },
                "file_details": []
            },
        }

        # Write all fixtures
        for filename, data in {**fixtures, **edge_cases}.items():
            filepath = output_dir / filename
            with open(filepath, 'w') as f:
                json.dump(data, f, indent=2)

        return len(fixtures) + len(edge_cases)

    def generate_prediction_fixtures(self) -> int:
        """Generate resource prediction fixtures."""
        output_dir = self.output_dir / "predictions"
        output_dir.mkdir(exist_ok=True)

        fixtures = {
            "high_throughput_prediction.json": {
                "sample_id": "high_throughput_test",
                "prediction_timestamp": "2024-01-15T10:00:00",
                "predictions": {
                    "cpu_requirements": {
                        "predicted_cores": 8,
                        "confidence_score": 0.92,
                        "min_cores": 4,
                        "max_cores": 16
                    },
                    "memory_requirements": {
                        "predicted_memory_gb": 32.0,
                        "confidence_score": 0.88,
                        "min_memory_gb": 16.0,
                        "max_memory_gb": 64.0
                    },
                    "time_requirements": {
                        "predicted_minutes": 120,
                        "confidence_score": 0.75,
                        "min_minutes": 60,
                        "max_minutes": 240
                    },
                    "disk_requirements": {
                        "predicted_disk_gb": 100.0,
                        "confidence_score": 0.85
                    }
                },
                "confidence_metrics": {
                    "overall_confidence": 0.85,
                    "model_version": "v1.0.0",
                    "prediction_method": "gradient_boost"
                },
                "tool_specific_predictions": {
                    "fastp": {"cpus": 4, "memory": "8.GB", "time": "30.min"},
                    "kraken2": {"cpus": 8, "memory": "16.GB", "time": "60.min"},
                    "nanoplot": {"cpus": 2, "memory": "4.GB", "time": "15.min"}
                }
            },

            "balanced_prediction.json": {
                "sample_id": "balanced_test",
                "prediction_timestamp": "2024-01-15T10:00:00",
                "predictions": {
                    "cpu_requirements": {
                        "predicted_cores": 4,
                        "confidence_score": 0.88,
                        "min_cores": 2,
                        "max_cores": 8
                    },
                    "memory_requirements": {
                        "predicted_memory_gb": 8.0,
                        "confidence_score": 0.90,
                        "min_memory_gb": 4.0,
                        "max_memory_gb": 16.0
                    },
                    "time_requirements": {
                        "predicted_minutes": 60,
                        "confidence_score": 0.82,
                        "min_minutes": 30,
                        "max_minutes": 120
                    },
                    "disk_requirements": {
                        "predicted_disk_gb": 50.0,
                        "confidence_score": 0.88
                    }
                },
                "confidence_metrics": {
                    "overall_confidence": 0.87,
                    "model_version": "v1.0.0",
                    "prediction_method": "gradient_boost"
                },
                "tool_specific_predictions": {
                    "fastp": {"cpus": 2, "memory": "4.GB", "time": "15.min"},
                    "kraken2": {"cpus": 4, "memory": "8.GB", "time": "30.min"},
                    "nanoplot": {"cpus": 1, "memory": "2.GB", "time": "10.min"}
                }
            },

            "conservative_prediction.json": {
                "sample_id": "conservative_test",
                "prediction_timestamp": "2024-01-15T10:00:00",
                "predictions": {
                    "cpu_requirements": {
                        "predicted_cores": 2,
                        "confidence_score": 0.95,
                        "min_cores": 1,
                        "max_cores": 4
                    },
                    "memory_requirements": {
                        "predicted_memory_gb": 4.0,
                        "confidence_score": 0.93,
                        "min_memory_gb": 2.0,
                        "max_memory_gb": 8.0
                    },
                    "time_requirements": {
                        "predicted_minutes": 30,
                        "confidence_score": 0.87,
                        "min_minutes": 15,
                        "max_minutes": 60
                    },
                    "disk_requirements": {
                        "predicted_disk_gb": 20.0,
                        "confidence_score": 0.90
                    }
                },
                "confidence_metrics": {
                    "overall_confidence": 0.91,
                    "model_version": "v1.0.0",
                    "prediction_method": "gradient_boost"
                },
                "tool_specific_predictions": {
                    "fastp": {"cpus": 1, "memory": "2.GB", "time": "10.min"},
                    "kraken2": {"cpus": 2, "memory": "4.GB", "time": "15.min"},
                    "nanoplot": {"cpus": 1, "memory": "2.GB", "time": "5.min"}
                }
            },
        }

        for filename, data in fixtures.items():
            filepath = output_dir / filename
            with open(filepath, 'w') as f:
                json.dump(data, f, indent=2)

        return len(fixtures)

    def generate_statistics_fixtures(self) -> int:
        """Generate real-time statistics fixtures."""
        output_dir = self.output_dir / "statistics"
        output_dir.mkdir(exist_ok=True)

        fixtures = {
            "snapshot_batch_001.json": {
                "batch_id": "batch_001",
                "timestamp": "2024-01-15T10:00:00",
                "sample_id": "test_sample",
                "batch_metrics": {
                    "files_processed": 10,
                    "total_reads": 50000,
                    "total_bases": 100000000,
                    "average_read_length": 2000,
                    "average_quality": 15.5
                },
                "quality_metrics": {
                    "q10_reads": 48000,
                    "q20_reads": 35000,
                    "q30_reads": 15000
                },
                "processing_time": {
                    "start_time": "2024-01-15T09:00:00",
                    "end_time": "2024-01-15T10:00:00",
                    "duration_seconds": 3600
                }
            },

            "cumulative_session_001.json": {
                "session_id": "session_001",
                "timestamp": "2024-01-15T10:00:00",
                "sample_id": "test_sample",
                "cumulative_metrics": {
                    "total_files_processed": 100,
                    "total_reads": 500000,
                    "total_bases": 1000000000,
                    "average_read_length": 2000,
                    "average_quality": 15.8
                },
                "cumulative_quality_metrics": {
                    "q10_reads": 480000,
                    "q20_reads": 350000,
                    "q30_reads": 150000
                },
                "session_duration": {
                    "start_time": "2024-01-15T00:00:00",
                    "current_time": "2024-01-15T10:00:00",
                    "duration_hours": 10
                },
                "batch_count": 10
            },
        }

        for filename, data in fixtures.items():
            filepath = output_dir / filename
            with open(filepath, 'w') as f:
                json.dump(data, f, indent=2)

        return len(fixtures)

    def generate_system_metrics_fixtures(self) -> int:
        """Generate system resource metrics fixtures."""
        output_dir = self.output_dir / "system_metrics"
        output_dir.mkdir(exist_ok=True)

        fixtures = {
            "normal_load.json": {
                "timestamp": "2024-01-15T10:00:00",
                "system_metrics": {
                    "cpu_usage_percent": 45.2,
                    "memory_usage_percent": 62.5,
                    "disk_usage_percent": 55.0,
                    "load_average_1min": 2.5,
                    "load_average_5min": 2.2,
                    "load_average_15min": 2.0
                },
                "available_resources": {
                    "available_cpus": 6,
                    "available_memory_gb": 12.0,
                    "available_disk_gb": 450.0
                },
                "gpu_metrics": {
                    "gpu_available": False,
                    "gpu_count": 0
                },
                "status": "normal"
            },

            "high_load.json": {
                "timestamp": "2024-01-15T10:00:00",
                "system_metrics": {
                    "cpu_usage_percent": 92.5,
                    "memory_usage_percent": 88.3,
                    "disk_usage_percent": 78.0,
                    "load_average_1min": 10.5,
                    "load_average_5min": 9.2,
                    "load_average_15min": 8.5
                },
                "available_resources": {
                    "available_cpus": 1,
                    "available_memory_gb": 2.5,
                    "available_disk_gb": 220.0
                },
                "gpu_metrics": {
                    "gpu_available": False,
                    "gpu_count": 0
                },
                "status": "high_load",
                "warnings": ["CPU usage above 90%", "Memory usage above 80%"]
            },

            "gpu_available.json": {
                "timestamp": "2024-01-15T10:00:00",
                "system_metrics": {
                    "cpu_usage_percent": 35.0,
                    "memory_usage_percent": 45.0,
                    "disk_usage_percent": 50.0,
                    "load_average_1min": 1.5,
                    "load_average_5min": 1.3,
                    "load_average_15min": 1.2
                },
                "available_resources": {
                    "available_cpus": 8,
                    "available_memory_gb": 24.0,
                    "available_disk_gb": 500.0
                },
                "gpu_metrics": {
                    "gpu_available": True,
                    "gpu_count": 1,
                    "gpu_memory_total_gb": 16.0,
                    "gpu_memory_used_gb": 2.5,
                    "gpu_utilization_percent": 15.0
                },
                "status": "normal"
            },
        }

        for filename, data in fixtures.items():
            filepath = output_dir / filename
            with open(filepath, 'w') as f:
                json.dump(data, f, indent=2)

        return len(fixtures)

    def generate_edge_case_fixtures(self) -> int:
        """Generate edge case test fixtures."""
        output_dir = self.output_dir / "edge_cases"
        output_dir.mkdir(exist_ok=True)

        fixtures = {
            "malformed_json.json": {
                # Note: This will be written as valid JSON, but represents a malformed structure
                "sample_id": "malformed_test",
                "missing_required_field": True,
                # Intentionally missing many expected fields
            },

            "unicode_sample.json": {
                "sample_id": "unicode_test_™️_©️_®️",
                "file_info": {
                    "filename": "测试文件.fastq",
                    "description": "Тестовый файл с unicode символами"
                }
            },

            "extreme_values.json": {
                "sample_id": "extreme_test",
                "total_size_bytes": 9999999999999,  # Very large
                "total_estimated_reads": -1,  # Invalid negative
                "complexity_metrics": {
                    "overall_complexity": 999.99  # Out of range
                }
            },
        }

        for filename, data in fixtures.items():
            filepath = output_dir / filename
            with open(filepath, 'w') as f:
                json.dump(data, f, indent=2)

        return len(fixtures)

    def generate_readme(self):
        """Generate README documenting all fixtures."""
        readme_path = self.output_dir / "README.md"

        readme_content = """# Test Fixtures for nanometanf Pipeline

This directory contains standardized test fixtures used throughout the nanometanf test suite.

## Purpose

Test fixtures provide:
- **Consistency**: Standardized test data across all tests
- **Reusability**: Eliminate duplicate data generation in setup blocks
- **Maintainability**: Single source of truth for test data
- **Documentation**: Clear examples of data structures

## Directory Structure

```
fixtures/
├── characteristics/    # Input analysis characteristics
├── predictions/        # Resource requirement predictions
├── statistics/         # Real-time processing statistics
├── system_metrics/     # System resource monitoring data
├── fastq/             # FASTQ test files
└── edge_cases/        # Edge case and error condition data
```

## Usage in Tests

### Instead of inline data generation:
```groovy
setup {
    \"\"\"
    cat > $outputDir/test_data.json << 'EOF'
    {"sample_id": "test", ...}
    EOF
    \"\"\"
}
```

### Use fixtures:
```groovy
when {
    process {
        \"\"\"
        input[0] = [
            [id: 'test'],
            file('$projectDir/tests/fixtures/characteristics/small_fastq.json')
        ]
        \"\"\"
    }
}
```

## Available Fixtures

### Characteristics Fixtures
- `small_fastq.json` - 10MB file, 50k reads, low complexity
- `medium_fastq.json` - 100MB file, 500k reads, medium complexity
- `large_fastq.json` - 1GB file, 5M reads, high complexity
- `pod5_typical.json` - POD5 input characteristics
- `empty_file.json` - Empty file edge case
- `minimal_file.json` - Minimal valid file (1KB)

### Prediction Fixtures
- `high_throughput_prediction.json` - High resource requirements
- `balanced_prediction.json` - Moderate resource requirements
- `conservative_prediction.json` - Minimal resource requirements

### Statistics Fixtures
- `snapshot_batch_001.json` - Single batch statistics
- `cumulative_session_001.json` - Cumulative session statistics

### System Metrics Fixtures
- `normal_load.json` - Normal system load
- `high_load.json` - High system load with warnings
- `gpu_available.json` - System with GPU resources

### Edge Case Fixtures
- `malformed_json.json` - Missing required fields
- `unicode_sample.json` - Unicode in sample names
- `extreme_values.json` - Out-of-range values

## Regenerating Fixtures

To regenerate all fixtures:
```bash
python3 tests/fixtures/generate_fixtures.py
```

To generate specific fixture types:
```bash
python3 tests/fixtures/generate_fixtures.py --fixtures characteristics,predictions
```

## Fixture Guidelines

1. **Minimal**: Fixtures should be as small as possible while remaining realistic
2. **Stable**: Avoid timestamps or random data that changes between runs
3. **Documented**: Each fixture should have a clear purpose
4. **Valid**: Fixtures should represent valid data structures
5. **Versioned**: Major changes should create new fixture files (v1, v2)

## Maintenance

- Review fixtures quarterly for relevance
- Update fixtures when data structures change
- Add new fixtures for new test scenarios
- Remove obsolete fixtures (after deprecation period)

---

**Generated by:** `tests/fixtures/generate_fixtures.py`
**Last updated:** """ + datetime.now().isoformat() + """
**Version:** 1.0.0
"""

        with open(readme_path, 'w') as f:
            f.write(readme_content)


def main():
    parser = argparse.ArgumentParser(
        description="Generate test fixtures for nanometanf pipeline"
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).parent,
        help="Output directory for fixtures"
    )
    parser.add_argument(
        "--fixtures",
        type=str,
        help="Comma-separated list of fixture types to generate (default: all)"
    )

    args = parser.parse_args()

    generator = FixtureGenerator(args.output_dir)

    if args.fixtures:
        fixture_types = args.fixtures.split(',')
        print(f"Generating specific fixtures: {', '.join(fixture_types)}")
        # TODO: Implement selective generation
    else:
        generator.generate_all()


if __name__ == "__main__":
    main()
