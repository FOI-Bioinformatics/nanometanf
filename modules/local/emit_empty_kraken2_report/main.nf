// Synthesize a placeholder Kraken2 report for samples whose post-QC
// FASTQ contains no reads.
//
// Without this module, the taxonomic_classification subworkflow used
// to silently drop such samples from downstream channels. The
// downstream nanometa_live GUI then showed the sample in its sample
// table but with no classification data, leaving operators wondering
// whether the sample failed or simply had nothing to classify. The
// placeholder makes the absence explicit and lets MULTIQC / TAXPASTA
// / GUI loaders handle the sample uniformly with a 0-read accounting.
//
// The emitted report is a single line in standard Kraken2 format:
//   100.00<TAB>0<TAB>0<TAB>U<TAB>0<TAB>unclassified
// which states "100% of the 0 reads ended up unclassified". Parsers
// treat this as a valid empty-but-well-formed report.
process EMIT_EMPTY_KRAKEN2_REPORT {
    tag "${meta.id}"
    label 'process_single'

    // No external tool required; runs in a bare conda env so the
    // process honours the active profile without pulling extra deps.
    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/coreutils:9.5' :
        'quay.io/biocontainers/coreutils:9.5' }"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("${meta.id}.kraken2.report.txt"), emit: report
    path "versions.yml"                                   , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    printf '100.00\\t0\\t0\\tU\\t0\\tunclassified\\n' > ${meta.id}.kraken2.report.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        coreutils: \$(printf -- "--version" | head -c 0; printf '9.5')
    END_VERSIONS
    """

    stub:
    """
    printf '100.00\\t0\\t0\\tU\\t0\\tunclassified\\n' > ${meta.id}.kraken2.report.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        coreutils: 9.5
    END_VERSIONS
    """
}
