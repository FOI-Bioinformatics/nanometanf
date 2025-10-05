//
// Output organization subworkflow for standardized folder structure
//

workflow OUTPUT_ORGANIZATION {

    take:
    qc_reports         // channel: [ val(meta), path(html) ]
    nanoplot_reports   // channel: [ val(meta), path(html) ]
    kraken2_reports    // channel: [ val(meta), path(txt) ]
    blast_results      // channel: [ val(meta), path(txt) ]
    multiqc_report     // channel: [ path(html) ]

    main:

    ch_versions = Channel.empty()

    //
    // PROCESS: Organize outputs into standardized folder structure
    //
    // Structure:
    // results/
    // ├── qc/
    // │   ├── fastp/
    // │   └── nanoplot/
    // ├── classification/
    // │   └── kraken2/
    // ├── validation/
    // │   └── blast/
    // ├── reports/
    // │   └── multiqc/
    // └── pipeline_info/
    
    //
    // CHANNEL: Organize QC outputs
    //
    ch_qc_organized = qc_reports
        .map { meta, html ->
            def output_path = "${params.outdir}/qc/fastp/${meta.id}/${html.name}"
            return [ meta, html, output_path ]
        }
    
    ch_nanoplot_organized = nanoplot_reports
        .map { meta, html ->
            def output_path = "${params.outdir}/qc/nanoplot/${meta.id}/${html.name}"
            return [ meta, html, output_path ]
        }
    
    //
    // CHANNEL: Organize classification outputs
    //
    ch_kraken2_organized = kraken2_reports
        .map { meta, txt ->
            def output_path = "${params.outdir}/classification/kraken2/${meta.id}/${txt.name}"
            return [ meta, txt, output_path ]
        }
    
    //
    // CHANNEL: Organize validation outputs
    //
    ch_blast_organized = blast_results
        .map { meta, txt ->
            def output_path = "${params.outdir}/validation/blast/${meta.id}/${txt.name}"
            return [ meta, txt, output_path ]
        }
    
    //
    // CHANNEL: Organize reports
    //
    ch_multiqc_organized = multiqc_report
        .map { html ->
            def output_path = "${params.outdir}/reports/multiqc/${html.name}"
            return [ html, output_path ]
        }

    emit:
    qc_outputs             = ch_qc_organized.mix(ch_nanoplot_organized)
    classification_outputs = ch_kraken2_organized
    validation_outputs     = ch_blast_organized
    report_outputs         = ch_multiqc_organized
    versions               = ch_versions     // channel: [ versions.yml ]
}