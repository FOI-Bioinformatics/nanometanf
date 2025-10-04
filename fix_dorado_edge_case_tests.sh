#!/bin/bash

# Script to fix DORADO_BASECALLER edge case tests
# Removes incorrect input[2] and input[3] parameters

FILE="tests/edge_cases/dorado_basecaller_edge_cases.nf.test"

echo "Fixing DORADO_BASECALLER edge case tests..."

# Use perl for multi-line pattern matching and replacement
perl -i.bak -0pe '
    # Pattern 1: Remove input[2] and input[3] lines before closing """
    s/(\s+input\[1\]\s*=\s*[^\n]+\n)\s+input\[2\]\s*=\s*[^\n]+\n\s+input\[3\]\s*=\s*\[\s*\n(?:\s+[^\]]+\n)*\s+\]\s*\n(\s+""")/$1$2/g;

    # Pattern 2: Single-line input[3]
    s/(\s+input\[1\]\s*=\s*[^\n]+\n)\s+input\[2\]\s*=\s*[^\n]+\n\s+input\[3\]\s*=\s*\[[^\]]+\]\s*\n(\s+""")/$1$2/g;
' "$FILE"

echo "✓ Removed input[2] and input[3] from all edge case tests"
echo "Original file backed up as: ${FILE}.bak"
echo ""
echo "Summary of changes:"
diff -u "${FILE}.bak" "$FILE" | grep "^-.*input\[" | wc -l | xargs echo "  Lines removed:"
