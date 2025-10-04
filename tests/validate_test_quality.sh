#!/usr/bin/env bash
#
# Automated Test Quality Validation for nanometanf Pipeline
#
# This script performs comprehensive quality checks on the nf-test suite to ensure:
# - Stub blocks have complete output structures
# - Snapshot testing coverage is adequate
# - Test files are reasonably sized
# - Edge case coverage exists
# - Test fixtures are being used
#
# Usage:
#   bash tests/validate_test_quality.sh [--strict] [--report-file output.txt]
#
# Exit codes:
#   0 - All quality checks passed
#   1 - Critical quality issues found
#   2 - Warnings detected (non-blocking)

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STRICT_MODE=false
REPORT_FILE=""
MAX_TEST_FILE_LINES=300
MIN_SNAPSHOT_COVERAGE=60
MIN_FIXTURE_ADOPTION=50

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --strict)
            STRICT_MODE=true
            shift
            ;;
        --report-file)
            REPORT_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--strict] [--report-file output.txt]"
            exit 1
            ;;
    esac
done

# Initialize counters
CRITICAL_ISSUES=0
WARNINGS=0
CHECKS_PASSED=0

# Output functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((CHECKS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
    ((CRITICAL_ISSUES++))
}

# Start validation
echo "=========================================="
echo "🔍 nanometanf Test Suite Quality Validation"
echo "=========================================="
echo ""

#
# Check 1: Stub Block Completeness
#
log_info "Check 1: Validating stub block completeness..."

STUB_ISSUES=""
while IFS= read -r module_file; do
    if grep -q "stub:" "$module_file" 2>/dev/null; then
        # Extract stub block and count lines
        stub_lines=$(sed -n '/stub:/,/^"""/p' "$module_file" | wc -l | tr -d ' ')

        # Stub should have reasonable length (not just placeholder)
        if [ "$stub_lines" -lt 5 ]; then
            STUB_ISSUES="${STUB_ISSUES}${module_file}: Stub block too minimal (${stub_lines} lines)\n"
        fi

        # Check if stub creates output files
        if ! sed -n '/stub:/,/^"""/p' "$module_file" | grep -q -E "(echo|cat|>)"; then
            STUB_ISSUES="${STUB_ISSUES}${module_file}: Stub block doesn't create output files\n"
        fi
    fi
done < <(find modules/local -name "main.nf" -type f 2>/dev/null)

if [ -n "$STUB_ISSUES" ]; then
    log_error "Stub block issues found:"
    echo -e "$STUB_ISSUES" | while read -r line; do
        [ -n "$line" ] && echo "  - $line"
    done
else
    log_success "All stub blocks are complete"
fi

#
# Check 2: Snapshot Test Coverage
#
log_info "Check 2: Checking snapshot test coverage..."

# Count modules with tests
MODULES_WITH_TESTS=$(find modules/local -type f -name "main.nf.test" 2>/dev/null | wc -l | tr -d ' ')

# Count modules using snapshot testing
MODULES_WITH_SNAPSHOTS=0
if [ "$MODULES_WITH_TESTS" -gt 0 ]; then
    while IFS= read -r test_file; do
        if grep -q "snapshot(" "$test_file" 2>/dev/null; then
            ((MODULES_WITH_SNAPSHOTS++))
        fi
    done < <(find modules/local -type f -name "main.nf.test" 2>/dev/null)
fi

if [ "$MODULES_WITH_TESTS" -gt 0 ]; then
    SNAPSHOT_COVERAGE=$((MODULES_WITH_SNAPSHOTS * 100 / MODULES_WITH_TESTS))
    echo "  Snapshot coverage: ${SNAPSHOT_COVERAGE}% (${MODULES_WITH_SNAPSHOTS}/${MODULES_WITH_TESTS} modules)"

    if [ "$SNAPSHOT_COVERAGE" -ge "$MIN_SNAPSHOT_COVERAGE" ]; then
        log_success "Snapshot coverage meets ${MIN_SNAPSHOT_COVERAGE}% target"
    elif [ "$SNAPSHOT_COVERAGE" -ge 30 ]; then
        log_warning "Snapshot coverage ${SNAPSHOT_COVERAGE}% below ${MIN_SNAPSHOT_COVERAGE}% target"
    else
        log_error "Snapshot coverage ${SNAPSHOT_COVERAGE}% critically low (target: ${MIN_SNAPSHOT_COVERAGE}%)"
    fi
