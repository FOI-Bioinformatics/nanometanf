//
// Demultiplexing subworkflow for multiplexed nanopore samples
//
// The pipeline accepts FASTQ input only. Samples are expected to arrive
// pre-demultiplexed as per-barcode directories or as single-sample FASTQ
// inputs. This subworkflow currently performs no additional demultiplexing
// and is retained as a pass-through stage so that downstream processes have
// a stable channel contract and so that in-pipeline demultiplexing can be
// re-introduced here later without further workflow wiring changes.
//

workflow DEMULTIPLEXING {

    take:
    ch_input     // channel: [ val(meta), path(reads) ]

    main:
    ch_versions = Channel.empty()

    // Convert input to channel if needed (for nf-test compatibility with ArrayList inputs)
    def input_channel = ch_input instanceof List ? Channel.fromList(ch_input) : ch_input

    //
    // Pass-through: FASTQ inputs are either already demultiplexed (per-barcode
    // directories) or treated as single-sample inputs. In-pipeline
    // demultiplexing is currently out of scope.
    //
    ch_all_samples = input_channel

    emit:
    samples  = ch_all_samples    // channel: [ val(meta), path(reads) ]
    versions = ch_versions       // channel: [ path(versions.yml) ]
}
