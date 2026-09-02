/*
 * Thin wrappers for testing RealtimeIntake via nf-test.
 * The class is auto-loaded from lib/ by Nextflow.
 */


// The exclusion reason for each path string, null when it is input.
def reasons(List paths) {
    return paths.collect { RealtimeIntake.excludedReason(java.nio.file.Paths.get(it)) }
}

// Partition a scanned list: [kept path names, excluded counts by reason].
def partition(List paths) {
    def parts = RealtimeIntake.partitionExisting(paths.collect { java.nio.file.Paths.get(it) })
    return [parts.inputs.collect { it.fileName.toString() }, parts.excluded]
}

// Offer paths in order to one seen-set; true marks a first sighting.
def sightings(List paths) {
    def seen = RealtimeIntake.newSeenSet()
    return paths.collect { RealtimeIntake.firstSighting(seen, java.nio.file.Paths.get(it)) }
}

// Build a tree of empty files (relative paths) under root and list it with
// listInputs for each glob, beside Nextflow's own file() glob for the same
// pattern: [[glob, ours, nextflow's], ...] with sorted relative names.
def listAgainstFileGlob(String root, List rel_paths, List globs) {
    def base = java.nio.file.Paths.get(root)
    rel_paths.each { r ->
        def f = base.resolve(r)
        java.nio.file.Files.createDirectories(f.parent)
        java.nio.file.Files.createFile(f)
    }
    return globs.collect { g ->
        def ours = RealtimeIntake.listInputs(root, g).collect { base.relativize(it).toString() }.sort()
        def hits = file("${root}/${g}")
        def theirs = (hits instanceof List ? hits : (hits ? [hits] : [])).collect { base.relativize(it).toString() }.sort()
        [g, ours, theirs]
    }
}
