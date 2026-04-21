#!/usr/bin/env bash
#
# apply_tags.sh - Helper script to apply tags to nf-test test files
#
# This script helps developers quickly apply the new tag system to test files
# by analyzing the test file location and content to suggest appropriate tags.
#
# Usage:
#   ./tests/scripts/apply_tags.sh <test_file.nf.test>
#   ./tests/scripts/apply_tags.sh --dry-run <test_file.nf.test>
#   ./tests/scripts/apply_tags.sh --batch-modules
#   ./tests/scripts/apply_tags.sh --batch-subworkflows
#
# Options:
#   --dry-run           Show suggested tags without modifying file
#   --batch-modules     Process all module tests
#   --batch-subworkflows Process all subworkflow tests
#   --help              Show this help message

set -eo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

show_help() {
    cat << EOF
apply_tags.sh - Helper script to apply tags to nf-test test files

Usage:
  ./tests/scripts/apply_tags.sh [OPTIONS] <test_file.nf.test>

Options:
  --dry-run              Show suggested tags without modifying file
  --batch-modules        Process all module tests
  --batch-subworkflows   Process all subworkflow tests
  --help                 Show this help message

Examples:
  # Analyze and suggest tags for a single test
  ./tests/scripts/apply_tags.sh --dry-run modules/local/kraken2/tests/main.nf.test

  # Apply tags to all module tests (interactive)
  ./tests/scripts/apply_tags.sh --batch-modules

  # Apply tags to all subworkflow tests (interactive)
  ./tests/scripts/apply_tags.sh --batch-subworkflows

Tag Categories (Required):
  1. Level:       module, subworkflow, workflow, pipeline, integration
  2. Name:        Component name (e.g., kraken2, qc_analysis)
  3. Feature:     realtime, qc, classification, validation
  4. Speed:       fast (<30s), medium (30s-5min), slow (>5min)
  5. Criticality: core (must pass), extended (should pass), experimental (may fail)

For detailed tagging guide, see: tests/TAGGING_GUIDE.md
For tag specification, see: tests/tags.yml

EOF
}

detect_test_level() {
    local test_file="$1"

    if echo "$test_file" | grep -q "modules/"; then
        echo "module"
    elif echo "$test_file" | grep -q "subworkflows/"; then
        echo "subworkflow"
    elif echo "$test_file" | grep -q "tests/.*\.nf\.test"; then
        # Top-level tests directory = pipeline tests
        echo "pipeline"
    else
        echo "unknown"
    fi
}

detect_component_name() {
    local test_file="$1"

    # Extract component name from path
    # modules/local/kraken2/tests/main.nf.test -> kraken2
    # subworkflows/local/qc_analysis/tests/main.nf.test -> qc_analysis

    if echo "$test_file" | grep -q "modules/local/"; then
        echo "$test_file" | sed -E 's|.*modules/local/([^/]+)/tests/.*|\1|'
    elif echo "$test_file" | grep -q "modules/nf-core/"; then
        echo "$test_file" | sed -E 's|.*modules/nf-core/([^/]+)/tests/.*|\1|'
    elif echo "$test_file" | grep -q "subworkflows/local/"; then
        echo "$test_file" | sed -E 's|.*subworkflows/local/([^/]+)/tests/.*|\1|'
    elif echo "$test_file" | grep -q "subworkflows/nf-core/"; then
        echo "$test_file" | sed -E 's|.*subworkflows/nf-core/([^/]+)/tests/.*|\1|'
    else
        # Try to extract from filename
        basename "$test_file" .nf.test | sed 's/_test$//'
    fi
}

detect_feature_area() {
    local test_file="$1"
    local component_name="$2"

    # Heuristics based on component name and path
    case "$component_name" in
        *realtime*|*monitoring*|*adaptive*|*priority*)
            echo "realtime"
            ;;
        *kraken*|*classification*|*taxonomic*)
            echo "classification"
            ;;
        *qc*|*fastp*|*chopper*|*filtlong*|*nanoplot*|*fastqc*)
            echo "qc"
            ;;
        *blast*|*validation*)
            echo "validation"
            ;;
        *barcode*|*demux*)
            echo "barcode_discovery"
            ;;
        *resource*|*dynamic*)
            echo "resource_allocation"
            ;;
        *error*|*circuit*|*retry*)
            echo "error_handling"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

detect_speed() {
    local test_file="$1"

    # Check if test uses stub mode
    if grep -q 'options "-stub"' "$test_file" 2>/dev/null; then
        echo "fast"
        return
    fi

    # Check for max_time parameter hints
    if grep -q "max_time = '1" "$test_file" 2>/dev/null; then
        echo "fast"
    elif grep -q "max_time = '[2-5]" "$test_file" 2>/dev/null; then
        echo "medium"
    else
        # Default based on test level
        local level
        level=$(detect_test_level "$test_file")
        case "$level" in
            module)
                echo "fast"
                ;;
            subworkflow)
                echo "medium"
                ;;
            pipeline)
                echo "slow"
                ;;
            *)
                echo "medium"
                ;;
        esac
    fi
}

