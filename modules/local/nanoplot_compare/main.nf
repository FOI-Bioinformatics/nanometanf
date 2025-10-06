process NANOPLOT_COMPARE {
    tag "$prefix"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/nanoplot:1.46.1--pyhdfd78af_0' :
        'biocontainers/nanoplot:1.46.1--pyhdfd78af_0' }"

    input:
    path(ontfiles)
    val prefix

    output:
    path("${prefix}_comparison")                  , emit: comparison_dir
    path("${prefix}_comparison/*.html")           , emit: html
    path("${prefix}_comparison/*.png") , optional: true, emit: png
    path("${prefix}_comparison/*.txt")            , emit: txt
    path  "versions.yml"                          , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def inputs = ontfiles.collect { file ->
        if ("$file".endsWith(".fastq.gz") || "$file".endsWith(".fq.gz") || "$file".endsWith(".fastq") || "$file".endsWith(".fq")) {
            "--fastq ${file}"
        } else if ("$file".endsWith(".txt")) {
            "--summary ${file}"
        } else {
            ""
        }
    }.findAll { it != "" }.join(' ')

    """
    NanoPlot \\
        $args \\
        -t $task.cpus \\
        -o ${prefix}_comparison \\
        $inputs

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        nanoplot: \$(echo \$(NanoPlot --version 2>&1) | sed 's/^.*NanoPlot //; s/ .*\$//')
    END_VERSIONS
    """

    stub:
    """
    mkdir -p ${prefix}_comparison

    touch ${prefix}_comparison/LengthvsQualityScatterPlot_dot.html
    touch ${prefix}_comparison/LengthvsQualityScatterPlot_kde.html
    touch ${prefix}_comparison/NanoPlot-report.html
    touch ${prefix}_comparison/NanoStats.txt
    touch ${prefix}_comparison/Non_weightedHistogramReadlength.html
    touch ${prefix}_comparison/Non_weightedLogTransformed_HistogramReadlength.html
    touch ${prefix}_comparison/WeightedHistogramReadlength.html
    touch ${prefix}_comparison/WeightedLogTransformed_HistogramReadlength.html
    touch ${prefix}_comparison/Yield_By_Length.html

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        nanoplot: \$(echo \$(NanoPlot --version 2>&1) | sed 's/^.*NanoPlot //; s/ .*\$//')
    END_VERSIONS
    """
}
