# Development Documentation

This directory contains comprehensive documentation for developers working on the nanometanf pipeline.

## Quick Links

### Testing & Quality Assurance
- [TESTING.md](TESTING.md) - Comprehensive testing guide with nf-test (includes quick reference)
- [CODE_QUALITY_EVALUATION_2025-11-04.md](archive/sessions/CODE_QUALITY_EVALUATION_2025-11-04.md) - Latest code quality assessment

### Architecture & Implementation
- [PROMETHION_OPTIMIZATIONS.md](PROMETHION_OPTIMIZATIONS.md) - Platform-specific performance optimizations
- [incremental_kraken2_implementation.md](incremental_kraken2_implementation.md) - Kraken2 incremental classification
- [PHASE_1.1_STATUS.md](PHASE_1.1_STATUS.md) - Incremental Kraken2 feature status
- [dynamic_resource_allocation.md](dynamic_resource_allocation.md) - Dynamic resource allocation system

### Deployment & Operations
- [production_deployment.md](production_deployment.md) - Production deployment guide
- [developer_api.md](developer_api.md) - Developer API reference

### Project Organization
- [test_organization.md](test_organization.md) - Test suite organization
- [v1_0_roadmap.md](v1_0_roadmap.md) - Version 1.0 roadmap

## Documentation Structure

```
development/
├── README.md                          # This file
├── TESTING.md                         # Comprehensive testing guide
├── RELEASE_PROCESS.md                 # Release workflow for maintainers
├── PROMETHION_OPTIMIZATIONS.md        # Performance optimizations
├── incremental_kraken2_implementation.md  # Kraken2 architecture
├── PHASE_1.1_STATUS.md                # Feature status
├── dynamic_resource_allocation.md     # Resource system
├── production_deployment.md           # Deployment guide
├── developer_api.md                   # API reference
├── test_organization.md               # Test structure
├── v1_0_roadmap.md                    # Roadmap
├── EVALUATION_SUMMARY.md              # Production readiness assessment
└── archive/                           # Historical documents
    ├── sessions/                      # Development session notes (incl. code quality)
    ├── progress/                      # Historical progress reports
    ├── phases/                        # Completed development phases
    └── v1.3.3/                        # v1.3.3 development history
```

## Getting Started with Development

### Prerequisites

1. **Nextflow** (>= 25.10.0)
2. **nf-test** (>= 0.9.0)
3. **Java** (>= 11)
4. **nf-core tools**

```bash
# Install nf-core tools
pip install nf-core

# Verify installation
nextflow -version
nf-test version
nf-core --version
```

### Development Workflow

1. **Read TESTING.md** for test development guidelines
2. **Follow nf-core standards** (see main README and CLAUDE.md)
3. **Run tests locally** before committing:
   ```bash
   nf-test test --verbose
   nf-core lint
   ```
4. **Document changes** in appropriate markdown files
5. **Update CHANGELOG.md** for user-facing changes

### Code Quality Standards

The pipeline follows nf-core best practices. Key requirements:

- ✅ DSL2 syntax throughout
- ✅ Meta map pattern for sample tracking
- ✅ nf-test coverage for all processes
- ✅ Stub blocks in all processes
- ✅ meta.yml for all modules
- ✅ Version tracking in all processes

See [CODE_QUALITY_EVALUATION_2025-11-04.md](archive/sessions/CODE_QUALITY_EVALUATION_2025-11-04.md) for detailed assessment.

### Documentation Standards

- **User-facing docs** → `docs/user/`
- **Developer docs** → `docs/development/`
- **Release notes** → `docs/releases/`
- **Test coverage** → `docs/validation/`
- **Performance benchmarks** → `docs/performance/`
- **Integration guides** → `docs/integration/`

### Key Development Files

| File | Purpose |
|------|---------|
| `main.nf` | Pipeline entry point |
| `workflows/nanometanf.nf` | Main workflow orchestration |
| `subworkflows/local/` | Custom subworkflows |
| `modules/local/` | Custom modules |
| `nextflow.config` | Pipeline configuration |
| `nextflow_schema.json` | Parameter validation |
| `conf/modules.config` | Module-specific configs |

### Testing Guidelines

```bash
# Run all tests
nf-test test

# Run specific test
nf-test test tests/pipeline_test.nf.test

# Run with tag
nf-test test --tag realtime

# Update snapshots
nf-test test --update-snapshot

# Test with stub mode
nf-test test -profile test,docker -stub-run
```

See [TESTING.md](TESTING.md) for comprehensive testing documentation.

## Contributing

1. **Create feature branch** from `dev`
2. **Implement changes** following nf-core standards
3. **Add tests** for new functionality
4. **Update documentation** as needed
5. **Run linting**: `nf-core lint`
6. **Create pull request** with detailed description

## Architecture Overview

### Input Modes

The pipeline supports 7 execution modes:

1. Standard FASTQ processing
2. Pre-demultiplexed barcode directories
3. Singleplex POD5 basecalling
4. Multiplex POD5 with demultiplexing
5. Real-time FASTQ monitoring
6. Real-time POD5 processing
7. Dynamic resource optimization

See [../user/usage.md](../user/usage.md) for detailed usage instructions.

### Workflow Components

```
Input Detection → Basecalling → QC → Classification → Validation → Reports
     ↓              ↓           ↓       ↓              ↓           ↓
  POD5/FASTQ    Dorado     CHOPPER  Kraken2        BLAST      MultiQC
  Barcodes                 NanoPlot  Taxpasta                   JSON
```

### Real-time Processing

Key features:
- **watchPath monitoring** with timeout handling
- **Adaptive batching** with min/max constraints
- **Priority routing** for urgent samples
- **Intelligent timeout** with grace period
- **Platform-specific optimizations** (MinION, PromethION)

See [PROMETHION_OPTIMIZATIONS.md](PROMETHION_OPTIMIZATIONS.md) for details.

## Troubleshooting Development Issues

### Test Failures

1. Check `.nf-test/tests/<test_id>/meta/nextflow.log`
2. Inspect work directory: `ls -la work/`
3. Run with verbose: `nf-test test --verbose`
4. Check stub mode: `nf-test test -stub-run`

### Lint Failures

```bash
# Run lint with details
nf-core lint --verbose

# Check specific components
nf-core modules lint modules/local/
nf-core subworkflows lint subworkflows/local/
```

### Pipeline Debugging

```bash
# Enable trace
nextflow run . -profile test,docker -with-trace

# Enable report
nextflow run . -profile test,docker -with-report report.html

# Enable timeline
nextflow run . -profile test,docker -with-timeline timeline.html

# Enable DAG
nextflow run . -profile test,docker -with-dag flowchart.png
```

## Resources

- [nf-core guidelines](https://nf-co.re/docs/contributing/guidelines)
- [Nextflow documentation](https://www.nextflow.io/docs/latest/)
- [nf-test documentation](https://www.nf-test.com/)
- [nanometanf main README](../../README.md)
- [nanometanf CLAUDE.md](../../CLAUDE.md) - AI development guide

## Archive

Historical documentation is organized in `archive/`:

- **`sessions/`** - Development session notes
- **`progress/`** - Historical progress reports
- **`phases/`** - Completed development phases
- **`v1.3.3/`** - v1.3.3 development history

These documents are preserved for historical reference but are not actively maintained.

---

**Last Updated:** 2025-11-09
**Maintainer:** Andreas Sjodin (@andreassjodin)
**Version:** 1.4.1dev
