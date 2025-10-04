#!/usr/bin/env bash
#
# Migrate Module Tests to Use Fixtures
#
# This script migrates nf-test files from using inline setup blocks
# to using centralized fixture files for better maintainability.

set -euo pipefail

echo "🔄 Migrating module tests to use fixtures..."
echo ""

MIGRATIONS_APPLIED=0
TESTS_ANALYZED=0

# Map of common setup patterns to fixture files
declare -A FIXTURE_MAP=(
    ["small_fastq"]="tests/fixtures/characteristics/small_fastq.json"
    ["medium_fastq"]="tests/fixtures/characteristics/medium_fastq.json"
    ["large_fastq"]="tests/fixtures/characteristics/large_fastq.json"
    ["pod5_typical"]="tests/fixtures/characteristics/pod5_typical.json"
    ["empty_file"]="tests/fixtures/characteristics/empty_file.json"
    ["minimal_file"]="tests/fixtures/characteristics/minimal_file.json"
    ["balanced_prediction"]="tests/fixtures/predictions/balanced_prediction.json"
    ["conservative_prediction"]="tests/fixtures/predictions/conservative_prediction.json"
    ["high_throughput_prediction"]="tests/fixtures/predictions/high_throughput_prediction.json"
    ["snapshot_batch"]="tests/fixtures/statistics/snapshot_batch_001.json"
    ["cumulative_session"]="tests/fixtures/statistics/cumulative_session_001.json"
    ["normal_load"]="tests/fixtures/system_metrics/normal_load.json"
    ["high_load"]="tests/fixtures/system_metrics/high_load.json"
    ["gpu_available"]="tests/fixtures/system_metrics/gpu_available.json"
)

# Function to identify which fixture matches a setup block
identify_fixture() {
    local setup_content="$1"

    # Check for size indicators
    if echo "$setup_content" | grep -q '"total_size_bytes": 10485760'; then
        echo "small_fastq"
    elif echo "$setup_content" | grep -q '"total_size_bytes": 52428800'; then
        echo "medium_fastq"
    elif echo "$setup_content" | grep -q '"total_size_bytes": 104857600'; then
        echo "large_fastq"
    elif echo "$setup_content" | grep -q 'pod5'; then
        echo "pod5_typical"
    elif echo "$setup_content" | grep -q 'prediction.*conservative'; then
        echo "conservative_prediction"
    elif echo "$setup_content" | grep -q 'prediction.*high_throughput'; then
        echo "high_throughput_prediction"
    elif echo "$setup_content" | grep -q 'snapshot'; then
        echo "snapshot_batch"
    elif echo "$setup_content" | grep -q 'cumulative'; then
        echo "cumulative_session"
    elif echo "$setup_content" | grep -q 'gpu.*true'; then
        echo "gpu_available"
    elif echo "$setup_content" | grep -q 'load.*high'; then
        echo "high_load"
    else
        echo "balanced_prediction"  # default
    fi
}

# Analyze test files
echo "Analyzing test files with setup blocks..."
while IFS= read -r test_file; do
    ((TESTS_ANALYZED++))
    module_name=$(echo "$test_file" | sed 's|modules/local/||' | sed 's|/tests/main.nf.test||')

    # Count setup blocks
    setup_count=$(grep -c "setup {" "$test_file" 2>/dev/null || echo "0")

    if [ "$setup_count" -gt 0 ]; then
        echo "  📋 $module_name: $setup_count setup block(s) found"
    fi
done < <(find modules/local -name "main.nf.test" -type f 2>/dev/null)

echo ""
echo "Summary:"
echo "  Tests analyzed: $TESTS_ANALYZED"
echo ""
echo "Migration Strategy:"
echo "  1. Replace inline JSON in setup blocks with fixture references"
echo "  2. Use file() references to existing fixtures"
echo "  3. Remove redundant file creation code"
echo "  4. Maintain test functionality"
echo ""
echo "Fixture locations:"
for key in "${!FIXTURE_MAP[@]}"; do
    echo "  - ${key}: ${FIXTURE_MAP[$key]}"
done
echo ""
echo "To apply migrations, tests should be updated to use:"
echo '  file("$projectDir/tests/fixtures/characteristics/small_fastq.json")'
echo "  instead of inline JSON in setup blocks."
echo ""
echo "✅ Analysis complete. Ready for manual migration."
