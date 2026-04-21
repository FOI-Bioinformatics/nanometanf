//
// Demultiplexing subworkflow for multiplexed nanopore samples
//
// Dorado-based demultiplexing was removed when POD5/Dorado inputs were dropped.
// Samples are expected to arrive pre-demultiplexed (per-barcode directories) or as
// single-sample FASTQ inputs. Any sample still flagged as needing demultiplexing is
// passed through unchanged so downstream processes can handle or skip it.
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
    // directories) or treated as single-sample inputs. Upstream demultiplexing is
    // out of scope after the POD5/Dorado removal.
    //
    ch_all_samples = input_channel

    emit:
    samples  = ch_all_samples    // channel: [ val(meta), path(reads) ]
    versions = ch_versions       // channel: [ path(versions.yml) ]
}
