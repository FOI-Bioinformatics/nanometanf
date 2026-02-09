/*
 * This file holds several functions used within the nf-core pipeline template.
 */

import nextflow.Nextflow
import groovy.text.SimpleTemplateEngine

class WorkflowNanometanf {

    //
    // Validate pipeline parameters before execution
    //
    public static void initialise(params, log) {
        // Validate input modes
        validateInputModes(params, log)

        // Validate real-time specific parameters
        if (params.realtime_mode) {
            validateRealtimeTimeouts(params, log)
            validateBatchingParameters(params, log)
        }

        // Validate QC tool selection
        validateQcTool(params, log)

        // Validate Kraken2 database if classification enabled
        if (!params.skip_kraken2) {
            validateKraken2Database(params, log)
        }

        log.info "Parameter validation complete ✓"
    }

    //
    // Issue 1.1: Validate mutually exclusive input modes
    //
    private static void validateInputModes(params, log) {
        def input_modes = [
            'samplesheet': params.input,
            'barcode_discovery': params.barcode_input_dir,
            'static_pod5': (!params.realtime_mode && params.use_dorado && params.pod5_input_dir),
            'realtime_fastq': (params.realtime_mode && !params.use_dorado && params.nanopore_output_dir),
            'realtime_pod5': (params.realtime_mode && params.use_dorado && params.pod5_input_dir)
        ]

        def active_modes = input_modes.findAll { k, v -> v }

        if (active_modes.size() == 0) {
            Nextflow.error("""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ ERROR: No input mode specified
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

You must provide one of the following input methods:

  1. Samplesheet mode (standard):
     --input samplesheet.csv

  2. Barcode discovery mode (pre-demultiplexed directories):
     --barcode_input_dir /path/to/barcodes/

  3. Static POD5 basecalling:
     --pod5_input_dir /path/to/pod5/ --use_dorado

  4. Real-time FASTQ monitoring:
     --realtime_mode --nanopore_output_dir /path/to/fastq/

  5. Real-time POD5 monitoring + basecalling:
     --realtime_mode --use_dorado --pod5_input_dir /path/to/pod5/

For more details, see: https://github.com/foi-bioinformatics/nanometanf
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
        }

        if (active_modes.size() > 1) {
            def mode_names = active_modes.keySet().join(', ')
            Nextflow.error("""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ ERROR: Multiple input modes detected
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Conflicting input modes: ${mode_names}

Only ONE input mode can be used per run. Please specify only one of:
  --input, --barcode_input_dir, --pod5_input_dir, or --nanopore_output_dir

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
        }

        // Validate mode-specific required parameters
        if (params.realtime_mode && params.use_dorado && !params.pod5_input_dir) {
            Nextflow.error("""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ ERROR: Real-time POD5 mode requires --pod5_input_dir
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

When using real-time POD5 monitoring with Dorado basecalling:
  --realtime_mode --use_dorado --pod5_input_dir /path/to/pod5/

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
        }

        if (params.realtime_mode && !params.use_dorado && !params.nanopore_output_dir) {
            Nextflow.error("""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ ERROR: Real-time FASTQ mode requires --nanopore_output_dir
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

When using real-time FASTQ monitoring:
  --realtime_mode --nanopore_output_dir /path/to/fastq/

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
        }

        if (params.use_dorado && !params.pod5_input_dir) {
            Nextflow.error("""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ ERROR: Dorado basecalling requires --pod5_input_dir
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

When using Dorado basecalling:
  --use_dorado --pod5_input_dir /path/to/pod5/

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
        }

        log.info "✓ Input mode validation passed: ${active_modes.keySet().join()}"
    }

    //
    // Issue 1.2: Validate real-time timeout parameters
    //
    private static void validateRealtimeTimeouts(params, log) {
        if (params.realtime_timeout_minutes) {
            if (params.realtime_timeout_minutes < 1) {
                Nextflow.error("""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ ERROR: Invalid --realtime_timeout_minutes
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Value must be >= 1 minute, got: ${params.realtime_timeout_minutes}

Recommended values:
  - MinION single sample: 10-15 minutes
  - PromethION high throughput: 30-60 minutes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
            }
        }

        if (params.realtime_processing_grace_period < 0) {
            Nextflow.error("""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ ERROR: Invalid --realtime_processing_grace_period
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Value must be >= 0 minutes, got: ${params.realtime_processing_grace_period}

Default: 5 minutes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
        }

        if (params.realtime_timeout_minutes && params.realtime_processing_grace_period > params.realtime_timeout_minutes) {
            log.warn """
⚠️  WARNING: Grace period exceeds detection timeout
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Grace period: ${params.realtime_processing_grace_period} minutes
Detection timeout: ${params.realtime_timeout_minutes} minutes
Total maximum wait: ${params.realtime_timeout_minutes + params.realtime_processing_grace_period} minutes

Consider adjusting for more reasonable total timeout.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
        }

        log.info "✓ Real-time timeout validation passed"
    }

    //
    // Issue 1.3: Validate batching parameters
    //
    private static void validateBatchingParameters(params, log) {
        // Validate batch sizes are positive
        if (params.min_batch_size < 1) {
            Nextflow.error("❌ ERROR: --min_batch_size must be >= 1, got: ${params.min_batch_size}")
        }

        if (params.max_batch_size < 1) {
            Nextflow.error("❌ ERROR: --max_batch_size must be >= 1, got: ${params.max_batch_size}")
        }

        if (params.batch_size < 1) {
            Nextflow.error("❌ ERROR: --batch_size must be >= 1, got: ${params.batch_size}")
        }

        // Validate min <= max
        if (params.min_batch_size > params.max_batch_size) {
            Nextflow.error("""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ ERROR: Invalid batch size range
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

--min_batch_size (${params.min_batch_size}) cannot exceed --max_batch_size (${params.max_batch_size})

Example valid configuration:
  --min_batch_size 1 --max_batch_size 50 --batch_size 10

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
        }

        // Warn if batch_size is outside adaptive range
        if (params.adaptive_batching) {
            if (params.batch_size < params.min_batch_size || params.batch_size > params.max_batch_size) {
                log.warn """
⚠️  WARNING: batch_size outside adaptive range
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

--batch_size (${params.batch_size}) is outside adaptive range [${params.min_batch_size}, ${params.max_batch_size}]

It will be clamped on first adjustment. Consider setting batch_size within range.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""
            }
        }

        // Validate batch_size_factor
        if (params.batch_size_factor <= 0) {
            Nextflow.error("❌ ERROR: --batch_size_factor must be > 0, got: ${params.batch_size_factor}")
        }

        log.info "✓ Batching parameter validation passed"
    }

    //
    // Issue 1.4: Validate QC tool selection
    //
    private static void validateQcTool(params, log) {
        def valid_tools = ['chopper', 'fastp', 'filtlong']

        if (!valid_tools.contains(params.qc_tool)) {
            Nextflow.error("""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ ERROR: Invalid QC tool
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Invalid --qc_tool: '${params.qc_tool}'

Valid options:
  • chopper  - Rust-based nanopore-native filtering (7x faster, default)
  • fastp    - General-purpose with rich HTML reporting
  • filtlong - Nanopore-optimized length-weighted filtering

Example:
  nextflow run . --input samples.csv --qc_tool chopper

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
        }

        log.info "✓ QC tool validation passed: ${params.qc_tool}"
    }

    //
    // Issue 1.5: Validate Kraken2 database
    //
    private static void validateKraken2Database(params, log) {
        if (!params.kraken2_db) {
            Nextflow.error("""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ERROR: Kraken2 database path required
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Kraken2 taxonomic classification is enabled but --kraken2_db is not specified.

Options:
  1. Provide database path:
     --kraken2_db /path/to/kraken2_standard

  2. Provide a tar.gz archive (local or URL):
     --kraken2_db /path/to/kraken2.tar.gz
     --kraken2_db https://example.com/kraken2.tar.gz

  3. Disable classification:
     --skip_kraken2

For database downloads, see:
https://benlangmead.github.io/aws-indexes/k2

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
        }

        def db_path = params.kraken2_db.toString()

        // Check if this is an archive (tar.gz or tgz) - will be extracted at runtime
        def is_archive = db_path.endsWith('.tar.gz') || db_path.endsWith('.tgz')

        // Check if this is a URL - cannot validate at parse time
        def is_url = db_path.startsWith('http://') || db_path.startsWith('https://') || db_path.startsWith('s3://') || db_path.startsWith('gs://')

        if (is_url) {
            // Skip validation for URLs - will be validated at runtime when downloaded
            log.info "Kraken2 database validation skipped (remote URL will be fetched at runtime): ${db_path}"
            return
        }

        if (is_archive) {
            // Validate archive file exists
            def archive_file = new File(db_path)
            if (!archive_file.exists()) {
                Nextflow.error("""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ERROR: Kraken2 database archive does not exist
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Path: ${db_path}

Verify the archive path is correct and accessible.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
            }
            log.info "Kraken2 database validation passed (archive will be extracted at runtime): ${db_path}"
            return
        }

        // Validate database directory exists
        def db_dir = new File(db_path)
        if (!db_dir.exists()) {
            Nextflow.error("""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ERROR: Kraken2 database directory does not exist
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Path: ${db_path}

Verify the path is correct and accessible.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
        }

        if (!db_dir.isDirectory()) {
            Nextflow.error("""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ERROR: Kraken2 database path is not a directory
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Path: ${db_path}

Provide a directory containing Kraken2 database files.
Alternatively, provide a tar.gz archive that will be extracted automatically.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
        }

        // Check for required Kraken2 database files
        def required_files = ['hash.k2d', 'opts.k2d', 'taxo.k2d']
        def missing_files = required_files.findAll { !new File(db_dir, it).exists() }

        if (missing_files.size() > 0) {
            Nextflow.error("""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ERROR: Incomplete Kraken2 database
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Database directory: ${db_path}

Missing required files:
  ${missing_files.collect { "- ${it}" }.join('\n  ')}

A valid Kraken2 database must contain:
  - hash.k2d - Hash table
  - opts.k2d - Database options
  - taxo.k2d - Taxonomy mappings

The database may be corrupted or incomplete. Re-download from:
https://benlangmead.github.io/aws-indexes/k2

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
""")
        }

        log.info "Kraken2 database validation passed: ${db_path}"
    }
}
