/*
 * Utility functions for barcode extraction and validation
 */

class BarcodeUtils {

    /**
     * Extract barcode identifier from filename using regex pattern matching
     *
     * Supports common nanopore barcode patterns:
     * - barcode01, barcode1 → "barcode01"
     * - sample_barcode05.fastq → "barcode05"
     * - reads_barcode12.fastq.gz → "barcode12"
     *
     * The extracted barcode is normalized to two-digit format (e.g., barcode1 → barcode01)
     * for consistent downstream processing and sample identification.
     *
     * @param filename The filename to extract barcode from (with or without extension)
     * @return Normalized barcode string (e.g., "barcode01") or null if no barcode found
     *
     * @example
     * BarcodeUtils.extractBarcodeFromFilename("barcode01_pass.fastq")  // Returns "barcode01"
     * BarcodeUtils.extractBarcodeFromFilename("sample_barcode5.fq.gz") // Returns "barcode05"
     * BarcodeUtils.extractBarcodeFromFilename("no_barcode.fastq")      // Returns null
     */
    static String extractBarcodeFromFilename(String filename) {
        if (!filename) {
            return null
        }

        // Match "barcodeNN" or "barcodeN" pattern (case-insensitive)
        def matcher = filename =~ /(?i)barcode(\d+)/

        if (matcher.find()) {
            // Extract the numeric portion and pad to 2 digits
            def barcode_num = matcher.group(1)
            return "barcode" + barcode_num.padLeft(2, '0')
        }

        return null
    }

    /**
     * Validate barcode format against standard nanopore barcode pattern
     *
     * Valid format: barcodeNN where NN is 01-99 (two digits, zero-padded)
     *
     * @param barcode Barcode string to validate
     * @return true if barcode matches valid format, false otherwise
     *
     * @example
     * BarcodeUtils.isValidBarcode("barcode01")  // Returns true
     * BarcodeUtils.isValidBarcode("barcode1")   // Returns false (not zero-padded)
     * BarcodeUtils.isValidBarcode("bc01")       // Returns false (wrong prefix)
     * BarcodeUtils.isValidBarcode("barcode99")  // Returns true
     * BarcodeUtils.isValidBarcode("barcode100") // Returns false (three digits)
     */
    static boolean isValidBarcode(String barcode) {
        if (!barcode) {
            return false
        }

        // Match exact pattern: "barcodeNN" where NN is 01-99
        return barcode ==~ /barcode\d{2}/
    }

    /**
     * Extract and validate barcode from filename in a single operation
     *
     * Convenience method that extracts barcode and validates it's in the correct format.
     * This is useful when you want to ensure extracted barcodes are valid before processing.
     *
     * @param filename The filename to extract and validate barcode from
     * @return Normalized barcode if valid, null if not found or invalid
     *
     * @example
     * BarcodeUtils.extractAndValidateBarcode("barcode01.fastq")  // Returns "barcode01"
     * BarcodeUtils.extractAndValidateBarcode("barcode1.fastq")   // Returns "barcode01" (normalized)
     * BarcodeUtils.extractAndValidateBarcode("invalid.fastq")    // Returns null
     */
    static String extractAndValidateBarcode(String filename) {
        def barcode = extractBarcodeFromFilename(filename)

        if (barcode && isValidBarcode(barcode)) {
            return barcode
        }

        return null
    }

    /**
     * Parse barcode number from barcode string
     *
     * Extracts the numeric portion from a barcode string.
     *
     * @param barcode Barcode string in format "barcodeNN"
     * @return Integer barcode number, or null if invalid format
     *
     * @example
     * BarcodeUtils.getBarcodeNumber("barcode01")  // Returns 1
     * BarcodeUtils.getBarcodeNumber("barcode12")  // Returns 12
     * BarcodeUtils.getBarcodeNumber("barcode99")  // Returns 99
     * BarcodeUtils.getBarcodeNumber("invalid")    // Returns null
     */
    static Integer getBarcodeNumber(String barcode) {
        if (!isValidBarcode(barcode)) {
            return null
        }

        def matcher = barcode =~ /barcode(\d{2})/
        if (matcher.find()) {
            return matcher.group(1).toInteger()
        }

        return null
    }

    /**
     * Format barcode number to standard barcode string
     *
     * Converts an integer to standard barcode format with zero-padding.
     *
     * @param barcodeNum Integer barcode number (1-99)
     * @return Formatted barcode string (e.g., "barcode01"), or null if out of range
     *
     * @example
     * BarcodeUtils.formatBarcode(1)   // Returns "barcode01"
     * BarcodeUtils.formatBarcode(12)  // Returns "barcode12"
     * BarcodeUtils.formatBarcode(0)   // Returns null (out of range)
     * BarcodeUtils.formatBarcode(100) // Returns null (out of range)
     */
    static String formatBarcode(Integer barcodeNum) {
        if (barcodeNum == null || barcodeNum < 1 || barcodeNum > 99) {
            return null
        }

        return "barcode" + barcodeNum.toString().padLeft(2, '0')
    }
}
