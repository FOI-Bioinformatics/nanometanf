/*
 * Thin wrappers for testing AssemblyReadAccumulator via nf-test.
 * The class is auto-loaded from lib/ by Nextflow.
 */

/*
 * Feed files one at a time and report the pool size and whether an attempt
 * was due at each step.
 *
 * @param files      list of file-name Strings, in arrival order
 * @param interval   files between periodic attempts
 * @param minGrowth  required fractional growth since the last attempt
 * @return           list of [poolSize, attemptDue] per file
 */
def feed(List files, int interval, double minGrowth) {
    def acc = new AssemblyReadAccumulator()
    return files.collect { f ->
        def pool = acc.accumulate('s1', f)
        [ pool.size(), acc.attemptDue('s1', pool.size(), interval, minGrowth, false) ]
    }
}

/* Feed every file, then ask for a final attempt. */
def feedThenFinal(List files, int interval, double minGrowth) {
    def acc = new AssemblyReadAccumulator()
    def during = files.collect { f ->
        def pool = acc.accumulate('s1', f)
        acc.attemptDue('s1', pool.size(), interval, minGrowth, false)
    }
    def pool = acc.accumulate('s1', null)
    return [ during, acc.attemptDue('s1', pool.size(), interval, minGrowth, true),
             acc.attemptsFor('s1') ]
}

/* Two keys must not share state. */
def twoKeys(List filesA, List filesB, int interval) {
    def acc = new AssemblyReadAccumulator()
    filesA.each { acc.accumulate('a', it) }
    filesB.each { acc.accumulate('b', it) }
    return [ acc.accumulate('a', null).size(), acc.accumulate('b', null).size() ]
}
