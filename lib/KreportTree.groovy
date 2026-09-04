/**
 * Depth-first row ordering for merged Kraken2 reports.
 *
 * A Kraken2 report encodes its taxonomy as two things at once: the rows are in
 * depth-first order, and the name column is indented two spaces per rank level.
 * Neither alone is enough -- an indent-stack parser (the standard way to read a
 * kreport, used by Pavian, KrakenTools and the Nanometa Live loaders)
 * reconstructs each row's parent by looking at the nearest PRECEDING row with a
 * smaller indent. Reordering the rows while keeping the indentation therefore
 * does not merely reshuffle the file, it re-parents the tree: a species sorted
 * above its own genus is read as a child of whatever now precedes it.
 *
 * The cumulative writers used to sort merged taxa by descending cumulative
 * reads, which is valid within a set of siblings and wrong across the tree.
 * This class rebuilds the parent links from the source reports' own row order
 * (parentsFromRows) and re-emits them depth first (depthFirstOrder), so an
 * indent-stack parse of the merged report yields the same parentage as a parse
 * of the source reports.
 *
 * Siblings are ordered by descending cumulative reads with the taxid as
 * tiebreak. That keeps the "most abundant first" readability the old sort was
 * reaching for, matches Kraken2's own sibling convention, and -- unlike
 * first-seen order -- makes the output a pure function of the merged counts.
 * Row order must not depend on which batch happened to finish first, because in
 * a realtime run that order is nondeterministic.
 *
 * Pure and side-effect free: every method returns new collections and mutates
 * nothing shared, so it is safe to call from the Nextflow head process.
 */
class KreportTree {

    /**
     * Leading-space count of a Kraken2 report name field (two spaces per rank).
     *
     * @param name  the sixth column of a report row, indentation included
     * @return      number of leading spaces, 0 for null or an unindented name
     */
    static int indentOf(Object name) {
        def s = name == null ? '' : name.toString()
        int i = 0
        while (i < s.length() && s.charAt(i) == ' ' as char) {
            i++
        }
        return i
    }

    /**
     * Parent taxid per row, recovered from one report's own row order.
     *
     * @param rows  list of [taxid, name] pairs in the report's depth-first
     *              order, name carrying its original indentation
     * @return      map of taxid (String) -> parent taxid (String) or null for a
     *              root row; the first occurrence of a taxid wins
     */
    static Map parentsFromRows(List rows) {
        def parents = [:]
        def stack = []
        rows.each { row ->
            if (row == null || row.size() < 1 || row[0] == null) {
                return
            }
            def taxid = row[0].toString()
            int ind = indentOf(row.size() > 1 ? row[1] : '')
            while (!stack.isEmpty() && stack[-1][0] >= ind) {
                stack.remove(stack.size() - 1)
            }
            if (!parents.containsKey(taxid)) {
                parents[taxid] = stack.isEmpty() ? null : stack[-1][1]
            }
            stack.add([ind, taxid])
        }
        return parents
    }

    /**
     * Rows of [taxid, name] from a Kraken2 report file, indentation kept.
     *
     * @param reportPath  path to a Kraken2 report, or null
     * @return            list of [taxid, name] pairs in report order; empty
     *                    when the file cannot be read
     */
    static List rowsFromReport(Object reportPath) {
        def rows = []
        if (reportPath == null) {
            return rows
        }
        def f = reportPath instanceof File ? reportPath : new File(reportPath.toString())
        if (!f.exists()) {
            return rows
        }
        try {
            f.eachLine { line ->
                def parts = line.split('\t')
                if (parts.length >= 6) {
                    rows.add([parts[4], parts[5]])
                }
            }
        } catch (Exception ignored) {
            return []
        }
        return rows
    }

    /**
     * Every taxid at or below `taxid`, itself included.
     *
     * Kraken2 assigns each read to the most specific node it can, so an
     * organism's reads scatter across its species node and its subspecies.
     * Selecting on the exact taxid therefore takes only part of the organism:
     * measured on a real report, 279 of the 1,051 reads of *F. tularensis*
     * sat on the species node and the other 772 on `holarctica` and
     * `tularensis` below it (nanometa_live assembly audit, 2026-09-03, A5b).
     * Anything judging an organism -- confirmatory alignment, an assembly, a
     * depth estimate -- wants the clade, not the node.
     *
     * This mirrors the species-includes-subspecies rule Nanometa Live applies
     * on its own side in core/taxonomy/ranks.py.
     *
     * @param rows   [taxid, name] pairs in report order, indentation kept
     * @param taxid  the clade root
     * @return       set of taxid Strings; just the input when it is absent or
     *               has no descendants
     */
    static Set cladeOf(List rows, Object taxid) {
        def want = taxid == null ? '' : taxid.toString()
        def members = [want] as Set
        if (!want || rows == null) {
            return members
        }
        int rootIndent = -1
        rows.each { row ->
            if (row == null || row.size() < 1 || row[0] == null) {
                return
            }
            int ind = indentOf(row.size() > 1 ? row[1] : '')
            if (rootIndent < 0) {
                if (row[0].toString() == want) {
                    rootIndent = ind
                }
                return
            }
            // Past the root: everything indented deeper belongs to it, and
            // the first row at or above its depth ends the clade.
            if (ind <= rootIndent) {
                rootIndent = -2
                return
            }
            if (rootIndent >= 0) {
                members.add(row[0].toString())
            }
        }
        return members
    }

    /**
     * Depth-first taxid order over a merged taxa map.
     *
     * @param taxa  map of taxid -> map carrying at least `cumul` (number) and
     *              `parent` (taxid or null)
     * @return      list of taxid Strings in depth-first order, siblings by
     *              descending cumul then taxid
     */
    static List depthFirstOrder(Map taxa) {
        if (!taxa) {
            return []
        }
        def keys = taxa.keySet().collect { it.toString() } as Set

        // Group children under their parent. A parent that is missing from the
        // merged set, or a row that claims itself as its own parent, is treated
        // as a root rather than dropped -- a malformed link must not cost a taxon.
        def children = [:]
        taxa.each { taxid, data ->
            def self = taxid.toString()
            def parent = data instanceof Map && data.parent != null ? data.parent.toString() : null
            if (parent == null || parent == self || !keys.contains(parent)) {
                parent = null
            }
            children.get(parent, []).add(self)
        }

        def cumulOf = { String t ->
            def data = taxa[t]
            def value = data instanceof Map ? data.cumul : null
            return value == null ? 0L : (value as long)
        }
        def bySize = { String a, String b ->
            long ca = cumulOf(a)
            long cb = cumulOf(b)
            return ca != cb ? (cb <=> ca) : (a <=> b)
        }
        children.each { parent, kids -> kids.sort(bySize) }

        // Iterative pre-order walk. Pushing the reversed child list means the
        // highest-ranked sibling is popped first, so the emitted order is
        // parent, then each subtree in sibling order.
        def ordered = []
        def visited = new HashSet()
        def pending = new ArrayDeque()
        (children[null] ?: []).reverse().each { pending.push(it) }
        while (!pending.isEmpty()) {
            def taxid = pending.pop()
            if (!visited.add(taxid)) {
                continue
            }
            ordered.add(taxid)
            (children[taxid] ?: []).reverse().each { pending.push(it) }
        }

        // Anything the walk could not reach (a cycle in the recovered links)
        // is appended rather than silently lost.
        keys.toList().sort().each { taxid ->
            if (visited.add(taxid)) {
                ordered.add(taxid)
            }
        }
        return ordered
    }
}
