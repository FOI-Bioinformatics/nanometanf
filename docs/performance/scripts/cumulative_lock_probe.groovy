// Measures the serialised section audit F9 names: the per-batch work the
// real-time classification subworkflow does inside ONE global lock
// (BatchUtils.withLock(cumulative_taxa_state) in
// subworkflows/local/taxonomic_classification/main.nf), for every batch of
// every barcode. Because the lock is global, these costs add across barcodes.
//
// The four steps are replicated from that subworkflow and drive the REAL lib/
// classes:
//   1. JsonSlurper over the batch's taxid counts
//   2. RealtimeResume.mergeBatchCounts into the sample's cumulative state
//   3. RealtimeResume.recordProcessedInput (a synchronized ledger append)
//   4. the report rebuild: KreportTree.depthFirstOrder over EVERY cumulative
//      taxon, a StringBuilder of all rows, and an atomic write
//
// Per-batch diversity and cumulative diversity are swept SEPARATELY, because
// they scale different steps and only one of them has an operator knob:
// steps 1-2 scale with the taxa in THIS batch, step 4 with every taxon seen so
// far. `report_write_interval` thins step 4 only.
//
//   java -cp groovy-4.x.jar:gpars-1.2.1.jar:groovy-json-4.x.jar \
//        groovy.ui.GroovyMain docs/performance/scripts/cumulative_lock_probe.groovy
import groovy.json.JsonSlurper
import groovy.json.JsonOutput

def repo = new File('/home/user/nanometanf/lib')
def gcl = new GroovyClassLoader(this.class.classLoader)
['BatchUtils.groovy', 'KreportTree.groovy', 'RealtimeResume.groovy'].each {
    gcl.parseClass(new File(repo, it))
}
def KreportTree    = gcl.loadClass('KreportTree')
def RealtimeResume = gcl.loadClass('RealtimeResume')

def root = new File(System.getProperty('java.io.tmpdir'), "f9_${System.nanoTime()}")
new File(root, 'kraken2').mkdirs()

// A plausible kreport tree: root -> domains -> phyla -> ... -> species.
def buildTaxa = { int nTaxa, int readsPerTaxon, int idBase ->
    def taxa = [:]
    taxa['1'] = [reads: 0, cumul: nTaxa * readsPerTaxon, rank: 'R', name: 'root', parent: null]
    int id = idBase
    def parents = ['1']
    def ranks = ['D', 'P', 'C', 'O', 'F', 'G', 'S']
    int made = 1, level = 0
    while (made < nTaxa) {
        def next = []
        for (p in parents) {
            for (int k = 0; k < 4 && made < nTaxa; k++) {
                def key = (id++).toString()
                taxa[key] = [reads: readsPerTaxon, cumul: readsPerTaxon,
                             rank: ranks[Math.min(level, ranks.size() - 1)],
                             name: "taxon_${key}", parent: p]
                next << key; made++
            }
        }
        parents = next ?: parents
        level++
    }
    return taxa
}
def wrap = { Map taxa, int reads -> [total_reads: reads, classified_reads: reads,
                                     unclassified_reads: 0, taxa: taxa] }

// Step 4, copied from write_cumulative_report.
def writeCumulative = { String sampleId, Map state ->
    def outdir = new File(root, 'kraken2')
    def total = state.total_reads ?: 1
    def sb = new StringBuilder()
    KreportTree.depthFirstOrder(state.taxa).each { taxid ->
        def tdata = state.taxa[taxid]
        if (tdata == null) return
        def pct = String.format("%.2f", ((tdata.cumul as double) / total) * 100.0)
        sb.append("${pct}\t${tdata.cumul}\t${tdata.reads}\t${tdata.rank}\t${taxid}\t${tdata.name}\n")
    }
    def temp = new File(outdir, "${sampleId}.cumulative.kraken2.report.txt.tmp")
    temp.text = sb.toString()
    def target = new File(outdir, "${sampleId}.cumulative.kraken2.report.txt")
    if (!temp.renameTo(target)) { target.text = temp.text; temp.delete() }
}

int BATCHES = 20
def cases = [[1000, 100], [3000, 300], [3000, 3000], [10000, 1000]]
println "The serialised section, per batch. Cumulative diversity scales the report"
println "rebuild; per-batch diversity scales the parse and merge. 20 batches."
println "-" * 86
printf "%10s %10s %12s %10s %10s %12s%n",
    'cumulative', 'per batch', 'parse+merge', 'ledger', 'report', 'TOTAL/batch'
println "-" * 86
def results = [:]
cases.each { nCum, nBatch ->
    def state = [total_reads: 0, classified_reads: 0, unclassified_reads: 0, taxa: [:]]
    // Grow the cumulative state to nCum taxa first, untimed: a late batch of a
    // real run merges into a state that already holds the run's diversity.
    RealtimeResume.mergeBatchCounts(state, wrap(buildTaxa(nCum, 10, 1000), 10 * nCum))
    def batchFile = new File(root, "b_${nCum}_${nBatch}.json")
    batchFile.text = JsonOutput.toJson(wrap(buildTaxa(nBatch, 200, 1000), 200 * nBatch))
    (1..3).each {   // warm the JIT, as the run's first batches do
        RealtimeResume.mergeBatchCounts(state, new JsonSlurper().parseText(batchFile.text))
        writeCumulative('warm', state)
    }
    long tParse = 0, tLedger = 0, tReport = 0
    (0..<BATCHES).each { b ->
        long t0 = System.nanoTime()
        def counts = new JsonSlurper().parseText(batchFile.text)
        RealtimeResume.mergeBatchCounts(state, counts)
        long t1 = System.nanoTime()
        RealtimeResume.recordProcessedInput(root.toString(), 'barcode01', b, "/watch/f${b}.fastq.gz")
        long t2 = System.nanoTime()
        writeCumulative('barcode01', state)
        long t3 = System.nanoTime()
        tParse += (t1 - t0); tLedger += (t2 - t1); tReport += (t3 - t2)
    }
    def ms = { long ns -> (ns / 1e6 / BATCHES) as double }
    def per = ms(tParse) + ms(tLedger) + ms(tReport)
    results[[nCum, nBatch]] = [per: per, report: ms(tReport)]
    printf "%10d %10d %10.1fms %8.2fms %8.1fms %10.1fms%n",
        nCum, nBatch, ms(tParse), ms(tLedger), ms(tReport), per
}
println "-" * 86
println "Serialised total across barcodes (20 batches each), and the part that"
println "report_write_interval can thin:"
printf "%10s %10s %14s %14s %16s%n", 'cumulative', 'per batch', '12 barcodes', '24 barcodes', 'thinnable share'
cases.each { nCum, nBatch ->
    def r = results[[nCum, nBatch]]
    printf "%10d %10d %12.1fs %12.1fs %14.0f%%%n",
        nCum, nBatch, r.per*12*20/1000, r.per*24*20/1000, (r.report / r.per) * 100
}
println "-" * 86
root.deleteDir()
