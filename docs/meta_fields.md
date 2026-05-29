# Pipeline Meta Fields

This document describes the custom metadata fields carried in the `meta` map
alongside channel items throughout the nanometanf pipeline. Nextflow nf-core
pipelines conventionally pass a `[meta, reads]` tuple where `meta` is a Groovy
map. The fields below extend the standard nf-core `meta.id` and
`meta.single_end` with pipeline-specific attributes used for real-time
streaming, batching, and barcode tracking.

## Standard Fields

### `id`

| Property | Value                                                      |
| -------- | ---------------------------------------------------------- |
| Type     | `String`                                                   |
| Set by   | samplesheet parser, `realtime_monitoring`, `input_scanner` |
| Used by  | all processes (tag, prefix)                                |

The sample identifier. In barcode mode this is typically `barcode01`,
`barcode02`, etc. In single-sample mode it equals `params.sample_name` or is
derived from the input filename.

### `single_end`

| Property | Value                                                                                                                                                |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Type     | `Boolean`                                                                                                                                            |
| Set by   | samplesheet parser, `realtime_monitoring`, `input_scanner`, `demultiplexing`                                                                         |
| Used by  | `FASTP`, `FASTP_STREAMING`, `KRAKEN2_KRAKEN2`, `KRAKEN2_OPTIMIZED`, `KRAKEN2_INCREMENTAL_CLASSIFIER`, `FILTLONG`, `utils_nfcore_nanometanf_pipeline` |

Indicates whether the reads are single-end. For Oxford Nanopore data this is
always `true`. Several modules branch on this field to choose between
single-end and paired-end command-line flags (e.g., `--paired` in Kraken2).

## Pipeline-Specific Fields

### `barcode`

| Property | Value                                                       |
| -------- | ----------------------------------------------------------- |
| Type     | `String`                                                    |
| Set by   | `realtime_monitoring`, `input_scanner`, `demultiplexing`    |
| Used by  | downstream grouping (e.g., `groupTuple`), dashboard display |

The barcode identifier (e.g., `barcode01`, `BC01`). Set when the sample ID
matches a barcode naming pattern or when Dorado demultiplexing assigns reads
to a barcode bin. Used for per-barcode result grouping and display in the
Nanometa Live dashboard.

### `batch_id`

| Property | Value                                                                                                                                                            |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Type     | `Integer` or `String`                                                                                                                                            |
| Set by   | `taxonomic_classification` (per-sample counter), `realtime_monitoring` (timestamp-based)                                                                         |
| Used by  | `KRAKEN2_INCREMENTAL_CLASSIFIER` (tag, prefix, JSON metadata), `qc_analysis` (NanoPlot interval gating), `taxonomic_classification` (progressive report writing) |

Identifies the batch within a sample's processing sequence. In the
taxonomic classification subworkflow, a synchronized per-sample counter
assigns integer batch IDs (0, 1, 2, ...) as files arrive. The incremental
Kraken2 classifier uses this for process tagging
(`${meta.id}_batch${meta.batch_id}`) and output file naming.

In the realtime monitoring subworkflow, batch IDs follow a timestamp format
(`batch_<epoch_ms>`) and are stored in the batch metadata map rather than
directly in the per-file meta.

### `is_final_batch`

| Property | Value                                                                                          |
| -------- | ---------------------------------------------------------------------------------------------- |
| Type     | `Boolean`                                                                                      |
| Set by   | real-time session completion signal                                                            |
| Used by  | `qc_analysis` (NanoPlot final run), `taxonomic_classification` (force cumulative report write) |

A flag set to `true` on the last batch emitted when a real-time monitoring
session ends. Both the QC analysis and taxonomic classification subworkflows
check this field to ensure that final outputs (NanoPlot reports, cumulative
Kraken2 reports) are always written regardless of interval-based gating
settings.

### `batch_count`

| Property | Value                                                 |
| -------- | ----------------------------------------------------- |
| Type     | `Integer`                                             |
| Set by   | `taxonomic_classification` (groupTuple result sizing) |
| Used by  | downstream aggregation                                |

The total number of batches collected for a sample after grouping. Set during
the `groupTuple` aggregation step in the taxonomic classification subworkflow
when gathering all batch outputs for a sample into a single tuple.

### `batch_time`

| Property | Value                                    |
| -------- | ---------------------------------------- |
| Type     | `String` (format: `yyyy-MM-dd_HH-mm-ss`) |
| Set by   | `realtime_monitoring`                    |
| Used by  | trace logging, output file naming        |

Timestamp recorded when the batch was assembled. Provides temporal context for
monitoring and debugging real-time processing sequences.