else
    log_warning "No module tests found"
fi

#
# Check 3: Test File Size
#
log_info "Check 3: Checking test file sizes..."

LARGE_TESTS=$(find tests -name "*.nf.test" -type f 2>/dev/null | while read -r test_file; do
    lines=$(wc -l < "$test_file" | tr -d ' ')
    if [ "$lines" -gt "$MAX_TEST_FILE_LINES" ]; then
        echo "${test_file}: ${lines} lines (exceeds ${MAX_TEST_FILE_LINES})"
    fi
done)

if [ -n "$LARGE_TESTS" ]; then
    log_warning "Large test files found (consider decomposition):"
    echo "$LARGE_TESTS" | while read -r line; do
        [ -n "$line" ] && echo "  - $line"
    done
else
    log_success "All test files under ${MAX_TEST_FILE_LINES} lines"
fi

#
# Check 4: Edge Case Coverage
#
log_info "Check 4: Checking edge case test coverage..."

EDGE_CASE_TESTS=$(find tests/edge_cases -name "*.nf.test" -type f 2>/dev/null | wc -l | tr -d ' ')
echo "  Edge case test files: ${EDGE_CASE_TESTS}"

if [ "$EDGE_CASE_TESTS" -ge 5 ]; then
    log_success "Good edge case coverage (${EDGE_CASE_TESTS} test files)"
elif [ "$EDGE_CASE_TESTS" -ge 3 ]; then
    log_warning "Limited edge case coverage (${EDGE_CASE_TESTS} test files, recommend 5+)"
else
    log_warning "Minimal edge case coverage (${EDGE_CASE_TESTS} test files)"
fi

#
# Check 5: Test Fixture Usage
#
log_info "Check 5: Checking test fixture adoption..."

# Count test files using fixtures
TESTS_USING_FIXTURES=$(grep -r "projectDir/tests/fixtures" tests/ 2>/dev/null | wc -l | tr -d ' ')

# Count total test assertions
TOTAL_TESTS=$(grep -r "test(\"" tests/ 2>/dev/null | wc -l | tr -d ' ')

if [ "$TOTAL_TESTS" -gt 0 ]; then
    FIXTURE_ADOPTION=$((TESTS_USING_FIXTURES * 100 / TOTAL_TESTS))
    echo "  Fixture adoption: ${FIXTURE_ADOPTION}% (${TESTS_USING_FIXTURES}/${TOTAL_TESTS} test references)"

    if [ "$FIXTURE_ADOPTION" -ge "$MIN_FIXTURE_ADOPTION" ]; then
        log_success "Fixture adoption meets ${MIN_FIXTURE_ADOPTION}% target"
    else
        log_warning "Fixture adoption ${FIXTURE_ADOPTION}% below ${MIN_FIXTURE_ADOPTION}% target"
    fi
else
    log_warning "No tests found to analyze fixture usage"
fi

#
# Check 6: Tautological Assertions (should be 0 after fixes)
#
log_info "Check 6: Checking for tautological assertions..."

TAUTOLOGICAL=$(grep -r "workflow\.success || workflow\.failed" tests/ subworkflows/ 2>/dev/null | wc -l | tr -d ' ')

if [ "$TAUTOLOGICAL" -eq 0 ]; then
    log_success "No tautological assertions found"
else
    log_error "Found ${TAUTOLOGICAL} tautological assertions (always pass)"
    grep -r "workflow\.success || workflow\.failed" tests/ subworkflows/ 2>/dev/null | head -5
fi

#
# Check 7: Hardcoded Paths (should be 0 after fixes)
#
log_info "Check 7: Checking for hardcoded absolute paths..."

HARDCODED=$(grep -r "/Users/" tests/ 2>/dev/null | grep -v "Binary file" | grep -v ".git" | wc -l | tr -d ' ')

if [ "$HARDCODED" -eq 0 ]; then
    log_success "No hardcoded absolute paths found"
else
    log_warning "Found ${HARDCODED} potential hardcoded paths"
    grep -r "/Users/" tests/ 2>/dev/null | grep -v "Binary file" | grep -v ".git" | head -3
fi

#
# Check 8: Test Tags
#
log_info "Check 8: Checking test tag usage..."

