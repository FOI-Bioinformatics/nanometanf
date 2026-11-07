/*
 * Thin wrapper for testing KreportTree via nf-test.
 * The class is auto-loaded from lib/ by Nextflow.
 *
 * Reproduces exactly what the cumulative writers do -- merge several batch
 * reports' counts, recover parentage from each batch's own row order, then
 * re-emit depth first -- and then parses the EMITTED rows back with the same
 * indent-stack rule an external kreport reader uses.
 *
 * Returning both parentages lets a test assert the property that matters: a
 * merged report must re-parse to the same tree as its sources. Sorting merged
 * rows by abundance breaks that silently, because the indentation still claims
 * a hierarchy the row order no longer supports.
 *
 * @param reports  list of reports; each report is a list of rows
 *                 [cumul, reads, rank, taxid, name] in the report's own order,
 *                 name carrying its original leading-space indentation
 * @return  [ emitted taxid order, parentage re-parsed from the emitted rows,
 *            parentage of the source reports ]
 */

def reportRoundTrip(List reports) {
    def merged = [:]
    def sourceParents = [:]

    reports.each { rows ->
        def parents = KreportTree.parentsFromRows(rows.collect { r -> [r[3], r[4]] })
        rows.each { r ->
            def taxid = r[3].toString()
            def parent = parents[taxid]
            if (!sourceParents.containsKey(taxid) || (sourceParents[taxid] == null && parent != null)) {
                sourceParents[taxid] = parent
            }
            if (!merged.containsKey(taxid)) {
                merged[taxid] = [cumul: 0L, reads: 0L, rank: r[2], name: r[4], parent: parent]
            } else if (merged[taxid].parent == null && parent != null) {
                merged[taxid].parent = parent
            }
            merged[taxid].cumul += (r[0] as long)
            merged[taxid].reads += (r[1] as long)
        }
    }

    def order = KreportTree.depthFirstOrder(merged)
    def emittedRows = order.collect { taxid -> [taxid, merged[taxid].name] }
    return [ order, KreportTree.parentsFromRows(emittedRows), sourceParents ]
}


/*
 * The taxid clade for a report, as EXTRACT_READS_BY_TAXID now selects.
 *
 * @param rows   [taxid, name] pairs in report order, indentation kept
 * @param taxid  the clade root
 * @return       sorted list of taxid Strings at or below it
 */
def cladeOfRows(List rows, String taxid) {
    return KreportTree.cladeOf(rows, taxid).sort()
}


/*
 * The percent column under a given default locale.
 *
 * Sets the JVM default locale for the duration of the call, as a field laptop
 * configured for Swedish or German would have it, and returns both the bare
 * String.format result (what the writer used to do) and KreportTree's. The
 * first proves the test exercises a comma-decimal locale; the second is the
 * property under test.
 *
 * @return [ bare String.format("%.2f") result, KreportTree.formatPercent result,
 *           KreportTree.formatRow result ]
 */
def percentUnderLocale(Object cumul, Object total, String language, String country) {
    // No try/finally: the strict v2 grammar does not allow it in a script.
    // The test JVM is disposable, and every branch below restores the locale.
    def previous = java.util.Locale.getDefault()
    java.util.Locale.setDefault(new java.util.Locale(language, country))
    def bare = String.format("%.2f", ((cumul as double) / (total as double)) * 100.0d)
    def viaTree = KreportTree.formatPercent(cumul, total)
    def row = KreportTree.formatRow('562', [cumul: cumul, reads: 3, rank: 'S', name: '  Escherichia coli'], total)
    java.util.Locale.setDefault(previous)
    return [ bare, viaTree, row ]
}