detect_criticality() {
    local feature="$1"

    # Core features
    case "$feature" in
        qc|classification|realtime)
            echo "core"
            ;;
        validation|barcode_discovery)
            echo "extended"
            ;;
        resource_allocation|error_handling)
            echo "experimental"
            ;;
        *)
            echo "core"
            ;;
    esac
}

suggest_tags() {
    local test_file="$1"

    echo -e "${BLUE}Analyzing test file: $test_file${NC}"

    if [[ ! -f "$test_file" ]]; then
        echo -e "${RED}Error: File not found: $test_file${NC}"
        return 1
    fi

    # Detect tags
    local level component feature speed criticality
    level=$(detect_test_level "$test_file")
    component=$(detect_component_name "$test_file")
    feature=$(detect_feature_area "$test_file" "$component")
    speed=$(detect_speed "$test_file")
    criticality=$(detect_criticality "$feature")

    # Check for stub mode
    local has_stub=""
    if grep -q 'options "-stub"' "$test_file" 2>/dev/null; then
        has_stub="stub"
    fi

    # Check for snapshot testing
    local has_snapshot=""
    if grep -q 'snapshot(' "$test_file" 2>/dev/null; then
        has_snapshot="snapshot"
    fi

    echo -e "${GREEN}Suggested tags:${NC}"
    echo "  Level:       $level"
    echo "  Component:   $component"
    echo "  Feature:     $feature"
    echo "  Speed:       $speed"
    echo "  Criticality: $criticality"

    if [[ -n "$has_stub" ]]; then
        echo "  Optional:    $has_stub (detected stub tests)"
    fi
    if [[ -n "$has_snapshot" ]]; then
        echo "  Optional:    $has_snapshot (detected snapshot tests)"
    fi

    echo ""
    echo -e "${YELLOW}Groovy tag block:${NC}"
    cat << EOF
    // Test Level & Component
    tag "$level"
    tag "$component"

    // Feature Area
    tag "$feature"

    // Execution Speed & Criticality
    tag "$speed"
    tag "$criticality"
EOF

    if [[ -n "$has_stub" || -n "$has_snapshot" ]]; then
        echo ""
        echo "    // Test Type"
        [[ -n "$has_stub" ]] && echo "    tag \"$has_stub\""
        [[ -n "$has_snapshot" ]] && echo "    tag \"$has_snapshot\""
    fi

    echo ""
}

apply_tags() {
    local test_file="$1"

    # First show suggestions
    suggest_tags "$test_file"

    # Ask for confirmation
    echo -e "${YELLOW}Apply these tags to $test_file? (y/n)${NC}"
    read -r response

    if [[ "$response" != "y" ]]; then
        echo "Skipped."
        return 0
    fi

    # TODO: Implement actual tag insertion
    # This requires careful parsing of the test file structure
    echo -e "${RED}Automatic tag application not yet implemented.${NC}"
    echo -e "${YELLOW}Please manually add tags to the test file.${NC}"
    echo "See tests/TAGGING_GUIDE.md for examples."
}

batch_process() {
    local pattern="$1"
    local file
    local count=0

    echo -e "${BLUE}Searching for test files matching pattern: $pattern${NC}"
    echo ""

    # Process files as they're found
    while IFS= read -r file; do
        count=$((count + 1))
        # Check if file already has new tag system
        if grep -q 'tag "module"' "$file" || \
           grep -q 'tag "subworkflow"' "$file" || \
           grep -q 'tag "pipeline"' "$file"; then
            echo -e "${GREEN}✓ Skipping (already tagged): $file${NC}"
            continue
        fi

        echo "---"
        suggest_tags "$file"
        echo ""
    done < <(find "$PROJECT_ROOT" -path "*/$pattern/*" -name "main.nf.test" 2>/dev/null || true)

    echo -e "${GREEN}Processed $count test files${NC}"
}

# Main script
main() {
    local dry_run=false
    local batch_mode=""
    local test_file=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --batch-modules)
                batch_mode="modules"
                shift
                ;;
            --batch-subworkflows)
                batch_mode="subworkflows"
                shift
                ;;
            *)
                test_file="$1"
                shift
                ;;
        esac
    done

    # Execute based on mode
    if [[ -n "$batch_mode" ]]; then
        case "$batch_mode" in
            modules)
                batch_process "modules/local/*/tests"
                ;;
            subworkflows)
                batch_process "subworkflows/local/*/tests"
                ;;
        esac
    elif [[ -n "$test_file" ]]; then
        if [[ "$dry_run" == true ]]; then
            suggest_tags "$test_file"
        else
            apply_tags "$test_file"
        fi
    else
        show_help
        exit 1
    fi
}

main "$@"
