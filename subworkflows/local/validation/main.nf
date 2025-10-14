//
// Validation subworkflow for BLAST analysis
//

include { BLAST_BLASTN            } from "${projectDir}/modules/nf-core/blast/blastn/main"

workflow VALIDATION {

    take:
    ch_query     // channel: [ val(meta), path(fasta) ]
    ch_db        // channel: [ path(blast_db) ]

    main:
    ch_versions = Channel.empty()
    
    //
    // MODULE: Run BLAST for sequence validation
    //
    BLAST_BLASTN (
        ch_query,
        ch_db
    )
    ch_versions = ch_versions.mix(BLAST_BLASTN.out.versions)

    emit:
    txt          = BLAST_BLASTN.out.txt           // channel: [ val(meta), path(txt) ]
    versions     = ch_versions                    // channel: [ path(versions.yml) ]
}