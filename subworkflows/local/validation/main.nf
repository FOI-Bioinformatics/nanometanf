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

    // Prepare database with meta for BLAST_BLASTN
    // Handle both channel and simple value inputs (for nf-test compatibility)
    def db_channel = ch_db instanceof List ? Channel.fromList(ch_db) : ch_db
    ch_db_with_meta = db_channel.map { db -> [ [id: 'blast_db'], db ] }

    //
    // MODULE: Run BLAST for sequence validation
    // BLAST_BLASTN expects 5 inputs:
    //   1. tuple val(meta), path(fasta) - query
    //   2. tuple val(meta2), path(db) - database with meta
    //   3. path taxidlist - optional taxonomy filter
    //   4. val taxids - optional taxonomy IDs
    //   5. val negative_tax - boolean for negative filtering
    //
    BLAST_BLASTN (
        ch_query,
        ch_db_with_meta,
        [],              // taxidlist - empty
        [],              // taxids - empty
        false            // negative_tax - false
    )
    ch_versions = ch_versions.mix(BLAST_BLASTN.out.versions)

    emit:
    txt          = BLAST_BLASTN.out.txt           // channel: [ val(meta), path(txt) ]
    versions     = ch_versions                    // channel: [ path(versions.yml) ]
}