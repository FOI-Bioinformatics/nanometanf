/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: ASSEMBLY
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Multi-tool genome assembly for long-read nanopore data

    Supported assemblers:
    - flye: Flye assembler for long and noisy reads (default)
    - miniasm: Miniasm ultra-fast assembler

    Features:
    - Tool-agnostic interface
    - Standardized assembly outputs
    - Easy addition of new assemblers
    - Optimized for nanopore data
----------------------------------------------------------------------------------------
*/

include { FLYE              } from '../../../modules/nf-core/flye/main'
include { MINIMAP2_AVA      } from '../../../modules/local/minimap2_ava/main'
include { MINIASM           } from '../../../modules/nf-core/miniasm/main'
include { CANONICAL_ASSEMBLY_WRITER } from '../../../modules/local/canonical_assembly_writer/main'

workflow ASSEMBLY {

    take:
    ch_reads     // channel: [ val(meta), path(reads) ]

    main:
    ch_versions = Channel.empty()
    ch_assembly = Channel.empty()
    ch_assembly_graph = Channel.empty()
    ch_assembly_info = Channel.empty()

    // Set assembler and validate parameters
    def assembler = params.assembler ?: 'flye'
    def genome_size = params.genome_size ?: '5m'  // Default to 5Mb for bacterial genomes
    def sequencing_mode = params.sequencing_mode ?: '--nano-raw'  // Default nanopore mode

    //
    // BRANCH: Route to appropriate assembler
    //
    if (assembler == 'flye') {
        //
        // MODULE: Run Flye for long-read assembly
        //
        FLYE (
            ch_reads,
            sequencing_mode
        )
        // FLYE emits its version via `topic: versions` (versions_flye); it is
        // collected centrally in the top-level workflow. There is no
        // `FLYE.out.versions` to mix here -- referencing it throws
        // MissingPropertyException and aborts the run.

        // Collect standardized outputs
        ch_assembly = FLYE.out.fasta.ifEmpty([])
        ch_assembly_graph = FLYE.out.gfa.ifEmpty([])
        ch_assembly_info = FLYE.out.txt.ifEmpty([])
    } else if (assembler == 'miniasm') {
        //
        // MODULE: all-vs-all read overlaps (miniasm prerequisite). One
        // input staged once; the reads-as-reference call of the nf-core
        // align module collided on the staged file name.
        //
        MINIMAP2_AVA ( ch_reads )
        ch_versions = ch_versions.mix(MINIMAP2_AVA.out.versions)

        //
        // MODULE: Run Miniasm for ultra-fast assembly
        //
        // A plain join, not remainder: true. With the remainder a key whose
        // overlap step produced no PAF emits [meta, reads, null] into
        // MINIASM's tuple val(meta), path(reads), path(paf), and Nextflow
        // fails staging a null path -- turning a dropped item into a crash.
        // Dropping the pair instead is what the canonical writer's join
        // below already does, for the reason written there.
        ch_miniasm_input = ch_reads
            .join(MINIMAP2_AVA.out.paf)

        MINIASM (
            ch_miniasm_input
        )
        // MINIASM emits its version via `topic: versions`; collected centrally.

        // Collect standardized outputs
        ch_assembly = MINIASM.out.assembly.ifEmpty([])
        ch_assembly_graph = MINIASM.out.gfa.ifEmpty([])
        ch_assembly_info = Channel.empty()  // Miniasm doesn't provide assembly stats
    } else {
        error "Unsupported assembler: ${assembler}. Currently supported: flye, miniasm"
    }

    //
    // MODULE: Convert assembly statistics to canonical JSON format
    // Produces tool-agnostic output for frontend consumption
    //
    ch_canonical_assembly = Channel.empty()
    if (params.write_canonical != false && assembler == 'flye') {
        // Flye provides assembly_info.txt; miniasm does not produce equivalent stats.
        //
        // The two inputs are JOINED on meta, not passed as two independently
        // filtered channels. Nextflow pairs separate queue-channel inputs by
        // emission order, so the nth assembly_info met the nth assembly -- fine
        // only while both channels carry exactly the same samples in the same
        // order. Either filter dropping an entry (a failed assembly absorbed by
        // conf/error_isolation.config, which sets 'ignore' on exit 1/2 for FLYE)
        // shifts every later pair by one, and the writer then describes one
        // sample's contigs with another sample's assembly stats -- silently, since
        // both files exist and parse. The join makes a missing half drop the pair
        // instead of corrupting its neighbours.
        def ch_assembly_paired = ch_assembly_info
            .filter { it instanceof List && it.size() >= 2 && it[1] != null }
            .join(
                ch_assembly.filter { it instanceof List && it.size() >= 2 && it[1] != null },
                by: 0
            )

        CANONICAL_ASSEMBLY_WRITER (
            ch_assembly_paired.map { meta, info, assembly -> [ meta, info ] },
            ch_assembly_paired.map { meta, info, assembly -> [ meta, assembly ] },
            Channel.value(assembler),
            Channel.value("auto")
        )
        ch_canonical_assembly = CANONICAL_ASSEMBLY_WRITER.out.canonical
        ch_versions = ch_versions.mix(CANONICAL_ASSEMBLY_WRITER.out.versions)
    }

    emit:
    canonical_assembly = ch_canonical_assembly // channel: [ val(meta), path(json) ] - Canonical assembly JSON
    assembly         = ch_assembly        // channel: [ val(meta), path(fasta.gz) ] - Main assembly
    assembly_graph   = ch_assembly_graph  // channel: [ val(meta), path(gfa.gz) ] - Assembly graph
    assembly_info    = ch_assembly_info   // channel: [ val(meta), path(txt) ] - Assembly statistics
    assembler_used   = Channel.value(assembler) // channel: val(assembler_name)
    versions         = ch_versions        // channel: [ path(versions.yml) ]
}
