# nanometanf Documentation

**Welcome to the nanometanf documentation hub.** This pipeline provides comprehensive Oxford Nanopore Technologies (ONT) sequencing data analysis with real-time processing capabilities.

**Quick Navigation:** Use the tables below to find what you need, or jump to the [Documentation Structure](#documentation-structure) for a complete overview.

---

## Quick Links

### 👤 For Users

| Document                                                | Purpose                      | When to Use                   |
| ------------------------------------------------------- | ---------------------------- | ----------------------------- |
| **[Quick Start](user/quickstart.md)**                   | 5-minute tutorial            | First time using the pipeline |
| **[Usage Guide](user/usage.md)**                        | Complete parameter reference | Setting up your analysis      |
| **[Output Guide](user/output.md)**                      | Output files explained       | Understanding results         |
| **[QC Guide](user/qc_guide.md)**                        | Quality metrics              | Interpreting QC reports       |
| **[Troubleshooting](user/troubleshooting.md)**          | Common problems & solutions  | When things go wrong          |
| **[Best Practices](user/best_practices.md)**            | Workflow recommendations     | Optimizing your workflow      |
| **[Performance Tuning](user/performance_tuning.md)**    | Resource optimization        | Improving speed/efficiency    |
| **[Real-time Processing](user/realtime_processing.md)** | Advanced real-time guide     | Live sequencing analysis      |

### 👨‍💻 For Developers

| Document                                                              | Purpose                    | When to Use                |
| --------------------------------------------------------------------- | -------------------------- | -------------------------- |
| **[Development Guide](development/README.md)**                        | Developer hub              | Starting development       |
| **[Testing Guide](development/TESTING.md)**                           | Comprehensive nf-test docs | Writing/running tests      |
| **[Code Quality](development/CODE_QUALITY_EVALUATION_2025-11-04.md)** | Latest assessment          | Understanding code quality |
| **[Release Process](development/RELEASE_PROCESS.md)**                 | How to release             | Creating new versions      |

### 🚀 For Deployers

| Document                                                            | Purpose             | When to Use              |
| ------------------------------------------------------------------- | ------------------- | ------------------------ |
| **[Production Deployment](development/production_deployment.md)**   | Deployment guide    | Setting up production    |
| **[Platform Optimizations](user/OPTIMIZATIONS_QUICK_REFERENCE.md)** | Performance tips    | Platform-specific tuning |
| **[Dynamic Resources](development/dynamic_resource_allocation.md)** | Advanced allocation | HPC optimization         |

### 📋 Release Information

| Document                                           | Purpose              | When to Use            |
| -------------------------------------------------- | -------------------- | ---------------------- |
| **[Current Version](releases/CURRENT_VERSION.md)** | Version guidance     | Choosing which version |
| **[Migration Guide](releases/MIGRATION_GUIDE.md)** | Upgrade instructions | Upgrading versions     |
| **[Release Notes](releases/)**                     | Version history      | What's new/changed     |
| **[Changelog](../CHANGELOG.md)**                   | Complete history     | Detailed change log    |

---

## Getting Started

### New Users

1. Read [Quick Start](user/quickstart.md) (5 minutes)
2. Review [Usage Guide](user/usage.md) for your scenario
3. Check [Current Version](releases/CURRENT_VERSION.md) for stable release

### Developers

1. Read [Development Guide](development/README.md)
2. Review [Testing Guide](development/TESTING.md)
3. Check [CLAUDE.md](../CLAUDE.md) for AI-assisted development

### System Administrators

1. Review [Production Deployment](development/production_deployment.md)
2. Check [Performance Tuning](user/performance_tuning.md)
3. Review [Platform Optimizations](user/OPTIMIZATIONS_QUICK_REFERENCE.md)

---

## Documentation Structure

```
docs/
├── README.md (this file)              # Documentation hub
│
├── user/                              # User-facing documentation
│   ├── quickstart.md                  # 5-minute tutorial
│   ├── usage.md                       # Complete usage guide (MAIN REFERENCE)
│   ├── output.md                      # Output files reference
│   ├── qc_guide.md                    # Quality control guide
│   ├── troubleshooting.md             # Common issues & solutions
│   ├── best_practices.md              # Workflow recommendations
│   ├── performance_tuning.md          # Performance optimization
│   ├── realtime_processing.md         # Real-time processing guide
│   └── OPTIMIZATIONS_QUICK_REFERENCE.md # Platform optimization reference
│
├── development/                       # Developer documentation
│   ├── README.md                      # Development hub
│   ├── TESTING.md                     # Comprehensive testing guide
│   ├── CODE_QUALITY_EVALUATION_2025-11-04.md # Quality assessment
│   ├── RELEASE_PROCESS.md             # Release procedures
│   ├── PROMETHION_OPTIMIZATIONS.md    # Platform optimizations
│   ├── incremental_kraken2_implementation.md # Kraken2 architecture
│   ├── PHASE_1.1_STATUS.md            # Feature status
│   ├── dynamic_resource_allocation.md # Resource system
│   ├── production_deployment.md       # Deployment guide
│   ├── developer_api.md               # API reference
│   ├── test_organization.md           # Test structure
│   ├── v1_0_roadmap.md                # Roadmap
│   ├── EVALUATION_SUMMARY.md          # Production readiness
│   └── archive/                       # Historical documents
│       ├── sessions/                  # Session notes
│       ├── progress/                  # Progress reports
│       ├── phases/                    # Completed phases
│       └── v1.3.3/                    # v1.3.3 history
│
├── releases/                          # Release documentation
│   ├── CURRENT_VERSION.md             # Version guidance (START HERE)
│   ├── MIGRATION_GUIDE.md             # Upgrade instructions
│   ├── v1.2.0.md                      # v1.2.0 release (stable)
│   ├── v1.3.0.md                      # v1.3.0 release (broken)
│   ├── v1.3.1.md                      # v1.3.1 hotfix
│   └── v1.3.3.md                      # v1.3.3 release (beta)
│
├── validation/                        # Test coverage & validation
│   ├── test_coverage_report.md
│   ├── V1_3_0_TESTING_PLAN.md
│   └── v1.3.0_warning.md
│
├── integration/                       # Integration documentation
│   └── output_api.md                  # Output API reference
│
└── performance/                       # Performance benchmarks
    └── qc_benchmarks.md               # QC tool benchmarks
```

---

## Pipeline Capabilities Summary

**Seven Execution Modes:**

1. Standard FASTQ processing (batch analysis)
2. Pre-demultiplexed barcode directories (automated discovery)
3. Singleplex POD5 basecalling (single sample)
4. Multiplex POD5 with demultiplexing (barcoded samples)
5. Real-time FASTQ monitoring (live sequencing)
6. Real-time POD5 processing (live basecalling + analysis)
7. Dynamic resource optimization (any mode with intelligent allocation)

**Scalable Streaming Architecture (v1.5+):**

- Per-sample parallelism for high-throughput runs (>10 barcodes)
- Append-only batch storage (O(1) per batch instead of O(n))
- Incremental taxid counting without cumulative file re-reads
- Backpressure control with configurable concurrency limits
- 4-5x throughput improvement for multi-barcode runs

**See [Usage Guide](user/usage.md) for complete details and examples.**

---

## Key Concepts

### Input Types

The pipeline supports three mutually exclusive input types:

- **FASTQ samplesheet** - Standard CSV-based input
- **Barcode directories** - Pre-demultiplexed folder structure
- **POD5 files** - Raw signal data with Dorado basecalling

**Details:** [Usage Guide - Input Preparation](user/usage.md#input-preparation)

### Real-time Processing

Monitor directories during sequencing for continuous analysis:

- Intelligent timeout with grace period
- Adaptive batching (dynamic sizing)
- Priority sample routing
- Per-barcode metadata extraction

**Details:** [Real-time Processing Guide](user/realtime_processing.md)

### Platform Profiles

Optimized configurations for different sequencers:

- **minion** - MinION/GridION (1-4 samples, clinical)
- **promethion_8** - PromethION balanced (5-12 samples)
- **promethion** - PromethION high-throughput (12-24+ samples)

**Details:** [Platform Optimizations](user/OPTIMIZATIONS_QUICK_REFERENCE.md)

---

## Related Files

### Root Documentation

- **[Main README](../README.md)** - Pipeline overview and quick start
- **[CLAUDE.md](../CLAUDE.md)** - AI-assisted development guide
- **[CHANGELOG.md](../CHANGELOG.md)** - Complete version history
- **[CITATIONS.md](../CITATIONS.md)** - Citations for tools used
- **[SECURITY.md](../SECURITY.md)** - Security policy

### Contributing

- **[Contributing Guidelines](../.github/CONTRIBUTING.md)** - How to contribute
- **[Pull Request Template](../.github/PULL_REQUEST_TEMPLATE.md)** - PR checklist
- **[Code of Conduct](../.github/CODE_OF_CONDUCT.md)** - Community standards

---

## Documentation Maintenance

**Update Frequency:**

- User docs: Updated with each feature release
- Development docs: Updated as needed
- Release notes: Created for each version
- This index: Updated when structure changes

**Contribution:**
Documentation improvements are welcome! See [Contributing Guidelines](../.github/CONTRIBUTING.md) for details.

**Issues:**
Found documentation issues? [Report them](https://github.com/foi-bioinformatics/nanometanf/issues) with the `documentation` label.

---

**Version:** 1.5.0
**Last Updated:** 2026-02-03
**Maintainer:** foi-bioinformatics team (@andreassjodin)

**This is the main documentation hub. Use the Quick Links above to navigate to specific topics.**
