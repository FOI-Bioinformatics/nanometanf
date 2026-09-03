/*
 * Shared utility for detecting input directory structure and extracting sample IDs.
 * Used by both real-time monitoring and scan-mode subworkflows.
 */
class InputDetector {

    static final List FASTQ_EXTENSIONS = ['.fastq', '.fastq.gz', '.fq', '.fq.gz']

    /**
     * Convert any path-like input (String, File, Path) to a java.io.File.
     */
    private static File toFile(input) {
        if (input instanceof File) return input
        if (input instanceof java.nio.file.Path) return input.toFile()
        return new File(input.toString())
    }

    /**
     * MinKNOW output bins: they group reads by outcome, not by sample, so a
     * run folder pointed at as the input root keeps its filename-based
     * naming below them.
     */
    static final List<String> NON_SAMPLE_DIR_NAMES = [
        'fastq_pass', 'fastq_fail', 'fastq_skip', 'pass', 'fail', 'skip', 'output',
    ]

    /** True when a direct subdirectory of the input root may name a sample. */
    static boolean isSampleDirName(String name) {
        return name && !name.startsWith('.') && !(name in NON_SAMPLE_DIR_NAMES)
    }

    /**
     * Direct subdirectories of dir that each name one sample: every
     * barcodeNN folder (an empty one awaiting reads included), the
     * unclassified bin and any custom-named folder holding reads. The
     * conventional-name-only rule split a Turex/ or Zymo/ layout into one
     * sample per file while the GUI, whose find_sample_subdirs this
     * mirrors, had accepted it as by_barcode input (nanometa_live audit
     * round 5, 2026-09-03, B4/C12).
     */
    static List<File> sampleSubdirs(dir, List extensions = FASTQ_EXTENSIONS) {
        def dirFile = toFile(dir)
        if (!dirFile.isDirectory()) return []
        def children = dirFile.listFiles()
        if (children == null) return []
        return children.findAll { child ->
            child.isDirectory() && isSampleDirName(child.name) &&
            (child.name =~ /^barcode\d+$/ || hasTargetFiles(child, extensions))
        }.sort { it.name }
    }

    /**
     * Detect whether a directory uses per-sample subdirectories or a flat
     * layout.
     *
     * @param dir Path to the input directory (String, File, or Path)
     * @param extensions List of file extensions to look for
     * @return 'barcode_subdirs' (per-sample folders holding reads) or 'flat'
     */
    static String detectStructure(dir, List extensions = FASTQ_EXTENSIONS) {
        def withReads = sampleSubdirs(dir, extensions).any { hasTargetFiles(it, extensions) }
        return withReads ? 'barcode_subdirs' : 'flat'
    }

    /**
     * Extract sample ID from a file path using a priority chain:
     * 1. Parent directory name if it matches barcode pattern
     * 1b. Parent directory name if it is a direct child of inputRoot
     *     (a custom-named sample folder such as Turex/)
     * 2. User-provided regex applied to filename
     * 3. BarcodeUtils extraction from filename
     * 4. Fallback to sample_name or filename stem
     *
     * @param filePath Path to the file (String, File, or Path)
     * @param sampleRegex Optional regex with capture group for sample ID
     * @param sampleName Optional fallback sample name
     * @param inputRoot Optional input root; a direct subdirectory of it
     *        names the sample (null keeps the conventional rules only)
     * @return Extracted sample ID string
     */
    static String extractSampleId(filePath, String sampleRegex = null, String sampleName = null, inputRoot = null) {
        def f = toFile(filePath)
        def parentName = f.parentFile?.name
        def filename = f.name
        def stem = filename.replaceAll(/\.(fastq|fq)(\.gz)?$/, '')

        // 1. Subdirectory-based: parent is a barcode dir or the unclassified
        //    bin MinKNOW writes beside them. Both name the sample; without
        //    the latter every chunk file in unclassified/ fell through to
        //    the filename stem and became its own sample.
        if (parentName && (parentName =~ /^barcode\d+$/ || parentName == 'unclassified')) {
            return parentName
        }

        // 1b. A custom-named folder directly under the input root is one
        //     sample (Turex/, Zymo/); MinKNOW's outcome bins are not.
        if (inputRoot != null && parentName && isSampleDirName(parentName)) {
            def rootFile = toFile(inputRoot)
            def parentOfParent = f.parentFile?.parentFile
            if (parentOfParent != null && rootFile.isDirectory() &&
                parentOfParent.canonicalFile == rootFile.canonicalFile) {
                return parentName
            }
        }

        // 2. User-provided regex
        if (sampleRegex) {
            def m = filename =~ sampleRegex
            if (m.find() && m.groupCount() >= 1) {
                return m.group(1)
            }
        }

        // 3. BarcodeUtils extraction from filename - only when parent suggests
        //    a MinKNOW output structure, to avoid false positives in singleplex mode
        if (parentName && parentName =~ /^(fastq_pass|output)$/) {
            def barcode = BarcodeUtils.extractBarcodeFromFilename(stem)
            if (barcode) {
                return barcode
            }
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
