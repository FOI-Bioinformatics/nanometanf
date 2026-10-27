// Re-runnable measurement behind docs/performance/realtime_many_barcodes_audit_2026-10-26.md
// (finding F1) and the fix for it.
//
// Measures cross-sample fairness of the real real-time interleavers
// (lib/BatchUtils.interleaveFilesBySample + lib/CrossBatchInterleaver), loaded
// from lib/, against a synthetic start-up backlog in two supported layouts.
// It reports how many files must be consumed before every sample has a first
// result, under the production sample-id key AND under the parent-directory
// key the code used before the fix, so the difference is one run's output.

def repo = new File('/home/user/nanometanf/lib')
def gcl = new GroovyClassLoader(this.class.classLoader)
gcl.parseClass(new File(repo, 'BarcodeUtils.groovy'))
def InputDetector = gcl.parseClass(new File(repo, 'InputDetector.groovy'))
def BatchUtils    = gcl.parseClass(new File(repo, 'BatchUtils.groovy'))
def XBI           = gcl.parseClass(new File(repo, 'CrossBatchInterleaver.groovy'))

// The production resolver, as subworkflows/local/realtime_monitoring builds it.
def prod   = { f -> InputDetector.extractSampleId(f, null, null, null) }
// The key the interleavers hardcoded before the fix.
def oldKey = { f -> f.parentFile?.name ?: 'unknown' }

int NB = 24, NF = 20, BATCH = 10
def layouts = [
 'per-sample dirs    fastq_pass/barcodeNN/reads_F.fastq.gz':
   { int b, int f -> new File(String.format("fastq_pass/barcode%02d/reads_%03d.fastq.gz", b, f)) },
 'flat, name-encoded fastq_pass/barcodeNN_F.fastq.gz':
   { int b, int f -> new File(String.format("fastq_pass/barcode%02d_%03d.fastq.gz", b, f)) },
]

layouts.each { label, mk ->
    def files = []
    (1..NB).each { b -> (0..<NF).each { f -> files << mk(b, f) } }
    Collections.shuffle(files, new Random(7))        // filesystem listing order is arbitrary
    int nSamples = files.collect(prod).toSet().size()

    def measure = { Closure key ->
        def ordered = BatchUtils.interleaveFilesBySample(files, key)
        def xbi = XBI.newInstance(key)
        def stream = []
        ordered.collate(BATCH).each { b -> stream.addAll(xbi.interleave(b)) }
        def seen = [] as Set
        int cover = -1
        stream.eachWithIndex { f, i ->
            if (seen.add(prod(f)) && seen.size() == nSamples && cover < 0) cover = i + 1
        }
        [cover: cover,
         firstTen: stream.take(10).collect(prod).toSet().size(),
         intact: stream.size() == files.size() && stream.toSet().size() == files.size()]
    }
    def now = measure(prod)
    def before = measure(oldKey)

    println "-" * 74
    println label
    printf "  samples / parent directories               : %d / %d%n",
        nSamples, files.collect { it.parentFile.name }.toSet().size()
    printf "  files before every sample has one result   : %d of %d  (parent-dir key: %d)%n",
        now.cover, files.size(), before.cover
    printf "  distinct samples in the first 10 files     : %d  (parent-dir key: %d)%n",
        now.firstTen, before.firstTen
    printf "  every file emitted exactly once            : %s%n", now.intact
}
println "-" * 74
