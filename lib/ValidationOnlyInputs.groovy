import java.nio.file.Path

/*
 * Sample discovery for the --validation_only entry (main.nf, VALIDATION_ONLY),
 * which Nanometa Live's on-demand validation runs against an existing outdir.
 *
 * Two classifier layouts publish into ``<outdir>/kraken2/``:
 *
 *  - standard (KRAKEN2_KRAKEN2): ``<sample>.kraken2.output.txt`` and
 *    ``<sample>.kraken2.report.txt``;
 *  - incremental (real time, chunked batch mode -- the default -- and
 *    kraken2_enable_incremental): KRAKEN2_FINAL_AGGREGATOR writes the
 *    end-of-session ``<sample>.cumulative.kraken2.output.txt`` and
 *    ``<sample>.cumulative.kraken2.report.txt``, and the only flat
 *    ``<sample>.kraken2.report.txt`` is EMIT_EMPTY_KRAKEN2_REPORT's
 *    zero-read placeholder for a batch that produced nothing.
 *
 * Until 2026-11 the entry globbed ``*.kraken2.output.txt`` and took the stem
 * as the sample id, so the incremental layout yielded a sample called
 * ``barcode01.cumulative`` that matched no read pool, and the run finished
 * with nothing validated (bug audit 2026-11-06, finding 4). The stem is the
 * sample id once the ``.cumulative`` marker is stripped; where both files
 * exist the cumulative one is the complete one and wins.
 */
class ValidationOnlyInputs {

    static final String CUMULATIVE_MARKER = '.cumulative'

    /**
     * One ``[sample_id, path]`` per sample from files ending in ``suffix``,
     * preferring the ``<sample>.cumulative<suffix>`` file over
     * ``<sample><suffix>`` when a sample has both. Sorted by sample id.
     */
    static List perSample(Collection paths, String suffix) {
        def chosen = [:]
        (paths ?: []).each { p ->
            def name = (p instanceof Path) ? p.fileName.toString() : new File(p.toString()).name
            if (!name.endsWith(suffix) || name.length() <= suffix.length()) {
                return
            }
            def stem = name.substring(0, name.length() - suffix.length())
            def cumulative = stem.endsWith(CUMULATIVE_MARKER)
            def id = cumulative ? stem.substring(0, stem.length() - CUMULATIVE_MARKER.length()) : stem
            if (!id) {
                return
            }
            def current = chosen[id]
            if (current == null || (cumulative && !current.cumulative)) {
                chosen[id] = [path: p, cumulative: cumulative]
            }
        }
        return chosen.keySet().sort().collect { id -> [id, chosen[id].path] }
    }
}
