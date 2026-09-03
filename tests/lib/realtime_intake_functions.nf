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

// Partition real files of the given ages (minutes) under a temp root with a
// maximum age: [kept names, excluded counts by reason]. A null max keeps all.
def partitionByAge(Map agesByName, Integer maxAgeMinutes) {
    def root = java.nio.file.Files.createTempDirectory('intake_age')
    def now = System.currentTimeMillis()
    def paths = agesByName.collect { name, age ->
        def f = root.resolve(name)
        java.nio.file.Files.createFile(f)
        java.nio.file.Files.setLastModifiedTime(
            f, java.nio.file.attribute.FileTime.fromMillis(now - age * 60000L))
        f
    }
    def parts = RealtimeIntake.partitionExisting(paths, maxAgeMinutes)
    return [parts.inputs.collect { it.fileName.toString() }.sort(), parts.excluded]
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
