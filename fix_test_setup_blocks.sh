#!/bin/bash

# Script to fix nf-test setup block syntax issues

echo "🔧 Fixing nf-test setup block syntax issues..."

# Array of files to check (excluding dorado_basecaller which we already fixed)
files=(
    "/Users/andreassjodin/Code/nanometanf/modules/local/generate_snapshot_stats/tests/main.nf.test"
    "/Users/andreassjodin/Code/nanometanf/modules/local/resource_feedback_learning/tests/main.nf.test"
    "/Users/andreassjodin/Code/nanometanf/modules/local/update_cumulative_stats/tests/main.nf.test"
    "/Users/andreassjodin/Code/nanometanf/modules/local/optimize_resource_allocation/tests/main.nf.test"
    "/Users/andreassjodin/Code/nanometanf/modules/local/apply_dynamic_resources/tests/main.nf.test"
    "/Users/andreassjodin/Code/nanometanf/modules/local/monitor_system_resources/tests/main.nf.test"
    "/Users/andreassjodin/Code/nanometanf/modules/local/resource_optimization_profiles/tests/main.nf.test"
    "/Users/andreassjodin/Code/nanometanf/modules/local/pipeline_validator/tests/main.nf.test"
    "/Users/andreassjodin/Code/nanometanf/modules/local/error_handler/tests/main.nf.test"
    "/Users/andreassjodin/Code/nanometanf/modules/local/generate_realtime_report/tests/main.nf.test"
    "/Users/andreassjodin/Code/nanometanf/modules/local/predict_resource_requirements/tests/main.nf.test"
    "/Users/andreassjodin/Code/nanometanf/modules/local/analyze_input_characteristics/tests/main.nf.test"
    "/Users/andreassjodin/Code/nanometanf/modules/local/dorado_demux/tests/main.nf.test"
)

for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
        echo "📝 Checking file: $(basename $file)"
        
        # Check if file has setup blocks with individual script calls
        if grep -q "setup {" "$file" && grep -q "script \"" "$file"; then
            echo "  ⚠️  Found problematic setup blocks in $file"
            
            # Show the problematic lines
            echo "  🔍 Problem lines:"
            grep -n "script \"" "$file" | grep -v "script \"../main.nf\"" | head -5
        else
            echo "  ✅ No problematic setup blocks found"
        fi
    else
        echo "  ❌ File not found: $file"
    fi
    echo ""
done

echo "🎯 Manual fixes needed for files with individual script calls in setup blocks"
echo "   Replace patterns like:"
echo "     script \"mkdir -p \$outputDir/test\""
echo "   With proper script blocks:"
echo "     \"\"\""
echo "     mkdir -p \$outputDir/test"
echo "     \"\"\""