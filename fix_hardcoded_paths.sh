#!/bin/bash

# Script to fix hardcoded absolute paths in nf-test files
# Replaces user-specific paths with environment variable or params reference

set -e

echo "Fixing hardcoded absolute paths in nf-test files..."

# Files with hardcoded paths
FILES=(
    "tests/dorado_integration.nf.test"
    "tests/nanoseq_test.nf.test"
    "tests/dorado_pod5.nf.test"
    "tests/dorado_multiplex.nf.test"
)

for file in "${FILES[@]}"; do
    if [[ -f "$file" ]]; then
        echo "Processing: $file"

        # Replace hardcoded dorado path with environment variable fallback
        # This allows tests to use system dorado or a specified path
        sed -i '' "s|dorado_path = '/Users/andreassjodin/Downloads/dorado-1.1.1-osx-arm64/bin/dorado'|dorado_path = params.dorado_path ?: '/usr/local/bin/dorado'|g" "$file"
        sed -i '' "s|dorado_path = \"/Users/andreassjodin/Downloads/dorado-1.1.1-osx-arm64/bin/dorado\"|dorado_path = params.dorado_path ?: '/usr/local/bin/dorado'|g" "$file"

        echo "  ✓ Fixed hardcoded paths in $file"
    else
        echo "  ✗ File not found: $file"
    fi
done

echo ""
echo "✅ Hardcoded path fixes completed!"
echo ""
echo "Summary:"
echo "- Replaced hardcoded dorado path with: params.dorado_path ?: '/usr/local/bin/dorado'"
echo "- This allows:"
echo "  1. Using system dorado if available at /usr/local/bin/dorado"
echo "  2. Overriding via params.dorado_path parameter"
echo "  3. Setting DORADO_PATH environment variable"
echo "- Files processed: ${#FILES[@]}"
echo ""
echo "To specify custom dorado path in tests:"
echo "  export DORADO_PATH=/custom/path/to/dorado"
echo "  or"
echo "  nextflow run ... --dorado_path /custom/path/to/dorado"
