// Thin wrappers so nf-test's function tests can drive the lib class.

def chunk(List files, int firstFiles, double growth) {
    return BatchChunkPlanner.chunk(files, firstFiles, growth)
}

def interleave(Map chunksBySample) {
    return BatchChunkPlanner.interleave(chunksBySample)
}

// Plan a flat backlog as chunks ordered across samples, keyed exactly as the
// pipeline keys meta.id. Returns [[sampleId, chunkIndex, basenames], ...] so a
// test can assert the emission order without absolute paths.
def planBacklog(List paths, int firstFiles, double growth) {
    def files = paths.collect { java.nio.file.Paths.get(it) }
    def rows = BatchChunkPlanner.planBySample(
        files,
        { f -> InputDetector.extractSampleId(f, null, null, null) },
        firstFiles,
        growth)
    return rows.collect { id, k, chunk -> [id, k, chunk.collect { it.fileName.toString() }] }
}
