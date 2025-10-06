# Troubleshooting Guide

Practical solutions for common issues when running nanometanf.

## Quick Diagnostics

```bash
# Check installation
nextflow -version          # Should be >= 23.04.0
java -version             # Should be 11+
docker --version          # If using Docker profile

# Test pipeline
nextflow run foi-bioinformatics/nanometanf -profile test,docker -stub

# Generate trace report
nextflow run ... -with-trace -with-report -with-timeline
```

---

## Installation Issues

### Error: "Nextflow version too old"

**Problem**: Pipeline requires Nextflow >= 23.04.0

**Solution**:
```bash
# Update Nextflow
nextflow self-update

# Or install specific version
curl -s https://get.nextflow.io | bash
./nextflow -version
```

---

### Error: "JAVA_HOME not set"

**Problem**: Java environment not configured (common with Conda)

**Solution**:
```bash
# For Conda users
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH

# Add to ~/.bashrc or ~/.zshrc for permanent fix
echo 'export JAVA_HOME=$CONDA_PREFIX/lib/jvm' >> ~/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc
```

---

## Input/Output Errors

### Error: "Cannot find input file"

**Problem**: File paths in samplesheet don't exist

**Check**:
```bash
# Verify file exists
ls -lh /path/to/file.fastq.gz

# Check samplesheet format
cat samplesheet.csv
# Should be: sample,fastq,barcode
# Sample1,/absolute/path/to/file.fastq.gz,
```

**Solutions**:
- Use absolute paths (not relative)
- Check file permissions (`chmod 644 file.fastq.gz`)
- Verify file isn't empty (`du -h file.fastq.gz`)

---

### Error: "Permission denied" when writing output

**Problem**: No write permission to output directory

**Solution**:
```bash
# Check permissions
ls -ld /path/to/outdir

# Fix permissions
chmod 755 /path/to/outdir

# Or use different directory
nextflow run ... --outdir $HOME/nanometanf_results
```

---

## Dorado Basecalling Issues

### Error: "Dorado not found"

**Problem**: Pipeline can't locate Dorado binary

**Solution**:
```bash
# Option 1: Set dorado_path parameter
nextflow run ... --dorado_path /full/path/to/dorado

# Option 2: Add to PATH
export PATH=/path/to/dorado/bin:$PATH

# Verify
which dorado
dorado --version
```

---

### Error: "Unsupported POD5 version"

**Problem**: POD5 files created with incompatible version

**Solution**:
```bash
# Check POD5 file
python3 << EOF
import pod5
with pod5.Reader("file.pod5") as reader:
    print(f"Version: {reader.file_version}")
EOF

# Update Dorado to latest version
# Download from: https://github.com/nanoporetech/dorado/releases
```

---

### Error: "CUDA out of memory" (GPU)

**Problem**: GPU memory exhausted during basecalling

**Solutions**:
```bash
# Option 1: Reduce batch size
nextflow run ... \
    --use_dorado \
    -c <(echo "process { withName:DORADO_BASECALLER { ext.args = '--batchsize 128' } }")

# Option 2: Use CPU mode
nextflow run ... --use_dorado  # Auto-detects and uses CPU if no GPU

# Option 3: Process POD5 files in smaller chunks
split -l 1000 --numeric-suffixes input.pod5 chunk_
```

---

## Memory/Resource Issues

### Error: "java.lang.OutOfMemoryError"

**Problem**: Nextflow JVM out of memory

**Solution**:
```bash
# Increase Nextflow memory
export NXF_OPTS='-Xms2g -Xmx8g'

# Then run pipeline
nextflow run ...
```

---

### Error: "Process exceeded memory limit"

**Problem**: Individual process needs more memory

**Solutions**:
```bash
# Option 1: Use resource-conservative profile
nextflow run ... --optimization_profile resource_conservative

# Option 2: Increase memory for specific process
nextflow run ... \
    -c <(echo "process { withName:KRAKEN2_KRAKEN2 { memory = '64.GB' } }")

# Option 3: Enable dynamic resource allocation
nextflow run ... --enable_dynamic_resources
```

---

### Error: "No space left on device"

**Problem**: Disk full

**Check**:
```bash
# Check disk space
df -h

# Find large files in work directory
du -sh work/* | sort -h | tail -10
```

**Solutions**:
```bash
# Option 1: Clean work directory
nextflow clean -f -k

# Option 2: Use different work directory
nextflow run ... -w /path/to/large/disk/work

# Option 3: Enable automatic cleanup
nextflow run ... -with-dag -resume
# After successful run:
nextflow clean -after <run-name> -f
```

---

## Taxonomy Classification Issues

### Error: "Kraken2 database not found"

**Problem**: Database path incorrect or database not downloaded

**Solution**:
```bash
# Download standard database
wget https://genome-idx.s3.amazonaws.com/kraken/k2_standard_20240904.tar.gz
mkdir kraken2_db
tar xzf k2_standard_20240904.tar.gz -C kraken2_db/

# Verify database
ls kraken2_db/
# Should contain: hash.k2d, opts.k2d, taxo.k2d

# Run with correct path
nextflow run ... --kraken2_db $(pwd)/kraken2_db/
```

---

### Error: "Kraken2 classification very slow"

**Problem**: Database too large for available memory

**Solutions**:
```bash
# Option 1: Use smaller database
# Download MiniKraken: https://ccb.jhu.edu/software/kraken/

# Option 2: Enable memory mapping
nextflow run ... \
    --kraken2_use_optimizations \
    --kraken2_memory_mapping

# Option 3: Reduce batch size
nextflow run ... --kraken2_batch_size 5
```

