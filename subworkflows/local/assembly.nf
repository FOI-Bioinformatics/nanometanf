/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    SUBWORKFLOW: ASSEMBLY  
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Multi-tool genome assembly for long-read nanopore data
    
    Supported assemblers:
    - flye: Flye assembler for long and noisy reads (default)
    - miniasm: Miniasm ultra-fast assembler
    
    Future assemblers (ready to implement):
    - canu: Canu single-molecule assembler
    - raven: Raven assembler for long reads
    - shasta: Shasta nanopore assembler
    
    Features:
    - Tool-agnostic interface
    - Standardized assembly outputs
    - Easy addition of new assemblers
    - Optimized for nanopore data
----------------------------------------------------------------------------------------
*/

include { FLYE              } from '../../modules/nf-core/flye/main'
include { MINIMAP2_ALIGN    } from '../../modules/nf-core/minimap2/align/main'
include { MINIASM           } from '../../modules/nf-core/miniasm/main'

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
    switch(assembler) {
        case 'flye':
            //
            // MODULE: Run Flye for long-read assembly
            //
            FLYE (
                ch_reads,
                sequencing_mode
            )
            ch_versions = ch_versions.mix(FLYE.out.versions)
            
            // Collect standardized outputs
            ch_assembly = FLYE.out.fasta
            ch_assembly_graph = FLYE.out.gfa
            ch_assembly_info = FLYE.out.txt
            break
            
        case 'miniasm':
            //
            // MODULE: Run Minimap2 for overlap detection (miniasm prerequisite)
            //
            MINIMAP2_ALIGN (
                ch_reads,                    // reads
                ch_reads,                    // reference (self-alignment for overlap)
                false,                       // bam_format
                false,                       // bam_index_extension  
                false,                       // cigar_paf_format
                false                        // cigar_bam
            )
            ch_versions = ch_versions.mix(MINIMAP2_ALIGN.out.versions)
            
            //
            // MODULE: Run Miniasm for ultra-fast assembly
            //
            ch_miniasm_input = ch_reads
                .join(MINIMAP2_ALIGN.out.paf)
                
            MINIASM (
                ch_miniasm_input
            )
            ch_versions = ch_versions.mix(MINIASM.out.versions)
            
            // Collect standardized outputs
            ch_assembly = MINIASM.out.assembly
            ch_assembly_graph = MINIASM.out.gfa
            ch_assembly_info = Channel.empty()  // Miniasm doesn't provide assembly stats
            break
            
        // Future assemblers to be added here:
        // case 'canu':
        //     CANU(ch_reads, genome_size)
        //     break
        // case 'raven':
        //     RAVEN(ch_reads)
        //     break
        // case 'shasta':
        //     SHASTA(ch_reads)
        //     break
        
        default:
            error "Unsupported assembler: ${assembler}. Currently supported: flye, miniasm"
    }

    emit:
    assembly         = ch_assembly        // channel: [ val(meta), path(fasta.gz) ] - Main assembly
    assembly_graph   = ch_assembly_graph  // channel: [ val(meta), path(gfa.gz) ] - Assembly graph
    assembly_info    = ch_assembly_info   // channel: [ val(meta), path(txt) ] - Assembly statistics
    assembler_used   = Channel.value(assembler) // channel: val(assembler_name)
    versions         = ch_versions        // channel: [ path(versions.yml) ]
}