// Thin wrappers so nf-test's function tests can drive the lib class.

def chunk(List files, int firstFiles, double growth) {
    return BatchChunkPlanner.chunk(files, firstFiles, growth)
}

def interleave(Map chunksBySample) {
    return BatchChunkPlanner.interleave(chunksBySample)
}