---

## Container/Environment Issues

### Error: "Docker daemon not running"

**Problem**: Docker service not started

**Solution**:
```bash
# macOS
open -a Docker

# Linux
sudo systemctl start docker

# Verify
docker ps
```

---

### Error: "Container permission denied"

**Problem**: User not in docker group (Linux)

**Solution**:
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in, or:
newgrp docker

# Verify
docker run hello-world
```

---

### Error: "Singularity container not found"

**Problem**: Container image URL incorrect or unreachable

**Solution**:
```bash
# Test singularity
singularity --version

# Pull container manually
singularity pull docker://biocontainers/fastqc:0.12.1--hdfd78af_0

# Use Docker profile instead
nextflow run ... -profile docker
```

---

## Real-time Monitoring Issues

### Error: "watchPath not finding new files"

**Problem**: Files not matching pattern or permissions issue

**Debug**:
```bash
# Test file pattern
find /nanopore/output -name "*.fastq.gz" -type f

# Check directory is being watched
ls -la /nanopore/output

# Verify pattern matches
nextflow run ... \
    --realtime_mode \
    --nanopore_output_dir /nanopore/output \
    --file_pattern "**/*.fastq.gz"  # Try different patterns
```

**Solutions**:
- Use absolute path for `nanopore_output_dir`
- Ensure sufficient permissions on directory
- Check file isn't being written (wait for complete files)

---

## Pipeline Execution Issues

### Error: "Process terminated with an error exit status (137)"

**Problem**: Process killed by OS (usually out of memory)

**Solution**:
```bash
# Check system memory
free -h

# Enable memory monitoring
nextflow run ... -with-trace

# Check trace.txt for memory usage
grep -A 5 "exit: 137" trace.txt

# Increase memory or use lighter profile
nextflow run ... --optimization_profile resource_conservative
```

---

### Error: "Task terminated for an unknown reason"

**Problem**: Various causes - check detailed logs

**Debug**:
```bash
# Find work directory for failed task
nextflow log <run-name> -f "workdir,exit,name"

# Check detailed logs
cd <work-directory>
cat .command.log
cat .command.err

# Check if command succeeded
cat .exitcode
```

---

## Performance Issues

### Pipeline very slow

**Check**:
```bash
# Generate execution report
nextflow run ... -with-report report.html -with-timeline timeline.html

# Open reports
open report.html
open timeline.html
```

**Common causes & solutions**:

1. **I/O bottleneck** - Use local disk for work directory
2. **Too many processes** - Reduce `process.maxForks`
3. **Network latency** - Download databases locally
4. **Inefficient resource allocation** - Enable dynamic resources

```bash
nextflow run ... \
    --enable_dynamic_resources \
    --optimization_profile high_throughput \
    -w /local/fast/disk/work
```

---

### Resume not working

**Problem**: `-resume` flag not resuming cached tasks

**Check**:
```bash
# List cached runs
nextflow log

# Check specific run
nextflow log <run-name>
```

**Solutions**:
```bash
# Option 1: Use explicit run name
nextflow run ... -resume <run-name>

# Option 2: Clean and restart
nextflow clean -f
nextflow run ...

# Option 3: Force resume with specific directory
nextflow run ... -resume -w /path/to/work
```

---

## Testing & Validation

### Tests failing

**Run diagnostic tests**:
```bash
# Quick validation
nextflow run ... -profile test,docker -stub

# Full test suite
export JAVA_HOME=$CONDA_PREFIX/lib/jvm
export PATH=$JAVA_HOME/bin:$PATH
nf-test test --verbose

# Specific test
nf-test test tests/parameter_validation.nf.test
```

---

## Getting Help

### Collect diagnostic information

```bash
# System info
uname -a
nextflow -version
java -version
docker --version || singularity --version

# Generate full diagnostic report
nextflow run ... \
    -with-report report.html \
    -with-trace trace.txt \
    -with-timeline timeline.html \
    -with-dag flowchart.html

# Check logs
cat .nextflow.log
```

### Where to get help

1. **Check documentation**: [Usage Guide](usage.md), [README](../../README.md)
2. **Search issues**: https://github.com/foi-bioinformatics/nanometanf/issues
3. **Create issue**: Include diagnostic info above
4. **Community**: nf-core Slack #nanometanf

### Issue template

When creating an issue, include:

```
**Environment**:
- Nextflow version:
- Profile: (docker/singularity/conda)
- OS: (macOS/Linux/Windows)

**Command**:
```bash
nextflow run ...
```

**Error message**:
```
[paste error]
```

**Logs**:
- Attach .nextflow.log
- Attach trace.txt
- Attach .command.log from failed task
```

---

## Common Patterns & Solutions Matrix

| Error Pattern | Likely Cause | Quick Fix |
|--------------|--------------|-----------|
| "Permission denied" | File/directory permissions | `chmod` or use different location |
| "Out of memory" | Insufficient RAM | Reduce batch size or use conservative profile |
| "No space left" | Disk full | Clean work directory or use larger disk |
| "Command not found" | Missing dependency | Check PATH or specify full path |
| "Exit status 137" | OOM killer | Increase memory limits |
| "Exit status 139" | Segmentation fault | Update software or report bug |
| "Connection refused" | Network/firewall | Check connectivity or download locally |
| "File not found" | Wrong path | Use absolute paths |

---

For additional help, see:
- [Quick Start Guide](quickstart.md)
- [Performance Tuning](performance_tuning.md)
- [Best Practices](best_practices.md)
- [Developer Documentation](../development/)
