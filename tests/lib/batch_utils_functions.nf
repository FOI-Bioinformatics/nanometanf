/*
 * Thin wrapper functions for testing BatchUtils via nf-test.
 * The BatchUtils class is auto-loaded from lib/ by Nextflow.
 */

def interleaveFilesByParentDir(List files) {
    return BatchUtils.interleaveFilesByParentDir(files)
}
