import groovy.json.JsonSlurper
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths

/*
 * Continue (-resume) support for a real-time run into a populated outdir.
 *
 * Nextflow's task cache cannot help a real-time run: every file's meta used
 * to carry a wall-clock stamp, the per-sample batch counter resumes at N+1
 * (so batch N of the second run is a different file), and the head-process
 * cumulative accumulator started from zero. Observed live (nanometa_live
 * round-4 audit, H15/H19): a Continue re-emitted all 47 existing files, the
 * aggregate the operator watched fell 9,697 -> 3,473 before climbing, and
 * barcode05 ended with 16 batches against the first run's 8.
 *
 * Three pieces make Continue mean "continue":
 *
 *  1. A ledger of processed inputs. When a batch's per-batch report has been
 *     generated, the source file is appended to
 *     ``<outdir>/pipeline_info/processed_inputs.tsv``. A file that was
 *     emitted but never classified (the run was cut) is NOT in the ledger and
 *     is processed again on Continue -- the ledger records completion, not
 *     intake.
 *  2. Intake skips ledgered files when ``workflow.resume`` is set.
 *  3. The cumulative accumulator is seeded from the previous run's per-batch
 *     taxid counts (``kraken2/<sample>/stats/batch_N_taxid_counts.json``),
 *     and the final aggregator is handed the previous run's batch files, so
 *     both the live and the end-of-session cumulative report cover both runs.
 *
 * Every reader tolerates a missing or partial file: a first run has no
 * ledger, a crashed run may have half a line.
 */
class RealtimeResume {

    static final String LEDGER_RELPATH = 'pipeline_info/processed_inputs.tsv'
    static final String LEDGER_HEADER = 'sample_id\tbatch_id\tsource_file\tcompleted_at'

    static File ledgerFile(String outdir) {
        return new File(outdir, LEDGER_RELPATH)
    }

    /** Absolute source paths the previous run(s) finished classifying. */
    static Set<String> readProcessedInputs(String outdir) {
        def out = new LinkedHashSet<String>()
        def f = ledgerFile(outdir)
        if (!f.isFile()) {
            return out
        }
        f.eachLine { line ->
            if (!line || line.startsWith('sample_id\t')) {
                return
            }
            def cols = line.split('\t', -1)
            if (cols.length >= 3 && cols[2]) {
                out.add(cols[2])
            }
        }
        return out
    }

    /** Append one completed input. Serialised: onNext callbacks may overlap. */
    static synchronized void recordProcessedInput(String outdir, String sampleId, Object batchId, String sourceFile) {
        if (!sourceFile) {
            return
        }
        def f = ledgerFile(outdir)
        f.parentFile.mkdirs()
        def isNew = !f.isFile() || f.length() == 0L
        def stamp = new Date().format("yyyy-MM-dd'T'HH:mm:ss")
        def line = "${sampleId}\t${batchId}\t${sourceFile}\t${stamp}\n"
        f.append((isNew ? LEDGER_HEADER + '\n' : '') + line)
    }

    /**
     * Merge one batch's taxid counts into a sample's cumulative state.
     *
     * ``parent`` comes from KRAKEN2_REPORT_GENERATOR, which recovers it from
     * the batch report's own row order and indentation; the cumulative report
     * must be written depth first, and a taxa map alone cannot say where a
     * row goes. A taxon can appear as a root in one batch and with its
     * lineage in a later, deeper one, so a null parent is filled in later.
     */
    static void mergeBatchCounts(Map state, Map batchCounts) {
        (batchCounts.taxa ?: [:]).each { taxid, data ->
            def key = String.valueOf(taxid)
            if (!state.taxa.containsKey(key)) {
                state.taxa[key] = [
                    reads: 0, cumul: 0,
                    rank: data.rank, name: data.name,
                    parent: data.parent
                ]
            } else if (state.taxa[key].parent == null && data.parent != null) {
                state.taxa[key].parent = data.parent
            }
            state.taxa[key].reads += ((data.reads ?: 0) as int)
            state.taxa[key].cumul += ((data.cumul ?: 0) as int)
        }
        state.total_reads += ((batchCounts.total_reads ?: 0) as int)
        state.classified_reads += ((batchCounts.classified_reads ?: 0) as int)
        state.unclassified_reads += ((batchCounts.unclassified_reads ?: 0) as int)
    }

    static int batchIndex(String filename) {
        def m = (filename =~ /batch_(\d+)[._]/)
        return m.find() ? (m.group(1) as int) : Integer.MAX_VALUE
    }

    /**
     * Per-batch taxid counts the previous run(s) published, by sample, in
     * batch order: ``kraken2/<sample>/stats/batch_N_taxid_counts.json``.
     * Unparseable files are skipped with a warning list the caller can log.
     */
    static Map<String, List<Map>> priorTaxidCounts(String outdir, List<String> warnings = []) {
        def result = new LinkedHashMap<String, List<Map>>()
        def kraken = new File(outdir, 'kraken2')
        if (!kraken.isDirectory()) {
            return result
        }
        kraken.listFiles()?.sort { it.name }?.each { sampleDir ->
            def stats = new File(sampleDir, 'stats')
            if (!sampleDir.isDirectory() || !stats.isDirectory()) {
                return
            }
            def files = stats.listFiles({ File f -> f.name ==~ /batch_\d+_taxid_counts\.json/ } as FileFilter)
            if (!files) {
                return
            }
            def parsed = []
            files.sort { batchIndex(it.name) }.each { f ->
                try {
                    def counts = new JsonSlurper().parseText(f.text)
                    if (counts instanceof Map) {
                        parsed.add(counts)
                    }
                } catch (Exception e) {
                    warnings.add("${f}: ${e.message}")
                }
            }
            if (parsed) {
                result[sampleDir.name] = parsed
            }
        }
        return result
    }

    /**
     * The previous run(s)' published per-batch files for the final
     * aggregator, as ``[sample_id, path]`` pairs. ``subdir`` is ``batches``
     * (per-read output) or ``batch_reports`` (per-batch report); only the
     * merger's ``batch_N.`` naming is taken, not the report generator's
     * ``<sample>_batchN`` copy of the same report.
     */
    static List priorBatchFiles(String outdir, String subdir, String suffix) {
        def pairs = []
        def kraken = new File(outdir, 'kraken2')
        if (!kraken.isDirectory()) {
            return pairs
        }
        kraken.listFiles()?.sort { it.name }?.each { sampleDir ->
            def dir = new File(sampleDir, subdir)
            if (!sampleDir.isDirectory() || !dir.isDirectory()) {
                return
            }
            dir.listFiles()
                ?.findAll { it.isFile() && (it.name =~ /^batch_\d+\./).find() && it.name.endsWith('.' + suffix) }
                ?.sort { batchIndex(it.name) }
                ?.each { f -> pairs.add([sampleDir.name, Paths.get(f.absolutePath)]) }
        }
        return pairs
    }
}
