#!/bin/bash

###############################################################################
#
# AXI Crossbar Verification Run Script
#
###############################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default settings
SIM=${SIM:-vcs}
TEST=${TEST:-all}
COVERAGE=${COVERAGE:-0}
GUI=${GUI:-0}
VERBOSITY=${VERBOSITY:-medium}

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
COV_DIR="${SCRIPT_DIR}/coverage"

###############################################################################
# Functions
###############################################################################

print_header() {
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}==========================================${NC}"
}

print_success() {
    echo -e "${GREEN}[PASS] $1${NC}"
}

print_error() {
    echo -e "${RED}[FAIL] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

###############################################################################
# Setup
###############################################################################

setup() {
    print_header "Setting up verification environment"

    # Create directories
    mkdir -p ${LOG_DIR}
    mkdir -p ${COV_DIR}

    # Check simulator
    if ! command -v ${SIM} &> /dev/null; then
        print_error "Simulator '${SIM}' not found!"
        exit 1
    fi

    print_success "Setup completed"
}

###############################################################################
# Compile
###############################################################################

compile() {
    print_header "Compiling design and testbench"

    cd ${SCRIPT_DIR}

    case ${SIM} in
        vcs)
            vcs -sverilog -full64 -debug_access+all -kdb -lca \
                -f filelist.f \
                -o simv \
                -l ${LOG_DIR}/compile.log
            ;;
        xcelium)
            xrun -sv -64bit -access +rwc \
                 -f filelist.f \
                 -elaborate \
                 -l ${LOG_DIR}/compile.log
            ;;
        modelsim)
            vlib work
            vlog -sv -f filelist.f -l ${LOG_DIR}/compile.log
            ;;
        *)
            print_error "Unknown simulator: ${SIM}"
            exit 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        print_success "Compilation completed"
    else
        print_error "Compilation failed!"
        exit 1
    fi
}

###############################################################################
# Run Tests
###############################################################################

run_test() {
    local test_name=$1
    local test_log="${LOG_DIR}/${test_name}.log"

    print_info "Running test: ${test_name}"

    case ${SIM} in
        vcs)
            if [ ${GUI} -eq 1 ]; then
                ./simv +TESTNAME=${test_name} +VERBOSITY=${VERBOSITY} \
                    -gui -l ${test_log}
            else
                ./simv +TESTNAME=${test_name} +VERBOSITY=${VERBOSITY} \
                    -l ${test_log}
            fi
            ;;
        xcelium)
            xrun -sv -64bit -access +rwc \
                 -f filelist.f \
                 +TESTNAME=${test_name} +VERBOSITY=${VERBOSITY} \
                 -l ${test_log}
            ;;
        modelsim)
            vsim -c work.axi_crossbar_tb \
                 -do "run -all" \
                 +TESTNAME=${test_name} +VERBOSITY=${VERBOSITY} \
                 -l ${test_log}
            ;;
    esac

    # Check result
    if grep -q "PASSED" ${test_log} && ! grep -q "FAILED\|ERROR" ${test_log}; then
        print_success "Test ${test_name} PASSED"
        return 0
    else
        print_error "Test ${test_name} FAILED"
        return 1
    fi
}

run_all_tests() {
    print_header "Running all tests"

    local total=0
    local passed=0
    local failed=0
    local tests=(
        "smoke_test"
        "single_master_test"
        "multi_master_test"
        "address_routing_test"
        "concurrent_access_test"
        "same_slave_contention_test"
        "burst_write_test"
        "burst_read_test"
        "outstanding_test"
        "pipeline_stress_test"
    )

    for test in "${tests[@]}"; do
        total=$((total + 1))
        if run_test ${test}; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
        fi
    done

    # Print summary
    echo ""
    print_header "Test Summary"
    echo -e "Total:  ${total}"
    echo -e "${GREEN}Passed: ${passed}${NC}"
    echo -e "${RED}Failed: ${failed}${NC}"
    echo ""

    return ${failed}
}

###############################################################################
# Coverage
###############################################################################

generate_coverage() {
    print_header "Generating coverage report"

    cd ${SCRIPT_DIR}

    case ${SIM} in
        vcs)
            urg -dir simv.vdb -report ${COV_DIR}/report
            ;;
        xcelium)
            xcov -dir cov_db -report ${COV_DIR}/report
            ;;
    esac

    print_success "Coverage report generated in ${COV_DIR}/report"
}

###############################################################################
# Clean
###############################################################################

clean() {
    print_header "Cleaning generated files"

    cd ${SCRIPT_DIR}

    rm -rf simv simv.daidir csrc *.vpd *.vcd
    rm -rf INCA_libs xcelium.d
    rm -rf work modelsim.ini
    rm -rf ${LOG_DIR}/*.log
    rm -rf ${COV_DIR}
    rm -rf DVEfiles inter.vpd
    rm -rf *.wlf *.vstf

    print_success "Clean completed"
}

###############################################################################
# Usage
###############################################################################

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --sim SIM        Simulator (vcs|xcelium|modelsim)"
    echo "  -t, --test TEST      Test to run (test_name or 'all')"
    echo "  -c, --coverage       Enable coverage collection"
    echo "  -g, --gui            Run with GUI"
    echo "  -v, --verbosity LVL  Verbosity (low|medium|high)"
    echo "  --clean              Clean generated files"
    echo "  --compile            Only compile"
    echo "  --help               Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 -s vcs -t smoke_test"
    echo "  $0 -s xcelium -t all -c"
    echo "  $0 --clean"
}

###############################################################################
# Main
###############################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--sim)
                SIM=$2
                shift 2
                ;;
            -t|--test)
                TEST=$2
                shift 2
                ;;
            -c|--coverage)
                COVERAGE=1
                shift
                ;;
            -g|--gui)
                GUI=1
                shift
                ;;
            -v|--verbosity)
                VERBOSITY=$2
                shift 2
                ;;
            --clean)
                clean
                exit 0
                ;;
            --compile)
                setup
                compile
                exit 0
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Run
    setup
    compile

    if [ "${TEST}" = "all" ]; then
        run_all_tests
        result=$?
    else
        run_test ${TEST}
        result=$?
    fi

    # Generate coverage if requested
    if [ ${COVERAGE} -eq 1 ]; then
        generate_coverage
    fi

    # Exit with result
    exit ${result}
}

# Run main
main "$@"
