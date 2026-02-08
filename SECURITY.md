# Security Policy

## Supported Versions

We release patches for security vulnerabilities for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 1.2.x   | :white_check_mark: |
| 1.1.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

The foi-bioinformatics/nanometanf team takes security vulnerabilities seriously. We appreciate your efforts to responsibly disclose your findings.

### How to Report

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report security vulnerabilities by emailing:

**andreas.sjodin@foi.se**

You should receive a response within 48 hours. If for some reason you do not, please follow up via email to ensure we received your original message.

### What to Include

Please include the following information in your report:

- Type of vulnerability (e.g., code injection, information disclosure, etc.)
- Full paths of source file(s) related to the manifestation of the vulnerability
- The location of the affected source code (tag/branch/commit or direct URL)
- Any special configuration required to reproduce the issue
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit it

This information will help us triage your report more quickly.

### Response Process

1. **Acknowledgment**: We will acknowledge receipt of your vulnerability report within 48 hours.

2. **Assessment**: We will investigate the issue and determine its severity and impact.

3. **Remediation**: We will work on a fix and prepare a security advisory.

4. **Disclosure**: Once a fix is available, we will:
   - Release a patched version
   - Publish a security advisory on GitHub
   - Credit you for the discovery (unless you prefer to remain anonymous)

### Preferred Languages

We prefer all communications to be in English.

## Security Best Practices for Users

### Pipeline Execution

1. **Run with appropriate permissions**: Avoid running the pipeline with unnecessary elevated privileges (root/sudo).

2. **Container security**: When using Docker/Singularity, ensure containers are from trusted sources.

3. **Input validation**: Validate and sanitize all input files, especially when processing data from untrusted sources.

4. **Network security**: Be cautious when specifying remote URLs for input data or databases.

### Data Protection

1. **Sensitive data**: Do not include credentials, API keys, or other sensitive information in configuration files committed to version control.

2. **Database security**: Ensure Kraken2 and BLAST databases are obtained from trusted sources and verify their integrity.

3. **Output security**: Be aware that pipeline outputs may contain sensitive information. Apply appropriate access controls to output directories.

### Dependency Management

1. **Keep updated**: Regularly update to the latest supported version to receive security patches.

2. **Container updates**: Periodically update container images to include the latest security patches.

3. **Dependency scanning**: Monitor for known vulnerabilities in pipeline dependencies.

## Security-Related Configuration

### Dorado Basecalling

- **Path security**: The `--dorado_path` parameter should only point to trusted Dorado installations.
- **Model verification**: Verify Dorado models are downloaded from official Oxford Nanopore Technologies sources.

### Real-time Monitoring

- **Directory permissions**: Ensure appropriate file system permissions on monitored directories (`--nanopore_output_dir`).
- **Resource limits**: Set `--max_files` to prevent resource exhaustion attacks in real-time mode.

### Database Security

- **Kraken2 databases**: Only use Kraken2 databases from trusted sources. Verify database integrity using checksums when available.
- **BLAST databases**: Ensure BLAST databases are from NCBI or other trusted sources.

## Known Security Considerations

### Experimental Features

- **Dynamic resource allocation** (v1.2.0+): This feature is experimental and should be thoroughly tested in your environment before production use.

### File System Access

- The pipeline requires read access to input files and write access to output directories.
- In real-time mode, the pipeline monitors file system changes which may have security implications in shared environments.

### Code Execution

- Custom scripts in `bin/` directory are executed during pipeline runs. Only add trusted scripts.
- Module and subworkflow definitions can execute arbitrary code. Review carefully before use.

## Security Updates

Security updates will be announced through:

1. GitHub Security Advisories
2. GitHub Releases with security fix tags
3. CHANGELOG.md with security-related entries

Subscribe to the repository to receive notifications about security updates.

## Attribution

This security policy is based on best practices from:

- [GitHub Security Policy Guidelines](https://docs.github.com/en/code-security/getting-started/adding-a-security-policy-to-your-repository)
- [nf-core Security Best Practices](https://nf-co.re/docs/contributing/guidelines)

## Questions

If you have questions about this security policy, please contact andreas.sjodin@foi.se.
