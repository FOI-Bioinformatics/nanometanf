#!/bin/bash

# Fix workflow.duration assertions that don't exist in nf-test
# These assertions were checking test execution time but workflow.duration property doesn't exist

FILES=(
    "tests/advanced_error_handling.nf.test"
    "tests/configuration_validation.nf.test"
    "tests/core_logic_test.nf.test"
    "tests/dynamic_resource_allocation.nf.test"
    "tests/edge_cases/malformed_inputs.nf.test"
    "tests/edge_cases/performance_scalability.nf.test"
    "tests/minimal_validation.nf.test"
    "tests/performance_scalability_framework.nf.test"
    "tests/realtime_processing.nf.test"
    "tests/realtime_statistics_modules.nf.test"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "Fixing $file"
        # Comment out duration assertions
        sed -i '' 's/^\([[:space:]]*\)assert workflow\.duration\./\1\/\/ REMOVED: workflow.duration property not available in nf-test\n\1\/\/ assert workflow.duration./g' "$file"
    fi
done

echo "Duration assertions fixed in all files"
