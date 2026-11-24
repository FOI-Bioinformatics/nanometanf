/*
 * Thin wrapper for testing ValidationOnlyInputs via nf-test.
 * The class is auto-loaded from lib/ by Nextflow.
 */

// Create the named files under a fake kraken2 dir and return the
// [sample_id, filename] pairs the --validation_only entry would build.
def perSampleFrom(String dir, List names, String suffix) {
    def d = new File(dir)
    d.mkdirs()
    def paths = names.collect { n ->
        def f = new File(d, n)
        f.text = 'x'
        f.toPath()
    }
    return ValidationOnlyInputs.perSample(paths, suffix).collect { [it[0], it[1].fileName.toString()] }
}
