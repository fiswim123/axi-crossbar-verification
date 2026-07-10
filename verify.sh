#!/bin/bash

###############################################################################
#
# AXI Crossbar Verification - Main Entry Point
#
###############################################################################

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  AXI Crossbar Verification Environment    ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Check for SystemVerilog support
check_simulator() {
    if command -v iverilog &> /dev/null; then
        echo -e "${GREEN}✓ Icarus Verilog found${NC}"
        return 0
    elif command -v vcs &> /dev/null; then
        echo -e "${GREEN}✓ VCS found${NC}"
        return 0
    elif command -v xrun &> /dev/null; then
        echo -e "${GREEN}✓ Xcelium found${NC}"
        return 0
    elif command -v vsim &> /dev/null; then
        echo -e "${GREEN}✓ ModelSim found${NC}"
        return 0
    else
        echo -e "${RED}✗ No SystemVerilog simulator found!${NC}"
        echo "Please install one of: iverilog, vcs, xrun, vsim"
        return 1
    fi
}

# Run syntax check
run_syntax_check() {
    echo -e "${BLUE}Running syntax check...${NC}"

    cd ${SCRIPT_DIR}

    # Check if files compile without errors
    if command -v iverilog &> /dev/null; then
        iverilog -g2012 -t null \
            src/*.sv \
            2>&1 | head -20
    fi

    echo -e "${GREEN}Syntax check completed${NC}"
}

# Run quick verification
run_quick_verify() {
    echo -e "${BLUE}Running quick verification...${NC}"

    cd ${SCRIPT_DIR}/verification
    ./run_quick_test.sh
}

# Run full verification
run_full_verify() {
    echo -e "${BLUE}Running full verification...${NC}"

    cd ${SCRIPT_DIR}/verification
    ./run_tests.sh -s vcs -t all
}

# Show verification plan
show_plan() {
    echo -e "${BLUE}Verification Plan Summary:${NC}"
    echo ""
    echo "  Design: AXI Crossbar (4x4)"
    echo "  - 4 Master interfaces"
    echo "  - 4 Slave interfaces"
    echo "  - 16-bit address, 8-bit ID, 32-bit data"
    echo ""
    echo "  Address Map:"
    echo "  - SLV0: 0x0000 - 0x0FFF (4KB)"
    echo "  - SLV1: 0x1000 - 0x1FFF (4KB)"
    echo "  - SLV2: 0x2000 - 0x2FFF (4KB)"
    echo "  - SLV3: 0x3000 - 0x3FFF (4KB)"
    echo ""
    echo "  Test Categories:"
    echo "  1. Smoke Tests (T001-T004)"
    echo "  2. Routing Tests (T010-T014)"
    echo "  3. Arbitration Tests (T020-T022)"
    echo "  4. Concurrency Tests (T030-T033)"
    echo "  5. Protocol Tests (T040-T043)"
    echo "  6. Boundary Tests (T050-T053)"
    echo "  7. Exception Tests (T060-T062)"
    echo ""
    echo "  Coverage Goals:"
    echo "  - Functional Coverage: > 95%"
    echo "  - Code Coverage: > 90%"
    echo "  - FSM Coverage: 100%"
    echo ""
    echo "  See verification/docs/verification_plan.md for details"
}

# Show help
show_help() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  check     - Check for simulator availability"
    echo "  syntax    - Run syntax check on source files"
    echo "  quick     - Run quick verification test"
    echo "  full      - Run full verification suite"
    echo "  plan      - Show verification plan summary"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 check"
    echo "  $0 quick"
    echo "  $0 full"
    echo ""
    echo "For detailed verification, see verification/README.md"
}

# Main menu
case "${1:-help}" in
    check)
        check_simulator
        ;;
    syntax)
        run_syntax_check
        ;;
    quick)
        check_simulator && run_quick_verify
        ;;
    full)
        check_simulator && run_full_verify
        ;;
    plan)
        show_plan
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        show_help
        exit 1
        ;;
esac
