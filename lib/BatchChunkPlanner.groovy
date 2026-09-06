import groovy.json.JsonOutput

/**
 * Chunk plan for batch mode with a backlog.
 *
 * A samplesheet run used to classify each sample's whole file list in one
 * task, in samplesheet order, so a barcode showed nothing until every read
 * of it was classified and barcodes finished one after another. This class
 * splits each sample's files into chunks whose sizes grow geometrically
 * (1, 2, 4, 8 ... files with firstFiles 1 and growth 2) and orders the chunks
 * across samples by chunk index, so the first chunk of every sample is
 * classified before the second chunk of any. Downstream, each chunk is a
 * batch with meta.batch_id, exactly as a real-time batch, and the cumulative
 * report advances after each one. A 200-file sample costs about eight
 * classifier tasks this way rather than 200 (one per file) or one.
 *
 * The planner is pure: it neither reads nor orders by file size. Every file
 * appears in exactly one chunk, in name-sorted order within its sample.
 */
class BatchChunkPlanner {

    /** Split name-sorted files into chunks of geometrically growing size. */
    static List<List> chunk(List files, int firstFiles = 1, double growth = 2.0) {
        def sorted = (files ?: []).sort(false) { it.toString() }
        def out = []
        int i = 0
        double size = Math.max(1, firstFiles)
        while (i < sorted.size()) {
            int n = Math.max(1, (int) Math.round(size))
            out << sorted.subList(i, Math.min(sorted.size(), i + n)).collect { it }
            i += n
            if (growth > 1.0) {
                size = size * growth
            }
        }
        return out
    }

    /**
     * Order chunks across samples by chunk index: every sample's chunk 0
     * (in the map's iteration order), then every sample's chunk 1, and so on.
     * Returns a list of [sampleId, chunkIndex, files].
     */
    static List interleave(Map<String, List<List>> chunksBySample) {
        def out = []
        int depth = (chunksBySample?.values()?.collect { it.size() } ?: [0]).max() ?: 0
        for (int k = 0; k < depth; k++) {
            chunksBySample.each { sample, chunks ->
                if (k < chunks.size()) {
                    out << [sample, k, chunks[k]]
                }
            }
        }
        return out
    }

    /** Write {sample: {files, chunks}} so the dashboard can show progress. */
    static void writePlan(String path, Map<String, List<List>> chunksBySample) {
        def summary = chunksBySample.collectEntries { sample, chunks ->
            [(sample): [files: chunks.sum { it.size() } ?: 0, chunks: chunks.size()]]
        }
        def target = new File(path)
        target.parentFile?.mkdirs()
        def temp = new File(target.parentFile, target.name + '.tmp')
        temp.text = JsonOutput.prettyPrint(JsonOutput.toJson(summary))
        java.nio.file.Files.move(temp.toPath(), target.toPath(),
            java.nio.file.StandardCopyOption.REPLACE_EXISTING,
            java.nio.file.StandardCopyOption.ATOMIC_MOVE)
    }
}