# Count test files with tags
TESTS_WITH_TAGS=$(grep -r "tag \"" modules/local/*/tests/main.nf.test 2>/dev/null | cut -d: -f1 | sort -u | wc -l | tr -d ' ')
TOTAL_MODULE_TESTS=$(find modules/local -name "main.nf.test" -type f 2>/dev/null | wc -l | tr -d ' ')

if [ "$TOTAL_MODULE_TESTS" -gt 0 ]; then
    TAG_COVERAGE=$((TESTS_WITH_TAGS * 100 / TOTAL_MODULE_TESTS))
    echo "  Tests with tags: ${TAG_COVERAGE}% (${TESTS_WITH_TAGS}/${TOTAL_MODULE_TESTS} test files)"

    if [ "$TAG_COVERAGE" -ge 80 ]; then
        log_success "Good tag coverage (${TAG_COVERAGE}%)"
    elif [ "$TAG_COVERAGE" -ge 50 ]; then
        log_warning "Moderate tag coverage (${TAG_COVERAGE}%, recommend 80%+)"
    else
        log_warning "Low tag coverage (${TAG_COVERAGE}%, recommend 80%+)"
    fi
else
    log_warning "No module tests found to check tags"
fi

#
# Check 9: Stub Test Validation
#
log_info "Check 9: Checking stub test validation quality..."

# Count stub tests that validate output structure (look for JSON parsing or field checks)
STUB_TESTS=$(grep -r "stub true" modules/local/*/tests/main.nf.test 2>/dev/null | wc -l | tr -d ' ')
VALIDATED_STUB_TESTS=$(grep -A20 "stub true" modules/local/*/tests/main.nf.test 2>/dev/null | grep -E "(JsonSlurper|containsKey|parse\()" | wc -l | tr -d ' ')

if [ "$STUB_TESTS" -gt 0 ]; then
    echo "  Stub tests: ${STUB_TESTS}"
    echo "  Validated stub tests: ${VALIDATED_STUB_TESTS}"
    VALIDATED_RATIO=$((VALIDATED_STUB_TESTS * 100 / STUB_TESTS))

    if [ "$VALIDATED_RATIO" -ge 50 ]; then
        log_success "Good stub validation coverage (${VALIDATED_RATIO}%)"
    else
        log_warning "Limited stub validation (${VALIDATED_RATIO}%, recommend validating stub output structure)"
    fi
else
    log_warning "No stub tests found"
fi

#
# Check 10: Test Fixture Availability
#
log_info "Check 10: Checking test fixture availability..."

FIXTURE_DIRS=("characteristics" "predictions" "statistics" "system_metrics" "edge_cases")
MISSING_FIXTURES=""

for dir in "${FIXTURE_DIRS[@]}"; do
    fixture_path="tests/fixtures/${dir}"
    if [ ! -d "$fixture_path" ]; then
        MISSING_FIXTURES="${MISSING_FIXTURES}${dir} "
    else
        fixture_count=$(find "$fixture_path" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [ "$fixture_count" -eq 0 ]; then
            MISSING_FIXTURES="${MISSING_FIXTURES}${dir}(empty) "
        fi
    fi
done

if [ -z "$MISSING_FIXTURES" ]; then
    log_success "All fixture directories present with files"
else
    log_warning "Missing or empty fixture directories: $MISSING_FIXTURES"
fi

#
# Summary
#
echo ""
echo "=========================================="
echo "📊 Test Quality Summary"
echo "=========================================="
echo ""
echo "Checks passed:      ${CHECKS_PASSED}"
echo "Warnings:           ${WARNINGS}"
echo "Critical issues:    ${CRITICAL_ISSUES}"
echo ""

# Write report file if requested
if [ -n "$REPORT_FILE" ]; then
    {
        echo "nanometanf Test Quality Report"
        echo "Generated: $(date)"
        echo ""
        echo "Summary:"
        echo "- Checks passed: ${CHECKS_PASSED}"
        echo "- Warnings: ${WARNINGS}"
        echo "- Critical issues: ${CRITICAL_ISSUES}"
    } > "$REPORT_FILE"
    echo "Report written to: $REPORT_FILE"
fi

# Determine exit code
if [ "$CRITICAL_ISSUES" -gt 0 ]; then
    echo "❌ Test suite has critical quality issues"
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    if [ "$STRICT_MODE" = true ]; then
        echo "❌ Strict mode: Warnings treated as errors"
        exit 1
    else
        echo "⚠️  Test suite has warnings (use --strict to treat as errors)"
        exit 2
    fi
else
    echo "✅ Test suite quality validation passed!"
    exit 0
fi
