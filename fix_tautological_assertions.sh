#!/bin/bash

# Script to fix tautological assertions in nf-test files
# Replaces "assert workflow.success || workflow.failed" with proper assertions

set -e

echo "Fixing tautological assertions in nf-test files..."

# Files with tautological assertions
FILES=(
    "subworkflows/local/utils_nfcore_nanometanf_pipeline/tests/main.nf.test"
    "tests/performance_scalability_framework.nf.test"
    "tests/advanced_error_handling.nf.test"
    "tests/realtime_statistics_modules.nf.test"
    "tests/edge_cases/performance_scalability.nf.test"
    "tests/edge_cases/malformed_inputs.nf.test"
    "tests/minimal_validation.nf.test"
    "tests/core_logic_test.nf.test"
    "tests/configuration_validation.nf.test"
    "tests/test_data_generators.nf.test"
    "tests/dynamic_resource_allocation.nf.test"
    "tests/main_workflow.nf.test"
    "tests/dorado_multiplex.nf.test"
    "tests/realtime_empty_samplesheet.nf.test"
    "subworkflows/local/realtime_monitoring/tests/main.nf.test"
    "subworkflows/local/realtime_pod5_monitoring/tests/main.nf.test"
    "subworkflows/local/assembly/tests/main.nf.test"
    "subworkflows/local/validation/tests/main.nf.test"
    "subworkflows/local/taxonomic_classification/tests/main.nf.test"
    "subworkflows/local/dynamic_resource_allocation/tests/main.nf.test"
    "subworkflows/local/enhanced_realtime_monitoring/tests/main.nf.test"
    "subworkflows/local/qc_analysis/tests/main.nf.test"
)

for file in "${FILES[@]}"; do
    if [[ -f "$file" ]]; then
        echo "Processing: $file"

        # Replace tautological assertions with proper success assertion
        # Pattern 1: Direct replacement
        sed -i '' 's/assert workflow\.success || workflow\.failed/assert workflow.success/g' "$file"

        # Pattern 2: With comment
        sed -i '' 's/assert workflow\.success || workflow\.failed  *\/\/ .*/assert workflow.success/g' "$file"

        echo "  ✓ Fixed tautological assertions in $file"
    else
        echo "  ✗ File not found: $file"
    fi
done

echo ""
echo "✅ Tautological assertion fixes completed!"
echo ""
echo "Summary:"
echo "- Replaced 'assert workflow.success || workflow.failed' with 'assert workflow.success'"
echo "- Files processed: ${#FILES[@]}"
echo ""
echo "Next steps:"
echo "1. Review the changes: git diff"
echo "2. Run tests: nf-test test"
echo "3. Commit changes: git commit -m 'fix: remove tautological assertions from test suite'"
