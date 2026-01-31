/*
 * Shared utility for detecting input directory structure and extracting sample IDs.
 * Used by both real-time monitoring and scan-mode subworkflows.
 */
class InputDetector {

    static final List FASTQ_EXTENSIONS = ['.fastq', '.fastq.gz', '.fq', '.fq.gz']
    static final List POD5_EXTENSIONS = ['.pod5']

    /**
     * Detect whether a directory uses barcode subdirectories or flat layout.
     *
     * @param dir Path to the input directory
     * @param extensions List of file extensions to look for
     * @return 'barcode_subdirs' or 'flat'
     */
    static String detectStructure(java.nio.file.Path dir, List extensions = FASTQ_EXTENSIONS) {
        def dirFile = dir.toFile()
        if (!dirFile.isDirectory()) return 'flat'

        def children = dirFile.listFiles()
        if (children == null) return 'flat'

        def hasBarcodeDirs = children.any { child ->
            child.isDirectory() &&
            child.name =~ /^barcode\d+$/ &&
            hasTargetFiles(child, extensions)
        }

        return hasBarcodeDirs ? 'barcode_subdirs' : 'flat'
    }

    /**
     * Extract sample ID from a file path using a priority chain:
     * 1. Parent directory name if it matches barcode pattern
     * 2. User-provided regex applied to filename
     * 3. BarcodeUtils extraction from filename
     * 4. Fallback to sample_name or filename stem
     *
     * @param filePath Path to the file
     * @param sampleRegex Optional regex with capture group for sample ID
     * @param sampleName Optional fallback sample name
     * @return Extracted sample ID string
     */
    static String extractSampleId(java.nio.file.Path filePath, String sampleRegex = null, String sampleName = null) {
        def parentName = filePath.parent?.fileName?.toString()
        def filename = filePath.fileName.toString()
        def stem = filename.replaceAll(/\.(fastq|fq)(\.gz)?$/, '')

        // 1. Subdirectory-based: parent is barcode dir
        if (parentName && parentName =~ /^barcode\d+$/) {
            return parentName
        }

        // 2. User-provided regex
        if (sampleRegex) {
            def m = filename =~ sampleRegex
            if (m.find() && m.groupCount() >= 1) {
                return m.group(1)
            }
        }

        // 3. BarcodeUtils extraction from filename
        def barcode = BarcodeUtils.extractBarcodeFromFilename(stem)
        if (barcode) {
            return barcode
        }

        // 4. Fallback
        return sampleName ?: stem
    }

    /**
     * Check if a directory contains files with any of the given extensions.
     */
    static boolean hasTargetFiles(File dir, List extensions) {
        def files = dir.listFiles()
        if (files == null) return false
        return files.any { f ->
            !f.isDirectory() && extensions.any { ext -> f.name.endsWith(ext) }
        }
    }
}
