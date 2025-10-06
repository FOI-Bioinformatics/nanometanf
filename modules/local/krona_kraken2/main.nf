process KRONA_KRAKEN2 {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/krona:2.8.1--pl5321hdfd78af_1' :
        'biocontainers/krona:2.8.1--pl5321hdfd78af_1' }"

    input:
    tuple val(meta), path(kraken_report)

    output:
    tuple val(meta), path("*.html"), emit: html
    path "versions.yml"            , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Convert Kraken2 report to Krona format
    # Kraken2 format: %reads, #reads_clade, #reads_taxon, rank, taxid, name
    # Krona format: count taxid [taxid taxid...]

    # Import Krona taxonomy database
    ktUpdateTaxonomy.sh

    # Convert Kraken2 report to Krona input
    awk -F'\\t' '\$4 != "U" {print \$3"\\t"\$5}' ${kraken_report} > ${prefix}.krona.txt

    # Generate interactive Krona plot
    ktImportTaxonomy \\
        -o ${prefix}.krona.html \\
        -t 5 \\
        -m 3 \\
        ${prefix}.krona.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        krona: \$( ktImportTaxonomy 2>&1 | sed -n 's/^.*KronaTools //p' | sed 's/ - .*\$//' )
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.krona.html

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        krona: 2.8.1
    END_VERSIONS
    """
}
