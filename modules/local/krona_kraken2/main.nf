process KRONA_KRAKEN2 {
    tag "$meta.id"
    label 'process_single'
    errorStrategy 'ignore'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/krona:2.8.1--pl5321hdfd78af_1' :
        'biocontainers/krona:2.8.1--pl5321hdfd78af_1' }"

    input:
    tuple val(meta), path(kraken_report)
    path db

    output:
    tuple val(meta), path("*.html"), emit: html
    path "versions.yml"            , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Build Krona taxonomy from Kraken2 database if available,
    # fall back to download, or proceed without taxonomy names
    KRONA_TAX_DIR=\$(dirname \$(which ktUpdateTaxonomy.sh))/../opt/krona/taxonomy
    mkdir -p "\$KRONA_TAX_DIR"
    if [ ! -s "\$KRONA_TAX_DIR/taxonomy.tab" ]; then
        if [ -f "${db}/names.dmp" ] && [ -f "${db}/nodes.dmp" ]; then
            echo "Building Krona taxonomy from Kraken2 database..." >&2
            cp "${db}/names.dmp" "${db}/nodes.dmp" "\$KRONA_TAX_DIR/"
            extractTaxonomy.pl "\$KRONA_TAX_DIR" >&2
        else
            echo "WARNING: No taxonomy files in Kraken2 DB, attempting download..." >&2
            if ! ktUpdateTaxonomy.sh 2>&1; then
                echo "WARNING: Krona taxonomy unavailable. Taxids shown as numbers." >&2
                touch "\$KRONA_TAX_DIR/taxonomy.tab"
            fi
        fi
    fi

    # Feed Kraken2 report directly to ktImportTaxonomy
    # -t 5: taxid column (col 5 in Kraken2 report)
    # -m 3: magnitude from reads_taxon (col 3, reads assigned at this node only)
    # Krona builds the hierarchy from taxonomy.tab, so using reads_taxon
    # avoids double-counting that occurs with reads_clade (col 2)
    if awk -F'\\t' '\$4 != "U" && \$3 > 0 {found=1; exit} END {exit !found}' ${kraken_report}; then
        ktImportTaxonomy \\
            -t 5 \\
            -m 3 \\
            -o ${prefix}.krona.html \\
            ${kraken_report}
    else
        echo "WARNING: No classified reads in report, generating empty Krona plot" >&2
        ktImportTaxonomy \\
            -o ${prefix}.krona.html \\
            <(echo -e "0\\t1")
    fi

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
