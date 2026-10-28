/*
 * Thin wrappers for testing RealtimeIntake.settle via nf-test. The class is
 * auto-loaded from lib/ by Nextflow. Written in the Nextflow strict-syntax
 * subset of Groovy: no classic for/while loops, no typed locals.
 */

def nowMs() { return System.currentTimeMillis() }

def touchNow(f) {
    java.nio.file.Files.setLastModifiedTime(f,
        java.nio.file.attribute.FileTime.fromMillis(System.currentTimeMillis()))
}

// A file written in full some time ago: must return at once.
def settleQuietFile(String dir) {
    def f = java.nio.file.Paths.get(dir, "quiet.fastq.gz")
    java.nio.file.Files.write(f, "@r1\nACGT\n+\nIIII\n".bytes)
    java.nio.file.Files.setLastModifiedTime(f,
        java.nio.file.attribute.FileTime.fromMillis(System.currentTimeMillis() - 60000L))
    def t0 = nowMs()
    def out = RealtimeIntake.settle(f, 2000L, 30000L, 100L)
    return [path: out.toString(), waited_ms: nowMs() - t0]
}

// A file still being appended to when first seen: must return only after
// the writes stop, with the final size.
def settleGrowingFile(String dir) {
    def f = java.nio.file.Paths.get(dir, "growing.fastq.gz")
    java.nio.file.Files.write(f, "@r1\nACGT\n+\nIIII\n".bytes)
    def writer = Thread.start {
        (2..7).each { i ->
            Thread.sleep(250L)
            java.nio.file.Files.write(f, "@r${i}\nACGT\n+\nIIII\n".toString().bytes,
                java.nio.file.StandardOpenOption.APPEND)
            // mtime resolution is one second on some filesystems; bump it
            // explicitly so every append is a visible change.
            touchNow(f)
        }
    }
    def t0 = nowMs()
    def out = RealtimeIntake.settle(f, 1000L, 30000L, 100L)
    def waited = nowMs() - t0
    def size_at_return = java.nio.file.Files.size(out)
    writer.join()
    return [path: out.toString(), waited_ms: waited,
            size_at_return: size_at_return, final_size: java.nio.file.Files.size(f)]
}

// A file that never stops changing is handed on at the wait ceiling.
def settleNeverQuietFile(String dir) {
    def f = java.nio.file.Paths.get(dir, "endless.fastq.gz")
    java.nio.file.Files.write(f, "x".bytes)
    def stop = new java.util.concurrent.atomic.AtomicBoolean(false)
    def writer = Thread.start {
        (1..200).each { i ->
            if (!stop.get()) {
                Thread.sleep(100L)
                java.nio.file.Files.write(f, "x".bytes, java.nio.file.StandardOpenOption.APPEND)
                touchNow(f)
            }
        }
    }
    def t0 = nowMs()
    def out = RealtimeIntake.settle(f, 1000L, 2000L, 100L)
    def waited = nowMs() - t0
    stop.set(true)
    writer.join()
    return [path: out.toString(), waited_ms: waited]
}

// A path that does not exist is returned as is, without waiting.
def settleVanishedFile(String dir) {
    def f = java.nio.file.Paths.get(dir, "gone.fastq.gz")
    def t0 = nowMs()
    def out = RealtimeIntake.settle(f, 2000L, 30000L, 100L)
    return [path: out.toString(), waited_ms: nowMs() - t0]
}
