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
