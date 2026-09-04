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
include { ASSEMBLY_DEPTH_GATE       } from '../../../modules/local/assembly_depth_gate/main'
include { ASSEMBLY_READ_POOL        } from '../../../modules/local/assembly_read_pool/main'

workflow ASSEMBLY {

    take:
    ch_reads      // channel: [ val(meta), path(reads) ] - whole-sample reads
    ch_targeted   // channel: [ val(meta), path(reads), path(reference) ] - per-organism reads and their reference

    main:
    ch_versions = Channel.empty()
    ch_assembly = Channel.empty()
    ch_assembly_graph = Channel.empty()
    ch_assembly_info = Channel.empty()

    // Set assembler and validate parameters
    def assembler = params.assembler ?: 'flye'
    def genome_size = params.genome_size ?: '5m'  // Default to 5Mb for bacterial genomes
    def sequencing_mode = params.sequencing_mode ?: '--nano-raw'  // Default nanopore mode
    def scope = params.assembly_scope ?: 'metagenome'

    //
    // GATE: measure before assembling, and record the answer either way.
    //
    // Assembly is the one step that can run, succeed and publish a number
    // that is not a result: a real corpus produced 63 contigs at an N50 of
    // 12,368 built at a median coverage of 4, with the run reporting healthy
    // (nanometa_live assembly audit, 2026-09-03). Nothing in that corpus
    // reached 2x of its reference where a draft needs 30x, so declining is
    // the normal answer for shallow input rather than an error -- and a
    // decline that is recorded is a measurement, where an absent assembly is
    // silence.
    //
    // Every candidate passes through the gate; only those it marks 'attempt'
    // reach an assembler. NO_REFERENCE is the staged placeholder for a
    // whole-sample assembly, which has no single genome to divide by.
    def want_metagenome = scope in ['metagenome', 'both']
    def want_targeted   = scope in ['targeted', 'both']

    //
    // POOL: an assembly sees the sample, not one arriving file.
    //
    // Realtime flattens each batch back into one emission per FASTQ, and QC is
    // per emission, so assembly ran per file and every result overwrote the
    // last at the same publish path: a 28-file run left four artifacts, each a
    // single batch's assembly at a ninth to a thirty-fourth of what the sample
    // could give (nanometa_live assembly audit, A3).
    //
    // One accumulator per run holds each key's read files and answers when an
    // attempt is due -- every `assembly_batch_interval` files, provided the
    // pool grew by `assembly_min_growth`. Batch mode emits each sample once,
    // so its first emission is also its final attempt and the same code path
    // serves both modes. The attempt number rides in meta so an attempt can
    // never overwrite an earlier one.
    def pool = new AssemblyReadAccumulator()
    def interval = (params.assembly_batch_interval ?: 0) as int
    def min_growth = (params.assembly_min_growth ?: 0) as double
    def is_batch = !(params.realtime_mode as boolean)

    ch_candidates = Channel.empty()
    if (want_metagenome) {
        ch_candidates = ch_candidates.mix(
            ch_reads
                .filter { it instanceof List && it.size() >= 2 && it[0] instanceof Map }
                .map { meta, reads ->
                    [ meta + [ assembly_scope: 'metagenome' ], reads,
                      file("${projectDir}/assets/NO_REFERENCE") ]
                }
        )
    }
    if (want_targeted) {
        ch_candidates = ch_candidates.mix(
            ch_targeted
                .filter { it instanceof List && it.size() >= 3 && it[0] instanceof Map }
                .map { meta, reads, reference ->
                    [ meta + [ assembly_scope: 'targeted' ], reads, reference ]
                }
        )
    }

    ch_pool_due = ch_candidates
        .map { meta, reads, reference ->
            def key = _assemblyKey(meta)
            def files = pool.accumulate(key, reads)
            def due = pool.attemptDue(key, files.size(), interval, min_growth, is_batch)
            due ? [ meta + [ assembly_attempt: pool.attemptsFor(key) ], files, reference ] : null
        }
        .filter { it != null }

    ASSEMBLY_READ_POOL ( ch_pool_due.map { meta, files, reference -> [ meta, files ] } )
    ch_versions = ch_versions.mix(ASSEMBLY_READ_POOL.out.versions.first())

    // Re-attach the reference to the pooled reads, keyed so a concurrent
    // attempt for another sample cannot be paired with the wrong genome.
    ch_gate_in = ASSEMBLY_READ_POOL.out.pooled
        .map { meta, pooled -> [ _attemptKey(meta), meta, pooled ] }
        .join(ch_pool_due.map { meta, files, reference -> [ _attemptKey(meta), reference ] })
        .map { key, meta, pooled, reference -> [ meta, pooled, reference ] }

    ASSEMBLY_DEPTH_GATE ( ch_gate_in )
    ch_versions = ch_versions.mix(ASSEMBLY_DEPTH_GATE.out.versions)
    ch_decision = ASSEMBLY_DEPTH_GATE.out.decision

    // Only the read sets the gate cleared. The decision file is small and is
    // parsed here rather than emitted as a value, so the branch cannot drift
    // from the record the operator is shown.
    ch_cleared = ch_gate_in
        .map { meta, reads, reference -> [ _assemblyKey(meta), meta, reads ] }
        .join(
            ch_decision.map { meta, json ->
                [ _assemblyKey(meta), new groovy.json.JsonSlurper().parse(json.toFile()) ]
            }
        )
        .filter { key, meta, reads, record -> record.decision == 'attempt' }
        .map { key, meta, reads, record -> [ meta, reads ] }

    //
    // BRANCH: Route to appropriate assembler
    //
    if (assembler == 'flye') {
        //
        // MODULE: Run Flye for long-read assembly
        //
        FLYE (
            ch_cleared,
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
        MINIMAP2_AVA ( ch_cleared )
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
        ch_miniasm_input = ch_cleared
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
    decision         = ch_decision        // channel: [ val(meta), path(json) ] - Why each candidate was or was not assembled
    canonical_assembly = ch_canonical_assembly // channel: [ val(meta), path(json) ] - Canonical assembly JSON
    assembly         = ch_assembly        // channel: [ val(meta), path(fasta.gz) ] - Main assembly
    assembly_graph   = ch_assembly_graph  // channel: [ val(meta), path(gfa.gz) ] - Assembly graph
    assembly_info    = ch_assembly_info   // channel: [ val(meta), path(txt) ] - Assembly statistics
    assembler_used   = Channel.value(assembler) // channel: val(assembler_name)
    versions         = ch_versions        // channel: [ path(versions.yml) ]
}


// A (sample, scope, taxid) key. Assembly is no longer one output per sample:
// with scope 'both' a sample yields a whole-sample assembly and one per
// detected organism, so meta.id alone would collide.
def _attemptKey(Map meta) {
    return "${_assemblyKey(meta)}|${meta.assembly_attempt ?: 1}"
}


def _assemblyKey(Map meta) {
    return "${meta.id}|${meta.assembly_scope ?: 'metagenome'}|${meta.taxid ?: ''}"
}
