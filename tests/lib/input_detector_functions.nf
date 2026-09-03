/*
 * Thin wrapper functions for testing InputDetector via nf-test.
 * The InputDetector class is auto-loaded from lib/ by Nextflow.
 */

def detectStructure(String dirPath) {
    return InputDetector.detectStructure(dirPath)
}

def extractSampleId(String filePath, String regex = null, String sampleName = null, String inputRoot = null) {
    return InputDetector.extractSampleId(filePath, regex, sampleName, inputRoot)
}

def sampleSubdirs(String dirPath) {
    return InputDetector.sampleSubdirs(dirPath).collect { it.name }
}
