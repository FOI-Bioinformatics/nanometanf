import java.nio.file.FileSystemLoopException
import java.nio.file.FileVisitOption
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.SimpleFileVisitor
import java.nio.file.attribute.BasicFileAttributes
import java.util.concurrent.ConcurrentHashMap

/*
 * Real-time intake: which files the watcher and the start-up scan hand on,
 * and how the two are reconciled.
 *
 * Nextflow's watchPath does not start watching when the channel is created.
 * The directory listener (DirWatcherV2, a polling FileAlterationMonitor)
 * starts inside a session igniter, i.e. after the whole workflow script has
 * been evaluated, and it takes the directory contents at that moment as its
 * baseline: nothing already present is ever reported. The start-up scan of
 * existing files used to run at script evaluation, so a file that landed
 * between the scan and the baseline snapshot was in neither set and was
 * never classified (nanometa_live round-4 audit, H4, "startup blind
 * window"). The subworkflow now creates the watcher first and runs the scan
 * from a later igniter, so the scan sees the baseline and the watcher sees
 * everything after it; a file seen by both is processed once through the
 * seen-set below. The same set absorbs a watcher re-emission for a file
 * whose mtime changes after it was picked up ('create,modify' events).
 *
 * The listing itself is not Nextflow's file() glob. That walk aborts on the
 * first NoSuchFileException -- a file renamed away between the directory
 * read and its stat, which is every producer that writes to a temporary
 * name and renames into place -- and returns whatever it had collected
 * (Nextflow.groovy: "No such file or directory: ... -- Skipping visit").
 * A drill that fed 100 files across the start-up saw one such listing
 * return 21 of the 30 present, scattered. listInputs walks with a visitor
 * that skips the vanished entry and continues.
 */
class RealtimeIntake {

    /**
     * Regular files under root matching the glob (relative to root, Java
     * glob syntax as Nextflow's file() uses), tolerant of entries that
     * disappear during the walk. Symlinks are followed; a loop is skipped.
     */
    static List<Path> listInputs(Object root, String glob) {
        def base = (root instanceof Path ? root : Paths.get(root.toString())).toAbsolutePath()
        if (!Files.isDirectory(base)) {
            return []
        }
        def matcher = base.fileSystem.getPathMatcher("glob:${glob}")
        def out = []
        def visitor = new SimpleFileVisitor<Path>() {
            @Override
            FileVisitResult visitFile(Path file, BasicFileAttributes attrs) {
                if (attrs.isRegularFile() && matcher.matches(base.relativize(file))) {
                    out << file
                }
                return FileVisitResult.CONTINUE
            }

            @Override
            FileVisitResult visitFileFailed(Path file, IOException e) {
                // A vanished entry or a symlink loop: skip it, keep walking.
                return e instanceof FileSystemLoopException
                    ? FileVisitResult.SKIP_SUBTREE
                    : FileVisitResult.CONTINUE
            }
        }
        Files.walkFileTree(base, EnumSet.of(FileVisitOption.FOLLOW_LINKS), Integer.MAX_VALUE, visitor)
        return out
    }

    /** MinKNOW output folders whose reads are not analysis input. */
    static final List<String> EXCLUDED_DIR_NAMES = ['fastq_fail', 'fastq_skip']

    /**
     * Why a matched path is not sequencing input, or null when it is.
     * Hidden files are AppleDouble sidecars on exFAT/USB media; the
     * excluded folder names are MinKNOW's failed and skipped reads.
     */
    static String excludedReason(Path path) {
        if (path.fileName.toString().startsWith('.')) {
            return 'hidden file'
        }
        for (int i = 0; i < path.nameCount - 1; i++) {
            def part = path.getName(i).toString()
            if (part in EXCLUDED_DIR_NAMES) {
                return "inside ${part}/"
            }
        }
        return null
    }

    static boolean isInput(Path path) {
        return excludedReason(path) == null
    }

    /**
     * Partition a scanned list into inputs and a per-reason count of the
     * excluded paths, for one log line at start-up.
     */
    static Map partitionExisting(List<Path> paths) {
        def inputs = []
        def excluded = new LinkedHashMap<String, Integer>()
        paths.each { p ->
            def reason = excludedReason(p)
            if (reason == null) {
                inputs << p
            } else {
                excluded[reason] = (excluded[reason] ?: 0) + 1
            }
        }
        return [inputs: inputs, excluded: excluded]
    }

    /** A thread-safe set of paths already handed downstream. */
    static Set<String> newSeenSet() {
        return ConcurrentHashMap.newKeySet()
    }

    /**
     * True the first time a path is offered, false on every later offer.
     * Keyed on the normalized absolute path so the scan and the watcher
     * (both absolute, per Channel.watchImpl) agree.
     */
    static boolean firstSighting(Set<String> seen, Path path) {
        return seen.add(path.toAbsolutePath().normalize().toString())
    }
}
