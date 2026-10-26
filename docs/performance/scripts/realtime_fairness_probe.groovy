// Re-runnable measurement behind docs/performance/realtime_many_barcodes_audit_2026-10-26.md (F1).
// Measures cross-barcode fairness of the REAL realtime interleavers
// (lib/BatchUtils.interleaveFilesByParentDir + lib/CrossBatchInterleaver),
// loaded from the repo, against two on-disk layouts the pipeline supports.
// Stand-in path objects expose .parent.name / .name exactly as Nextflow's do.
class P { String dir; String name; P parent
  P(String d, String n){ dir=d; name=n; parent = (d==null? null : new P(null, d)) }
  String toString(){ "${dir}/${name}" } }

def repo = new File('/home/user/nanometanf/lib')
def gcl = new GroovyClassLoader(this.class.classLoader)
def BatchUtils = gcl.parseClass(new File(repo, 'BatchUtils.groovy'))
def XBI        = gcl.parseClass(new File(repo, 'CrossBatchInterleaver.groovy'))

int NB = 24, NF = 20, BATCH = 10

// sample id as InputDetector resolves it for each layout (rules 1 and 3)
def layouts = [
 'MinKNOW per-barcode dirs   fastq_pass/barcodeNN/reads_F.fastq.gz':
   [ mk: { int b, int f -> new P("barcode${String.format('%02d',b)}", "reads_${String.format('%03d',f)}.fastq.gz") },
     sid: { p -> p.dir } ],
 'flat dir, barcode in name  fastq_pass/barcodeNN_F.fastq.gz':
   [ mk: { int b, int f -> new P("fastq_pass", "barcode${String.format('%02d',b)}_${String.format('%03d',f)}.fastq.gz") },
     sid: { p -> (p.name =~ /(?i)barcode(\d+)/).with { it.find(); "barcode" + it.group(1) } } ],
]

layouts.each { label, L ->
    def files = []
    (1..NB).each { b -> (0..<NF).each { f -> files << L.mk(b, f) } }
    Collections.shuffle(files, new Random(7))          // filesystem order is arbitrary
    def nSamples = files.collect(L.sid).toSet().size()
    def nParents = files.collect { it.parent.name }.toSet().size()

    def ordered = BatchUtils.interleaveFilesByParentDir(files)   // start-up backlog
    def xbi = XBI.newInstance()
    def stream = []
    ordered.collate(BATCH).each { b -> stream.addAll(xbi.interleave(b)) }   // per-batch

    def seen = [] as Set; int coverAll = -1
    stream.eachWithIndex { f, i ->
        if (seen.add(L.sid(f)) && seen.size() == nSamples && coverAll < 0) coverAll = i + 1 }

    println "-"*74
    println label
    printf "  samples / parent dirs                      : %d / %d%n", nSamples, nParents
    printf "  files classified before every sample has 1 : %d of %d%n", coverAll, files.size()
    printf "  distinct samples in the first 10 files     : %d%n", stream.take(10).collect(L.sid).toSet().size()
    printf "  distinct samples in the first 24 files     : %d%n", stream.take(24).collect(L.sid).toSet().size()
}
println "-"*74
