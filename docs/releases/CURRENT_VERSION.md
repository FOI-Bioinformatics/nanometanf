# Current Version Status

**Last Updated:** 2025-11-04

---

## Recommended Version

### ✅ v1.2.0 (Production Ready)

**Release Date:** 2025-10-16
**Status:** Stable
**nf-core Compliance:** 100% (707/707 lint tests passing)

**Use this version for:**
- Production deployments
- Critical analyses
- Publication-quality data

**Documentation:** [v1.2.0 Release Notes](v1.2.0.md)

---

## Version Matrix

| Version | Status | Release Date | Recommendation |
|---------|--------|--------------|----------------|
| **v1.2.0** | ✅ Stable | 2025-10-16 | **Use for production** |
| **v1.3.0** | 🚫 Broken | 2025-10-19 | **Do not use** (parse error) |
| **v1.3.1** | ⚠️ Hotfix | 2025-10-20 | Testing only |
| **v1.3.3** | ⚠️ Beta | 2025-10-25 | Advanced features, testing recommended |
| **1.3.1dev** | 🔧 Development | Ongoing | Developers only |

---

## Critical Issue: v1.3.0 is Broken

### ⚠️ DO NOT USE v1.3.0

**Problem:** Missing Kraken2 incremental classifier modules cause parse-time error
**Impact:** Pipeline fails immediately on ANY invocation
**Workaround:** Use v1.2.0 until v1.3.1 or later

**Error message:**
```
ERROR ~ No such variable: KRAKEN2_INCREMENTAL_CLASSIFIER
```

**Details:** See [v1.3.0 Warning](../validation/v1.3.0_warning.md)

---

## Version Selection Guide

### For Production Use

**Use v1.2.0** if you need:
- Proven stability
- Published pipelines
- Regulatory compliance
- Maximum reliability

### For Testing New Features

**Use v1.3.3** if you want:
- Real-time monitoring enhancements (2-stage timeout, grace period)
- Adaptive batching with min/max constraints
- Priority sample routing
- Per-barcode metadata extraction
- PromethION optimizations (platform profiles, incremental Kraken2)

**Important:** Test v1.3.3 thoroughly before production use

### For Development

**Use 1.3.1dev (main/dev branch)** if you're:
- Contributing to the pipeline
- Testing unreleased features
- Developing new modules
- Following bleeding-edge updates

---

## Key Features by Version

### v1.2.0 (Current Stable)

**Highlights:**
- ✅ Chopper as default QC tool (7x faster than NanoFilt)
- ✅ Multi-tool QC support (chopper, fastp, filtlong)
- ✅ 100% nf-core compliance
- ✅ Dorado 1.1.1 compatibility
- ✅ Clean semantic versioning
- ✅ RO-Crate metadata for FAIR principles

**Documentation:** [v1.2.0 Release Notes](v1.2.0.md)

### v1.3.3 (Latest Beta)

**New features:**
- Advanced real-time monitoring (2-stage timeout with grace period)
- Adaptive batching (dynamic adjustment between min/max)
- Priority routing for urgent samples
- Per-barcode metadata extraction from filenames
- PromethION platform profiles (minion, promethion_8, promethion)
- Performance optimizations (18x throughput improvement possible)

**Status:** Beta - test before production
**Documentation:** [v1.3.3 Release Notes](v1.3.3.md)

---

## Migration Paths

### From v1.0.x → v1.2.0

**Breaking Changes:** None
**Action Required:** None (fully backward compatible)
**Recommended:** Update to benefit from Chopper performance improvements

**Details:** [Migration Guide](MIGRATION_GUIDE.md#from-v10x-to-v120)

### From v1.2.0 → v1.3.3

**Breaking Changes:** None
**Action Required:** Test with your data before production
**Recommended:** Evaluate new real-time features if using `--realtime_mode`

**Details:** [Migration Guide](MIGRATION_GUIDE.md#from-v120-to-v133)

### From v1.3.0 → v1.3.1+

**Breaking Changes:** None
**Action Required:** **Immediate upgrade required** (v1.3.0 is broken)
**Recommended:** Use v1.2.0 (stable) or v1.3.3 (latest)

---

## Installation

### Install Specific Version

```bash
# Stable version (recommended)
nextflow run foi-bioinformatics/nanometanf -r v1.2.0 \
  --input samplesheet.csv \
  --outdir results \
  -profile docker

# Latest version (testing)
nextflow run foi-bioinformatics/nanometanf -r v1.3.3 \
  --input samplesheet.csv \
  --outdir results \
  -profile docker

# Development version
nextflow run foi-bioinformatics/nanometanf -r dev \
  --input samplesheet.csv \
  --outdir results \
  -profile docker
```

### Check Installed Version

```bash
# Within pipeline directory
grep "version" nextflow.config | head -1

# From git tag
git describe --tags
```

---

## Version Support Policy

### Long-term Support (LTS)

**v1.2.0** is the current LTS release:
- Bug fixes: Until v1.4.0 release
- Security patches: Until v1.6.0 release
- Critical issues: Immediate hotfixes

### Regular Releases

- **Minor versions** (1.X.0): New features, non-breaking changes
- **Patch versions** (1.2.X): Bug fixes, documentation updates
- **Development versions** (X.Y.Zdev): Unstable, frequent changes

### Deprecation Policy

- Features deprecated with 2 minor version warning
- Example: Deprecated in v1.2.0 → Removed in v1.4.0

---

## Getting Help

### Version-Specific Issues

1. **Check release notes** for known issues
2. **Search existing issues:** https://github.com/foi-bioinformatics/nanometanf/issues
3. **Report new issues:** Include version information

### Version Information Template

When reporting issues, include:

```
Pipeline version: v1.2.0
Nextflow version: 24.10.5
Platform: Linux/macOS/WSL
Profile: docker/singularity/conda
Command: [your command]
Error: [error message]
```

---

## Release History

| Version | Date | Type | Status |
|---------|------|------|--------|
| v1.3.3 | 2025-10-25 | Minor | Beta |
| v1.3.1 | 2025-10-20 | Patch | Hotfix |
| v1.3.0 | 2025-10-19 | Minor | **Broken** |
| **v1.2.0** | **2025-10-16** | **Minor** | **✅ LTS** |
| v1.1.0 | 2025-10-10 | Minor | Superseded |
| v1.0.0 | 2025-09-15 | Major | Superseded |

See [Release Notes Directory](./) for complete version history.

---

## Quick Links

- **[Release Notes](./)**
- **[Migration Guide](MIGRATION_GUIDE.md)**
- **[Known Issues](../validation/v1.3.0_warning.md)**
- **[Changelog](../../CHANGELOG.md)**
- **[GitHub Releases](https://github.com/foi-bioinformatics/nanometanf/releases)**

---

**Maintained By:** foi-bioinformatics team
**Update Frequency:** On each release
**Source of Truth:** This file is the authoritative version reference
