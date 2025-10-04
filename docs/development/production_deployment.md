# nanometanf Production Deployment Guide

**Version:** 1.0.0  
**Date:** September 2024  
**Maintainer:** Andreas Sjödin (andreas.sjodin@foi.se)

## Overview

This guide provides comprehensive instructions for deploying nanometanf in production environments, including high-performance computing clusters, cloud platforms, and dedicated servers.

## Table of Contents

1. [Production Readiness Checklist](#production-readiness-checklist)
2. [Infrastructure Requirements](#infrastructure-requirements)
3. [Deployment Configurations](#deployment-configurations)
4. [Security Considerations](#security-considerations)
5. [Monitoring and Logging](#monitoring-and-logging)
6. [Error Handling and Recovery](#error-handling-and-recovery)
7. [Performance Optimization](#performance-optimization)
8. [Maintenance and Updates](#maintenance-and-updates)

## Production Readiness Checklist

### ✅ Pre-deployment Validation

- [ ] **Environment Setup**
  - [ ] Nextflow ≥ 24.10.5 installed
  - [ ] Java 11+ available
  - [ ] Container engine (Docker/Singularity) configured
  - [ ] Required databases downloaded and validated

- [ ] **Resource Planning**
  - [ ] CPU and memory requirements calculated
  - [ ] Storage capacity planned (input, output, work directories)
  - [ ] Network bandwidth assessed
  - [ ] GPU availability confirmed (for Dorado basecalling)

- [ ] **Configuration Validation**
  - [ ] Production config profile tested
  - [ ] Parameter validation completed
  - [ ] Test run executed successfully
  - [ ] Performance benchmarks established

- [ ] **Security Setup**
  - [ ] Access controls configured
  - [ ] Data encryption enabled
  - [ ] Audit logging activated
  - [ ] Backup procedures established

## Infrastructure Requirements

### Minimum Production Requirements

| Component | Minimum | Recommended | Notes |
|-----------|---------|-------------|--------|
| **CPU** | 16 cores | 32+ cores | Intel/AMD x86_64 |
| **Memory** | 64 GB | 128+ GB | DDR4 recommended |
| **Storage** | 1 TB SSD | 10+ TB NVMe | High-speed I/O critical |
| **Network** | 1 Gbps | 10+ Gbps | For large dataset transfer |
| **GPU** | Optional | NVIDIA V100/A100 | For Dorado basecalling |

### Storage Architecture

```bash
# Recommended directory structure
/production/nanometanf/
├── data/
│   ├── input/           # Raw sequencing data
│   ├── databases/       # Reference databases
│   └── output/          # Analysis results
├── work/                # Nextflow work directory
├── logs/                # Application and system logs
├── config/              # Production configurations
└── backups/             # Data backups
```

### Network Configuration

- **Firewall**: Allow outbound HTTPS (443) for container pulls
- **DNS**: Ensure resolution for container registries
- **Bandwidth**: Plan for concurrent data transfers
- **Latency**: Minimize between compute and storage

## Deployment Configurations

### 1. Production Server Deployment

```bash
# Production deployment command
nextflow run foi-bioinformatics/nanometanf \\
    -profile production \\
    -c /production/nanometanf/config/production.config \\
    --input /production/nanometanf/data/input/samplesheet.csv \\
    --outdir /production/nanometanf/data/output \\
    --enable_error_recovery true \\
    --enable_performance_logging true \\
    --max_cpus 32 \\
    --max_memory '256.GB' \\
    --max_time '48.h' \\
    -work-dir /production/nanometanf/work \\
    -resume
```

### 2. HPC Cluster Deployment

```bash
# SLURM cluster deployment
nextflow run foi-bioinformatics/nanometanf \\
    -profile cluster \\
    -c /shared/nanometanf/config/cluster.config \\
    --input /shared/data/nanometanf/samplesheet.csv \\
    --outdir /shared/results/nanometanf \\
    --optimization_profile high_throughput \\
    --max_cpus 128 \\
    --max_memory '1.TB' \\
    --enable_dynamic_resources true \\
    -work-dir /scratch/$USER/nanometanf_work \\
    -resume
```

### 3. Cloud Deployment (AWS)

```bash
# AWS Batch deployment
nextflow run foi-bioinformatics/nanometanf \\
    -profile cloud \\
    --input s3://your-bucket/input/samplesheet.csv \\
    --outdir s3://your-bucket/results \\
    --enable_spot_instances true \\
    --enable_cost_monitoring true \\
    --optimization_profile balanced \\
    -work-dir s3://your-work-bucket/work \\
    -bucket-dir s3://your-scratch-bucket \\
    -resume
```

## Security Considerations

### Access Control

```bash
# Set appropriate permissions
chmod 750 /production/nanometanf/
chown -R nanometanf:nanometanf /production/nanometanf/

# Create dedicated service account
useradd -r -s /bin/false nanometanf
usermod -aG docker nanometanf  # If using Docker
```

### Data Encryption

```bash
# Enable encryption at rest
# For filesystem level
sudo cryptsetup luksFormat /dev/sdX
sudo cryptsetup luksOpen /dev/sdX nanometanf_data

# For cloud storage
aws s3api put-bucket-encryption \\
    --bucket your-nanometanf-bucket \\
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'
```

### Network Security

```bash
# Configure firewall (UFW example)
sudo ufw allow 22/tcp          # SSH
sudo ufw allow 443/tcp         # HTTPS outbound
sudo ufw enable

# Restrict container registry access
echo '{"registry-mirrors": ["https://your-private-registry.com"]}' | \\
    sudo tee /etc/docker/daemon.json
```

## Monitoring and Logging

### System Monitoring

```bash
# Install monitoring stack
# Prometheus + Grafana setup
docker run -d --name prometheus \\
    -p 9090:9090 \\
    -v /production/nanometanf/config/prometheus.yml:/etc/prometheus/prometheus.yml \\
    prom/prometheus

docker run -d --name grafana \\
    -p 3000:3000 \\
    -v grafana-storage:/var/lib/grafana \\
    grafana/grafana
```

### Application Logging

```bash
# Configure centralized logging
# rsyslog configuration for nanometanf
echo "local0.* /var/log/nanometanf.log" | \\
    sudo tee -a /etc/rsyslog.conf

# Rotate logs
echo "/var/log/nanometanf.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 syslog syslog
}" | sudo tee /etc/logrotate.d/nanometanf
```

### Performance Metrics

Key metrics to monitor:
- **CPU utilization** per process
- **Memory usage** and swap activity
- **Disk I/O** throughput and latency
- **Network I/O** for data transfers
- **Queue depth** for pending jobs
- **Error rates** and recovery success

## Error Handling and Recovery

### Automated Recovery

```bash
# Enhanced error handling configuration
params {
    enable_error_recovery = true
    max_retry_attempts = 3
    retry_exponential_backoff = true
    error_notification_email = "admin@your-domain.com"
    
    // Error-specific recovery strategies
    memory_error_multiplier = 2.0
    disk_error_cleanup = true
    network_error_delay = "5min"
}
```

### Manual Recovery Procedures

1. **Memory Errors**
   ```bash
   # Increase memory allocation
   nextflow run ... --max_memory '512.GB'
   
   # Enable memory optimization
   nextflow run ... --optimization_profile resource_conservative
   ```

2. **Disk Space Issues**
   ```bash
   # Clean work directory
   nextflow clean -f
   
   # Enable compression
   nextflow run ... --compress_intermediate_files true
   ```

3. **Network Failures**
   ```bash
   # Resume from checkpoint
   nextflow run ... -resume
   
   # Use local cache
   nextflow run ... -offline
   ```

### Backup and Disaster Recovery

```bash
# Automated backup script
#!/bin/bash
BACKUP_DIR="/backups/nanometanf/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# Backup critical data
rsync -av /production/nanometanf/data/output/ "$BACKUP_DIR/output/"
rsync -av /production/nanometanf/config/ "$BACKUP_DIR/config/"

# Backup database indexes
tar -czf "$BACKUP_DIR/databases.tar.gz" /production/nanometanf/data/databases/

# Test backup integrity
tar -tzf "$BACKUP_DIR/databases.tar.gz" > /dev/null && echo "Backup verified"
```

## Performance Optimization

### Resource Tuning

```bash
# System-level optimizations
# Increase file descriptor limits
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# Optimize I/O scheduler
echo deadline > /sys/block/sdX/queue/scheduler

# Tune network settings
echo 'net.core.rmem_max = 268435456' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 268435456' >> /etc/sysctl.conf
sysctl -p
```

### Nextflow Optimization

```bash
# Performance-optimized execution
nextflow run foi-bioinformatics/nanometanf \\
    -profile production \\
    --optimization_profile high_throughput \\
    --enable_dynamic_resources true \\
    --resource_safety_factor 0.9 \\
    --max_parallel_jobs 50 \\
    -Xmx8g \\  # Increase Nextflow JVM memory
    -resume
```

### Database Optimization

```bash
# Optimize Kraken2 database for memory mapping
kraken2-build --db /production/databases/kraken2 --clean

# Create RAM disk for temporary operations
sudo mount -t tmpfs -o size=32g tmpfs /tmp/ramdisk
export TMPDIR=/tmp/ramdisk
```

## Maintenance and Updates

### Regular Maintenance Tasks

1. **Weekly**
   - Monitor disk space usage
   - Review error logs
   - Check system performance metrics
   - Validate backup integrity

2. **Monthly**
   - Update container images
   - Review and optimize configurations
   - Analyze performance trends
   - Update documentation

3. **Quarterly**
   - Update Nextflow and dependencies
   - Review security configurations
   - Conduct disaster recovery tests
   - Update reference databases

### Update Procedures

```bash
# Update nanometanf pipeline
nextflow pull foi-bioinformatics/nanometanf

# Update container images
nextflow run foi-bioinformatics/nanometanf \\
    --help \\  # This will pull latest containers

# Update databases
# Kraken2 database update
kraken2-build --download-taxonomy --db /production/databases/kraken2
kraken2-build --download-library bacteria --db /production/databases/kraken2
kraken2-build --build --db /production/databases/kraken2
```

### Version Control

```bash
# Track pipeline versions
echo "nanometanf_version: $(nextflow info foi-bioinformatics/nanometanf | grep revision)" \\
    >> /production/nanometanf/logs/version_history.yaml

# Configuration versioning
git add /production/nanometanf/config/
git commit -m "Production config update $(date)"
git tag "production-$(date +%Y%m%d)"
```

## Troubleshooting

### Common Issues and Solutions

| Issue | Symptoms | Solution |
|-------|----------|----------|
| **Out of Memory** | Process killed, exit code 137 | Increase memory allocation, enable swap |
| **Disk Full** | Cannot write files, exit code 1 | Clean work directory, increase storage |
| **Permission Denied** | Exit code 126 | Fix file permissions, check SELinux |
| **Container Pull Failed** | Network errors | Check firewall, use cached images |
| **Database Corruption** | Segmentation faults | Rebuild databases, check disk integrity |

### Support and Contact

- **Documentation**: https://github.com/foi-bioinformatics/nanometanf/docs
- **Issues**: https://github.com/foi-bioinformatics/nanometanf/issues
- **Contact**: andreas.sjodin@foi.se
- **Emergency**: Create GitHub issue with 'urgent' label

---

**Note**: This document should be reviewed and updated regularly to reflect current best practices and infrastructure changes.